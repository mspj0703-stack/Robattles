--!nonstrict
-- 서버 Feedback/State → 연출 큐(cue) 변환 (순수 로직, CLI 테스트 가능). 렌더링은 EffectPlayer(Roblox 전용)가 한다.
-- cue 이름은 shared/Data/EffectCatalog.Cues 의 키다. 알 수 없는 이벤트는 무시하고 예외를 던지지 않는다.
local Link = require(script.Parent.Parent.Link)
local Catalog = Link.shared("Data/EffectCatalog")

local EffectsModel = {}

-- 서버가 보내는 투사체 정의 id → (발사 연출, 시각용 탄) 큐 이름. 알 수 없는 정의는 기본 페인트탄으로 그린다.
local PROJECTILE_CUES = {
	color_bomb = { fire = "paint.bomb.throw", proj = "paint.bomb.projectile" },
	piercing_shot = { fire = "paint.pierce.fire", proj = "paint.pierce.projectile" },
	sling_Lmb = { fire = "sling.fire", proj = "sling.projectile" },
	sling_Triple = { fire = "sling.fire", proj = "sling.projectile" },
	sling_Snare = { fire = "sling.snare", proj = "sling.projectile" },
	sling_Backstep = { fire = "sling.fire", proj = "sling.projectile" },
}

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
	elseif t == "CharSkill" then
		-- 캐릭터 모듈이 보낸 일반 스킬 이벤트: 서버가 지정한 큐 이름이 카탈로그에 있을 때만 재생(그 외는 무시)
		if type(event.cue) == "string" and Catalog.Cues[event.cue] ~= nil then
			local dash = event.dash
			table.insert(out, {
				cue = event.cue, playerId = event.playerId, targetId = event.targetId, mine = event.playerId == myId,
				pos = event.pos, dir = event.dir or event.direction, origin = event.origin, tip = event.tip,
				distance = type(dash) == "table" and (dash.speed or 0) * (dash.duration or 0) or event.distance, radius = event.radius,
			})
		end
	elseif t == "Explosion" then
		if type(event.pos) == "table" then
			table.insert(out, { cue = "paint.explosion", pos = event.pos, radius = event.radius, playerId = event.ownerId, mine = event.ownerId == myId })
		end
	elseif t == "Spawned" then
		-- 직선/포물선/관통 투사체: 발사 연출 + 클라이언트 측 시각용 탄. (판정은 서버가 한다)
		local visible = event.projectileType == "Linear" or event.projectileType == "Arc" or event.projectileType == "Pierce"
		if visible and type(event.pos) == "table" and type(event.dir) == "table" then
			local special = PROJECTILE_CUES[event.defId]
			table.insert(out, { cue = special and special.fire or "paint.fire", playerId = event.ownerId, mine = event.ownerId == myId, pos = event.pos, dir = event.dir })
			table.insert(out, {
				cue = special and special.proj or "paint.projectile", projectileId = event.projectileId, playerId = event.ownerId, pos = event.pos, dir = event.dir,
				speed = event.speed, radius = event.radius, lifetime = event.lifetime, startTime = event.time, gravity = event.gravity,
			})
		end
	elseif t == "Ended" then
		table.insert(out, { cue = "projectile.end", projectileId = event.projectileId, pos = event.pos, reason = event.reason })
		if event.reason == "Hit" or event.reason == "World" or event.reason == "Blocked" or event.reason == "Detonated" then
			table.insert(out, { cue = "paint.splat", projectileId = event.projectileId, pos = event.pos, reason = event.reason })
		end
	elseif t == "BallSpawn" then
		-- SUPERBALL 볼: 서버가 위치·속도·모드를 알려 주고(튕김/모드 전환 때마다 재기준) 클라이언트는 그 사이를 보간만 한다.
		if type(event.pos) == "table" and type(event.vel) == "table" and event.ballId ~= nil then
			out[#out + 1] = EffectsModel.ballCue("ball.projectile", event, myId)
		end
	elseif t == "BallBounce" or t == "BallMode" then
		if event.ballId ~= nil and type(event.pos) == "table" then
			out[#out + 1] = EffectsModel.ballCue("ball.update", event, myId)
			if t == "BallBounce" then
				out[#out + 1] = { cue = "ball.bounce", pos = event.pos, projectileId = event.ballId }
			end
		end
	elseif t == "BallEnd" then
		out[#out + 1] = { cue = "projectile.end", projectileId = event.ballId, pos = event.pos, reason = event.reason }
	elseif t == "BombSpawn" then
		-- TIMEBOMB 폭탄: 비행은 보간, 착지(BombLand)에서 고정, 폭발/종료(BombExplode/BombEnd)에서 제거
		if type(event.pos) == "table" and type(event.vel) == "table" and event.bombId ~= nil then
			out[#out + 1] = EffectsModel.ballCue("bomb.projectile", { ballId = event.bombId, ownerId = event.ownerId, pos = event.pos, vel = event.vel, gravity = event.gravity, lifetime = 60, time = event.time }, myId)
		end
	elseif t == "BombLand" then
		if event.bombId ~= nil and type(event.pos) == "table" then
			out[#out + 1] = EffectsModel.ballCue("ball.update", { ballId = event.bombId, ownerId = event.ownerId, pos = event.pos, vel = { X = 0, Y = 0, Z = 0 }, mode = "Landed", time = event.time }, myId)
		end
	elseif t == "BombExplode" then
		if type(event.pos) == "table" then
			out[#out + 1] = { cue = "bomb.explosion", pos = event.pos, radius = event.radius, playerId = event.ownerId, mine = event.ownerId == myId, stage = event.stage }
		end
		out[#out + 1] = { cue = "projectile.end", projectileId = event.bombId, pos = event.pos, reason = "Exploded" }
	elseif t == "BombEnd" then
		out[#out + 1] = { cue = "projectile.end", projectileId = event.bombId, pos = event.pos, reason = event.reason }
	elseif t == "Reloaded" then
		table.insert(out, { cue = "reload.done", playerId = event.playerId, mine = event.playerId == myId })
	elseif t == "Died" then
		table.insert(out, { cue = "death.poof", playerId = event.playerId, mine = event.playerId == myId })
	elseif t == "Respawned" then
		table.insert(out, { cue = "respawn.flash", playerId = event.playerId, mine = event.playerId == myId })
	end
	return out
end

-- 볼 이벤트 → 큐(위치/속도 기준점). dir/speed 는 vel 에서 계산한다.
function EffectsModel.ballCue(cueName, event, myId)
	local vel = type(event.vel) == "table" and event.vel or { X = 0, Y = 0, Z = 0 }
	local speed = math.sqrt(vel.X * vel.X + vel.Y * vel.Y + vel.Z * vel.Z)
	local dir = speed > 1e-6 and { X = vel.X / speed, Y = vel.Y / speed, Z = vel.Z / speed } or { X = 0, Y = 0, Z = 1 }
	return {
		cue = cueName, ball = true, projectileId = event.ballId, playerId = event.ownerId, mine = event.ownerId == myId,
		pos = event.pos, dir = dir, speed = event.mode == "Return" and (event.speed or speed) or speed, gravity = event.gravity or 0,
		radius = event.radius, lifetime = event.lifetime, startTime = event.time, mode = event.mode, orbit = event.orbit,
	}
end

-- 시각용 볼 위치(모드별). Fly: 서버와 같은 포물선 / Return: 소유자 쪽으로 직선 / Orbit: 소유자 주위 원운동. 소유자 위치를 모르면 마지막 기준점.
function EffectsModel.ballPosition(cue, now, ownerPos)
	if type(cue.startTime) ~= "number" or type(cue.pos) ~= "table" then
		return nil
	end
	local elapsed = math.max(0, now - cue.startTime)
	local mode = cue.mode or "Fly"
	if mode == "Landed" then
		return cue.pos
	end
	if mode == "Orbit" then
		local o = cue.orbit
		if type(o) ~= "table" or not ownerPos then
			return cue.pos
		end
		local ang = o.phase + o.omega * (now - o.startAt)
		return { X = ownerPos.X + math.cos(ang) * o.radius, Y = ownerPos.Y + o.height, Z = ownerPos.Z + math.sin(ang) * o.radius }
	elseif mode == "Return" then
		if not ownerPos then
			return cue.pos
		end
		local to = { X = ownerPos.X - cue.pos.X, Y = ownerPos.Y + 1.5 - cue.pos.Y, Z = ownerPos.Z - cue.pos.Z }
		local dist = math.sqrt(to.X * to.X + to.Y * to.Y + to.Z * to.Z)
		if dist < 1e-6 then
			return cue.pos
		end
		local k = math.min(dist, (cue.speed or 0) * elapsed) / dist
		return { X = cue.pos.X + to.X * k, Y = cue.pos.Y + to.Y * k, Z = cue.pos.Z + to.Z * k }
	end
	if elapsed > (cue.lifetime or 6) then
		return nil
	end
	local g = type(cue.gravity) == "number" and cue.gravity or 0
	return {
		X = cue.pos.X + cue.dir.X * (cue.speed or 0) * elapsed,
		Y = cue.pos.Y + cue.dir.Y * (cue.speed or 0) * elapsed - 0.5 * g * elapsed * elapsed,
		Z = cue.pos.Z + cue.dir.Z * (cue.speed or 0) * elapsed,
	}
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
	local g = type(cue.gravity) == "number" and cue.gravity or 0 -- 포물선(Color Bomb 등): 서버와 같은 중력식
	return {
		X = cue.pos.X + cue.dir.X * cue.speed * elapsed,
		Y = cue.pos.Y + cue.dir.Y * cue.speed * elapsed - 0.5 * g * elapsed * elapsed,
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
