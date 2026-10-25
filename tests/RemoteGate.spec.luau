--!nonstrict
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Gate = Env.server("RemoteGate")
local Cooldown = Env.server("CooldownService")
local Characters = Env.shared("Data/Characters")

local function setup(overrides)
	local state = { alive = true, pos = H.v(0, 0, 0), serverTime = 100, character = Characters.PAINTBALL }
	for k, v in overrides or {} do
		state[k] = v
	end
	local gate = Gate.new({
		cooldown = Cooldown.new(),
		getState = function(id)
			return if id == "ghost" then nil else state
		end,
	})
	return gate, state
end

local function attack(extra)
	local p = { action = "Primary", aimOrigin = H.v(0, 1, 0), aimDirection = H.v(0, 0, 1), clientTime = 100 }
	for k, v in extra or {} do
		p[k] = v
	end
	return p
end

T.describe("RemoteGate (서버 진입 검증)", function()
	T.it("정상 요청 통과", function()
		local gate = setup()
		local ok, reason = gate:check("p1", "Attack", attack(), 100)
		T.expect(ok, reason)
	end)
	T.it("피해량·명중 대상 필드가 있으면 거부", function()
		local gate = setup()
		local ok, reason = gate:check("p1", "Attack", attack({ damage = 9999 }), 100)
		T.expect(not ok and string.find(reason, "invalid_payload", 1, true) ~= nil)
		T.expect(not (gate:check("p1", "Attack", attack({ hitTargets = { "p2" } }), 100)))
	end)
	T.it("알 수 없는 리모트 / 쓰레기 페이로드 거부", function()
		local gate = setup()
		T.expect(select(2, gate:check("p1", "GiveAdmin", {}, 100)) == "unknown_remote")
		T.expect(not (gate:check("p1", "Attack", "x", 100)))
		T.expect(not (gate:check("p1", "Attack", nil, 100)))
	end)
	T.it("과도한 요청 빈도 거부", function()
		local gate = setup()
		local rejected = 0
		for i = 1, 60 do
			local ok, reason = gate:check("p1", "Attack", attack(), 100 + i * 0.001)
			if not ok and reason == "rate_limited" then
				rejected += 1
			end
		end
		T.expect(rejected >= 30)
	end)
	T.it("사망/캐릭터 없음 거부", function()
		local gate = setup({ alive = false })
		T.expect(select(2, gate:check("p1", "Attack", attack(), 100)) == "dead")
		T.expect(select(2, gate:check("ghost", "Attack", attack(), 100)) == "no_character")
	end)
	T.it("시각 편차·조준 원점 위조 거부", function()
		local gate = setup()
		T.expect(select(2, gate:check("p1", "Attack", attack({ clientTime = 500 }), 100)) == "time_skew")
		T.expect(select(2, gate:check("p2", "Attack", attack({ aimOrigin = H.v(80, 0, 0) }), 100)) == "origin_mismatch")
	end)
	T.it("재장전은 탄약이 있는 캐릭터만", function()
		local ok = setup()
		T.expect((ok:check("p1", "Reload", {}, 100)))
		local gate = setup({ character = Characters.SWORD })
		T.expect(select(2, gate:check("p1", "Reload", {}, 100)) == "no_reload")
	end)
end)
return true
