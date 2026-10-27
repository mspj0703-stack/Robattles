--!strict
-- 7개 투사체 타입의 참조 템플릿(테스트·Phase 2 캐릭터 데이터의 출발점). 수치는 임시값(ASSUMPTION A11).

local function base(id: string, typ: string): { [string]: any }
	return {
		id = id,
		type = typ,
		collision = { mode = "Spherecast", radius = 0.4 },
		speed = 150,
		gravity = 0,
		lifetime = 3,
		damage = 10,
		rehitInterval = 0,
	}
end

local T: { [string]: any } = {}

T.Linear = base("tpl_linear", "Linear")

do
	local d = base("tpl_arc", "Arc")
	d.speed = 70
	d.gravity = 80
	T.Arc = d
end

do
	local d = base("tpl_bounce", "Bounce")
	d.lifetime = 4
	d.bounce = { maxBounces = 3, restitution = 1, damageMultPerBounce = 1 }
	T.Bounce = d
end

do
	local d = base("tpl_pierce", "Pierce")
	d.pierce = { maxHits = 3 }
	T.Pierce = d
end

do
	local d = base("tpl_explosion", "Explosion")
	d.speed = 0
	d.lifetime = 0.2
	d.explosion = { radius = 12, damage = 30, falloffMin = 0.4, knockback = 60, friendlyOwnerDamage = false }
	T.Explosion = d
end

do
	local d = base("tpl_beam", "Beam")
	d.speed = 0
	d.lifetime = 2
	d.rehitInterval = 0.25
	d.beam = { duration = 2, tickInterval = 0.25, length = 60, endsOnOwnerDeath = true }
	T.Beam = d
end

do
	local d = base("tpl_placed", "Placed")
	d.speed = 0
	d.lifetime = 8
	d.placed = { armTime = 0.5, fuseTime = 6, survivesOwnerDeath = true }
	d.explosion = { radius = 14, damage = 40, falloffMin = 0.5, knockback = 80, friendlyOwnerDamage = true }
	T.Placed = d
end

return T
