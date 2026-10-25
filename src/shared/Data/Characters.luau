--!strict
-- Phase 1 테스트 캐릭터: SWORD, PAINTBALL만. 기본 수치는 임시값(ASSUMPTION A12~A14)이며 확정 시 교체한다.
-- Phase 2 Step 1: SWORD 전체 스킬 구현(확정 피해량 + 임시 수치는 각 항목 주석 / A65~A67). PAINTBALL 스킬·궁극기는 별도 Step(미구현).
-- 나머지 3종(SUPERBALL, TIMEBOMB, SLINGSHOT)은 범위 밖이다.

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

Characters.PAINTBALL = {
	id = "PAINTBALL",
	displayName = "Paintball",
	-- ASSUMPTION A14
	primary = {
		kind = "Projectile",
		automatic = true,
		fireInterval = 0.12,
		damage = 4,
		moveSpeedMult = 0.9,
		stagger = false,
		projectile = {
			id = "paintball_pellet",
			type = "Linear",
			collision = { mode = "Spherecast", radius = 0.3 },
			speed = 220,
			gravity = 0,
			lifetime = 2,
			maxRange = 300,
			damage = 4,
			rehitInterval = 0,
		},
	},
	ammo = {
		magazine = 30,
		reloadSeconds = 1.8,
	},
	ultimate = { duration = 3, placeholder = true }, -- ASSUMPTION A33
}

return Characters
