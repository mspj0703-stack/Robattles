--!nonstrict
-- 5캐릭터(SWORD/PAINTBALL/SLINGSHOT/SUPERBALL/TIMEBOMB) 애니메이션 수명주기 테스트: 사망·리스폰·캐릭터 변경·경기 종료/재시작·충전 중단·
-- 궁극기 End 누락·반복 입력·12인 동시 환경(상태/트랙 중복). 순수 로직만 검증한다.
-- Roblox 의존부(SwordAnimator/CharacterAnimator 의 연결 해제, Motor6D, Animator)는 CLI 로 확인할 수 없어 Studio 검증이 필요하다.
-- ⚠ Luau 실행기가 있는 환경에서만 실행된다. 실행하지 못했다면 "통과"로 보고하지 않는다.
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local Math = Env.client("Logic/MotionMath")
local SwordState = Env.client("Logic/SwordAnimState")
local CharState = Env.client("Logic/CharacterAnimState")
local TrackBook = Env.client("Logic/TrackBook")
local MatchReset = Env.client("Logic/MatchResetModel")
local SwordData = Env.shared("Data/SwordMotions")
local Registry = Env.shared("Data/CharacterMotionRegistry")

local IDS = { "SWORD", "PAINTBALL", "SLINGSHOT", "SUPERBALL", "TIMEBOMB" }

local function make(cid, opts)
	if cid == "SWORD" then
		return SwordState.new(SwordData, opts)
	end
	return CharState.new(cid, Registry.Data[cid], opts)
end
local function cs(cue, extra)
	local e = { type = "CharSkill", cue = cue, playerId = 1 }
	for k, v in extra or {} do
		e[k] = v
	end
	return e
end
local function ss(skill, phase, extra)
	local e = { type = "SwordSkill", skill = skill, phase = phase, playerId = 1 }
	for k, v in extra or {} do
		e[k] = v
	end
	return e
end

-- 캐릭터별 대표 입력. basic = 기본/스킬 모션 1개, ultStart/ultEnd = 장시간 궁극기, chargeStart/chargeEnd = 충전형 입력(없으면 nil)
local SCEN = {
	SWORD = {
		basic = { type = "Swing", step = 1, playerId = 1 },
		ultStart = ss("BladeStorm", "Start"), ultEnd = ss("BladeStorm", "End"),
		chargeStart = ss("Lunge", "Charge", { chargeSeconds = 1.0 }), chargeCancel = ss("Lunge", "Cancel"),
	},
	PAINTBALL = {
		basic = cs("paint.burst"),
		ultStart = cs("paint.ult.windup", { skill = "ColorBreak", phase = "Windup", windup = 0.8 }),
		ultEnd = cs("paint.ult.end", { skill = "ColorBreak", phase = "End" }),
	},
	SLINGSHOT = {
		basic = cs("sling.triple"),
		ultStart = cs("sling.ult.windup", { skill = "Bullseye", phase = "Windup", windup = 0.7 }),
		ultEnd = cs("sling.ult.end", { skill = "Bullseye", phase = "End" }),
		chargeStart = cs("sling.charge", { chargeSeconds = 1.0 }), chargeRelease = cs("sling.shot"),
	},
	SUPERBALL = {
		basic = cs("ball.rapid"),
		ultStart = cs("ball.cyclone.start", { skill = "BallCyclone", phase = "Start", duration = 12 }),
		ultEnd = cs("ball.cyclone.end", { skill = "BallCyclone", phase = "End" }),
		chargeStart = cs("ball.charge", { chargeSeconds = 1.0 }), chargeRelease = cs("ball.throw"),
	},
	TIMEBOMB = {
		basic = cs("bomb.cluster"),
		ultStart = cs("bomb.bigbang", { skill = "BigBang", phase = "Throw" }),
	},
}

local function step(s, from, to, dt)
	local t = from
	while t < to do
		t += dt
		s:update(t)
	end
	return t
end
local function idle(s)
	return s:snapshot().actionId == nil and not s:snapshot().storm and not s:snapshot().dead
end
local function kinds(entries, kind)
	local n = 0
	for _, e in entries do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

