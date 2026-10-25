--!strict
-- RoBattles! 공통 설정값. 확정되지 않은 값은 "ASSUMPTION Axx"로 표시하고 docs/ASSUMPTIONS.md에 기록한다.
-- 키 이름은 Enum.KeyCode의 Name 문자열이다(클라이언트에서 Enum.KeyCode[name]으로 변환).

local Config = {
	Movement = {
		WalkSpeed = 17, -- 확정
		RunSpeed = 23, -- 확정
		JumpCount = 1, -- 확정: 기본 1단 점프
		-- 공격 중 이동 속도 배율의 기본값. 공격별 값은 캐릭터 데이터의 moveSpeedMult가 덮어쓴다.
		DefaultAttackMoveMult = 1.0, -- ASSUMPTION A01
	},

	Dodge = {
		MaxCharges = 2, -- 확정
		RechargeSeconds = 5, -- 확정: 충전당 5초
		InvulnSeconds = 0.15, -- 확정: 시작 직후 0.15초
		AllowAirborne = true, -- 확정: 공중 회피 지원
		Distance = 14, -- ASSUMPTION A02
		Duration = 0.25, -- ASSUMPTION A02
	},

	Camera = {
		InitialMode = "Locked", -- 확정: 기본은 마우스 고정 전투 시점. "Free" | "Locked" 설정값 분리
		Distance = 12, -- ASSUMPTION A42: 카메라 거리
		ShoulderOffset = 2.0, -- ASSUMPTION A42: Locked 모드 어깨 너머 오프셋
		PitchMinDegrees = -60, -- ASSUMPTION A42
		PitchMaxDegrees = 70, -- ASSUMPTION A42
		SensitivityDegreesPerPixel = 0.25, -- ASSUMPTION A42
		CollisionRadius = 0.4, -- ASSUMPTION A42: 벽 관통 방지 구 반지름
		MinDistance = 1.5, -- ASSUMPTION A42
		ToggleKey = "V", -- ASSUMPTION A03: 전환키 미확정
		MeleeAimAssistDegrees = 12, -- ASSUMPTION A04: 근접만 약한 방향 보정
		RangedAimAssist = false, -- 확정: 원거리 자동 조준 보정 없음 (변경 금지)
	},

	Input = {
		RunToggleKey = "LeftControl", -- 확정
		DodgeKey = "LeftShift", -- 확정
		UltimateKey = "F", -- 확정
		PrimaryButton = "MouseButton1", -- 확정: LMB 기본 공격
		SecondaryButton = "MouseButton2", -- 확정: RMB 보조 공격(SWORD는 패링)
		ReloadKey = "R", -- 확정: 탄약이 있는 캐릭터(PAINTBALL 등)에만 적용
		Skill1Key = "One", -- 확정: 숫자 1·2·3 일반 스킬
		Skill2Key = "Two",
		Skill3Key = "Three",
		ScoreboardKey = "Tab", -- 확정: 홀드 스코어보드
		FreeLookButton = "MouseButton3", -- ASSUMPTION A40: 자유 시점 회전 입력(RMB는 항상 보조 공격)
	},

	Combat = {
		EyeHeight = 1.5, -- ASSUMPTION A31: 투사체 발사 높이(캐릭터 위치 기준)
		HitRadius = 2.5, -- ASSUMPTION A31: 캐릭터 피격 구 반지름
		HitInvulnerability = false, -- 확정: 일반 피격 무적 없음
		BasicAttackStagger = false, -- 확정: 기본 공격 경직 없음
		StaggerResistWindow = 4.0, -- ASSUMPTION A06: 연속 경직 저항 윈도우(초)
		StaggerResistFactor = 0.5, -- ASSUMPTION A06: 윈도우 내 경직마다 지속시간에 곱해짐
		ChainExplosionFalloff = 0.5, -- ASSUMPTION A07: 동일 공격자 연쇄 폭발 피해 배율(반복마다 곱)
		ChainExplosionMinMult = 0.25, -- ASSUMPTION A07
		ChainExplosionWindow = 1.5, -- ASSUMPTION A07
		-- 확정(TIMEBOMB 사양, A76): req.explosionProfile == "Timebomb" 인 폭발만 쓰는 별도 감쇠. 같은 공격자·같은 대상에 0.3초 안에 반복되면 100% → 60% → 30%(이후 30%).
		-- 다른 캐릭터의 폭발(PAINTBALL Color Bomb 등)과 빔·다단 히트는 위 A07 값을 그대로 쓴다(영향 없음).
		TimebombChainMults = { 1, 0.6, 0.3 },
		TimebombChainWindow = 0.3,
		MaxHealth = 100, -- ASSUMPTION A08
		MaxSingleHitDamage = 200, -- ASSUMPTION A18: 서버 계산 피해의 안전 상한
		StaggerMaxDuration = 0.4, -- ASSUMPTION A19
		HardCCMaxDuration = 1.5, -- ASSUMPTION A20: 기절·에어본 상한
		HardCCImmunity = 3.0, -- ASSUMPTION A20: 기절·에어본 종료 후 면역 시간
		HitRecordRetention = 10, -- ASSUMPTION A21: 중복 피해 기록 보관(초)
	},

	Ultimate = {
		Max = 100, -- 확정: 0~100
		GainPerDamage = 0.2, -- ASSUMPTION A09
		GainPerKill = 20, -- ASSUMPTION A09
		GainPerSecond = 1, -- ASSUMPTION A09
		CancelableByUser = false, -- 확정: 자발적 취소 불가
		CharacterSwitchCarryMax = 40, -- 확정: 캐릭터 변경 시 min(기존 게이지, 40) 이월 (다음 리스폰부터)
	},

	Net = {
		-- 서버 최종 검증용 허용치
		MaxAimDirectionError = 0.1, -- 방향 벡터 길이 허용 오차
		MaxClientTimeSkew = 1.0, -- ASSUMPTION A10: 클라이언트 시각 허용 편차(초)
		MaxRequestsPerSecond = 30, -- ASSUMPTION A10: 플레이어·리모트당 요청 제한
		MeleeRangeTolerance = 2, -- ASSUMPTION A10: 근접 사거리 서버 허용 오차(스터드)
		MaxOriginDeviation = 6, -- ASSUMPTION A22: 클라이언트 조준 원점과 서버 캐릭터 위치 최대 차이
	},

	-- 서버 이동 검증(A41 후속, A48~A52). 일반 이동을 막지 않도록 허용치를 넉넉히 둔다. 모든 값은 Studio 실측 후 조정 대상.
	MoveCheck = {
		SpeedTolerance = 1.25, -- 최대 이동 속도(RunSpeed)에 곱하는 배율
		LatencySlackSeconds = 0.25, -- 네트워크 지연·프레임 지터로 한 번에 더 이동한 것으로 보이는 허용 시간
		MaxSampleDt = 0.5, -- 샘플 간격 상한(그 이상 끊겼어도 허용량 계산은 이 값까지만)
		ExcessThreshold = 6, -- 초과 이동(스터드) 누적이 이 값을 넘으면 위치 보정
		ExcessDecayPerSecond = 8, -- 초과 이동 누적의 초당 감쇠
		HardStep = 40, -- 허용량을 이만큼 넘으면 누적 없이 즉시 보정(순간이동)
		MaxUpSpeed = 70, -- 상승 속도 상한(기본 점프 힘 50 기준)
		BodyRadius = 1, -- 벽 관통 검사용 반지름
		WallSkin = 0.3, -- 회피가 벽 앞에서 멈출 여유 거리
		WallPenetration = 0.75, -- 벽을 가로지른 것으로 판정하는 최소 관통 길이(스터드)
		DodgeWindowGrace = 0.25, -- 회피 종료 후 지연으로 늦게 도착하는 위치를 허용하는 시간
		DodgeTolerance = 1.3, -- 회피 총 이동량 허용 배율
		MaxAirDodges = 1, -- 한 번의 체공(착지 전) 동안 허용되는 공중 회피 횟수
		GroundProbe = 4, -- 발 아래 지면 확인 거리(HRP 기준)
		MaxCorrectionsPerSecond = 4, -- 보정 남발 방지(초과 시 서버 로그 대상)
		ImpulseGrace = 0.25,
		-- 서버가 발급하는 이동 허가(permit) 종류별 상한(A58). 클라이언트는 허가를 요청할 수 없고, 서버 코드만 issue 한다.
		-- maxSpeed: 수평 속도 상한, maxUp: 상승 속도 상한, maxDuration: 유효 시간 상한, minInterval: 같은 종류 재발급 최소 간격
		-- directional: true 면 허가된 방향 성분만 추가 이동으로 인정. 값은 전부 임시이며 스킬 확정 시 교체한다(Lunge~BlastJump 는 미구현 스킬용 예약).
		Permits = {
			JumpPad = { maxSpeed = 60, maxUp = 90, maxDuration = 1.0, minInterval = 0.3, directional = false },
			Knockback = { maxSpeed = 200, maxUp = 100, maxDuration = 0.6, minInterval = 0, directional = false },
			Lunge = { maxSpeed = 80, maxUp = 0, maxDuration = 0.4, minInterval = 1, directional = true },
			TripleSlash = { maxSpeed = 40, maxUp = 0, maxDuration = 1.0, minInterval = 0.25, directional = true }, -- A65: SWORD 구현으로 단계 간 최소 간격 0.25초로 조정
			PaintSlide = { maxSpeed = 45, maxUp = 0, maxDuration = 1.5, minInterval = 1, directional = true },
			BounceDash = { maxSpeed = 90, maxUp = 40, maxDuration = 0.8, minInterval = 1, directional = false },
			BlastJump = { maxSpeed = 70, maxUp = 110, maxDuration = 1.2, minInterval = 1, directional = false },
			BlastGuard = { maxSpeed = 60, maxUp = 20, maxDuration = 0.5, minInterval = 1, directional = false }, -- A76: TIMEBOMB Blast Guard 자기 반동
		},
		MaxActivePermits = 8,	},

	Projectile = {
		MaxStepSeconds = 1 / 30, -- ASSUMPTION A29: 투사체 시뮬레이션 최대 하위 스텝
		MaxActivePerOwner = 64, -- ASSUMPTION A29
		MaxActiveTotal = 1024, -- ASSUMPTION A29
		SurfaceEpsilon = 0.02, -- ASSUMPTION A29: 반사 후 표면에서 띄우는 거리
		MaxEventsPerAdvance = 16, -- ASSUMPTION A29: 한 번의 전진에서 처리할 최대 충돌 이벤트
	},

	Parry = {
		Enabled = true, -- 확정 사양은 Data/Characters.SWORD.secondary 참고
	},

	Hud = {
		StateSyncHz = 10, -- ASSUMPTION A43: 서버 → 클라이언트 상태 스냅샷 주기
		AimSyncHz = 15, -- ASSUMPTION A70: 시전 중 조준 갱신(Aim 리모트) 전송 주기 — PAINTBALL Color Break 중에만 전송
		ScoreboardSyncSeconds = 1, -- ASSUMPTION A43
		RunReconcileTimeout = 1.0, -- ASSUMPTION A43: 달리기 토글 서버 확인 대기 상한(초)
	},

	Ultimate_Dev = {
		-- 실플레이에서는 항상 false여야 한다. 자리표시자 궁극기를 실행하려면 테스트 코드가 컨트롤러 옵션으로 명시해야 한다.
		AllowMockUltimate = false,
	},

	Match = {
		MaxPlayers = 12, -- 확정 목표
		RespawnSeconds = 4, -- 확정: 사망 후 4초 뒤 부활
		RespawnProtectionSeconds = 2, -- 확정: 부활 후 2초 피해 면역(공격 행동 시작 시 즉시 해제)
		MaxLoadsPerWindow = 6, -- ASSUMPTION A57: 무한 리스폰 방지 — 이 창(WindowSeconds) 안의 캐릭터 로드 상한
		LoadWindowSeconds = 30,
		MaxLoadAttempts = 5, -- 로드 실패 재시도 상한
		LoadTimeoutSeconds = 10, -- 로드 호출이 반환한 뒤 CharacterAdded 가 오지 않으면 실패로 처리 / 호출이 이만큼 길어지면 slow 로그
		LoadHangSeconds = 60, -- 호출이 반환하지 않는 채 이 시간이 지나면 hung 로 기록하고 재시도 중단(호출 취소 안 함)
	},

	-- 서버 넉백 적용(A59). 기본 꺼짐: 켜면 DamageService 의 Knockback 효과 결과를 HRP 속도로 적용하고 이동 허가를 발급한다.
	Knockback = { Enabled = false, Duration = 0.4 },

	-- 스폰 선택 보조 규칙(A54). 위험도 계산 자체는 맵 쪽 SpawnRisk 가 하고, 여기는 전투 쪽 안전 필터다.
	Spawn = {
		MinEnemyDistance = 16, -- 생존 적이 이 거리 안에 있는 스폰은 다른 후보가 있으면 제외
		ReserveSeconds = 2, -- 다른 플레이어가 방금 고른 스폰을 잠깐 예약(동시 리스폰 겹침 방지)
		RecentCount = 2, -- 같은 플레이어가 최근 사용한 스폰 기억 개수(연속 같은 자리 방지)
		ForceFieldGuardSeconds = 2, -- 스폰 직후 이 시간 동안만, 서버 관리 표시가 없는 ForceField 를 제거(엔진 스폰 ForceField 방지)
		HrpOffset = 3.2, -- 지면 → HumanoidRootPart 높이
		TopN = 3, -- 위험도 하위 N개 중 무작위(예측 가능한 스폰 완화). 1이면 항상 최저 위험
	},
}

return Config
