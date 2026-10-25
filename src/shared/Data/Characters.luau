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

-- SUPERBALL (Phase 2). 확정: HP 100, LMB 일반 18(지형 튕김 2회·수명 약 5초)/약 1초 충전 28(3회·약 6초), RMB Bounce Dash 10스터드·쿨 7·무적 없음,
-- 스킬1 Rapid Bounce 3발×12·쿨 9, 스킬2 Scatter Ball 5발×7·쿨 12, 스킬3 Recall 귀환 볼당 12·쿨 8(볼당 대상당 1회, 유도 없음),
-- 궁극기 Ball Cyclone 볼 10개 공전·최대 12초·접촉 8·LMB 발사 시 추가 12, 볼 총량 12(일반+궁극기),
-- 패시브 Trick Master: 지형 튕김 뒤 적 유효 적중 시 가장 긴 스킬 쿨타임 0.5초 감소·1초 재발동 제한.
-- 임시(A72~A75): 속도·중력·반경·반발계수·발사 간격·산탄 각도·공전 반지름/주기·접촉 간격·귀환 속도·충전 최대 유지 시간 등 위에 없는 모든 수치.
Characters.SUPERBALL = {
	id = "SUPERBALL",
	displayName = "Superball",
	maxHealth = 100, -- 확정
	module = "Superball",
	ballCap = 12, -- 확정: 일반 + 궁극기 볼 합산 상한
	primary = {
		kind = "Projectile", automatic = false, damage = 18, chargedDamage = 28, -- 확정
		chargeSeconds = 1.0, maxHoldSeconds = 4, fireInterval = 0.6, -- 충전 약 1초 확정 / 나머지 임시
		moveSpeedMult = 0.9, chargeMoveMult = 0.8, -- 임시
		normal = { bounces = 2, lifetime = 5, speed = 75, gravity = 28, radius = 0.6, restitution = 0.8 }, -- 튕김·수명 확정, 나머지 임시
		charged = { bounces = 3, lifetime = 6, speed = 100, gravity = 28, radius = 0.8, restitution = 0.8 },
	},
	-- RMB Bounce Dash: 이동기(무적 없음). 서버 이동 허가(BounceDash) 필수. 공중 사용 가능.
	secondary = {
		id = "BounceDash", name = "Bounce Dash", kind = "Movement",
		cooldown = 7, distance = 10, -- 확정
		duration = 0.25, minDistance = 1, permit = "BounceDash", -- 임시
	},
	skills = {
		[1] = {
			id = "RapidBounce", name = "Rapid Bounce", kind = "Skill", cooldown = 9, damage = 12, balls = 3, -- 확정
			spread = { { 0, 0 }, { -5, 0 }, { 5, 0 } }, -- 임시
			ball = { bounces = 2, lifetime = 5, speed = 75, gravity = 28, radius = 0.6, restitution = 0.8 },
		},
		[2] = {
			id = "ScatterBall", name = "Scatter Ball", kind = "Skill", cooldown = 12, damage = 7, balls = 5, -- 확정
			spread = { { 0, 0 }, { -9, 0 }, { 9, 0 }, { -18, 0 }, { 18, 0 } }, -- 임시
			ball = { bounces = 2, lifetime = 5, speed = 70, gravity = 28, radius = 0.5, restitution = 0.8 },
		},
		[3] = {
			id = "Recall", name = "Recall", kind = "Skill", cooldown = 8, damage = 12, -- 확정: 귀환 볼 1발당 12
			returnSpeed = 70, -- 임시
		},
	},
	ultimate = {
		id = "BallCyclone", name = "Ball Cyclone", kind = "Ultimate",
		balls = 10, duration = 12, contactDamage = 8, shotDamage = 12, -- 확정
		orbitRadius = 4, orbitSeconds = 1.6, orbitHeight = 1.5, contactInterval = 0.6, targetInterval = 0.2, -- 임시
		shot = { speed = 90, gravity = 10, radius = 0.6, bounces = 1, lifetime = 3, restitution = 0.8 }, shotInterval = 0.4, -- 임시
	},
	passive = { id = "TrickMaster", reduceSeconds = 0.5, lockSeconds = 1 }, -- 확정
}

