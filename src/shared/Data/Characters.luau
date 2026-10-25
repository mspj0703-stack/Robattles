--!strict
-- Phase 1 테스트 캐릭터: SWORD, PAINTBALL만. 기본 수치는 임시값(ASSUMPTION A12~A14)이며 확정 시 교체한다.
-- Phase 2: SWORD(A65~A67), PAINTBALL(A68~), 이후 SUPERBALL·TIMEBOMB·SLINGSHOT. 캐릭터별 maxHealth 는 확정값.

local Characters = {}

Characters.SWORD = {
	id = "SWORD",
	displayName = "Sword",
	-- ASSUMPTION A12
	primary = {
		kind = "Melee",
		damage = 14,
		cooldown = 0.55,
		range = 7,
		arcDegrees = 110,
		moveSpeedMult = 0.85,
		stagger = false, -- 기본 공격 경직 없음
		knockback = 12,
		combo = { damages = { 14, 14, 18 }, resetSeconds = 1.2, finishCooldown = 0.8 }, -- damages 확정 / 나머지 임시 A65
	},
	-- 확정: LMB 3타 콤보 14/14/18. 임시(A65): 콤보 이어짐 창, 3타 후 후딜.
	-- (primary.damage 는 1타 값과 같다: 기존 단일 공격 규칙·테스트 호환)
	-- 확정: 보조 공격(RMB) = 패링. 0.4초, 전방 180°의 방어 가능한 공격만 차단, 성공 시 자동 반격 18, 쿨타임 10초.
	secondary = {
		kind = "Parry",
		cooldown = 10, -- 확정
		windowSeconds = 0.4, -- 확정
		frontArcDegrees = 180, -- 확정: 캐릭터 전방 180°
		counterDamage = 18, -- 확정
		counterRange = 7, -- ASSUMPTION A44: "유효 사거리" = SWORD 기본 공격 사거리(+서버 허용 오차)
		moveSpeedMult = 0.5, -- ASSUMPTION A32
	},
	-- 확정 수치: 피해량·단계 수·재발동 4초. 그 외(쿨타임, 사거리, 각도, 시간, 이동 거리)는 전부 임시(A65~A66).
	skills = {
		[1] = {
			id = "TripleSlash", name = "Triple Slash", kind = "Skill",
			damages = { 10, 14, 22 }, -- 확정: 키를 세 번 눌러 개별 연계
			cooldown = 8, chainWindow = 1.5, stepInterval = 0.3, -- 임시: 쿨타임은 연계 종료(3타 또는 창 만료) 시점부터
			range = 7, arcDegrees = 120, advance = 4, advanceDuration = 0.15, -- 임시: 타격별 전진
			permit = "TripleSlash",
		},
		[2] = {
			id = "Lunge", name = "Lunge", kind = "Skill",
			minDamage = 18, maxDamage = 32, -- 확정: 충전량에 비례
			chargeSeconds = 1.0, autoReleaseGrace = 0.5, chargeMoveMult = 0.5, -- 임시
			cooldown = 9, dashDistance = 16, dashDuration = 0.28, pathRadius = 1.5, -- 임시: 이동 경로 중심선 ± 반지름(+피격 반지름) 안의 모든 적 1회 적중
			permit = "Lunge",
		},
		[3] = {
			id = "BladeWave", name = "Blade Wave", kind = "Skill",
			damage = 20, -- 확정: 전방 부채꼴 광역
			cooldown = 6, range = 14, arcDegrees = 90, -- 임시
		},
	},
	-- 궁극기 Blade Storm: 확정 5×8 + 마무리 25. 임시: 간격, 반경, 방어 불가.
	ultimate = {
		id = "BladeStorm", name = "Blade Storm", kind = "Ultimate",
		duration = 3, ticks = 8, tickDamage = 5, tickInterval = 0.3, finisherDamage = 25, finisherAt = 2.7, radius = 10, blockable = false,
	},
	-- 패시브 Duelist: 확정 3회 연속·+8·전역 재발동 4초. 임시: 연속 창.
	passive = { id = "Duelist", consecutiveHits = 3, bonusDamage = 8, lockSeconds = 4, windowSeconds = 3 },
}

-- 캐릭터별 최대 체력(확정): SWORD 110 / PAINTBALL 95 / SUPERBALL 100 / TIMEBOMB 105 / SLINGSHOT 100.
Characters.SWORD.maxHealth = 110

