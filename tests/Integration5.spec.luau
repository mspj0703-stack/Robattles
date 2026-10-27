--!nonstrict
-- Phase 2 통합 안정화: 5캐릭터 선택·전환·HP, 입력/HUD/궁극기/패시브 초기화, 사망·리스폰·전환 중 남은 상태(충전·투사체·설치물·지연 Remote),
-- 12인 동시 사용 시 이벤트 수·객체 상한·정리. CLI 로직 검증만이며 Roblox 실제 동작은 Studio 미검증이다.
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Core = Env.server("CombatCore")
local ProjectileService = Env.server("ProjectileService")
local Controller = Env.server("CharacterController")
local Characters = Env.shared("Data/Characters")
local Config = Env.shared("Config")
local RemoteSpec = Env.shared("RemoteSpec")
local Vec = Env.shared("Vec")

local v = H.v
local floor = { point = v(0, 0, 0), normal = v(0, 1, 0) }
local CHARS = { "SWORD", "PAINTBALL", "SUPERBALL", "TIMEBOMB", "SLINGSHOT" }
local HP = { SWORD = 110, PAINTBALL = 95, SUPERBALL = 100, TIMEBOMB = 105, SLINGSHOT = 100 }

-- ids: { id = characterId }, ring: true 면 반지름 12 원 위에 배치
local function setup(ids, opts)
	opts = opts or {}
	local core = Core.new(Config)
	local pos, face = {}, {}
	local world = H.fakeWorld({ floor })
	local order = {}
	for id in ids do table.insert(order, id) end
	table.sort(order)
	local function targets()
		local list = {}
		for _, id in order do
			table.insert(list, { id = id, pos = pos[id], radius = Config.Combat.HitRadius, alive = core.damage:isAlive(id) })
		end
		return list
	end
	local ps = ProjectileService.new({ damage = core.damage, targets = targets, world = world, config = Config })
	local c = Controller.new({
		config = Config, core = core, projectiles = ps, targets = targets, world = world,
		getPose = function(id) return { pos = pos[id], forward = face[id], airborne = false } end,
	})
	local counts, total = {}, 0
	c:onFeedback(function(e)
		total += 1
		counts[e.type] = (counts[e.type] or 0) + 1
	end)
	ps:onEvent(function(e) -- 서버 Main 이 투사체 이벤트도 Feedback 으로 중계하므로 같은 집계에 넣는다
		total += 1
		counts[e.type] = (counts[e.type] or 0) + 1
	end)
	local n = #order
	for i, id in order do
		c:addPlayer(id, ids[id])
		if opts.ring then
			local a = (i - 1) / n * math.pi * 2
			pos[id] = v(math.cos(a) * 12, 1.5, math.sin(a) * 12)
		else
			pos[id] = v((i - 1) * 6, 1.5, 0)
		end
		face[id] = v(0, 0, 1)
	end
	local function aimAt(from, to)
		local d = Vec.normalize(Vec.sub(pos[to], pos[from]))
		d = Vec.normalize(v(d.X, d.Y * 0.2, d.Z)) -- 수평에 가깝게
		face[from] = d
		return d
	end
	return c, core, pos, ps, order, counts, function() return total end, aimAt
end

local function run(c, from, to, dt)
	local t = from
	dt = dt or 0.05
	while t < to - 1e-9 do
		t = math.min(t + dt, to)
		c:update(t, dt)
	end
end

local function fill(core, id) for _ = 1, 5 do core.ultimate:addKill(id) end end
local function atk(dir, action, phase) return { action = action, aimDirection = dir, aimOrigin = v(0, 0, 0), clientTime = 0, phase = phase } end
local function sk(slot, dir, phase) return { slot = slot, aimDirection = dir, aimOrigin = v(0, 0, 0), clientTime = 0, phase = phase } end