-- TIMEBOMB (Phase 2). 확정: HP 105, LMB 타이머 폭탄(약 1초 뒤 폭발·20·간격 약 1.2초), RMB Blast Guard(근처 적 10 + 넉백, 자기 반동 이동, 쿨 8),
-- 스킬1 Cluster Bomb 18 + 자탄 4×8·쿨 13, 스킬2 Remote Bomb(설치 최대 2·충전 2·충전당 11초·28·반경 7; 짧게 누르면 던지기/설치, 0.4초 이상 누르고 떼면 전체 기폭, 기폭은 충전 소모 없음),
-- 스킬3 Blast Jump(약 14스터드·공중 가능·쿨 9·BlastJump 이동 허가), 궁극기 Big Bang(착지 3초 뒤 폭발·반경 18·중심 70/가장자리 35·Blast Jump 후 공중에서 쓰면 더 멀리),
-- 패시브 Chain Reaction(자기 폭탄 반경 7스터드 연쇄, 최초 폭발 포함 최대 3단계). 폭발 감쇠: 같은 공격자의 폭발이 같은 대상에 0.3초 안에 반복되면 100% → 60% → 30%.
-- 임시(A76~A78): 폭발 반경(Timed 6·Cluster 6·자탄 4·Blast Guard 6), 투척 속도·중력, 자탄 각도·간격, Blast Guard 반동 거리/넉백, Blast Jump 방향/시간, 설치 수명, 기폭 입력 상한, Big Bang 비행 한도 등.
Characters.TIMEBOMB = {
	id = "TIMEBOMB",
	displayName = "Timebomb",
	maxHealth = 105, -- 확정
	module = "Timebomb",
	primary = {
		kind = "Projectile", automatic = false, damage = 20, fireInterval = 1.2, fuse = 1.0, -- 확정(약)
		radius = 6, falloffMin = 1, moveSpeedMult = 0.9, -- 임시
		bomb = { speed = 45, gravity = 35, bombRadius = 0.4 },
	},
	secondary = {
		id = "BlastGuard", name = "Blast Guard", kind = "Skill", cooldown = 8, damage = 10, -- 확정
		radius = 6, knockback = 40, falloffMin = 1, -- 임시
		recoil = { distance = 6, duration = 0.25, minDistance = 1, permit = "BlastGuard" }, -- 자기 반동 이동(임시): 조준 반대 수평 방향
	},
	skills = {
		[1] = {
			id = "ClusterBomb", name = "Cluster Bomb", kind = "Skill", cooldown = 13, damage = 18, -- 확정
			fuse = 1.0, radius = 6, falloffMin = 1, bomb = { speed = 45, gravity = 35, bombRadius = 0.4 }, -- 임시
			mini = { count = 4, damage = 8, radius = 4, fuse = 0.5, fuseStep = 0.35, speed = 14, pitchDeg = 50, gravity = 35 }, -- 개수·피해 확정, 나머지 임시. 간격 0.35초: 감쇠 창(0.3초) 밖이라 자탄마다 100%
		},
		[2] = {
			id = "RemoteBomb", name = "Remote Bomb", kind = "Skill", damage = 28, radius = 7, falloffMin = 1, -- 확정
			maxPlaced = 2, charges = 2, rechargeSeconds = 11, holdSeconds = 0.4, -- 확정
			throwInterval = 0.3, placedLifetime = 30, maxHoldSeconds = 10, bomb = { speed = 40, gravity = 35, bombRadius = 0.4 }, -- 임시
		},
		[3] = {
			id = "BlastJump", name = "Blast Jump", kind = "Movement", cooldown = 9, -- 확정
			distance = 14, duration = 0.5, minDistance = 2, minUp = 0.5, permit = "BlastJump", -- 14 확정, 나머지 임시. 판정(피해) 없음: 폭발은 연쇄 반응만 유발
		},
	},
	ultimate = {
		id = "BigBang", name = "Big Bang", kind = "Ultimate", duration = 1.0, -- duration: 발동 표시 시간(임시)
		damage = 70, edgeDamage = 35, radius = 18, fuseAfterLand = 3, -- 확정
		speed = 50, airSpeed = 75, airWindow = 3, gravity = 30, flightLimit = 6, bombRadius = 0.6, -- 임시
	},
	passive = { id = "ChainReaction", radius = 7, maxStages = 3 }, -- 확정
}

return Characters
