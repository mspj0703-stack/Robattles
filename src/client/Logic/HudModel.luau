--!nonstrict
-- 서버 HUD 스냅샷 → 화면 표시용 데이터(순수). 임시 UI: 확정되지 않은 디자인은 단순 표시만 한다.
local HudModel = {}

local function remaining(readyAt, now)
	return math.max(0, (readyAt or 0) - now)
end

function HudModel.build(snap, now)
	if type(snap) ~= "table" then
		return nil
	end
	local m = {}
	m.alive = snap.alive == true
	m.healthFrac = snap.health and snap.health.max > 0 and math.clamp(snap.health.cur / snap.health.max, 0, 1) or 0
	m.healthText = snap.health and string.format("%d / %d", math.ceil(snap.health.cur), snap.health.max) or ""

	-- 탄약: 탄약이 있는 캐릭터에만 표시
	if snap.ammo then
		local reloading = snap.ammo.reloadingUntil and snap.ammo.reloadingUntil > now
		m.ammo = {
			text = string.format("%d / %d", snap.ammo.cur, snap.ammo.mag),
			reloading = reloading == true,
			reloadFrac = reloading and 1 - (snap.ammo.reloadingUntil - now) / snap.ammo.reloadSeconds or nil,
		}
	end

	-- 쿨타임
	local cd = snap.cooldowns or {}
	m.primary = { remaining = remaining(cd.primary and cd.primary.readyAt, now) }
	if snap.hasSecondary then
		local rem = remaining(cd.secondary and cd.secondary.readyAt, now)
		local total = cd.secondary and cd.secondary.total or 0
		m.secondary = { remaining = rem, frac = total > 0 and rem / total or 0, ready = rem <= 0 }
	end

	-- 숫자 스킬: 구현된 캐릭터는 이름·쿨타임·연계/충전 상태, 아니면 미구현 표시
	m.skills = {}
	for i = 1, 3 do
		local s = snap.skills and snap.skills[i]
		if s ~= nil and s.implemented == true then
			local rem = remaining(s.readyAt, now)
			local total = s.total or 0
			local label
			if s.state == "Chain" then
				label = string.format("%s %d/%d", s.name or "", s.step or 0, s.steps or 3)
			elseif s.state == "charging" then
				label = string.format("%s 충전 %d%%", s.name or "", math.floor((s.chargeFrac or 0) * 100))
			elseif s.state == "dashing" then
				label = (s.name or "") .. " 돌진"
			elseif rem > 0 then
				label = string.format("%s %.1fs", s.name or "", rem)
			else
				label = (s.name or "") .. " 준비"
			end
			m.skills[i] = {
				key = tostring(i), implemented = true, name = s.name, label = label, remaining = rem,
				frac = total > 0 and math.clamp(rem / total, 0, 1) or 0, ready = rem <= 0 and s.state == nil, state = s.state,
			}
		else
			m.skills[i] = { key = tostring(i), implemented = false, label = "미구현" }
		end
	end
	if snap.combo then
		m.combo = { step = snap.combo.step, steps = snap.combo.steps, text = string.format("콤보 %d/%d", snap.combo.step, snap.combo.steps) }
	end
	if snap.passive then
		local left = remaining(snap.passive.lockedUntil, now)
		m.passive = { id = snap.passive.id, lockRemaining = left, ready = left <= 0, text = left > 0 and string.format("%s %.1fs", snap.passive.id, left) or (snap.passive.id .. " 준비") }
	end

	-- 회피 충전
	if snap.dodge then
		m.dodge = { charges = snap.dodge.charges, max = snap.dodge.max, nextIn = snap.dodge.nextChargeAt and remaining(snap.dodge.nextChargeAt, now) or nil }
	end

	-- 궁극기: 게이지는 항상 표시하되, 미구현이면 F로 쓸 수 없음을 명시
	if snap.ultimate then
		local u = snap.ultimate
		m.ultimate = {
			gauge = u.gauge,
			frac = u.max > 0 and math.clamp(u.gauge / u.max, 0, 1) or 0,
			ready = u.gauge >= u.max and u.implemented == true and not u.active,
			active = u.active,
			implemented = u.implemented == true,
			label = (u.implemented == true) and (u.active and ((u.name or "궁극기") .. " 발동 중") or (u.gauge >= u.max and ((u.name or "궁극기") .. " F 발동 가능") or "충전 중")) or "궁극기 미구현",
		}
	end

	m.running = snap.running == true
	-- 부활 보호(서버 권위 상태의 표시): 남은 시간과 비율
	if snap.protectedUntil and snap.protectedUntil > now then
		local total = snap.protectSeconds or 2
		local left = snap.protectedUntil - now
		m.protection = { remaining = left, frac = math.clamp(left / math.max(total, 1e-6), 0, 1) }
	end
	m.parryActive = snap.parryUntil ~= nil and snap.parryUntil > now
	m.canAct = snap.canAct == true
	m.characterId = snap.characterId
	m.pendingCharacterId = snap.pendingCharacterId
	return m
end

return HudModel
