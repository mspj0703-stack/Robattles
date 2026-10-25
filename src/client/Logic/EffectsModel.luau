--!nonstrict
-- 서버 Feedback/State → 연출 큐(cue) 변환 (순수 로직, CLI 테스트 가능). 렌더링은 EffectPlayer(Roblox 전용)가 한다.
-- cue 이름은 shared/Data/EffectCatalog.Cues 의 키다. 알 수 없는 이벤트는 무시하고 예외를 던지지 않는다.
local EffectsModel = {}

-- 반환: { { cue, playerId?, targetId?, pos?, dir?, mine?, ... } }
function EffectsModel.translate(event, myId)
	local out = {}
	if type(event) ~= "table" or type(event.type) ~= "string" then
		return out
	end
	local t = event.type
	if t == "Swing" then
		table.insert(out, { cue = event.step == 3 and "sword.slash3" or "sword.slash", playerId = event.playerId, mine = event.playerId == myId, step = event.step })
	elseif t == "SwordSkill" then
		local me = event.playerId == myId
		if event.skill == "TripleSlash" then
			table.insert(out, { cue = "skill.triple" .. tostring(math.clamp(event.step or 1, 1, 3)), playerId = event.playerId, mine = me, step = event.step })
		elseif event.skill == "Lunge" then
			if event.phase == "Charge" then
				table.insert(out, { cue = "skill.lunge.charge", playerId = event.playerId, mine = me })
			elseif event.phase == "Dash" then
				local dash = event.dash or {}
				table.insert(out, {
					cue = "skill.lunge.dash", playerId = event.playerId, mine = me, dir = event.direction,
					distance = (dash.speed or 0) * (dash.duration or 0), charge = event.charge,
				})
			end
		elseif event.skill == "BladeWave" then
			table.insert(out, { cue = "skill.bladewave", playerId = event.playerId, mine = me, range = event.range, arc = event.arc })
		elseif event.skill == "BladeStorm" then
			if event.phase == "Tick" then
				table.insert(out, { cue = "skill.storm.tick", playerId = event.playerId, mine = me, index = event.index })
			elseif event.phase == "Finisher" then
				table.insert(out, { cue = "skill.storm.finish", playerId = event.playerId, mine = me })
			elseif event.phase == "Start" then
				table.insert(out, { cue = "skill.storm.start", playerId = event.playerId, mine = me })
			end
		end
	elseif t == "Duelist" then
		table.insert(out, { cue = "duelist.proc", playerId = event.playerId, targetId = event.targetId, mine = event.playerId == myId, bonus = event.bonus })
	elseif t == "Parry" then
		table.insert(out, { cue = "parry.start", playerId = event.playerId, mine = event.playerId == myId })
	elseif t == "ParrySuccess" then
		table.insert(out, { cue = "parry.success", playerId = event.playerId, mine = event.playerId == myId, countered = event.countered == true })
		if event.attackerId ~= nil then
			table.insert(out, { cue = "parry.blocked", playerId = event.attackerId, mine = event.attackerId == myId })
		end
	elseif t == "Damaged" then
		if event.targetId ~= nil then
			table.insert(out, { cue = "hit.flash", targetId = event.targetId, mine = event.targetId == myId })
			table.insert(out, { cue = "hit.impact", targetId = event.targetId, attackerId = event.attackerId, amount = event.amount, mine = event.attackerId == myId })
		end
	elseif t == "Dodge" then
		local dir = event.info and event.info.direction
		table.insert(out, {
			cue = "dodge.afterimage", playerId = event.playerId, mine = event.playerId == myId,
			dir = dir, distance = event.info and event.info.distance, origin = event.info and event.info.origin,
		})
	elseif t == "Spawned" then
		-- 페인트볼 등 직선 투사체: 발사 연출 + 클라이언트 측 시각용 탄. (판정은 서버가 한다)
		if event.projectileType == "Linear" and type(event.pos) == "table" and type(event.dir) == "table" then
			table.insert(out, { cue = "paint.fire", playerId = event.ownerId, mine = event.ownerId == myId, pos = event.pos, dir = event.dir })
			table.insert(out, {
				cue = "paint.projectile", projectileId = event.projectileId, playerId = event.ownerId, pos = event.pos, dir = event.dir,
				speed = event.speed, radius = event.radius, lifetime = event.lifetime, startTime = event.time,
			})
		end
	elseif t == "Ended" then
		table.insert(out, { cue = "projectile.end", projectileId = event.projectileId, pos = event.pos, reason = event.reason })
		if event.reason == "Hit" or event.reason == "World" or event.reason == "Blocked" or event.reason == "Detonated" then
			table.insert(out, { cue = "paint.splat", projectileId = event.projectileId, pos = event.pos, reason = event.reason })
		end
	elseif t == "Reloaded" then
		table.insert(out, { cue = "reload.done", playerId = event.playerId, mine = event.playerId == myId })
	elseif t == "Died" then
		table.insert(out, { cue = "death.poof", playerId = event.playerId, mine = event.playerId == myId })
	elseif t == "Respawned" then
		table.insert(out, { cue = "respawn.flash", playerId = event.playerId, mine = event.playerId == myId })
	end
	return out
end

-- 재장전 시작 감지: 이전/현재 HUD 스냅샷의 reloadingUntil 로 상승 에지를 판단한다. 반환 true 이면 reload.start 를 재생.
function EffectsModel.reloadStarted(prevSnap, snap, now)
	local function reloading(s)
		return s ~= nil and s.ammo ~= nil and s.ammo.reloadingUntil ~= nil and s.ammo.reloadingUntil > (s.t or now)
	end
	return reloading(snap) and not reloading(prevSnap)
end

-- 시각용 탄 위치(직선, 중력 0 가정). 수명이 끝나면 nil. 서버 Ended 가 오면 즉시 제거해야 한다.
function EffectsModel.projectilePosition(cue, now)
	if type(cue.speed) ~= "number" or type(cue.startTime) ~= "number" then
		return nil
	end
	local elapsed = now - cue.startTime
	if elapsed < 0 or elapsed > (cue.lifetime or 2) then
		return nil
	end
	return {
		X = cue.pos.X + cue.dir.X * cue.speed * elapsed,
		Y = cue.pos.Y + cue.dir.Y * cue.speed * elapsed,
		Z = cue.pos.Z + cue.dir.Z * cue.speed * elapsed,
	}
end

-- 회피 잔상 위치: 시작점에서 방향으로 distance 까지 count 개를 균등 배치(벽에 막힌 거리 반영).
function EffectsModel.afterimagePoints(origin, dir, distance, count)
	local pts = {}
	if type(origin) ~= "table" or type(dir) ~= "table" then
		return pts
	end
	local d = math.clamp(type(distance) == "number" and distance or 0, 0, 100)
	for i = 1, count do
		local f = (i - 1) / math.max(1, count)
		table.insert(pts, { X = origin.X + dir.X * d * f, Y = origin.Y, Z = origin.Z + dir.Z * d * f })
	end
	return pts
end

return EffectsModel
