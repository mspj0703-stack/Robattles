--!nonstrict
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local P = Env.shared("ProjectileSpec")
local Templates = Env.shared("Data/ProjectileTemplates")
local Characters = Env.shared("Data/Characters")

local function clone(t)
	local c = {}
	for k, v in t do
		c[k] = if type(v) == "table" then clone(v) else v
	end
	return c
end

T.describe("ProjectileSpec", function()
	for _, typeName in P.Types do
		T.it("템플릿 통과: " .. typeName, function()
			local ok, err = P.validate(Templates[typeName])
			T.expect(ok, err)
		end)
	end
	T.it("PAINTBALL 투사체 데이터 통과", function()
		local ok, err = P.validate(Characters.PAINTBALL.primary.projectile)
		T.expect(ok, err)
	end)
	T.it("Hitscan은 allowHitscan 없이 거부, 명시하면 허용(확장 지점)", function()
		local d = clone(Templates.Linear)
		d.collision = { mode = "Hitscan", radius = 0 }
		d.maxRange = 200
		T.expectRejected(P.validate(d))
		d.collision.allowHitscan = true
		T.expect((P.validate(d)))
		d.maxRange = nil
		T.expectRejected(P.validate(d)) -- maxRange 필수
	end)
	T.it("Linear + gravity 거부 / Arc gravity 0 거부", function()
		local a = clone(Templates.Linear)
		a.gravity = 10
		T.expectRejected(P.validate(a))
		local b = clone(Templates.Arc)
		b.gravity = 0
		T.expectRejected(P.validate(b))
	end)
	T.it("타입별 필수 블록 누락 거부", function()
		for typeName, field in { Bounce = "bounce", Pierce = "pierce", Explosion = "explosion", Beam = "beam", Placed = "placed" } do
			local d = clone(Templates[typeName])
			d[field] = nil
			local ok, err = P.validate(d)
			T.expectRejected(ok, err, typeName)
		end
	end)
	T.it("타입에 맞지 않는 블록 거부", function()
		local d = clone(Templates.Linear)
		d.bounce = { maxBounces = 2, restitution = 1, damageMultPerBounce = 1 }
		T.expectRejected(P.validate(d))
	end)
	T.it("수명 0·음수 속도·NaN 거부", function()
		local d = clone(Templates.Linear)
		d.lifetime = 0
		T.expectRejected(P.validate(d))
		d = clone(Templates.Linear)
		d.speed = -5
		T.expectRejected(P.validate(d))
		d = clone(Templates.Linear)
		d.damage = 0 / 0
		T.expectRejected(P.validate(d))
	end)
	T.it("Ray는 radius 0, Spherecast는 radius>0", function()
		local d = clone(Templates.Linear)
		d.collision = { mode = "Ray", radius = 0.5 }
		T.expectRejected(P.validate(d))
		d.collision = { mode = "Spherecast", radius = 0 }
		T.expectRejected(P.validate(d))
	end)
	T.it("Beam은 사망 시 종료, Placed는 사망 후 유지 (확정 규칙 반영)", function()
		T.expect(Templates.Beam.beam.endsOnOwnerDeath == true)
		T.expect(Templates.Placed.placed.survivesOwnerDeath == true)
	end)
end)

return true