T.describe("5캐릭터 애니메이션: 사망·리스폰·캐릭터 변경", function()
	for _, cid in IDS do
		T.it(cid .. ": 사망 → 전부 정리·이벤트 무시, 리스폰 → 깨끗한 Idle", function()
			local sc = SCEN[cid]
			local s = make(cid)
			s:onEvent(sc.ultStart, 0)
			s:onEvent(sc.basic, 0.1)
			s:onEvent({ type = "Died", playerId = 1 }, 0.2)
			local snap = s:snapshot()
			T.expect(snap.dead and snap.actionId == nil and not snap.storm)
			local pose, info = s:update(0.3)
			T.expect(pose == nil and info.dead)
			s:onEvent(sc.basic, 0.4)
			s:onEvent(sc.ultStart, 0.5)
			T.expect(s:snapshot().actionId == nil, "사망 중 이벤트 무시")
			T.expect(kinds(s:drain(), "stopAll") >= 1, "에셋 트랙 정리 로그")
			s:onEvent({ type = "Respawned", playerId = 1 }, 1.0)
			T.expect(idle(s))
			s:onEvent(sc.basic, 1.1)
			T.expect(s:snapshot().actionId ~= nil, "리스폰 뒤 정상 재생")
		end)
		T.it(cid .. ": 캐릭터 변경(reset) → 모션·잠금·대기 상태 정리 후 새 상태기계는 독립", function()
			local sc = SCEN[cid]
			local s = make(cid)
			s:onEvent(sc.ultStart, 0)
			s:reset()
			T.expect(idle(s))
			T.expect(kinds(s:drain(), "stopAll") >= 1)
			for _, other in IDS do
				local fresh = make(other)
				T.expect(idle(fresh), other .. " 새 상태기계가 깨끗하지 않음")
			end
		end)
	end
	T.it("SWORD 상태기계는 baseSampler 없이도 이전과 같은 기본 자세(Idle)를 만든다(호환)", function()
		local s = make("SWORD")
		local pose = s:update(0)
		T.expectNear(pose.Root.ry, -8, 1e-6)
		T.expectNear(pose.RArm.rx, 38, 1e-6)
		-- 캐릭터 상태기계는 SWORD 의 Idle 자세를 쓰지 않는다(서로 다른 인스턴스·다른 base)
		local c = make("PAINTBALL")
		T.expect(math.abs(c:update(0).RArm.rx - 38) > 5)
		-- 한쪽의 상태가 다른 쪽에 새지 않는다
		c:onEvent(SCEN.PAINTBALL.ultStart, 0.1)
		T.expect(s:snapshot().actionId == nil and not s:snapshot().storm)
	end)
end)

T.describe("5캐릭터 애니메이션: 경기 종료·재시작, 충전 중단, 궁극기 End 누락", function()
	for _, cid in IDS do
		T.it(cid .. ": 경기 종료(reset) 도중 궁극기 → 즉시 Idle, 곧바로 일반 모션 재생 가능", function()
			local sc = SCEN[cid]
			local s = make(cid)
			s:onEvent(sc.ultStart, 0)
			step(s, 0, 0.3, 1 / 60)
			s:reset()
			T.expect(idle(s))
			s:onEvent(sc.basic, 0.4)
			T.expect(s:snapshot().actionId ~= nil, "궁극기 잠금이 남아 일반 모션이 거부됨")
		end)
		T.it(cid .. ": 궁극기 End 이벤트가 영영 없어도 15초 안에 잠금·자세가 풀린다", function()
			local s = make(cid)
			s:onEvent(SCEN[cid].ultStart, 0)
			step(s, 0, 15, 1 / 60)
			T.expect(idle(s), cid .. " 궁극기 고착")
			s:onEvent(SCEN[cid].basic, 15.1)
			T.expect(s:snapshot().actionId ~= nil)
		end)
	end
	T.it("충전 중단(SLINGSHOT/SUPERBALL): 해제 입력만 있고 서버 이벤트가 없으면 잔존하지 않고, 이벤트가 유실돼도 최대 시간에 풀린다", function()
		for _, cid in { "SLINGSHOT", "SUPERBALL" } do
			local sc = SCEN[cid]
			local a = make(cid)
			a:onEvent(sc.chargeStart, 0)
			a:onEvent({ type = "LocalRelease" }, 0.5)
			step(a, 0.5, 1.2, 1 / 60)
			T.expect(idle(a), cid .. " 해제 후 충전 자세 잔존")
			local b = make(cid)
			b:onEvent(sc.chargeStart, 0)
			step(b, 0, 6.5, 1 / 60)
			T.expect(idle(b), cid .. " 충전 이벤트 유실 시 고착")
		end
	end)
	T.it("충전 중단(SWORD Lunge): Cancel 이벤트로 복귀, Cancel 이 유실돼도 만료", function()
		local s = make("SWORD")
		s:onEvent(SCEN.SWORD.chargeStart, 0)
		T.expect(s:snapshot().actionId ~= nil)
		s:onEvent(SCEN.SWORD.chargeCancel, 0.4)
		step(s, 0.4, 1.2, 1 / 60)
		T.expect(idle(s))
		local lost = make("SWORD")
		lost:onEvent(SCEN.SWORD.chargeStart, 0)
		step(lost, 0, 6, 1 / 60)
		T.expect(idle(lost))
	end)
	T.it("충전 → 정상 해제 이벤트: 충전 자세가 방출 모션으로 교체되고 곧 Idle", function()
		for _, cid in { "SLINGSHOT", "SUPERBALL" } do
			local sc = SCEN[cid]
			local s = make(cid)
			s:onEvent(sc.chargeStart, 0)
			step(s, 0, 0.7, 1 / 60)
			s:onEvent(sc.chargeRelease, 0.7)
			local id = s:snapshot().actionId
			T.expect(id ~= nil and string.find(id, "Charge", 1, true) == nil, cid .. " 충전 모션이 남음")
			step(s, 0.7, 1.6, 1 / 60)
			T.expect(idle(s))
		end
	end)
	T.it("정상 End 이벤트가 있으면 궁극기 잠금이 즉시 풀린다(TIMEBOMB 제외: 잠금 없는 단발)", function()
		for _, cid in { "SWORD", "PAINTBALL", "SLINGSHOT", "SUPERBALL" } do
			local sc = SCEN[cid]
			local s = make(cid)
			s:onEvent(sc.ultStart, 0)
			step(s, 0, 0.5, 1 / 60)
			s:onEvent(sc.ultEnd, 0.5)
			T.expect(not s:snapshot().storm, cid)
		end
	end)
end)