-- 한 캐릭터의 전체 키트를 한 번씩 눌러 본다(충전형은 Press 만 보내 충전 상태를 남긴다). 오류가 나면 테스트 실패(pcall 로 감싸 원인 보고).
local function exercise(c, core, id, dir, t)
	local ok, err = pcall(function()
		fill(core, id)
		c:handleAttack(id, atk(dir, "Primary", "Press"), t)
		c:handleSkill(id, sk(1, dir, "Press"), t + 0.1)
		c:handleSkill(id, sk(2, dir, "Press"), t + 0.2)
		c:handleSkill(id, sk(3, dir, "Press"), t + 0.3)
		c:handleAttack(id, atk(dir, "Secondary"), t + 0.4)
		c:handleUltimate(id, { aimDirection = dir }, t + 0.5)
	end)
	return ok, err
end

-- 사망 후 남아 있으면 안 되는 충전형 입력(캐릭터별): 늦게 도착한 Release 는 항상 거부되어야 한다.
local LATE_RELEASE = {
	SWORD = function(c, id, d, t) return c:handleSkill(id, sk(2, d, "Release"), t) end,
	TIMEBOMB = function(c, id, d, t) return c:handleSkill(id, sk(2, d, "Release"), t) end,
	SUPERBALL = function(c, id, d, t) return c:handleAttack(id, atk(d, "Primary", "Release"), t) end,
	SLINGSHOT = function(c, id, d, t) return c:handleAttack(id, atk(d, "Primary", "Release"), t) end,
}

