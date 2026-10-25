--!nonstrict
-- SWORD 임시(R6 절차적) 모션 타이밍·포즈 데이터. 순수 데이터 — Roblox API 없음. 정식 에셋으로 바꾸려면 MotionRegistry 참고.
--
-- 좌표/각도 규칙 (모든 각도는 도, 몸통 기준 오른손 법칙 회전. +X=캐릭터 오른쪽, +Y=위, +Z=캐릭터 뒤):
--   팔·다리(어깨/고관절에 매달린 아래 방향 벡터 기준): rx>0 = 앞으로 들기, rz>0 = 오른쪽(+X)으로 벌리기(오른팔 바깥/왼팔 안쪽), ry = 수직축 선회(ry>0 = 앞쪽 팔이 왼쪽으로 쓸림)
--   Root/Neck(위쪽 벡터 기준): rx>0 = 뒤로 젖힘(앞으로 숙임은 음수), ry>0 = 왼쪽으로 비틂, rz>0 = 오른쪽으로 기움
--   적용 순서는 yaw(ry)·pitch(rx)·roll(rz). px/py/pz 는 Part0 공간 오프셋(py 음수 = 몸을 낮춤). HRP 실제 위치·서버 이동에는 영향 없음(시각 전용).
-- 시간 t 는 서버 이벤트 수신 기준 초. impact = 서버가 피해를 이미 확정한 시점에 맞춘 "타격 포즈" 키프레임 시각.
--   서버는 입력 즉시 판정하므로 준비 동작은 짧다(≤0.07s). 큰 준비 동작은 Idle 자세(검 든 자세)와 연계 모션의 회복 구간으로 만든다.
local M = {}

-- 포즈 생성 보조: pose(root, rArm, lArm, rLeg, lLeg) — nil 인 관절은 모션이 건드리지 않는다.
local function pose(root, rArm, lArm, rLeg, lLeg)
	local p = {}
	p.Root, p.RArm, p.LArm, p.RLeg, p.LLeg = root, rArm, lArm, rLeg, lLeg
	return p
end

-- 이벤트 → 모션 시간 보정: 서버 이벤트가 이만큼(초)까지 늦게 도착한 것으로 보고 시작 시각을 앞당긴다.
M.MaxCatchUp = 0.12
-- 상태 전환 시 이전 출력 포즈에서 새 포즈로 섞는 시간(초)
M.DefaultBlendIn = 0.04

-- Idle / Run 절차 파라미터 (LocomotionPose)
M.Locomotion = {
	runStartSpeed = 1.5, -- 이보다 느리면 Idle
	runFullSpeed = 6, -- 이 이상이면 Run 100%
	strideHz = 0.075, -- 속도(stud/s) × strideHz = 초당 걸음 주기
	runLegSwing = 42,
	runArmSwing = 38,
	runLean = -9, -- Root rx (음수 = 앞으로 숙임)
	runBob = 0.07,
	idleBreathHz = 0.45,
	idleBreathAmp = 0.035,
}