-- PAINTBALL (Phase 2). 확정: HP 95, LMB 7·초당 3발·탄창 16·재장전 1.2초, RMB 5발×5(최대 25)·탄 3 소모·약 1초 후딜,
-- 스킬1 Color Bomb 광역 24·쿨 9, 스킬2 Piercing Shot 대상당 30·최대 3명·쿨 12, 스킬3 Paint Slide 12스터드·쿨 7,
-- 궁극기 Color Break(전조 0.8초 + 약 2.5초 빔, 0.25초마다 6, 대상당 최대 60), 패시브 Color Reload(탄 3 회복, 재발동 5초).
-- 임시(A68): 투사체 속도·사거리·반경·산탄 각도·이동속도 배율·빔 길이 등 위에 없는 모든 수치.
Characters.PAINTBALL = {
	id = "PAINTBALL",
	displayName = "Paintball",
	maxHealth = 95, -- 확정
	module = "Paintball",
	primary = {
		kind = "Projectile",
		automatic = true,
		fireInterval = 1 / 3, -- 확정: 초당 3발
		damage = 7, -- 확정
		moveSpeedMult = 0.9, -- 임시
		stagger = false,
		projectile = {
			id = "paint_shot",
			type = "Linear",
			collision = { mode = "Spherecast", radius = 0.3 },
			speed = 220, -- 임시
			gravity = 0,
			lifetime = 2,
			maxRange = 300,
			damage = 7,
			rehitInterval = 0,
		},
	},
	ammo = {
		magazine = 16, -- 확정
		reloadSeconds = 1.2, -- 확정
	},
	-- RMB Paint Burst: 독립 투사체 5개(각각 5 피해, 같은 대상 다중 적중 허용 → 최대 25). 탄 3 소모, 약 1초 후딜(쿨타임).
	secondary = {
		id = "PaintBurst", name = "Paint Burst", kind = "Projectile",
		pellets = 5, pelletDamage = 5, ammoCost = 3, cooldown = 1.0, moveSpeedMult = 0.8,
		-- 산탄 패턴(임시, 결정적): { 좌우 도, 상하 도 }
		spread = { { 0, 0 }, { -4, 0 }, { 4, 0 }, { 0, -3 }, { 0, 3 } },
		damage = 5,
		projectile = {
			id = "paint_pellet", type = "Linear", collision = { mode = "Spherecast", radius = 0.3 },
			speed = 200, gravity = 0, lifetime = 0.6, maxRange = 70, damage = 5, rehitInterval = 0, -- 속도·사거리 임시
		},
	},
	skills = {
		[1] = {
			id = "ColorBomb", name = "Color Bomb", kind = "Skill",
			damage = 24, cooldown = 9, -- 확정
			radius = 8, -- 임시: 폭발 반경
			projectile = {
				id = "color_bomb", type = "Arc", collision = { mode = "Spherecast", radius = 0.5 },
				speed = 80, gravity = 40, lifetime = 3, maxRange = 120, damage = 0, rehitInterval = 0, -- 임시: 직접 피해 없음, 폭발만
				explosion = { radius = 8, damage = 24, falloffMin = 1, knockback = 0, friendlyOwnerDamage = false },
			},
		},
		[2] = {
			id = "PiercingShot", name = "Piercing Shot", kind = "Skill",
			damage = 30, cooldown = 12, maxTargets = 3, -- 확정
			projectile = {
				id = "piercing_shot", type = "Pierce", collision = { mode = "Spherecast", radius = 0.4 },
				speed = 260, gravity = 0, lifetime = 1.2, maxRange = 150, damage = 30, rehitInterval = 0, -- 속도·사거리 임시
				pierce = { maxHits = 3 },
			},
		},
		[3] = {
			id = "PaintSlide", name = "Paint Slide", kind = "Movement",
			cooldown = 7, distance = 12, -- 확정
			duration = 0.4, minDistance = 1, permit = "PaintSlide", -- 임시: 지속 시간(속도 30), 벽에 막혀 이보다 짧으면 거부
		},
	},
	-- 궁극기 Color Break: 확정 전조 0.8초, 빔 약 2.5초, 0.25초마다 6, 대상당 최대 60. 임시: 길이·반경·방어 불가.
	ultimate = {
		id = "ColorBreak", name = "Color Break", kind = "Ultimate",
		windup = 0.8, beamSeconds = 2.5, tickInterval = 0.25, tickDamage = 6, maxPerTarget = 60,
		duration = 3.3, length = 70, radius = 1.2, blockable = false,
	},
	passive = { id = "ColorReload", ammoRestore = 3, lockSeconds = 5 }, -- 확정
}

return Characters