T.describe("5캐릭터 선택·HP", function()
	T.it("캐릭터별 최대 HP(SWORD 110 / PAINTBALL 95 / SUPERBALL 100 / TIMEBOMB 105 / SLINGSHOT 100)", function()
		for _, ch in CHARS do
			T.expectEqual(Characters[ch].maxHealth, HP[ch], ch)
			local c, core = setup({ a = ch })
			T.expectEqual(core.damage:getMaxHealth("a"), HP[ch], ch)
			T.expectEqual(core.damage:getHealth("a"), HP[ch], ch)
		end
	end)
	T.it("RemoteSpec 선택 목록 = 실제 5캐릭터(그 외 id 거부, GUNNER 없음)", function()
		for _, ch in CHARS do
			T.expect(RemoteSpec.validate("SelectCharacter", { characterId = ch }), ch)
		end
		for _, bad in { "GUNNER", "sword", "", "SLINGSHOT ", "NONE" } do
			T.expect(not RemoteSpec.validate("SelectCharacter", { characterId = bad }), bad)
		end
		local n = 0
		for _ in Characters do n += 1 end
		T.expectEqual(n, 5)
	end)
	T.it("25가지 전환(X→Y): 선택은 다음 리스폰부터, 리스폰 후 HP·캐릭터·HUD 가 새 캐릭터 기준", function()
		for _, from in CHARS do
			for _, to in CHARS do
				local c, core, pos = setup({ a = from, b = "SWORD" })
				local r = c:selectCharacter("a", to)
				T.expect(r == "pending" or r == "unchanged", from .. ">" .. to)
				T.expectEqual(c:getCharacterId("a"), from) -- 아직 적용 전
				c:handleDeath("a", 1)
				c:respawn("a", 5)
				T.expectEqual(c:getCharacterId("a"), to, from .. ">" .. to)
				T.expectEqual(core.damage:getMaxHealth("a"), HP[to], from .. ">" .. to)
				T.expectEqual(core.damage:getHealth("a"), HP[to], from .. ">" .. to)
				local snap = c:getHudSnapshot("a", 5.1)
				T.expectEqual(snap.characterId, to)
				T.expect(snap.alive)
				T.expectEqual(#snap.skills, 3)
				for i = 1, 3 do T.expect(snap.skills[i].implemented == true, to .. " skill" .. i) end
				T.expect(snap.ultimate.implemented, to)
				T.expect(snap.passive ~= nil and snap.passive.id ~= nil, to)
			end
		end
	end)
	T.it("선택 대기 중 게이지 이월 규칙(min(기존, 40))은 유지된다", function()
		local c, core = setup({ a = "SWORD" })
		for _ = 1, 5 do core.ultimate:addKill("a") end
		T.expectEqual(core.ultimate:getGauge("a"), Config.Ultimate.Max)
		c:selectCharacter("a", "SLINGSHOT")
		c:handleDeath("a", 1)
		c:respawn("a", 5)
		T.expectEqual(core.ultimate:getGauge("a"), math.min(Config.Ultimate.Max, Config.Ultimate.SwitchCarry or 40))
	end)
end)

T.describe("사망·리스폰·전환 중 남은 상태 초기화", function()
	T.it("5캐릭터 전부: 키트 전체를 누른 직후 사망 → 늦은 Release 거부, 이동속도·보호·HUD 정상", function()
		for _, ch in CHARS do
			local c, core, pos, ps, order, _, _, aimAt = setup({ a = ch, b = "SWORD" })
			local dir = aimAt("a", "b")
			local ok, err = exercise(c, core, "a", dir, 0)
			T.expect(ok, ch .. " exercise: " .. tostring(err))
			c:handleDeath("a", 1)
			if LATE_RELEASE[ch] then
				T.expect(not (LATE_RELEASE[ch](c, "a", dir, 1.1)), ch .. " 사망 중 Release 거부")
			end
			run(c, 1, 5)
			c:respawn("a", 5)
			if LATE_RELEASE[ch] then
				local before = core.damage:getHealth("b")
				local okRel = LATE_RELEASE[ch](c, "a", dir, 5.1)
				T.expect(not okRel, ch .. " 리스폰 후 지연 Release 거부")
				T.expect(c:isProtected("a", 5.2), ch .. " 거부된 Release 는 부활 보호를 풀지 않는다")
				T.expectEqual(core.damage:getHealth("b"), before)
			end
			T.expectEqual(c:getMoveSpeed("a", 5.2), Config.Movement.WalkSpeed, ch .. " 충전 감속 잔존 없음")
			local snap = c:getHudSnapshot("a", 5.2)
			T.expect(snap.alive and snap.ultimate.active == false, ch .. " 궁극기 활성 잔존 없음")
			if snap.extra then
				T.expect(snap.extra.chargeFrac == nil or snap.extra.chargeFrac == 0, ch .. " 충전 표시 잔존 없음")
			end
		end
	end)
	T.it("사망 후 60초: 투사체·볼·폭탄이 모두 정리된다(5캐릭터 × 사망 시점)", function()
		for _, ch in CHARS do
			local c, core, pos, ps, _, _, _, aimAt = setup({ a = ch, b = "SWORD" })
			local dir = aimAt("a", "b")
			exercise(c, core, "a", dir, 0)
			run(c, 0, 0.6)
			c:handleDeath("a", 0.6)
			run(c, 0.6, 61)
			T.expectEqual(ps:getActiveCount(), 0, ch .. " 투사체 잔존")
			local impl = c._impl[ch]
			if impl and impl.bombs then T.expectEqual(impl.bombs:count(), 0, ch .. " 폭탄 잔존") end
			if impl and impl.balls then T.expectEqual(impl.balls:count(), 0, ch .. " 볼 잔존") end
		end
	end)
	T.it("퇴장(removePlayer): 소유 객체·표식·충전이 제거되고 이후 업데이트에서 오류가 없다", function()
		for _, ch in CHARS do
			local c, core, pos, ps, _, _, _, aimAt = setup({ a = ch, b = ch == "SWORD" and "PAINTBALL" or "SWORD" })
			local dir = aimAt("a", "b")
			exercise(c, core, "a", dir, 0)
			run(c, 0, 0.6)
			c:removePlayer("a", 0.6)
			local ok, err = pcall(run, c, 0.6, 61)
			T.expect(ok, ch .. " 퇴장 후 update 오류: " .. tostring(err))
			T.expectEqual(ps:getActiveCount(), 0, ch .. " 투사체 잔존")
			local impl = c._impl[ch]
			if impl and impl.bombs then T.expectEqual(impl.bombs:count(), 0, ch) end
			if impl and impl.balls then T.expectEqual(impl.balls:count(), 0, ch) end
			-- 퇴장 후 지연 입력은 거부(오류 없이)
			T.expect(not (c:handleAttack("a", atk(dir, "Primary", "Release"), 62)))
			T.expect(not (c:handleSkill("a", sk(2, dir, "Release"), 62)))
		end
	end)
	T.it("캐릭터 전환 직후(다음 리스폰): 이전 캐릭터 모듈 상태가 새 캐릭터 입력에 영향 없다", function()
		for _, from in CHARS do
			local to = CHARS[(table.find(CHARS, from) % 5) + 1]
			local c, core, pos, ps, _, _, _, aimAt = setup({ a = from, b = "SWORD" })
			local dir = aimAt("a", "b")
			exercise(c, core, "a", dir, 0)
			c:selectCharacter("a", to)
			c:handleDeath("a", 1)
			run(c, 1, 5)
			c:respawn("a", 5)
			-- 새 캐릭터로 첫 입력이 정상 동작(충전형이면 Press 가 승인)
			local okPress = c:handleAttack("a", atk(dir, "Primary", "Press"), 5.5)
			T.expect(okPress ~= nil)
			T.expectEqual(c:getCharacterId("a"), to)
		end
	end)
	T.it("위조·지연 Remote: Press 없는 Release / 알 수 없는 슬롯 / 중복 Release 는 오류 없이 거부, 쿨타임·보호 불변", function()
		for _, ch in CHARS do
			local c, core, pos, _, _, _, _, aimAt = setup({ a = ch, b = "SWORD" })
			local dir = aimAt("a", "b")
			c:respawn("a", 0)
			for _ = 1, 3 do
				if LATE_RELEASE[ch] then
					local ok, why = LATE_RELEASE[ch](c, "a", dir, 0.5)
					T.expect(not ok, ch .. " Press 없는 Release 거부")
				end
				local okBadSlot = c:handleSkill("a", { slot = 4, aimDirection = dir, aimOrigin = v(0, 0, 0), clientTime = 0 }, 0.5)
				T.expect(not okBadSlot)
			end
			T.expect(c:isProtected("a", 0.6), ch .. " 거부된 요청은 부활 보호를 풀지 않는다")
			T.expect(core.cooldown:isReady("a", "primary", 0.6), ch .. " 거부는 쿨타임을 쓰지 않는다")
			T.expect(not RemoteSpec.validate("Skill", { slot = 4, aimDirection = dir, aimOrigin = v(0, 0, 0), clientTime = 0 }))
			T.expect(not RemoteSpec.validate("Attack", { action = "Primary", phase = "Hold", aimDirection = dir, aimOrigin = v(0, 0, 0), clientTime = 0 }))
		end
	end)
end)

T.describe("12인 동시 사용 시나리오", function()
	local function mix12()
		local ids = {}
		local assign = { "SWORD", "PAINTBALL", "SUPERBALL", "TIMEBOMB", "SLINGSHOT" }
		for i = 1, 12 do ids[string.format("p%02d", i)] = assign[(i - 1) % 5 + 1] end
		return ids
	end
	T.it("12명(5캐릭터 혼합)이 키트 전체를 반복 사용: 객체 상한 유지, 이벤트 수 상한, 오류 없음", function()
		local ids = mix12()
		local c, core, pos, ps, order, counts, totalFn, aimAt = setup(ids, { ring = true })
		local maxActive, maxBombs, maxBalls = 0, 0, 0
		local t = 0
		local ok, err = pcall(function()
			for round = 1, 6 do
				for i, id in order do
					local target = order[(i % #order) + 1]
					local dir = aimAt(id, target)
					fill(core, id)
					c:handleAttack(id, atk(dir, "Primary", "Press"), t)
					c:handleSkill(id, sk(1, dir, "Press"), t + 0.05)
					c:handleSkill(id, sk(2, dir, "Press"), t + 0.1)
					c:handleSkill(id, sk(3, dir, "Press"), t + 0.15)
					c:handleAttack(id, atk(dir, "Secondary"), t + 0.2)
				end
				run(c, t, t + 0.6)
				t += 0.6
				for i, id in order do
					local target = order[(i % #order) + 1]
					local dir = aimAt(id, target)
					c:handleAttack(id, atk(dir, "Primary", "Release"), t)
					c:handleSkill(id, sk(2, dir, "Release"), t)
					c:handleUltimate(id, { aimDirection = dir }, t + 0.05)
				end
				for _ = 1, 40 do
					run(c, t, t + 0.05)
					t += 0.05
					if ps:getActiveCount() > maxActive then maxActive = ps:getActiveCount() end
					for _, id in order do
						local impl = c._impl[ids[id]]
						if impl and impl.bombs then maxBombs = math.max(maxBombs, impl.bombs:count()) end
						if impl and impl.balls then maxBalls = math.max(maxBalls, impl.balls:count()) end
					end
				end
				-- 라운드마다 일부 사망·리스폰(전환 포함)
				for i, id in order do
					if i % 3 == round % 3 then
						c:selectCharacter(id, CHARS[(i + round) % 5 + 1])
						c:handleDeath(id, t)
					end
				end
				run(c, t, t + 4)
				t += 4
				for i, id in order do
					if not core.damage:isAlive(id) or c:getHudSnapshot(id, t).alive == false then
						c:respawn(id, t)
						ids[id] = c:getCharacterId(id)
						core.damage:setMaxHealth(id, HP[ids[id]], true)
					end
				end
			end
		end)
		T.expect(ok, "12인 시나리오 오류: " .. tostring(err))
		T.expect(maxActive <= Config.Projectile.MaxActiveTotal, "투사체 총 상한")
		T.expect(maxBombs <= 12 * 24 and maxBalls <= 12 * 12, "폭탄/볼 소유자 상한")
		local total = totalFn()
		print(string.format("[12인] 시뮬레이션 %.0fs, 이벤트 %d건(초당 %.1f), 최대 투사체 %d, 최대 폭탄 %d, 최대 볼 %d", t, total, total / t, maxActive, maxBombs, maxBalls))
		T.expect(total / t < 400, "초당 이벤트 수 상한(임시 400)")
		local parts = {}
		for k, n in counts do table.insert(parts, k .. "=" .. n) end
		table.sort(parts)
		print("[12인] 이벤트 종류별: " .. table.concat(parts, " "))
		-- 시나리오가 실제로 5캐릭터 전부의 행동을 승인시켰는지(거부만 쌓인 무의미한 통과 방지)
		for _, k in { "Swing", "SwordSkill", "Spawned", "CharSkill", "BallSpawn", "BombSpawn", "Ultimate", "Died", "Respawned" } do
			T.expect((counts[k] or 0) > 0, "승인된 행동 없음: " .. k)
		end
		-- 정리: 60초 휴지 후 모든 객체가 사라진다
		for _, id in order do
			if c:getHudSnapshot(id, t).alive then c:handleDeath(id, t) end
		end
		run(c, t, t + 60)
		T.expectEqual(ps:getActiveCount(), 0, "투사체 정리")
		for _, id in order do
			local impl = c._impl[c:getCharacterId(id)]
			if impl and impl.bombs then T.expectEqual(impl.bombs:count(), 0) end
			if impl and impl.balls then T.expectEqual(impl.balls:count(), 0) end
		end
	end)
	T.it("12명 전원 퇴장: 상태 테이블이 비워지고 이후 update 는 빠르게 끝난다", function()
		local ids = mix12()
		local c, core, pos, ps, order, _, _, aimAt = setup(ids, { ring = true })
		for i, id in order do
			local dir = aimAt(id, order[(i % #order) + 1])
			exercise(c, core, id, dir, 0)
		end
		run(c, 0, 0.5)
		for _, id in order do c:removePlayer(id, 0.5) end
		local ok, err = pcall(run, c, 0.5, 70)
		T.expect(ok, tostring(err))
		T.expectEqual(ps:getActiveCount(), 0)
		for _, id in order do T.expect(c:getCharacterId(id) == nil) end
		local sl = c._impl.SLINGSHOT
		for _, id in order do
			T.expect(sl._charge[id] == nil and sl._ult[id] == nil and sl._marks[id] == nil, "SLINGSHOT 상태 잔존 " .. id)
		end
		T.expectEqual(#sl._shots, 0)
		local n = 0
		for _ in sl._tags do n += 1 end
		T.expectEqual(n, 0, "SLINGSHOT 탄 태그 잔존")
	end)
end)

return true
