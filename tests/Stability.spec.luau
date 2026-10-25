--!nonstrict
-- 안정화 회귀: ForceField 충돌 방지(스폰 패드 규격), 공격 행동 보호 해제 공통화(ActionPolicy/approveAction),
-- 지연 공격(설치·기폭) 악용 방지, 로드 타임아웃/중복 방지. Roblox 의 실제 ForceField·SpawnLocation 동작은 Studio 미검증.
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Core = Env.server("CombatCore")
local ProjectileService = Env.server("ProjectileService")
local Controller = Env.server("CharacterController")
local Scheduler = Env.server("RespawnScheduler")
local PadSpec = Env.server("SpawnPadSpec")
local Policy = Env.server("ActionPolicy")
local Characters = Env.shared("Data/Characters")
local Config = Env.shared("Config")

local v = H.v
local fwd = v(0, 0, 1)

local function setup(chars, opts)
	local core = Core.new()
	local pos = {}
	local world = H.fakeWorld({})
	local function targets()
		local list = {}
		for id in chars do
			table.insert(list, { id = id, pos = pos[id], radius = Config.Combat.HitRadius, alive = core.damage:isAlive(id) })
		end
		return list
	end
	local ps = ProjectileService.new({ damage = core.damage, targets = targets, world = world })
	local c = Controller.new({
		core = core, projectiles = ps, targets = targets, world = world, allowMockUltimate = opts and opts.mockUltimate or false,
		getPose = function(id) return { pos = pos[id], forward = fwd, airborne = false } end,
	})
	local events = {}
	c:onFeedback(function(e) table.insert(events, e) end)
	for id, ch in chars do
		c:addPlayer(id, ch)
		pos[id] = v(0, 0, 0)
	end
	return c, core, pos, events
end

local function ended(events)
	local n = 0
	for _, e in events do if e.type == "ProtectionEnded" then n += 1 end end
	return n
end

local function hitReq(attacker, target, id)
	return { attackerId = attacker, targetId = target, attackId = id, amount = 10, kind = "Melee" }
end