T.describe("5캐릭터 애니메이션: 반복 입력", function()
	-- 결정적 의사 난수(LCG)
	local function rng(seed)
		local x = seed
		return function(n)
			x = (x * 1103515245 + 12345) % 2147483648
			return (x % n) + 1
		end
	end
	for _, cid in IDS do
		T.it(cid .. ": 무작위 이벤트 600건에도 항상 유한한 포즈·로그 상한·마지막에 Idle 복귀", function()
			local sc = SCEN[cid]
			local pool = {}
			for _, e in { sc.basic, sc.ultStart, sc.ultEnd, sc.chargeStart, sc.chargeRelease, sc.chargeCancel, { type = "LocalRelease" }, { type = "Died", playerId = 1 }, { type = "Respawned", playerId = 1 } } do
				table.insert(pool, e)
			end
			for _ = 1, 3 do
				table.insert(pool, sc.basic) -- 일반 모션 비중을 높인다
			end
			local n = #pool
			local pick = rng(12345)
			local s = make(cid)
			local t = 0
			for _ = 1, 600 do
				t += 0.03
				s:onEvent(pool[pick(n)], t)
				local pose = s:update(t)
				T.expect(pose == nil or not Math.hasBadNumber(pose), cid .. " 비정상 포즈")
				T.expect(#s:drain() <= 64)
			end
			s:onEvent({ type = "Respawned", playerId = 1 }, t + 0.1)
			step(s, t + 0.1, t + 16, 1 / 60)
			T.expect(idle(s), cid .. " 반복 입력 뒤 고착")
		end)
	end
end)

-- 가짜 Animator 호스트: 트랙 객체의 재생 여부/횟수를 추적한다.
local function fakeHost()
	local host = { tracks = {}, plays = 0, stops = 0 }
	host.isAsset = function()
		return true
	end
	host.acquire = function(id)
		local tr = host.tracks[id]
		if tr == nil then
			tr = { id = id, playing = false }
			host.tracks[id] = tr
		end
		return tr
	end
	host.play = function(tr)
		tr.playing = true
		host.plays += 1
	end
	host.stop = function(tr)
		tr.playing = false
		host.stops += 1
	end
	return host
end
local function playingCount(host)
	local n = 0
	for _, tr in host.tracks do
		if tr.playing then
			n += 1
		end
	end
	return n
end

T.describe("5캐릭터 애니메이션: 12인 환경(상태·트랙 중복 방지)", function()
	T.it("12개 상태기계(5캐릭터 혼합)가 서로 독립이고, 한 명의 사망/리셋이 다른 사람에게 영향을 주지 않는다", function()
		local players = {}
		for i = 1, 12 do
			local cid = IDS[(i - 1) % #IDS + 1]
			players[i] = { cid = cid, s = make(cid), book = TrackBook.new(), host = fakeHost() }
		end
		for i, p in players do
			p.s:onEvent(SCEN[p.cid].ultStart, 0.01 * i)
		end
		players[3].s:onEvent({ type = "Died", playerId = 3 }, 0.2)
		players[5].s:reset()
		for i, p in players do
			if i == 3 then
				T.expect(p.s:snapshot().dead)
			elseif i == 5 then
				T.expect(idle(p.s))
			elseif p.cid ~= "TIMEBOMB" then
				T.expect(p.s:snapshot().storm, "플레이어 " .. i .. " 의 궁극기가 다른 플레이어 조작으로 사라짐")
			end
		end
	end)
	T.it("에셋 트랙: 프레임마다 12명이 입력을 반복해도 한 명당 재생 중 트랙은 최대 1개, 정리 후 0개", function()
		local players = {}
		for i = 1, 12 do
			local cid = IDS[(i - 1) % #IDS + 1]
			players[i] = { cid = cid, s = make(cid, { assetDriven = function() return true end }), book = TrackBook.new(), host = fakeHost() }
		end
		local t = 0
		for frame = 1, 300 do
			t += 1 / 60
			for i, p in players do
				if frame % (7 + i) == 0 then
					p.s:onEvent(SCEN[p.cid].basic, t)
				end
				if frame % (41 + i) == 0 then
					p.s:onEvent(SCEN[p.cid].ultStart, t)
				end
				if frame % (97 + i) == 0 and SCEN[p.cid].ultEnd then
					p.s:onEvent(SCEN[p.cid].ultEnd, t)
				end
				p.s:update(t)
				p.book:apply(p.s:drain(), p.host)
				T.expect(p.book:count() <= 1, p.cid .. " 트랙 매핑 중복 " .. p.book:count())
				T.expect(playingCount(p.host) <= 1, p.cid .. " 재생 중 트랙 중복 " .. playingCount(p.host))
			end
		end
		for _, p in players do
			p.s:reset()
			p.book:apply(p.s:drain(), p.host)
			T.expectEqual(p.book:count(), 0)
			T.expectEqual(playingCount(p.host), 0)
		end
	end)
	T.it("TrackBook: 같은 모션 연속 재생 시 옛 stop 이 새 재생을 끊지 않는다", function()
		local host, book = fakeHost(), TrackBook.new()
		book:apply({ { kind = "play", id = "A", serial = 1, speed = 1 } }, host)
		book:apply({ { kind = "stop", id = "A", serial = 1 }, { kind = "play", id = "A", serial = 2, speed = 1 } }, host)
		T.expect(host.tracks.A.playing)
		book:apply({ { kind = "stop", id = "A", serial = 1 } }, host) -- 늦게 도착한 옛 serial 의 stop
		T.expect(host.tracks.A.playing, "옛 stop 이 새 재생을 끊음")
		T.expectEqual(book:count(), 1)
		book:apply({ { kind = "stop", id = "A", serial = 2 } }, host)
		T.expect(not host.tracks.A.playing)
		T.expectEqual(book:count(), 0)
	end)
	T.it("TrackBook: stopAll 은 전부 멈추고 비우며, 에셋이 아닌 모션은 무시한다", function()
		local host, book = fakeHost(), TrackBook.new()
		book:apply({ { kind = "play", id = "A", serial = 1 }, { kind = "play", id = "B", serial = 2 } }, host)
		T.expectEqual(playingCount(host), 2)
		book:apply({ { kind = "stopAll" } }, host)
		T.expectEqual(playingCount(host), 0)
		T.expectEqual(book:count(), 0)
		host.isAsset = function()
			return false
		end
		book:apply({ { kind = "play", id = "C", serial = 3 } }, host)
		T.expectEqual(book:count(), 0)
		host.isAsset = function()
			return true
		end
		host.acquire = function()
			return nil -- 트랙 로드 실패
		end
		book:apply({ { kind = "play", id = "D", serial = 4 } }, host)
		T.expectEqual(book:count(), 0)
	end)
end)

T.describe("5캐릭터 애니메이션: 경기 종료·재시작 신호(MatchResetModel)", function()
	T.it("RESULTS 진입 시 한 번, 새 경기(matchId 변경) 시 한 번만 정리하고 같은 상태에서는 반복하지 않는다", function()
		local playing = { phase = "PLAYING", matchId = 1 }
		local results = { phase = "RESULTS", matchId = 1 }
		T.expect(not MatchReset.shouldReset(nil, playing))
		T.expect(not MatchReset.shouldReset(playing, playing))
		local r, why = MatchReset.shouldReset(playing, results)
		T.expect(r and why == "results")
		T.expect(not MatchReset.shouldReset(results, results), "RESULTS 중 매 스냅샷마다 정리하면 안 됨")
		local nr, nwhy = MatchReset.shouldReset(results, { phase = "WAITING", matchId = 2 })
		T.expect(nr and nwhy == "newMatch")
		T.expect(not MatchReset.shouldReset({ phase = "WAITING", matchId = 2 }, { phase = "COUNTDOWN", matchId = 2 }))
		local cancelled = { phase = "WAITING", matchId = 2, reason = "insufficient_players", cancelled = true }
		local old = { phase = "ACTIVE", matchId = 2 }
		local stop, stopReason = MatchReset.shouldReset(old, cancelled)
		T.expect(stop and stopReason == "cancelled", "인원 부족 경기 취소 시 모션 정리")
		T.expect(not MatchReset.shouldReset(cancelled, cancelled), "취소된 WAITING 중 중복 정리 금지")
		T.expect(not MatchReset.shouldReset(old, {phase="WAITING",matchId=2,reason="countdown_cancelled"}), "카운트다운 취소는 전투 경계가 아님")
	end)
	T.it("인원 부족 취소 직후 WAITING 스냅샷을 건너뛰어도 5캐릭터 모션을 초기화한다", function()
		-- 10Hz 스냅샷 사이에 ACTIVE -> WAITING -> COUNTDOWN 이 빠르게 발생할 수 있다.
		local old = { phase = "ACTIVE", matchId = 7 }
		local nextCountdown = { phase = "COUNTDOWN", matchId = 7, reason = "enough_players" }
		local reset, why = MatchReset.shouldReset(old, nextCountdown)
		T.expect(reset and why == "cancelled_snapshot_skipped")
		T.expect(not MatchReset.shouldReset(nextCountdown, nextCountdown), "같은 카운트다운에서 반복 정리하면 안 됨")
		T.expect(not MatchReset.shouldReset({ phase = "WAITING", matchId = 7 }, nextCountdown), "정상 카운트다운은 정리 대상 아님")
		T.expect(not MatchReset.shouldReset({ phase = "COUNTDOWN", matchId = 7 }, { phase = "WAITING", matchId = 7, reason = "countdown_cancelled" }), "일반 카운트다운 취소는 정리하지 않음")
		for _, cid in IDS do
			local s = make(cid)
			s:onEvent(SCEN[cid].ultStart, 0)
			if MatchReset.shouldReset(old, nextCountdown) then s:reset() end
			T.expect(idle(s), cid .. " 이전 경기 잔존 모션")
		end
	end)
	T.it("표기 차이(Results/RESULTS), match 없음, 비정상 입력을 안전하게 처리한다", function()
		T.expect(MatchReset.shouldReset({ phase = "PLAYING" }, { phase = "Results" }))
		T.expect(not MatchReset.shouldReset(nil, nil))
		T.expect(not MatchReset.shouldReset({ phase = "PLAYING" }, nil))
		T.expect(not MatchReset.shouldReset("x", 5))
		T.expect(not MatchReset.shouldReset({ phase = 3 }, { phase = {} }))
		T.expect(MatchReset.matchOf({ match = { phase = "A" } }).phase == "A")
		T.expect(MatchReset.matchOf({ ui = { match = { phase = "B" } } }).phase == "B")
		T.expect(MatchReset.matchOf(nil) == nil and MatchReset.matchOf({}) == nil)
	end)
	T.it("정리 신호가 오면 5캐릭터 모두 궁극기 중이어도 Idle 로 돌아가 다음 경기에서 정상 동작한다", function()
		for _, cid in IDS do
			local s = make(cid)
			s:onEvent(SCEN[cid].ultStart, 0)
			local prev, cur = { phase = "PLAYING", matchId = 1 }, { phase = "RESULTS", matchId = 1 }
			if MatchReset.shouldReset(prev, cur) then
				s:reset()
			end
			T.expect(idle(s), cid)
			s:onEvent(SCEN[cid].basic, 1)
			T.expect(s:snapshot().actionId ~= nil, cid)
		end
	end)
end)

return true
