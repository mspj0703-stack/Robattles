--!strict
-- 투사체 데이터 스키마 + 타입별 의미 검증. 모든 수치(수명, 재적중 간격, 관통/반사 횟수 등)는 데이터로 설정한다.
-- 지원 타입 7종: Linear(고속 직선), Arc(포물선), Bounce(표면 반사), Pierce(관통),
--                Explosion(범위 폭발), Beam(지속형 빔), Placed(설치형 폭탄)

local Schema = require(script.Parent.Schema)

local ProjectileSpec = {}

ProjectileSpec.Types = { "Linear", "Arc", "Bounce", "Pierce", "Explosion", "Beam", "Placed" }

-- 충돌 모드. Hitscan은 기본 비허용: 개별 공격이 allowHitscan = true를 명시해야 한다(예: 추후 Bullseye).
ProjectileSpec.CollisionModes = { "Ray", "Spherecast", "Hitscan" }

local explosionSpec = Schema.object({
	radius = Schema.number({ min = 0.5, max = 60 }),
	damage = Schema.number({ min = 0, max = 1000 }),
	falloffMin = Schema.number({ min = 0, max = 1 }), -- 가장자리 피해 배율
	knockback = Schema.number({ min = 0, max = 200 }),
	friendlyOwnerDamage = Schema.boolean(), -- 시전자 자신 피해 여부
})

ProjectileSpec.Schema = Schema.object({
	id = Schema.string(48),
	type = Schema.oneOf(ProjectileSpec.Types),
	collision = Schema.object({
		mode = Schema.oneOf(ProjectileSpec.CollisionModes),
		radius = Schema.number({ min = 0, max = 10 }), -- Spherecast 반지름 (Ray는 0)
		allowHitscan = Schema.optional(Schema.boolean()),
	}),
	speed = Schema.number({ min = 0, max = 2000 }),
	gravity = Schema.number({ min = -400, max = 400 }), -- 0이면 직선
	lifetime = Schema.number({ min = 0.05, max = 60 }),
	maxRange = Schema.optional(Schema.number({ min = 1, max = 5000 })),
	damage = Schema.number({ min = 0, max = 1000 }),
	-- 방어 가능 여부(패링 등). 생략 시 Linear/Arc/Bounce/Pierce 직접 피해만 true, 폭발·빔·설치형은 false.
	blockable = Schema.optional(Schema.boolean()),
	rehitInterval = Schema.number({ min = 0, max = 10 }), -- 같은 대상 재적중 간격(초). 0=재적중 불가(1회)
	pierce = Schema.optional(Schema.object({ maxHits = Schema.integer(1, 50) })),
	bounce = Schema.optional(Schema.object({
		maxBounces = Schema.integer(1, 20),
		restitution = Schema.number({ min = 0, max = 1 }),
		damageMultPerBounce = Schema.number({ min = 0, max = 2 }),
	})),
	explosion = Schema.optional(explosionSpec),
	beam = Schema.optional(Schema.object({
		duration = Schema.number({ min = 0.1, max = 30 }),
		tickInterval = Schema.number({ min = 0.05, max = 5 }),
		length = Schema.number({ min = 1, max = 500 }),
		endsOnOwnerDeath = Schema.boolean(), -- 확정 규칙: 캐릭터 연결 지속 공격은 사망 시 종료
	})),
	placed = Schema.optional(Schema.object({
		armTime = Schema.number({ min = 0, max = 10 }),
		fuseTime = Schema.number({ min = 0.1, max = 60 }),
		survivesOwnerDeath = Schema.boolean(), -- 확정 규칙: 설치물은 남은 수명 동안 유지
	})),
})

-- 스키마 + 타입별 필수/금지 조합 검증. 반환: ok, 오류 메시지.
function ProjectileSpec.validate(def: any): (boolean, string?)
	local ok, err = Schema.validate(ProjectileSpec.Schema, def)
	if not ok then
		return false, err
	end
	local t = def.type

	if def.collision.mode == "Hitscan" and def.collision.allowHitscan ~= true then
		return false, "Hitscan은 allowHitscan=true를 명시한 개별 공격에서만 허용"
	end
	if def.collision.mode == "Hitscan" and def.maxRange == nil then
		return false, "Hitscan은 maxRange 필요"
	end
	if def.collision.mode == "Ray" and def.collision.radius ~= 0 then
		return false, "Ray 모드는 radius=0이어야 함"
	end
	if def.collision.mode == "Spherecast" and def.collision.radius <= 0 then
		return false, "Spherecast 모드는 radius>0 필요"
	end

	if t == "Linear" or t == "Arc" or t == "Bounce" or t == "Pierce" then
		if def.speed <= 0 then
			return false, t .. ": speed>0 필요"
		end
	end
	if t == "Linear" and def.gravity ~= 0 then
		return false, "Linear는 gravity=0이어야 함"
	end
	if t == "Arc" and def.gravity == 0 then
		return false, "Arc는 gravity≠0 필요"
	end
	if t == "Bounce" and def.bounce == nil then
		return false, "Bounce는 bounce 설정 필요"
	end
	if t == "Pierce" and def.pierce == nil then
		return false, "Pierce는 pierce 설정 필요"
	end
	if t == "Explosion" and def.explosion == nil then
		return false, "Explosion은 explosion 설정 필요"
	end
	if t == "Beam" and def.beam == nil then
		return false, "Beam은 beam 설정 필요"
	end
	if t == "Placed" and (def.placed == nil or def.explosion == nil) then
		return false, "Placed는 placed와 explosion 설정 필요"
	end
	-- 해당 타입이 아닌데 타입 전용 블록이 있으면 거부(설정 실수 방지). Arc/Linear 등은 pierce/bounce 블록 금지.
	if t ~= "Pierce" and def.pierce ~= nil then
		return false, t .. ": pierce 블록 불가"
	end
	if t ~= "Bounce" and def.bounce ~= nil then
		return false, t .. ": bounce 블록 불가"
	end
	if t ~= "Beam" and def.beam ~= nil then
		return false, t .. ": beam 블록 불가"
	end
	if t ~= "Placed" and def.placed ~= nil then
		return false, t .. ": placed 블록 불가"
	end
	return true, nil
end

return ProjectileSpec