T.describe("스폰 패드 규격 / RespawnLocation 유효성 (ForceField 방지)", function()
	local good = { isSpawnLocation = true, inWorkspace = true, enabled = true, neutral = true, duration = 0 }
	T.it("규격 값: Duration=0 명시, Neutral, Enabled, 팀 변경 없음", function()
		T.expectEqual(PadSpec.Props.Duration, 0)
		T.expectEqual(PadSpec.Props.Neutral, true)
		T.expectEqual(PadSpec.Props.Enabled, true)
		T.expectEqual(PadSpec.Props.AllowTeamChangeOnTouch, false)
		T.expectEqual(PadSpec.Props.CanCollide, false)
	end)
	T.it("유효한 패드는 통과", function()
		local ok, problems = PadSpec.validate(good)
		T.expect(ok and #problems == 0)
	end)
	T.it("각 결함을 개별 탐지: SpawnLocation 아님 / Workspace 밖 / Disabled / Neutral 아님 / Duration≠0 / Duration 없음", function()
		local function with(k, val)
			local t = H.clone(good)
			t[k] = val
			return t
		end
		for k, val in { isSpawnLocation = false, inWorkspace = false, enabled = false, neutral = false, duration = 10 } do
			local ok, problems = PadSpec.validate(with(k, val))
			T.expect(not ok and #problems == 1, k)
		end
		T.expect(not (PadSpec.validate(with("duration", nil))))
		T.expect(not (PadSpec.validate(nil)))
		T.expect(not (PadSpec.validate({})))
	end)
	T.it("기본 ForceField 시간(예: 10)이 남아 있으면 검증 실패 → 호출부가 규격을 다시 적용", function()
				local bad = H.clone(good)
		bad.duration = 10
		local ok2, p2 = PadSpec.validate(bad)
		T.expect(not ok2 and string.find(p2[1], "Duration", 1, true) ~= nil)
	end)
end)

T.describe("보호 경계: 서버 보호 종료 후 정상 피해 / 보호 중 거부 (ForceField 와 무관)", function()
	T.it("보호 종료 직전(1.999초)은 거부, 종료 시각(2.0초)부터 피해 적용", function()
		local c, core = setup({ p1 = "SWORD", p2 = "SWORD" })
		c:respawn("p2", 10)
		local r1 = core.damage:applyDamage(hitReq("p1", "p2", 1), 11.999)
		T.expect(not r1.applied and r1.reason == "spawn_protected")
		local r2 = core.damage:applyDamage(hitReq("p1", "p2", 2), 12.0)
		T.expect(r2.applied)
		T.expectEqual(core.damage:getHealth("p2"), 90)
	end)
	T.it("보호는 2초에서 연장되지 않는다: 만료 이벤트 이후 update 를 반복해도, 외부 스폰 설정과 무관하게 피해 적용", function()
		local c, core = setup({ p1 = "SWORD", p2 = "SWORD" })
		c:respawn("p2", 0)
		for t = 0.5, 6, 0.5 do c:update(t, 0.5) end
		T.expect(not c:isProtected("p2", 2.0))
		T.expect(not c:isProtected("p2", 5))
		T.expect(core.damage:applyDamage(hitReq("p1", "p2", 1), 5).applied)
	end)
	T.it("보호 중 거부 → 만료 직후 같은 공격자의 새 공격은 허용(거부가 기록·쿨다운을 남기지 않음)", function()
		local c, core = setup({ p1 = "SWORD", p2 = "SWORD" })
		c:respawn("p2", 0)
		for i = 1, 5 do
			T.expect(not core.damage:applyDamage(hitReq("p1", "p2", i), 0.2 * i).applied)
		end
		T.expect(core.damage:applyDamage(hitReq("p1", "p2", 6), 2.0).applied)
	end)
	T.it("보호가 공격 시작으로 해제된 직후에도 정상 피해", function()
		local c, core, pos = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		c:respawn("p1", 0)
		T.expect(not core.damage:applyDamage(hitReq("p2", "p1", 1), 0.1).applied)
		T.expect((c:handleAttack("p1", { action = "Primary", aimDirection = fwd }, 0.2)))
		T.expect(core.damage:applyDamage(hitReq("p2", "p1", 2), 0.3).applied)
	end)
end)

T.describe("ActionPolicy: 공격 행동 분류 (안전한 기본값)", function()
	T.it("실제 캐릭터 데이터: 기본 공격·궁극기는 공격, 패링은 비공격", function()
		T.expect(Policy.isOffensive(Characters.SWORD.primary))
		T.expect(Policy.isOffensive(Characters.PAINTBALL.primary))
		T.expect(not Policy.isOffensive(Characters.SWORD.secondary))
		T.expect(Policy.isOffensive({ kind = "Ultimate" }))
		T.expect(Policy.isOffensive(Characters.SWORD.ultimate))
	end)
	T.it("공격형 일반 스킬·공격형 보조 기술·지연 공격(설치·기폭)은 공격", function()
		for _, def in {
			{ kind = "Skill", damage = 12 }, { kind = "Attack" }, { kind = "Projectile", projectile = {} },
			{ kind = "Beam", beam = {} }, { kind = "Explosion", explosion = {} },
			{ kind = "Place", placed = { fuseTime = 3 } }, { kind = "Placed" }, { kind = "Detonate" },
			{ kind = "Detonate", detonate = true }, { kind = "Melee", damage = 5 },
		} do
			T.expect(Policy.isOffensive(def), tostring(def.kind))
		end
	end)
	T.it("판정 없는 이동기·패링·회피·달리기·유틸은 비공격", function()
		for _, kind in { "Movement", "Parry", "Dodge", "Run", "Utility" } do
			T.expect(not Policy.isOffensive({ kind = kind }), kind)
		end
		T.expect(not Policy.isOffensive({ kind = "Movement", distance = 20, duration = 0.3 })) -- Lunge 류의 순수 이동 부분
	end)
	T.it("이동기에 피해·효과·히트박스가 있으면 공격 (Lunge/BlastJump/Bounce Dash 가 판정을 가질 때)", function()
		for _, f in { "damage", "effects", "knockback", "hitbox", "explosion", "stagger", "projectile" } do
			local def = { kind = "Movement" }
			def[f] = f == "damage" and 10 or {}
			T.expect(Policy.isOffensive(def), f)
		end
	end)
	T.it("데이터가 offensive=false 라고 선언해도 판정 필드가 있으면 우회 불가", function()
		T.expect(Policy.isOffensive({ kind = "Skill", offensive = false, damage = 10 }))
		T.expect(Policy.isOffensive({ kind = "Detonate", offensive = false }))
		T.expect(Policy.isOffensive({ kind = "Place", offensive = false, placed = {} }))
	end)
	T.it("알 수 없는 종류·kind 없음·잘못된 입력은 공격으로 취급(보호 악용 방지)", function()
		T.expect(Policy.isOffensive({ kind = "SomethingNew" }))
		T.expect(Policy.isOffensive({}))
		T.expect(Policy.isOffensive(nil))
		T.expect(Policy.isOffensive("Movement"))
		T.expect(Policy.isOffensive(42))
	end)
end)

T.describe("공통 공격 시작 처리 (approveAction)", function()
	T.it("공격형 행동 승인 시 보호 즉시 해제, 이벤트 1회, 이후 중복 호출은 무시", function()
		local c, _, _, events = setup({ p1 = "SWORD" })
		c:respawn("p1", 0)
		T.expect(c:approveAction("p1", { kind = "Skill", damage = 8 }, 0.3))
		T.expect(not c:isProtected("p1", 0.3))
		T.expect(not c:approveAction("p1", { kind = "Skill", damage = 8 }, 0.4))
		T.expectEqual(ended(events), 1)
	end)
	T.it("피해가 적중하지 않아도(허공) 승인된 공격 시작이면 해제", function()
		local c = setup({ p1 = "SWORD" }) -- 대상 없음
		c:respawn("p1", 0)
		local ok, info = c:handleAttack("p1", { action = "Primary", aimDirection = fwd }, 0.2)
		T.expect(ok and #info.hits == 0)
		T.expect(not c:isProtected("p1", 0.2))
	end)
	T.it("비공격 행동(패링 정의·순수 이동기)은 보호 유지", function()
		local c = setup({ p1 = "SWORD" })
		c:respawn("p1", 0)
		T.expect(not c:approveAction("p1", Characters.SWORD.secondary, 0.2))
		T.expect(not c:approveAction("p1", { kind = "Movement" }, 0.3))
		T.expect(c:isProtected("p1", 0.4))
	end)
	T.it("LMB 쿨타임으로 거부된 요청은 보호를 해제하지 않는다", function()
		local c, core = setup({ p1 = "SWORD" })
		c:respawn("p1", 0)
		T.expect((core.cooldown:tryUse("p1", "primary", 5, 0))) -- 쿨타임 점유
		local ok, why = c:handleAttack("p1", { action = "Primary", aimDirection = fwd }, 0.5)
		T.expect(not ok and why == "on_cooldown")
		T.expect(c:isProtected("p1", 0.5))
	end)
	T.it("탄약 부족·재장전 중 거부는 보호를 해제하지 않는다", function()
		local c = setup({ p1 = "PAINTBALL" })
		c:respawn("p1", 0)
		c._p["p1"].ammo = 0
		local ok, why = c:handleAttack("p1", { action = "Primary", aimDirection = fwd }, 0.5)
		T.expect(not ok and why == "no_ammo")
		T.expect(c:isProtected("p1", 0.5))
		local ok2, why2 = c:handleAttack("p1", { action = "Primary", aimDirection = fwd }, 0.7)
		T.expect(not ok2 and why2 == "reloading")
		T.expect(c:isProtected("p1", 0.7))
	end)
	T.it("RMB 패링은 유지 / (PAINTBALL) 스킬 1·2·3 거부(미구현)·궁극기 거부는 유지", function()
		local c = setup({ p1 = "SWORD", p2 = "PAINTBALL" })
		c:respawn("p1", 0)
		c:respawn("p2", 0)
		T.expect((c:handleAttack("p1", { action = "Secondary", aimDirection = fwd }, 0.2)))
		T.expect(c:isProtected("p1", 0.5)) -- SWORD 패링은 비공격
		for slot = 1, 3 do T.expect(not (c:handleSkill("p2", { slot = slot }, 0.3))) end
		T.expect(not (c:handleUltimate("p2", {}, 0.4)))
		T.expect(c:isProtected("p2", 0.5))
	end)
	T.it("궁극기 승인 시 해제(모의 궁극기, 게이지 100)", function()
		local c, core = setup({ p1 = "SWORD" }, { mockUltimate = true })
		c:respawn("p1", 0)
		for _ = 1, 5 do core.ultimate:addKill("p1") end
		T.expectEqual(core.ultimate:getGauge("p1"), 100)
		T.expect((c:handleUltimate("p1", {}, 0.5)))
		T.expect(not c:isProtected("p1", 0.5))
	end)
	T.it("사망/미등록 플레이어의 승인 요청은 무시", function()
		local c, core = setup({ p1 = "SWORD" })
		c:respawn("p1", 0)
		core.damage:forceKill("p1", 0.1)
		T.expect(not c:approveAction("p1", { kind = "Skill", damage = 1 }, 0.2))
		T.expect(not c:approveAction("ghost", { kind = "Skill", damage = 1 }, 0.2))
	end)
end)

T.describe("지연 공격(설치·원격 기폭) 보호 악용 방지", function()
	T.it("설치 승인은 공격 시작 → 보호 해제", function()
		local c = setup({ p1 = "SWORD" })
		c:respawn("p1", 0)
		T.expect(c:approveAction("p1", { kind = "Place", placed = { fuseTime = 5 } }, 0.3))
		T.expect(not c:isProtected("p1", 0.3))
	end)
	T.it("설치 후 사망·재부활(새 보호)한 상태에서 원격 기폭 명령을 내리면 그 시점에 보호가 해제된다", function()
		local c, core = setup({ p1 = "SWORD" })
		c:respawn("p1", 0)
		c:approveAction("p1", { kind = "Place", placed = {} }, 0.3)
		core.damage:forceKill("p1", 1)
		c:respawn("p1", 5)
		T.expect(c:isProtected("p1", 5.5))
		T.expect(c:approveAction("p1", { kind = "Detonate", offensive = false }, 5.5)) -- offensive=false 선언 무시
		T.expect(not c:isProtected("p1", 5.5))
	end)
	T.it("타이머/조건으로 스스로 터지는 기존 설치물은 소유자 행동이 아니므로 승인 처리 없이 보호를 해제하지 않는다(문서화된 동작)", function()
		local c = setup({ p1 = "SWORD" })
		c:respawn("p1", 0)
		c:update(1.0, 1.0) -- 소유자 행동 없이 시간만 경과
		T.expect(c:isProtected("p1", 1.0))
	end)
end)

T.describe("캐릭터 로드: 타임아웃·중복·재시도 (RespawnScheduler)", function()
	T.it("호출이 반환했는데 CharacterAdded 가 없으면 타임아웃 후 실패 처리, 재시도는 1초 뒤", function()
		local logs = {}
		local s = Scheduler.new({ onLog = function(k) table.insert(logs, k) end })
		s:onDeath("p1", 0)
		T.expectEqual(#s:due(4), 1)
		T.expect(s:finishCall("p1", s:getAttempt("p1"), true, 4.5)) -- 호출은 정상 반환
		T.expectEqual(#s:due(4.5 + Config.Match.LoadTimeoutSeconds - 1), 0)
		T.expectEqual(#s:due(4.5 + Config.Match.LoadTimeoutSeconds), 0) -- 타임아웃 처리, 재시도는 1초 뒤
		T.expectEqual(logs[1], "respawn_load_timeout")
		T.expectEqual(#s:due(4.5 + Config.Match.LoadTimeoutSeconds + 1), 1)
	end)
	T.it("반환 후 타임아웃이 반복돼도 재시도 상한 후 포기(영구 반복 없음)", function()
		local s = Scheduler.new()
		s:onDeath("p1", 0)
		local t, loads = 4, 0
		for _ = 1, 400 do
			local d = s:due(t)
			loads += #d
			if #d > 0 then s:finishCall("p1", s:getAttempt("p1"), true, t) end
			t += 1
		end
		T.expectEqual(loads, Config.Match.MaxLoadAttempts)
	end)
	T.it("성공 응답(onSpawned) 후 늦게 도착한 타임아웃 검사는 영향 없음", function()
		local s = Scheduler.new()
		s:onDeath("p1", 0)
		s:due(4)
		s:onSpawned("p1")
		s:finishCall("p1", s:getAttempt("p1"), true, 5)
		T.expectEqual(#s:due(100), 0)
	end)
end)

T.describe("로드 경쟁 상태: 시도 ID · 겹침 금지 · 오래된 완료 무시", function()
	T.it("호출이 반환하지 않으면 타임아웃이 지나도 새 로드를 시작하지 않는다(타임아웃 플래그 초기화는 수정이 아님)", function()
		local logs = {}
		local s = Scheduler.new({ onLog = function(k) table.insert(logs, k) end })
		s:onDeath("p1", 0)
		T.expectEqual(#s:due(4), 1)
		local calls = 1
		for t = 5, 4 + Config.Match.LoadHangSeconds - 1 do
			calls += #s:due(t)
		end
		T.expectEqual(calls, 1)
		T.expect(s:isInFlight("p1"))
		local slow = false
		for _, k in logs do if k == "respawn_load_slow" then slow = true end end
		T.expect(slow)
	end)
	T.it("오래 걸린 호출이 늦게 반환: 같은 시도면 반영, 반환 전에는 재호출 없음", function()
		local s = Scheduler.new()
		s:onDeath("p1", 0)
		s:due(4)
		local a1 = s:getAttempt("p1")
		T.expectEqual(#s:due(20), 0) -- 타임아웃 지난 뒤에도 겹치지 않음
		T.expect(s:finishCall("p1", a1, false, 21)) -- 늦은 실패 반환
		T.expect(not s:isInFlight("p1"))
		T.expectEqual(#s:due(22), 1) -- 이제야 재시도
		T.expect(s:getAttempt("p1") ~= a1)
	end)
	T.it("오래된 시도 ID 의 완료는 현재 시도 상태를 바꾸지 않는다", function()
		local s = Scheduler.new()
		s:onDeath("p1", 0)
		s:due(4)
		local a1 = s:getAttempt("p1")
		s:finishCall("p1", a1, false, 5) -- 시도 1 실패
		s:due(6) -- 시도 2 시작
		local a2 = s:getAttempt("p1")
		T.expect(a2 ~= a1)
		T.expect(not s:finishCall("p1", a1, false, 7)) -- 시도 1 의 중복/늦은 완료
		T.expect(s:isInFlight("p1"))
		T.expectEqual(s:getAttempt("p1"), a2)
		T.expect(s:finishCall("p1", a2, true, 8))
	end)
	T.it("중복 finishCall 은 두 번째부터 무시", function()
		local s = Scheduler.new()
		s:onDeath("p1", 0)
		s:due(4)
		local a = s:getAttempt("p1")
		T.expect(s:finishCall("p1", a, false, 5))
		T.expect(not s:finishCall("p1", a, false, 5))
	end)
	T.it("CharacterAdded 가 호출 반환보다 먼저 와도(onSpawned 선행) 호출이 끝나기 전까지 새 호출을 막고, 끝나면 재시도 없음", function()
		local s = Scheduler.new()
		s:onDeath("p1", 0)
		s:due(4)
		local a = s:getAttempt("p1")
		T.expect(s:onSpawned("p1")) -- 예상된 스폰
		T.expect(s:isInFlight("p1"))
		s:onDeath("p1", 5) -- 곧바로 다시 사망
		T.expectEqual(#s:due(9.5), 0) -- 호출이 아직 반환 전: 겹침 없음
		s:finishCall("p1", a, true, 10)
		T.expectEqual(#s:due(10), 1) -- 반환 후 대기 중이던 부활이 진행
	end)
	T.it("늦은 캐릭터(타임아웃 후 도착)도 재시도를 취소하고 상태를 정리한다", function()
		local s = Scheduler.new()
		s:onDeath("p1", 0)
		s:due(4)
		s:finishCall("p1", s:getAttempt("p1"), true, 5)
		s:due(5 + Config.Match.LoadTimeoutSeconds) -- 타임아웃 → 재시도 예약
		T.expect(s:getDueAt("p1") ~= nil)
		s:onSpawned("p1") -- 늦게 도착
		T.expectEqual(s:getDueAt("p1"), nil)
		T.expectEqual(#s:due(100), 0)
	end)
	T.it("퇴장(remove) 후 도착한 완료는 무시, 재입장하면 새 상태(시도 ID 불일치)", function()
		local s = Scheduler.new()
		s:onDeath("p1", 0)
		s:due(4)
		local a = s:getAttempt("p1")
		s:remove("p1")
		T.expect(not s:finishCall("p1", a, true, 5))
		T.expect(not s:onSpawned("p1"))
		s:register("p1")
		s:requestInitial("p1", 6)
		T.expectEqual(#s:due(6), 1)
		T.expect(not s:finishCall("p1", a, false, 7)) -- 이전 입장의 시도 ID
		T.expect(s:isInFlight("p1"))
	end)
	T.it("hung(60초 무응답): 재시도 중단 로그, 이후 캐릭터가 도착하면 정상 복구", function()
		local logs = {}
		local s = Scheduler.new({ onLog = function(k) table.insert(logs, k) end })
		s:onDeath("p1", 0)
		s:due(4)
		s:due(4 + Config.Match.LoadHangSeconds)
		local hung = false
		for _, k in logs do if k == "respawn_load_hung" then hung = true end end
		T.expect(hung)
		T.expect(s:isHung("p1")) -- 실패 상태 + 진단 로그, 호출은 1회뿐
		T.expectEqual(#s:due(500), 0)
		T.expect(s:onSpawned("p1")) -- 엔진이 나중에 캐릭터를 만들었다
		T.expect(s:onDeath("p1", 501)) -- 다음 사망은 정상 예약
	end)
	T.it("같은 틱에 여러 플레이어: 시도 ID 는 전역 고유", function()
		local s = Scheduler.new()
		for i = 1, 5 do s:onDeath("p" .. i, 0) end
		s:due(4)
		local seen = {}
		for i = 1, 5 do
			local a = s:getAttempt("p" .. i)
			T.expect(not seen[a])
			seen[a] = true
		end
	end)
end)

T.describe("CharacterAdded 게이트: 중복 · 교체 · 퇴장", function()
	local Gate = Env.server("CharacterSpawnGate")
	T.it("같은 모델의 중복 CharacterAdded 는 두 번째부터 무시", function()
		local g = Gate.new()
		local m = {}
		T.expect(g:begin("p1", m) ~= nil)
		T.expectEqual(g:begin("p1", m), nil)
	end)
	T.it("더 새로운 스폰이 시작되면 이전 처리(yield 중)는 stale 이라 현재 캐릭터를 덮지 못한다", function()
		local g = Gate.new()
		local m1, m2 = {}, {}
		local e1 = g:begin("p1", m1)
		local e2 = g:begin("p1", m2)
		T.expect(g:isStale("p1", e1))
		T.expect(not g:commit("p1", e1, m1))
		T.expect(g:commit("p1", e2, m2))
		T.expectEqual(g:getCurrent("p1"), m2)
	end)
	T.it("오래된 모델의 늦은 Died 는 무시, 현재 모델의 Died 만 인정", function()
		local g = Gate.new()
		local m1, m2 = {}, {}
		local e1 = g:begin("p1", m1); g:commit("p1", e1, m1)
		T.expect(g:acceptsDeath("p1", e1, m1))
		local e2 = g:begin("p1", m2); g:commit("p1", e2, m2)
		T.expect(not g:acceptsDeath("p1", e1, m1))
		T.expect(g:acceptsDeath("p1", e2, m2))
	end)
	T.it("퇴장 중 완료: remove 후에는 진행 중이던 처리가 모두 stale, 사망도 불인정", function()
		local g = Gate.new()
		local m = {}
		local e = g:begin("p1", m)
		g:remove("p1")
		T.expect(g:isStale("p1", e))
		T.expect(not g:commit("p1", e, m))
		T.expect(not g:acceptsDeath("p1", e, m))
	end)
	T.it("플레이어별로 독립", function()
		local g = Gate.new()
		local ea = g:begin("a", {})
		g:begin("b", {})
		T.expect(not g:isStale("a", ea))
	end)
end)

T.describe("ForceField 제거 범위 축소 (의도한 보호 효과는 보존)", function()
	local base = { isForceField = true, managed = false, name = "ForceField", hasAttributes = false, tagged = false, sinceSpawn = 0.1, windowSeconds = 2 }
	local function with(over)
		local t = {}
		for k, v in base do t[k] = v end
		for k, v in over do t[k] = v end
		return t
	end
	T.it("스폰 직후 창 안 + 기본 이름 + 속성·태그 없음 + 비관리: 엔진 스폰 ForceField 로 식별 → 제거", function()
		T.expectEqual(PadSpec.classifyForceField(base), "strip")
	end)
	T.it("서버 관리 표시(RoBattlesManaged) 는 보존", function()
		T.expectEqual(PadSpec.classifyForceField(with({ managed = true })), "keep")
	end)
	T.it("창이 끝난 뒤의 ForceField 는 보존", function()
		T.expectEqual(PadSpec.classifyForceField(with({ sinceSpawn = 2.5 })), "keep")
	end)
	T.it("식별 불가(다른 이름·속성·태그): 제거하지 않고 보고만", function()
		T.expectEqual(PadSpec.classifyForceField(with({ name = "SkillShield" })), "report")
		T.expectEqual(PadSpec.classifyForceField(with({ hasAttributes = true })), "report")
		T.expectEqual(PadSpec.classifyForceField(with({ tagged = true })), "report")
	end)
	T.it("ForceField 가 아니거나 시간 정보가 없으면 대상 아님", function()
		T.expectEqual(PadSpec.classifyForceField(with({ isForceField = false })), "keep")
		local noTime = with({})
		noTime.sinceSpawn = nil
		T.expectEqual(PadSpec.classifyForceField(noTime), "keep")
	end)
	T.it("shouldStripForceField 는 strip 일 때만 true", function()
		T.expect(PadSpec.shouldStripForceField(base))
		T.expect(not PadSpec.shouldStripForceField(with({ name = "X" })))
	end)
end)
return true