M.Motions = {
	-- ── 기본 공격 3타 콤보 (Swing step 1~3). 쿨타임 0.55 / 3타 후 0.8 안에 회복 완료. ──
	Slash1 = {
		priority = 2, commit = 0.12, duration = 0.5, fadeOut = 0.16, impact = 0.06,
		keys = {
			{ t = 0.00, pose = pose({ ry = -38, rx = 4 }, { rx = 98, ry = -62, rz = 8 }, { rx = 22, rz = -26 }) },
			{ t = 0.06, ease = "out", pose = pose({ ry = 32, rx = -6 }, { rx = 96, ry = 58 }, { rx = 34, rz = -36 }) },
			{ t = 0.18, ease = "out", pose = pose({ ry = 40, rx = -4 }, { rx = 90, ry = 72 }, { rx = 38, rz = -38 }) },
			{ t = 0.50, ease = "inout", pose = pose({ ry = 0 }, { rx = 38, ry = 0, rz = 14 }, { rx = 10, rz = -12 }) },
		},
	},
	Slash2 = { -- 반대 방향 되베기(왼→오른쪽, 낮게→높게)
		priority = 2, commit = 0.12, duration = 0.5, fadeOut = 0.16, impact = 0.06,
		keys = {
			{ t = 0.00, pose = pose({ ry = 40, rx = -2 }, { rx = 74, ry = 74, rz = 0 }, { rx = 30, rz = -30 }) },
			{ t = 0.06, ease = "out", pose = pose({ ry = -34, rx = 4 }, { rx = 112, ry = -58 }, { rx = 20, rz = -22 }) },
			{ t = 0.18, ease = "out", pose = pose({ ry = -42, rx = 6 }, { rx = 120, ry = -70 }, { rx = 16, rz = -20 }) },
			{ t = 0.50, ease = "inout", pose = pose({ ry = 0 }, { rx = 38, ry = 0, rz = 14 }, { rx = 10, rz = -12 }) },
		},
	},
	Slash3 = { -- 내려찍기(양손). 후딜이 길다.
		priority = 2, commit = 0.2, duration = 0.78, fadeOut = 0.22, impact = 0.07,
		keys = {
			{ t = 0.00, pose = pose({ rx = 14, ry = 0 }, { rx = 172, ry = 0, rz = 6 }, { rx = 150, rz = -14 }, { rx = -18, rz = 6 }, { rx = 20, rz = -6 }) },
			{ t = 0.07, ease = "in", pose = pose({ rx = -26, ry = 0 }, { rx = 46, ry = 4, rz = 2 }, { rx = 44, rz = -10 }, { rx = -34, rz = 8 }, { rx = 30, rz = -8 }) },
			{ t = 0.28, ease = "out", pose = pose({ rx = -28, ry = 0 }, { rx = 40, ry = 4 }, { rx = 40, rz = -10 }, { rx = -34, rz = 8 }, { rx = 30, rz = -8 }) },
			{ t = 0.78, ease = "inout", pose = pose({ rx = 0, ry = 0 }, { rx = 38, ry = 0, rz = 14 }, { rx = 10, rz = -12 }, { rx = -8, rz = 4 }, { rx = 10, rz = -4 }) },
		},
	},

	-- ── Triple Slash (키 3번, 단계별 전진 4 / 0.15s 는 서버 이동. 여기서는 앞으로 숙이는 시각 연출만) ──
	TripleSlash1 = {
		priority = 3, commit = 0.12, duration = 0.34, fadeOut = 0.1, impact = 0.05,
		keys = {
			{ t = 0.00, pose = pose({ ry = -40, rx = -10 }, { rx = 100, ry = -66, rz = 8 }, { rx = 20, rz = -28 }) },
			{ t = 0.05, ease = "out", pose = pose({ ry = 34, rx = -16 }, { rx = 96, ry = 62 }, { rx = 34, rz = -38 }) },
			{ t = 0.34, ease = "inout", pose = pose({ ry = 10, rx = -6 }, { rx = 70, ry = 20, rz = 6 }, { rx = 20, rz = -20 }) },
		},
	},
	TripleSlash2 = {
		priority = 3, commit = 0.12, duration = 0.34, fadeOut = 0.1, impact = 0.05,
		keys = {
			{ t = 0.00, pose = pose({ ry = 42, rx = -10 }, { rx = 76, ry = 76, rz = 0 }, { rx = 30, rz = -30 }) },
			{ t = 0.05, ease = "out", pose = pose({ ry = -36, rx = -14 }, { rx = 114, ry = -60 }, { rx = 20, rz = -22 }) },
			{ t = 0.34, ease = "inout", pose = pose({ ry = -8, rx = -6 }, { rx = 70, ry = -20, rz = 6 }, { rx = 20, rz = -20 }) },
		},
	},
	TripleSlash3 = { -- 마무리 큰 내려베기(피해 22). 가장 큰 포즈.
		priority = 3, commit = 0.2, duration = 0.6, fadeOut = 0.2, impact = 0.07,
		keys = {
			{ t = 0.00, pose = pose({ rx = 16, ry = 0 }, { rx = 175, ry = 0, rz = 6 }, { rx = 155, rz = -14 }, { rx = -22, rz = 6 }, { rx = 24, rz = -6 }) },
			{ t = 0.07, ease = "in", pose = pose({ rx = -32, ry = 0 }, { rx = 44, ry = 4, rz = 2 }, { rx = 42, rz = -10 }, { rx = -40, rz = 8 }, { rx = 34, rz = -8 }) },
			{ t = 0.26, ease = "out", pose = pose({ rx = -34, ry = 0 }, { rx = 38, ry = 4 }, { rx = 38, rz = -10 }, { rx = -40, rz = 8 }, { rx = 34, rz = -8 }) },
			{ t = 0.60, ease = "inout", pose = pose({ rx = 0, ry = 0 }, { rx = 38, ry = 0, rz = 14 }, { rx = 10, rz = -12 }, { rx = -8, rz = 4 }, { rx = 10, rz = -4 }) },
		},
	},

	-- ── Lunge: 충전(Charge) → 돌진 방출(Release) → 회복(Recover). 충전 키 시간은 0~1 정규화(실제 길이 = chargeSeconds). ──
	LungeCharge = {
		priority = 4, commit = 0, duration = 1.0, hold = true, maxDuration = 2.2, blendIn = 0.1,
		wobble = { joint = "Root", field = "rz", amp = 1.6, hz = 13 }, -- 충전 끝에 가까울수록 미세 떨림(화면 흔들림 아님)
		keys = {
			{ t = 0.0, pose = pose({ ry = -20, rx = -8, py = -0.1 }, { rx = 62, ry = -34, rz = 10 }, { rx = 22, rz = -30 }, { rx = 24, rz = 8 }, { rx = -18, rz = -8 }) },
			{ t = 1.0, ease = "out", pose = pose({ ry = -38, rx = -18, py = -0.38 }, { rx = 86, ry = -74, rz = 6 }, { rx = 32, ry = -20, rz = -34 }, { rx = 34, rz = 14 }, { rx = -28, rz = -14 }) },
		},
	},
	LungeRelease = { -- duration 기준 0.28s (서버 dash.duration 에 맞춰 시간 배율)
		priority = 4, commit = 0.28, duration = 0.28, hold = true, maxDuration = 0.6, impact = 0.1, blendIn = 0.03, -- 마지막 자세를 서버 End 이벤트(돌진 종료)까지 유지
		keys = {
			{ t = 0.00, pose = pose({ ry = -38, rx = -18, py = -0.38 }, { rx = 86, ry = -74, rz = 6 }, { rx = 32, ry = -20, rz = -34 }, { rx = 34, rz = 14 }, { rx = -28, rz = -14 }) },
			{ t = 0.10, ease = "out", pose = pose({ ry = 16, rx = -34, py = -0.1 }, { rx = 92, ry = 12, rz = 0 }, { rx = -26, rz = -42 }, { rx = -48, rz = 4 }, { rx = 52, rz = -4 }) },
			{ t = 0.28, pose = pose({ ry = 18, rx = -36, py = 0 }, { rx = 92, ry = 14, rz = 0 }, { rx = -28, rz = -44 }, { rx = -50, rz = 4 }, { rx = 54, rz = -4 }) },
		},
	},
	LungeRecover = { -- Lunge End/Cancel 후 복귀. 어떤 행동이든 끊을 수 있다.
		priority = 1, commit = 0, duration = 0.28, fadeOut = 0.2, blendIn = 0.05,
		keys = {
			{ t = 0.00, pose = pose({ ry = 10, rx = -20, py = -0.1 }, { rx = 80, ry = 8 }, { rx = -10, rz = -36 }, { rx = -30, rz = 4 }, { rx = 34, rz = -4 }) },
			{ t = 0.28, ease = "inout", pose = pose({ ry = 0, rx = 0, py = 0 }, { rx = 38, ry = 0, rz = 14 }, { rx = 10, rz = -12 }, { rx = -8, rz = 4 }, { rx = 10, rz = -4 }) },
		},
	},

	-- ── Blade Wave: 큰 횡베기 후 검기 방출 ──
	BladeWave = {
		priority = 3, commit = 0.3, duration = 0.58, fadeOut = 0.2, impact = 0.07,
		keys = {
			{ t = 0.00, pose = pose({ ry = -44, rx = 8 }, { rx = 124, ry = -84, rz = 14 }, { rx = 62, ry = -44, rz = -20 }) },
			{ t = 0.07, ease = "out", pose = pose({ ry = 46, rx = -10 }, { rx = 92, ry = 74, rz = 0 }, { rx = 74, ry = 64, rz = -14 }) },
			{ t = 0.26, ease = "out", pose = pose({ ry = 52, rx = -8 }, { rx = 88, ry = 84 }, { rx = 70, ry = 70, rz = -14 }) },
			{ t = 0.58, ease = "inout", pose = pose({ ry = 0, rx = 0 }, { rx = 38, ry = 0, rz = 14 }, { rx = 10, rz = -12 }) },
		},
	},

	-- ── Blade Storm: Start → Loop(회전, 틱마다 팔 펄스) → Finisher → Recover. 전 구간 priority 5(회복 제외). ──
	StormStart = {
		priority = 5, commit = 0.3, duration = 0.3, next = "StormLoop", blendIn = 0.06,
		keys = {
			{ t = 0.00, pose = pose({ rx = 0, ry = 0 }, { rx = 60, ry = 0, rz = 14 }, { rx = 30, rz = -14 }) },
			{ t = 0.30, ease = "out", pose = pose({ rx = 10, ry = 0 }, { rx = 168, ry = 0, rz = 10 }, { rx = 150, rz = -10 }) },
		},
	},
	StormLoop = { -- 3s 궁극기. 서버 End 이벤트 또는 maxDuration 에서 끝난다.
		priority = 5, commit = 0, duration = 0.2, hold = true, maxDuration = 3.4, blendIn = 0.08,
		spin = { joint = "Root", field = "ry", degPerSec = 480 },
		pulse = { decay = 0.14, add = { RArm = { rz = 16 }, LArm = { rz = -16 } } }, -- Tick 이벤트마다 팔을 순간적으로 더 벌린다
		keys = {
			{ t = 0.00, pose = pose({ rx = 10, ry = 0 }, { rx = 168, ry = 0, rz = 10 }, { rx = 150, rz = -10 }, { rz = 10 }, { rz = -10 }) },
			{ t = 0.20, ease = "out", pose = pose({ rx = -8, ry = 0 }, { rx = 92, ry = 0, rz = 66 }, { rx = 92, rz = -66 }, { rz = 16 }, { rz = -16 }) },
		},
	},
	StormFinisher = { -- 마무리 25 (2.7s). 크게 내려친다.
		priority = 5, commit = 0.3, duration = 0.5, hold = true, maxDuration = 1.2, impact = 0.07, blendIn = 0.12,
		keys = {
			{ t = 0.00, pose = pose({ rx = 18, ry = 0 }, { rx = 172, ry = 0, rz = 8 }, { rx = 160, rz = -8 }, { rx = -16, rz = 8 }, { rx = 18, rz = -8 }) },
			{ t = 0.07, ease = "in", pose = pose({ rx = -30, ry = 0 }, { rx = 44, ry = 0, rz = 2 }, { rx = 42, rz = -6 }, { rx = -38, rz = 8 }, { rx = 32, rz = -8 }) },
			{ t = 0.50, ease = "out", pose = pose({ rx = -32, ry = 0 }, { rx = 40, ry = 0 }, { rx = 38, rz = -6 }, { rx = -38, rz = 8 }, { rx = 32, rz = -8 }) },
		},
	},
	StormRecover = {
		priority = 1, commit = 0, duration = 0.32, fadeOut = 0.22, blendIn = 0.1,
		keys = {
			{ t = 0.00, pose = pose({ rx = -20, ry = 0 }, { rx = 60, ry = 0, rz = 10 }, { rx = 40, rz = -10 }, { rx = -20, rz = 6 }, { rx = 20, rz = -6 }) },
			{ t = 0.32, ease = "inout", pose = pose({ rx = 0, ry = 0 }, { rx = 38, ry = 0, rz = 14 }, { rx = 10, rz = -12 }, { rx = -8, rz = 4 }, { rx = 10, rz = -4 }) },
		},
	},

	-- ── Parry: 가드(0.4s 유지 후 내림) / 성공 시 반격 ──
	ParryGuard = {
		priority = 4, commit = 0.4, duration = 0.52, fadeOut = 0.14, blendIn = 0.03, impact = 0.07,
		keys = {
			{ t = 0.00, pose = pose({ rx = 0, ry = -6 }, { rx = 60, ry = -10, rz = 14 }, { rx = 30, rz = -12 }) },
			{ t = 0.07, ease = "out", pose = pose({ rx = 9, ry = -12 }, { rx = 128, ry = -14, rz = 0 }, { rx = 84, ry = 22, rz = -8 }) },
			{ t = 0.40, pose = pose({ rx = 9, ry = -12 }, { rx = 128, ry = -14, rz = 0 }, { rx = 84, ry = 22, rz = -8 }) },
			{ t = 0.52, ease = "inout", pose = pose({ rx = 0, ry = 0 }, { rx = 40, ry = 0, rz = 14 }, { rx = 10, rz = -12 }) },
		},
	},
	ParryCounter = { -- 자동 반격 18. 짧은 찌르기.
		priority = 4, commit = 0.2, duration = 0.38, fadeOut = 0.14, impact = 0.05, blendIn = 0.02,
		keys = {
			{ t = 0.00, pose = pose({ rx = 9, ry = -12 }, { rx = 128, ry = -14, rz = 0 }, { rx = 84, ry = 22, rz = -8 }) },
			{ t = 0.05, ease = "out", pose = pose({ rx = -26, ry = 16 }, { rx = 94, ry = 22, rz = 0 }, { rx = 20, rz = -36 }) },
			{ t = 0.20, pose = pose({ rx = -28, ry = 18 }, { rx = 92, ry = 24, rz = 0 }, { rx = 18, rz = -38 }) },
			{ t = 0.38, ease = "inout", pose = pose({ rx = 0, ry = 0 }, { rx = 38, ry = 0, rz = 14 }, { rx = 10, rz = -12 }) },
		},
	},
}

-- 구현 대상 모션 10종(요구 목록)이 사용하는 모션 id. 레지스트리 누락 검사에 쓴다.
M.Groups = {
	Idle = { "Idle" },
	Run = { "Run" },
	Slash1 = { "Slash1" },
	Slash2 = { "Slash2" },
	Slash3 = { "Slash3" },
	Parry = { "ParryGuard", "ParryCounter" },
	TripleSlash = { "TripleSlash1", "TripleSlash2", "TripleSlash3" },
	Lunge = { "LungeCharge", "LungeRelease", "LungeRecover" },
	BladeWave = { "BladeWave" },
	BladeStorm = { "StormStart", "StormLoop", "StormFinisher", "StormRecover" },
}

return M
