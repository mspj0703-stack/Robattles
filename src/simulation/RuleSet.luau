--!nonstrict
-- 시뮬레이션 규칙 집합. 모든 항목에 출처를 붙인다.
--   REAL   = 게임 실제 설정(Config / Data.Characters)에서 읽은 값. 게임 값이 바뀌면 자동으로 따라간다.
--   APPROX = 시뮬레이션 근사(봇 행동, 맵, 지연 등). 게임 규칙이 아니며 결과 해석 시 반드시 구분한다.
-- 이 모듈은 게임 서버 코드를 호출하지 않는다(값만 읽는다).
local RuleSet = {}

function RuleSet.build(Config, Characters, overrides)
	local rules = { provenance = {} }
	local function real(key, value, ref)
		rules[key] = value
		table.insert(rules.provenance, { key = key, source = "REAL", ref = ref })
	end
	local function approx(key, value, note)
		rules[key] = value
		table.insert(rules.provenance, { key = key, source = "APPROX", note = note })
	end
	local function tableReal(key, t, ref)
		rules[key] = t
		table.insert(rules.provenance, { key = key, source = "REAL", ref = ref })
	end

	-- 공통 (REAL)
	real("maxHealth", Config.Combat.MaxHealth, "Config.Combat.MaxHealth")
	real("hitRadius", Config.Combat.HitRadius, "Config.Combat.HitRadius")
	real("walkSpeed", Config.Movement.WalkSpeed, "Config.Movement.WalkSpeed")
	real("runSpeed", Config.Movement.RunSpeed, "Config.Movement.RunSpeed")
	real("respawnSeconds", Config.Match.RespawnSeconds, "Config.Match.RespawnSeconds")
	real("protectionSeconds", Config.Match.RespawnProtectionSeconds, "Config.Match.RespawnProtectionSeconds")
	tableReal("dodge", {
		maxCharges = Config.Dodge.MaxCharges,
		rechargeSeconds = Config.Dodge.RechargeSeconds,
		invulnSeconds = Config.Dodge.InvulnSeconds,
		distance = Config.Dodge.Distance,
		duration = Config.Dodge.Duration,
	}, "Config.Dodge")
	tableReal("ultimate", {
		max = Config.Ultimate.Max,
		gainPerDamage = Config.Ultimate.GainPerDamage,
		gainPerKill = Config.Ultimate.GainPerKill,
		gainPerSecond = Config.Ultimate.GainPerSecond,
	}, "Config.Ultimate (Phase 1 궁극기는 자리표시자라 시뮬레이션에서도 사용하지 않고 게이지만 기록)")
	real("knockbackEnabled", Config.Knockback.Enabled, "Config.Knockback.Enabled (기본 false → 시뮬레이션도 넉백 없음)")
	local sw, pb = Characters.SWORD, Characters.PAINTBALL
	tableReal("sword", {
		damage = sw.primary.damage, cooldown = sw.primary.cooldown, range = sw.primary.range,
		arcDegrees = sw.primary.arcDegrees, moveMult = sw.primary.moveSpeedMult,
		parry = {
			cooldown = sw.secondary.cooldown, window = sw.secondary.windowSeconds,
			frontArcDegrees = sw.secondary.frontArcDegrees, counterDamage = sw.secondary.counterDamage,
			counterRange = sw.secondary.counterRange, moveMult = sw.secondary.moveSpeedMult,
		},
	}, "Data.Characters.SWORD")
	tableReal("paintball", {
		interval = pb.primary.fireInterval, damage = pb.primary.damage, moveMult = pb.primary.moveSpeedMult,
		speed = pb.primary.projectile.speed, lifetime = pb.primary.projectile.lifetime,
		maxRange = pb.primary.projectile.maxRange, radius = pb.primary.projectile.collision.radius,
		magazine = pb.ammo.magazine, reload = pb.ammo.reloadSeconds,
	}, "Data.Characters.PAINTBALL")

	-- 근사 (APPROX)
	approx("dt", 1 / 30, "고정 틱 30Hz. 실제 서버는 Heartbeat 가변 간격")
	approx("arenaHalf", 45, "정사각 빈 공간(장애물·벽 차단·고저차 없음). BRICKYARD 지형은 시뮬레이션하지 않음")
	approx("spawnRing", 38, "고정 8개 스폰, 가장 먼 적에서 먼 곳 선택. 실제 SpawnDirector 위험도 계산과 다름")
	approx("attackMoveSeconds", 0.3, "공격 직후 moveSpeedMult 가 적용되는 시간(실제 값 미확정)")
	approx("meleeInstant", true, "근접은 휘두르는 즉시 판정(캐릭터 데이터에 선딜 없음). 실제 애니메이션 타이밍은 미검증")
	approx("parryConsumesWindow", true, "패링 성공 1회로 창 종료(문서에 다중 차단 규칙 없음)")
	approx("parryBlocksProjectiles", true, "패링은 전방 180° 근접·투사체 모두 차단한다고 가정")
	approx("parryCooldownFromUse", true, "패링 쿨타임은 사용 시작 시점부터")
	approx("protectedProjectileConsumed", true, "보호 중인 대상에 맞은 투사체는 소멸")
	approx("bot", {
		aimErrorDeg = 3, -- 조준 오차(균등 ±값에 가까운 가우시안 σ)
		reactionSeconds = 0.2, -- 적 위치 인지 지연
		dodgeRate = 2.5, -- 위협 감지 시 초당 회피 시도 확률(레이트)
		parryRate = 4, -- 위협 감지 시 초당 패링 시도 확률
		strafeMin = 0.8, strafeMax = 1.6,
		swordPreferred = 5, paintPreferred = 22, paintRetreat = 14, paintApproach = 32,
		runDistance = 12,
		threatMeleePad = 3, -- 상대 근접 사거리 + 이 값 안이면 위협
		threatProjectileMiss = 1.5, -- 투사체 최근접 거리 < 피격 반지름 + 이 값이면 위협
		threatProjectileLookahead = 0.35, -- 초
	}, "봇 행동 전반. 실제 플레이어 행동이 아님 — 승률은 봇 파라미터에 크게 의존")
	approx("killTarget", 5, "기본 종료 조건: 먼저 N킬")
	approx("timeLimit", 90, "기본 종료 조건: 시간(초)")

	if overrides then
		for k, v in overrides do
			rules[k] = v
		end
	end
	return rules
end

return RuleSet
