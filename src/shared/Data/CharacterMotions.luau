--!nonstrict
-- SWORD 외 캐릭터의 임시(R6 절차적) 모션 타이밍·포즈 데이터. 순수 데이터 — Roblox API 없음.
-- 형식·각도 규칙은 SwordMotions.luau 머리말과 동일(도, 몸통 기준 오른손 법칙. 팔: rx>0 앞으로 들기, ry>0 앞쪽 팔이 왼쪽으로 쓸림, rz>0 +X 쪽으로 벌림.
-- Root/Neck: rx>0 뒤로 젖힘, ry>0 왼쪽 비틂(= 오른쪽 어깨가 앞으로)). 값은 추정치이며 Studio 에서 다듬는다.
-- 서버는 입력 즉시 판정하므로 타격/발사 포즈(impact)는 이벤트 후 0.03~0.08초 안에 둔다(큰 준비 동작은 충전·전조 이벤트가 있는 모션에만).
-- Phase 1: PAINTBALL, SLINGSHOT.  Phase 2: SUPERBALL, TIMEBOMB.
local M = {}

local function pose(root, rArm, lArm, rLeg, lLeg)
	local p = {}
	p.Root, p.RArm, p.LArm, p.RLeg, p.LLeg = root, rArm, lArm, rLeg, lLeg
	return p
end

local COMMON = { MaxCatchUp = 0.12, DefaultBlendIn = 0.04 }

-- ─────────────────────────── PAINTBALL ───────────────────────────
-- 오른손 마커(페인트 총)를 앞으로 겨눈 준비 자세. 오른쪽 어깨가 약간 앞.
M.PAINTBALL = {
	MaxCatchUp = COMMON.MaxCatchUp, DefaultBlendIn = COMMON.DefaultBlendIn,
	Locomotion = {
		runStartSpeed = 1.5, runFullSpeed = 6, strideHz = 0.075, runLegSwing = 40, runLean = -8, runBob = 0.06,
		idleBreathHz = 0.45, idleBreathAmp = 0.03, armBob = 3,
		freeArms = {}, -- 달릴 때 흔들리는 팔(없음: 두 팔 모두 총을 잡고 있다)
		stance = {
			Root = { ry = 10 }, Neck = { ry = -10 },
			RArm = { rx = 82, ry = 10, rz = 4 }, LArm = { rx = 70, ry = -25, rz = -4 },
			RLeg = { rx = -10, rz = 5 }, LLeg = { rx = 12, rz = -5 },
		},
	},
	Motions = {
		PaintFire = { -- Spawned(paint_shot): 초당 3발 자동 연사. 짧은 반동.
			priority = 2, commit = 0, duration = 0.16, fadeOut = 0.08, impact = 0.03, blendIn = 0.02,
			keys = {
				{ t = 0.00, pose = pose({ rx = 0 }, { rx = 82, ry = 10 }, { rx = 70, ry = -25 }) },
				{ t = 0.03, ease = "out", pose = pose({ rx = 3 }, { rx = 92, ry = 10 }, { rx = 74, ry = -25 }) },
				{ t = 0.16, ease = "inout", pose = pose({ rx = 0 }, { rx = 82, ry = 10 }, { rx = 70, ry = -25 }) },
			},
		},
		PaintReload = { -- 로컬 재장전 시작(State 스냅샷)에서만 재생. 길이는 ammo.reloadSeconds(1.2)
			priority = 3, commit = 1.2, duration = 1.2, fadeOut = 0.15, blendIn = 0.08,
			keys = {
				{ t = 0.00, pose = pose({ rx = 0 }, { rx = 82, ry = 10 }, { rx = 70, ry = -25 }) },
				{ t = 0.20, ease = "inout", pose = pose({ rx = -4 }, { rx = 50, ry = 26, rz = 10 }, { rx = 48, ry = -12 }) },
				{ t = 0.60, ease = "inout", pose = pose({ rx = -4 }, { rx = 46, ry = 28, rz = 10 }, { rx = 38, ry = 6 }) },
				{ t = 0.90, ease = "inout", pose = pose({ rx = -2 }, { rx = 52, ry = 24, rz = 8 }, { rx = 50, ry = -14 }) },
				{ t = 1.20, ease = "inout", pose = pose({ rx = 0 }, { rx = 82, ry = 10 }, { rx = 70, ry = -25 }) },
			},
		},
		PaintReloadDone = { -- Reloaded 이벤트(모든 플레이어): 장전 완료 펌프 동작
			priority = 3, commit = 0, duration = 0.3, fadeOut = 0.1, blendIn = 0.04,
			keys = {
				{ t = 0.00, pose = pose({ rx = 0 }, { rx = 74, ry = 14 }, { rx = 60, ry = -18 }) },
				{ t = 0.10, ease = "out", pose = pose({ rx = 2 }, { rx = 70, ry = 12 }, { rx = 56, ry = -12 }) },
				{ t = 0.30, ease = "inout", pose = pose({ rx = 0 }, { rx = 82, ry = 10 }, { rx = 70, ry = -25 }) },
			},
		},
		PaintBurst = { -- CharSkill paint.burst (RMB 산탄 5발): 양손으로 밀어 쏘는 큰 반동
			priority = 3, commit = 0.15, duration = 0.45, fadeOut = 0.15, impact = 0.04, blendIn = 0.02,
			keys = {
				{ t = 0.00, pose = pose({ rx = 0 }, { rx = 82, ry = 10 }, { rx = 70, ry = -25 }) },
				{ t = 0.04, ease = "out", pose = pose({ rx = 8 }, { rx = 98, ry = 12 }, { rx = 92, ry = -24 }) },
				{ t = 0.16, ease = "out", pose = pose({ rx = 6 }, { rx = 94, ry = 12 }, { rx = 88, ry = -22 }) },
				{ t = 0.45, ease = "inout", pose = pose({ rx = 0 }, { rx = 82, ry = 10 }, { rx = 70, ry = -25 }) },
			},
		},
		BombThrow = { -- CharSkill paint.bomb.throw (Color Bomb): 아래손 던지기
			priority = 3, commit = 0.2, duration = 0.5, fadeOut = 0.18, impact = 0.08, blendIn = 0.03,
			keys = {
				{ t = 0.00, pose = pose({ ry = 16, rx = 4 }, { rx = -60, ry = 0, rz = 8 }, { rx = 70, ry = -20 }) },
				{ t = 0.08, ease = "out", pose = pose({ ry = -10, rx = -14 }, { rx = 140, ry = 0, rz = 0 }, { rx = 40, ry = -10 }) },
				{ t = 0.22, ease = "out", pose = pose({ ry = -12, rx = -12 }, { rx = 118, ry = 4 }, { rx = 36, ry = -8 }) },
				{ t = 0.50, ease = "inout", pose = pose({ ry = 10, rx = 0 }, { rx = 82, ry = 10, rz = 4 }, { rx = 70, ry = -25, rz = -4 }) },
			},
		},
		PierceFire = { -- CharSkill paint.pierce.fire (Piercing Shot): 무거운 단발 반동
			priority = 3, commit = 0.25, duration = 0.55, fadeOut = 0.2, impact = 0.05, blendIn = 0.03,
			keys = {
				{ t = 0.00, pose = pose({ rx = 0, ry = 10 }, { rx = 82, ry = 10 }, { rx = 70, ry = -25 }) },
				{ t = 0.05, ease = "out", pose = pose({ rx = 10, ry = 6 }, { rx = 106, ry = 8 }, { rx = 94, ry = -30 }) },
				{ t = 0.22, ease = "out", pose = pose({ rx = 8, ry = 8 }, { rx = 100, ry = 8 }, { rx = 90, ry = -28 }) },
				{ t = 0.55, ease = "inout", pose = pose({ rx = 0, ry = 10 }, { rx = 82, ry = 10 }, { rx = 70, ry = -25 }) },
			},
		},
		PaintSlide = { -- CharSkill paint.slide (이동기): 낮게 기울인 활강. 길이는 서버 dash.duration(0.4)에 맞춘다
			priority = 3, commit = 0.4, duration = 0.4, fadeOut = 0.1, blendIn = 0.05,
			keys = {
				{ t = 0.00, pose = pose({ rx = 0, py = 0 }, { rx = 82, ry = 10 }, { rx = 70, ry = -25 }, { rx = -10 }, { rx = 12 }) },
				{ t = 0.08, ease = "out", pose = pose({ rx = -22, rz = 6, py = -0.3 }, { rx = 60, rz = 14 }, { rx = 30, rz = -30 }, { rx = -40, rz = 8 }, { rx = 34, rz = -8 }) },
				{ t = 0.32, pose = pose({ rx = -22, rz = 6, py = -0.3 }, { rx = 60, rz = 14 }, { rx = 30, rz = -30 }, { rx = -40, rz = 8 }, { rx = 34, rz = -8 }) },
				{ t = 0.40, ease = "inout", pose = pose({ rx = -6, rz = 0, py = -0.05 }, { rx = 78, ry = 10 }, { rx = 62, ry = -20 }, { rx = -14 }, { rx = 16 }) },
			},
		},
		-- 궁극기 Color Break: Windup(전조 0.8s, 서버 windup 값) → Beam(Tick 마다 유지 연장) → Recover. 전 구간 priority 5(회복 제외).
		ColorBreakWindup = {
			priority = 5, commit = 0.8, duration = 0.8, next = "ColorBreakBeam", blendIn = 0.08,
			wobble = { joint = "Root", field = "rz", amp = 1.2, hz = 12 },
			keys = {
				{ t = 0.00, pose = pose({ rx = 0, py = 0 }, { rx = 82, ry = 10 }, { rx = 70, ry = -25 }, { rx = -10 }, { rx = 12 }) },
				{ t = 0.80, ease = "in", pose = pose({ rx = 8, py = -0.15 }, { rx = 100, ry = 5 }, { rx = 98, ry = -18 }, { rx = -18, rz = 8 }, { rx = 24, rz = -8 }) },
			},
		},
		ColorBreakBeam = { -- 서버 Tick(0.25s 간격) 마다 만료를 +tickExtend 연장 → 틱 횟수·지속시간이 바뀌어도 대응
			priority = 5, commit = 0, duration = 0.2, hold = true, maxDuration = 1.0, tickExtend = 0.6, blendIn = 0.05,
			wobble = { joint = "Root", field = "rz", amp = 0.8, hz = 16 },
			keys = {
				{ t = 0.00, pose = pose({ rx = 8, py = -0.15 }, { rx = 100, ry = 5 }, { rx = 98, ry = -18 }, { rx = -18, rz = 8 }, { rx = 24, rz = -8 }) },
				{ t = 0.20, ease = "out", pose = pose({ rx = 6, py = -0.12 }, { rx = 92, ry = 6 }, { rx = 90, ry = -16 }, { rx = -18, rz = 8 }, { rx = 24, rz = -8 }) },
			},
		},
		ColorBreakRecover = {
			priority = 1, commit = 0, duration = 0.35, fadeOut = 0.25, blendIn = 0.1,
			keys = {
				{ t = 0.00, pose = pose({ rx = 4, py = -0.08 }, { rx = 92, ry = 6 }, { rx = 90, ry = -16 }, { rx = -16, rz = 6 }, { rx = 20, rz = -6 }) },
				{ t = 0.35, ease = "inout", pose = pose({ rx = 0, py = 0 }, { rx = 82, ry = 10, rz = 4 }, { rx = 70, ry = -25, rz = -4 }, { rx = -10, rz = 5 }, { rx = 12, rz = -5 }) },
			},
		},
	},
	-- 실제 Characters.PAINTBALL 보유 행동 → 모션 id (레지스트리 누락 검사용)
	Groups = {
		Idle = { "Idle" }, Run = { "Run" }, PaintShot = { "PaintFire" }, Reload = { "PaintReload", "PaintReloadDone" },
		PaintBurst = { "PaintBurst" }, ColorBomb = { "BombThrow" }, PiercingShot = { "PierceFire" }, PaintSlide = { "PaintSlide" },
		ColorBreak = { "ColorBreakWindup", "ColorBreakBeam", "ColorBreakRecover" },
	},
}

-- ─────────────────────────── SLINGSHOT ───────────────────────────
-- 왼팔로 새총 틀을 앞으로 뻗고 오른손으로 고무줄을 당기는 자세. 왼쪽 어깨가 앞(Root ry 음수).
M.SLINGSHOT = {
	MaxCatchUp = COMMON.MaxCatchUp, DefaultBlendIn = COMMON.DefaultBlendIn,
	Locomotion = {
		runStartSpeed = 1.5, runFullSpeed = 6, strideHz = 0.075, runLegSwing = 40, runLean = -8, runBob = 0.06,
		idleBreathHz = 0.45, idleBreathAmp = 0.03, armBob = 3,
		freeArms = { "RArm" }, -- 달릴 때 오른팔은 자유롭게 흔든다(왼팔은 새총을 든 채 유지)
		runArmSwing = 30,
		stance = {
			Root = { ry = -18 }, Neck = { ry = 18 },
			RArm = { rx = 45, ry = 20, rz = 6 }, LArm = { rx = 84, ry = -8, rz = -4 },
			RLeg = { rx = -10, rz = 5 }, LLeg = { rx = 12, rz = -5 },
		},
	},
	Motions = {
		SlingCharge = { -- CharSkill sling.charge (LMB 누름): 충전 진행(키 시간 0~1 정규화, 길이=chargeSeconds). Release 까지 유지
			priority = 4, commit = 0, duration = 1.0, hold = true, maxDuration = 5.0, blendIn = 0.1,
			wobble = { joint = "Root", field = "rz", amp = 1.0, hz = 12 },
			keys = {
				{ t = 0.0, pose = pose({ ry = -20, rx = 0 }, { rx = 60, ry = 10, rz = 8 }, { rx = 86, ry = -8 }) },
				{ t = 1.0, ease = "out", pose = pose({ ry = -26, rx = 2 }, { rx = 95, ry = -70, rz = 20 }, { rx = 92, ry = -6 }) },
			},
		},
		SlingRelease = { -- CharSkill sling.shot (놓음 또는 즉시 발사): 줄이 튕기는 반동
			priority = 3, commit = 0.1, duration = 0.3, fadeOut = 0.1, impact = 0.04, blendIn = 0.02,
			keys = {
				{ t = 0.00, pose = pose({ ry = -26, rx = 2 }, { rx = 95, ry = -70, rz = 20 }, { rx = 92, ry = -6 }) },
				{ t = 0.04, ease = "out", pose = pose({ ry = -18, rx = 4 }, { rx = 60, ry = 10, rz = 8 }, { rx = 90, ry = -8 }) },
				{ t = 0.30, ease = "inout", pose = pose({ ry = -18, rx = 0 }, { rx = 45, ry = 20, rz = 6 }, { rx = 84, ry = -8, rz = -4 }) },
			},
		},
		SlingTriple = { -- CharSkill sling.triple (Triple Shot): 빠른 3연 당김-놓음
			priority = 3, commit = 0.2, duration = 0.5, fadeOut = 0.12, impact = 0.05, blendIn = 0.03,
			keys = {
				{ t = 0.00, pose = pose({ ry = -22 }, { rx = 90, ry = -50, rz = 14 }, { rx = 88, ry = -8 }) },
				{ t = 0.05, ease = "out", pose = pose({ ry = -18 }, { rx = 60, ry = 10, rz = 8 }, { rx = 90, ry = -8 }) },
				{ t = 0.17, pose = pose({ ry = -22 }, { rx = 90, ry = -50, rz = 14 }, { rx = 88, ry = -8 }) },
				{ t = 0.22, ease = "out", pose = pose({ ry = -18 }, { rx = 60, ry = 10, rz = 8 }, { rx = 90, ry = -8 }) },
				{ t = 0.34, pose = pose({ ry = -22 }, { rx = 90, ry = -50, rz = 14 }, { rx = 88, ry = -8 }) },
				{ t = 0.39, ease = "out", pose = pose({ ry = -18 }, { rx = 60, ry = 10, rz = 8 }, { rx = 90, ry = -8 }) },
				{ t = 0.50, ease = "inout", pose = pose({ ry = -18 }, { rx = 45, ry = 20, rz = 6 }, { rx = 84, ry = -8, rz = -4 }) },
			},
		},
		SlingSnare = { -- CharSkill sling.snare (Snare Shot): 아래에서 위로 크게 퍼 올려 쏜다
			priority = 3, commit = 0.2, duration = 0.5, fadeOut = 0.15, impact = 0.06, blendIn = 0.03,
			keys = {
				{ t = 0.00, pose = pose({ ry = -24, rx = -2 }, { rx = 20, ry = -30, rz = 14 }, { rx = 60, ry = -6 }) },
				{ t = 0.06, ease = "out", pose = pose({ ry = -16, rx = -8 }, { rx = 74, ry = 8, rz = 6 }, { rx = 96, ry = -8 }) },
				{ t = 0.20, ease = "out", pose = pose({ ry = -16, rx = -6 }, { rx = 68, ry = 10, rz = 6 }, { rx = 92, ry = -8 }) },
				{ t = 0.50, ease = "inout", pose = pose({ ry = -18, rx = 0 }, { rx = 45, ry = 20, rz = 6 }, { rx = 84, ry = -8, rz = -4 }) },
			},
		},
		SlingBackstep = { -- CharSkill sling.backstep (이동기+사격): 몸을 젖히며 뒤로 물러나 쏜다. 위치 이동은 서버 permit 이 담당
			priority = 3, commit = 0.25, duration = 0.4, fadeOut = 0.12, impact = 0.05, blendIn = 0.03,
			keys = {
				{ t = 0.00, pose = pose({ rx = 0, ry = -18 }, { rx = 45, ry = 20, rz = 6 }, { rx = 84, ry = -8 }, { rx = -10 }, { rx = 12 }) },
				{ t = 0.05, ease = "out", pose = pose({ rx = 14, ry = -14 }, { rx = 66, ry = 6, rz = 8 }, { rx = 96, ry = -6 }, { rx = 24, rz = 6 }, { rx = -30, rz = -6 }) },
				{ t = 0.25, pose = pose({ rx = 12, ry = -14 }, { rx = 62, ry = 8, rz = 8 }, { rx = 94, ry = -6 }, { rx = 20, rz = 6 }, { rx = -26, rz = -6 }) },
				{ t = 0.40, ease = "inout", pose = pose({ rx = 0, ry = -18 }, { rx = 45, ry = 20, rz = 6 }, { rx = 84, ry = -8 }, { rx = -10 }, { rx = 12 }) },
			},
		},
		-- 궁극기 Bullseye: Aim(전조 0.7s, 서버 windup 값 → Fire 까지 유지) → Fire → (중단 시) Recover
		BullseyeAim = {
			priority = 5, commit = 0.7, duration = 0.7, hold = true, maxDuration = 2.5, blendIn = 0.08,
			wobble = { joint = "Root", field = "rz", amp = 0.8, hz = 12 },
			keys = {
				{ t = 0.00, pose = pose({ ry = -18, rx = 0 }, { rx = 45, ry = 20, rz = 6 }, { rx = 84, ry = -8 }, { rx = -10 }, { rx = 12 }) },
				{ t = 0.70, ease = "inout", pose = pose({ ry = -26, rx = -4 }, { rx = 100, ry = -80, rz = 18 }, { rx = 100, ry = -4 }, { rx = -16, rz = 6 }, { rx = 20, rz = -6 }) },
			},
		},
		BullseyeFire = {
			priority = 5, commit = 0.3, duration = 0.55, fadeOut = 0.2, impact = 0.04, blendIn = 0.02,
			keys = {
				{ t = 0.00, pose = pose({ ry = -26, rx = -4 }, { rx = 100, ry = -80, rz = 18 }, { rx = 100, ry = -4 }, { rx = -16, rz = 6 }, { rx = 20, rz = -6 }) },
				{ t = 0.04, ease = "out", pose = pose({ ry = -16, rx = 8 }, { rx = 60, ry = 10, rz = 8 }, { rx = 96, ry = -4 }, { rx = -14, rz = 6 }, { rx = 18, rz = -6 }) },
				{ t = 0.55, ease = "inout", pose = pose({ ry = -18, rx = 0 }, { rx = 45, ry = 20, rz = 6 }, { rx = 84, ry = -8, rz = -4 }, { rx = -10, rz = 5 }, { rx = 12, rz = -5 }) },
			},
		},
		BullseyeRecover = {
			priority = 1, commit = 0, duration = 0.35, fadeOut = 0.25, blendIn = 0.1,
			keys = {
				{ t = 0.00, pose = pose({ ry = -22, rx = -2 }, { rx = 80, ry = -40, rz = 12 }, { rx = 94, ry = -6 }, { rx = -14, rz = 6 }, { rx = 16, rz = -6 }) },
				{ t = 0.35, ease = "inout", pose = pose({ ry = -18, rx = 0 }, { rx = 45, ry = 20, rz = 6 }, { rx = 84, ry = -8, rz = -4 }, { rx = -10, rz = 5 }, { rx = 12, rz = -5 }) },
			},
		},
	},
	-- Aim Mode(RMB)는 서버 이벤트가 없는 클라이언트 전용 기능이라 이번 범위에서 모션을 만들지 않았다(Idle 자세 유지).
	Groups = {
		Idle = { "Idle" }, Run = { "Run" }, ChargedShot = { "SlingCharge", "SlingRelease" }, TripleShot = { "SlingTriple" },
		SnareShot = { "SlingSnare" }, BackstepShot = { "SlingBackstep" },
		Bullseye = { "BullseyeAim", "BullseyeFire", "BullseyeRecover" },
	},
}

-- ─────────────────────────── SUPERBALL ───────────────────────────
-- 오른손에 공을 쥔 자세, 왼팔은 자유. 던지기 전조는 충전(ball.charge)에만 있고 즉시 던지기는 짧은 투구 동작이다.
local SB_STANCE_R = { rx = 55, ry = 12, rz = 6 }
local SB_STANCE_L = { rx = 40, ry = -14, rz = -6 }
M.SUPERBALL = {
	MaxCatchUp = COMMON.MaxCatchUp, DefaultBlendIn = COMMON.DefaultBlendIn,
	Locomotion = {
		runStartSpeed = 1.5, runFullSpeed = 6, strideHz = 0.075, runLegSwing = 40, runLean = -8, runBob = 0.06,
		idleBreathHz = 0.45, idleBreathAmp = 0.03, armBob = 3,
		freeArms = { "LArm" }, runArmSwing = 28,
		stance = {
			Root = { ry = 6 }, Neck = { ry = -6 }, RArm = SB_STANCE_R, LArm = SB_STANCE_L,
			RLeg = { rx = -10, rz = 5 }, LLeg = { rx = 12, rz = -5 },
		},
	},
	Motions = {
		BallCharge = { -- ball.charge (LMB 누름): 공을 뒤로 젖혀 든다. 길이 = chargeSeconds, 던지기 이벤트까지 유지(서버도 4.5초 뒤 충전을 정리)
			priority = 4, commit = 0, duration = 1.0, hold = true, maxDuration = 4.5, blendIn = 0.1,
			wobble = { joint = "Root", field = "rz", amp = 1.0, hz = 12 },
			keys = {
				{ t = 0.0, pose = pose({ ry = 4, rx = 0 }, { rx = 55, ry = 12, rz = 6 }, { rx = 40, ry = -14, rz = -6 }) },
				{ t = 1.0, ease = "out", pose = pose({ ry = -24, rx = -4 }, { rx = -70, ry = 0, rz = 14 }, { rx = 95, ry = -10, rz = -8 }) },
			},
		},
		BallThrow = { -- ball.throw: 즉시/약한 던지기
			priority = 3, commit = 0.15, duration = 0.45, fadeOut = 0.15, impact = 0.05, blendIn = 0.02,
			keys = {
				{ t = 0.00, pose = pose({ ry = -20, rx = -3 }, { rx = -60, rz = 12 }, { rx = 90, ry = -10 }) },
				{ t = 0.05, ease = "out", pose = pose({ ry = 16, rx = 6 }, { rx = 150, ry = -4 }, { rx = 60, ry = 10 }) },
				{ t = 0.18, pose = pose({ ry = 14, rx = 4 }, { rx = 132, ry = -2 }, { rx = 56, ry = 10 }) },
				{ t = 0.45, ease = "inout", pose = pose({ ry = 6, rx = 0 }, { rx = 55, ry = 12, rz = 6 }, { rx = 40, ry = -14, rz = -6 }) },
			},
		},
		BallThrowCharged = { -- ball.throw.charged: 충전 던지기(큰 팔로우스루)
			priority = 3, commit = 0.2, duration = 0.6, fadeOut = 0.2, impact = 0.06, blendIn = 0.02,
			keys = {
				{ t = 0.00, pose = pose({ ry = -26, rx = -4 }, { rx = -80, rz = 14 }, { rx = 100, ry = -10 }) },
				{ t = 0.06, ease = "out", pose = pose({ ry = 22, rx = 10 }, { rx = 165, ry = -4 }, { rx = 50, ry = 14 }) },
				{ t = 0.25, pose = pose({ ry = 20, rx = 8 }, { rx = 150, ry = -2 }, { rx = 46, ry = 14 }) },
				{ t = 0.60, ease = "inout", pose = pose({ ry = 6, rx = 0 }, { rx = 55, ry = 12, rz = 6 }, { rx = 40, ry = -14, rz = -6 }) },
			},
		},
		BounceDash = { -- ball.dash (이동기): 몸을 웅크려 공처럼 굴러간다. 길이 = 서버 dash.duration
			priority = 3, commit = 0.25, duration = 0.25, fadeOut = 0.08, blendIn = 0.04,
			keys = {
				{ t = 0.00, pose = pose({ rx = 0, py = 0 }, { rx = 55, ry = 12, rz = 6 }, { rx = 40, ry = -14, rz = -6 }, { rx = -10, rz = 5 }, { rx = 12, rz = -5 }) },
				{ t = 0.06, ease = "out", pose = pose({ rx = 28, py = -0.2 }, { rx = 70, rz = 20 }, { rx = 70, rz = -20 }, { rx = -50, rz = 4 }, { rx = 60, rz = -4 }) },
				{ t = 0.20, pose = pose({ rx = 28, py = -0.2 }, { rx = 70, rz = 20 }, { rx = 70, rz = -20 }, { rx = -50, rz = 4 }, { rx = 60, rz = -4 }) },
				{ t = 0.25, ease = "inout", pose = pose({ rx = 6, py = -0.05 }, { rx = 55, ry = 12, rz = 6 }, { rx = 40, ry = -14, rz = -6 }, { rx = -14, rz = 5 }, { rx = 16, rz = -5 }) },
			},
		},
		RapidBounce = { -- ball.rapid (스킬1): 빠른 3연 투구
			priority = 3, commit = 0.2, duration = 0.55, fadeOut = 0.12, impact = 0.05, blendIn = 0.03,
			keys = {
				{ t = 0.00, pose = pose({ ry = -16 }, { rx = -50, rz = 12 }, { rx = 80 }) },
				{ t = 0.05, ease = "out", pose = pose({ ry = 12 }, { rx = 140 }, { rx = 56 }) },
				{ t = 0.17, pose = pose({ ry = -16 }, { rx = -50, rz = 12 }, { rx = 80 }) },
				{ t = 0.22, ease = "out", pose = pose({ ry = 12 }, { rx = 140 }, { rx = 56 }) },
				{ t = 0.34, pose = pose({ ry = -16 }, { rx = -50, rz = 12 }, { rx = 80 }) },
				{ t = 0.39, ease = "out", pose = pose({ ry = 12 }, { rx = 140 }, { rx = 56 }) },
				{ t = 0.55, ease = "inout", pose = pose({ ry = 6 }, { rx = 55, ry = 12, rz = 6 }, { rx = 40, ry = -14, rz = -6 }) },
			},
		},
		ScatterBall = { -- ball.scatter (스킬2): 두 팔을 넓게 휘둘러 흩뿌린다
			priority = 3, commit = 0.2, duration = 0.55, fadeOut = 0.15, impact = 0.06, blendIn = 0.03,
			keys = {
				{ t = 0.00, pose = pose({ ry = -12 }, { rx = 40, rz = 70 }, { rx = 40, rz = -70 }) },
				{ t = 0.06, ease = "out", pose = pose({ ry = 10, rx = 4 }, { rx = 100, ry = 20, rz = 10 }, { rx = 100, ry = -20, rz = -10 }) },
				{ t = 0.20, pose = pose({ ry = 8, rx = 3 }, { rx = 92, ry = 18, rz = 12 }, { rx = 92, ry = -18, rz = -12 }) },
				{ t = 0.55, ease = "inout", pose = pose({ ry = 6 }, { rx = 55, ry = 12, rz = 6 }, { rx = 40, ry = -14, rz = -6 }) },
			},
		},
		Recall = { -- ball.recall (스킬3): 손을 펼쳐 불러들이고 끌어당긴다
			priority = 3, commit = 0.25, duration = 0.6, fadeOut = 0.15, impact = 0.1, blendIn = 0.03,
			keys = {
				{ t = 0.00, pose = pose({ rx = 0 }, { rx = 55, ry = 12, rz = 6 }, { rx = 40, ry = -14, rz = -6 }) },
				{ t = 0.10, ease = "out", pose = pose({ rx = 6 }, { rx = 105, rz = 32 }, { rx = 105, rz = -32 }) },
				{ t = 0.35, ease = "inout", pose = pose({ rx = -2 }, { rx = 40, rz = 8 }, { rx = 40, rz = -8 }) },
				{ t = 0.60, ease = "inout", pose = pose({ rx = 0 }, { rx = 55, ry = 12, rz = 6 }, { rx = 40, ry = -14, rz = -6 }) },
			},
		},
		-- 궁극기 Ball Cyclone: Start(웅크렸다 팔을 번쩍) → Spin(서버가 알려준 duration 동안 유지, 몸 회전) ⇄ Shot(발사 때마다 짧게) → End 시 Recover.
		CycloneStart = {
			priority = 5, commit = 0.45, duration = 0.45, next = "CycloneSpin", blendIn = 0.06,
			keys = {
				{ t = 0.00, pose = pose({ rx = 6, py = -0.2 }, { rx = 70, rz = 20 }, { rx = 70, rz = -20 }, { rx = -18, rz = 8 }, { rx = 24, rz = -8 }) },
				{ t = 0.45, ease = "out", pose = pose({ rx = -4, py = 0.05 }, { rx = 170, rz = 25 }, { rx = 170, rz = -25 }, { rx = -8, rz = 6 }, { rx = 10, rz = -6 }) },
			},
		},
		CycloneSpin = { -- 길이는 Start 이벤트의 duration(+0.5)로 지정. 이벤트가 유실돼도 maxDuration/울트 만료 시각에 풀린다.
			priority = 5, commit = 0, duration = 0.3, hold = true, maxDuration = 13.0, blendIn = 0.05,
			bodySpin = { degPerSec = 300 },
			wobble = { joint = "Root", field = "rz", amp = 1.5, hz = 4 },
			keys = {
				{ t = 0.00, pose = pose({ rx = -4, py = 0.05 }, { rx = 170, rz = 25 }, { rx = 170, rz = -25 }, { rx = -8, rz = 6 }, { rx = 10, rz = -6 }) },
				{ t = 0.30, ease = "inout", pose = pose({ rx = -2, py = 0.02 }, { rx = 160, rz = 28 }, { rx = 160, rz = -28 }, { rx = -8, rz = 6 }, { rx = 10, rz = -6 }) },
			},
		},
		CycloneShot = { -- ball.cyclone.shot: 한 팔로 공을 쏘아 낸다
			priority = 5, commit = 0, duration = 0.25, impact = 0.04, next = "CycloneSpin", blendIn = 0.02,
			keys = {
				{ t = 0.00, pose = pose({ rx = -4, py = 0.05 }, { rx = 165, rz = 25 }, { rx = 165, rz = -25 }, { rx = -8, rz = 6 }, { rx = 10, rz = -6 }) },
				{ t = 0.04, ease = "out", pose = pose({ rx = 6, py = 0 }, { rx = 118, ry = 6, rz = 6 }, { rx = 165, rz = -25 }, { rx = -8, rz = 6 }, { rx = 10, rz = -6 }) },
				{ t = 0.25, ease = "inout", pose = pose({ rx = -4, py = 0.05 }, { rx = 165, rz = 25 }, { rx = 165, rz = -25 }, { rx = -8, rz = 6 }, { rx = 10, rz = -6 }) },
			},
		},
		CycloneRecover = {
			priority = 1, commit = 0, duration = 0.4, fadeOut = 0.3, blendIn = 0.1,
			keys = {
				{ t = 0.00, pose = pose({ rx = -2, py = 0.02 }, { rx = 150, rz = 24 }, { rx = 150, rz = -24 }, { rx = -8, rz = 6 }, { rx = 10, rz = -6 }) },
				{ t = 0.40, ease = "inout", pose = pose({ rx = 0, py = 0 }, { rx = 55, ry = 12, rz = 6 }, { rx = 40, ry = -14, rz = -6 }, { rx = -10, rz = 5 }, { rx = 12, rz = -5 }) },
			},
		},
	},
	Groups = {
		Idle = { "Idle" }, Run = { "Run" }, SuperThrow = { "BallCharge", "BallThrow", "BallThrowCharged" }, BounceDash = { "BounceDash" },
		RapidBounce = { "RapidBounce" }, ScatterBall = { "ScatterBall" }, Recall = { "Recall" },
		BallCyclone = { "CycloneStart", "CycloneSpin", "CycloneShot", "CycloneRecover" },
	},
}

-- ─────────────────────────── TIMEBOMB ───────────────────────────
-- 오른손에 폭탄을 낮게 든 자세. 폭발은 서버가 따로 시간을 재므로(퓨즈 1초/3초) 모션은 던지기·설치·기폭 "입력 이벤트" 시각에만 맞춘다.
M.TIMEBOMB = {
	MaxCatchUp = COMMON.MaxCatchUp, DefaultBlendIn = COMMON.DefaultBlendIn,
	Locomotion = {
		runStartSpeed = 1.5, runFullSpeed = 6, strideHz = 0.075, runLegSwing = 40, runLean = -8, runBob = 0.06,
		idleBreathHz = 0.45, idleBreathAmp = 0.03, armBob = 3,
		freeArms = { "LArm" }, runArmSwing = 30,
		stance = {
			Root = { ry = -8 }, Neck = { ry = 8 }, RArm = { rx = 30, ry = 8, rz = 14 }, LArm = { rx = 14, rz = -10 },
			RLeg = { rx = -10, rz = 5 }, LLeg = { rx = 12, rz = -5 },
		},
	},
	Motions = {
		TimedThrow = { -- bomb.throw (LMB): 짧은 던지기
			priority = 2, commit = 0.15, duration = 0.5, fadeOut = 0.15, impact = 0.08, blendIn = 0.03,
			keys = {
				{ t = 0.00, pose = pose({ ry = 14, rx = 2 }, { rx = -50, rz = 12 }, { rx = 30 }) },
				{ t = 0.08, ease = "out", pose = pose({ ry = -10, rx = -10 }, { rx = 140 }, { rx = 20, ry = -8 }) },
				{ t = 0.24, pose = pose({ ry = -12, rx = -8 }, { rx = 120, ry = 2 }, { rx = 18, ry = -8 }) },
				{ t = 0.50, ease = "inout", pose = pose({ ry = -8, rx = 0 }, { rx = 30, ry = 8, rz = 14 }, { rx = 14, rz = -10 }) },
			},
		},
		BlastGuard = { -- bomb.guard (RMB): 두 손을 내밀어 터뜨리고 반동으로 뒤로 젖혀진다
			priority = 3, commit = 0.2, duration = 0.5, fadeOut = 0.15, impact = 0.05, blendIn = 0.02,
			keys = {
				{ t = 0.00, pose = pose({ rx = 0 }, { rx = 60, rz = 10 }, { rx = 60, rz = -10 }, { rx = -10, rz = 5 }, { rx = 12, rz = -5 }) },
				{ t = 0.05, ease = "out", pose = pose({ rx = 14 }, { rx = 110, rz = 6 }, { rx = 110, rz = -6 }, { rx = 20, rz = 5 }, { rx = -26, rz = -5 }) },
				{ t = 0.25, pose = pose({ rx = 12 }, { rx = 100, rz = 8 }, { rx = 100, rz = -8 }, { rx = 16, rz = 5 }, { rx = -22, rz = -5 }) },
				{ t = 0.50, ease = "inout", pose = pose({ rx = 0, ry = -8 }, { rx = 30, ry = 8, rz = 14 }, { rx = 14, rz = -10 }, { rx = -10, rz = 5 }, { rx = 12, rz = -5 }) },
			},
		},
		ClusterThrow = { -- bomb.cluster (스킬1): 크게 휘두르는 오버핸드 던지기
			priority = 3, commit = 0.25, duration = 0.6, fadeOut = 0.15, impact = 0.1, blendIn = 0.03,
			keys = {
				{ t = 0.00, pose = pose({ ry = 16, rx = 8 }, { rx = -100, rz = 10 }, { rx = 40 }) },
				{ t = 0.10, ease = "out", pose = pose({ ry = -14, rx = -12 }, { rx = 160 }, { rx = 20, ry = -10 }) },
				{ t = 0.30, pose = pose({ ry = -14, rx = -10 }, { rx = 140, ry = 2 }, { rx = 18, ry = -10 }) },
				{ t = 0.60, ease = "inout", pose = pose({ ry = -8, rx = 0 }, { rx = 30, ry = 8, rz = 14 }, { rx = 14, rz = -10 }) },
			},
		},
		RemotePlace = { -- bomb.remote (스킬2 짧게 누름): 아래로 살짝 던져 설치
			priority = 3, commit = 0.15, duration = 0.45, fadeOut = 0.15, impact = 0.06, blendIn = 0.03,
			keys = {
				{ t = 0.00, pose = pose({ ry = 10, rx = 6 }, { rx = -20, rz = 10 }, { rx = 20 }) },
				{ t = 0.06, ease = "out", pose = pose({ ry = -8, rx = -4 }, { rx = 85, rz = 4 }, { rx = 15 }) },
				{ t = 0.20, pose = pose({ ry = -8, rx = -2 }, { rx = 70, rz = 6 }, { rx = 14 }) },
				{ t = 0.45, ease = "inout", pose = pose({ ry = -8, rx = 0 }, { rx = 30, ry = 8, rz = 14 }, { rx = 14, rz = -10 }) },
			},
		},
		RemoteDetonate = { -- bomb.detonate (스킬2 길게 누르고 뗌): 기폭 스위치를 누르는 동작. 실제 폭발 시각은 서버 BombExplode 가 따로 정한다
			priority = 3, commit = 0.2, duration = 0.5, fadeOut = 0.15, impact = 0.08, blendIn = 0.03,
			keys = {
				{ t = 0.00, pose = pose({ rx = 0 }, { rx = 60, ry = 10, rz = 10 }, { rx = 70, ry = -10, rz = -8 }) },
				{ t = 0.08, ease = "out", pose = pose({ rx = -3 }, { rx = 95, ry = -20, rz = 4 }, { rx = 100, ry = -12, rz = -4 }) },
				{ t = 0.22, pose = pose({ rx = -3 }, { rx = 90, ry = -18, rz = 4 }, { rx = 96, ry = -10, rz = -4 }) },
				{ t = 0.50, ease = "inout", pose = pose({ rx = 0, ry = -8 }, { rx = 30, ry = 8, rz = 14 }, { rx = 14, rz = -10 }) },
			},
		},
		BlastJump = { -- bomb.jump (스킬3 이동기): 웅크렸다 발밑 폭발로 솟구친다. 길이 = 서버 dash.duration
			priority = 3, commit = 0.3, duration = 0.5, fadeOut = 0.12, blendIn = 0.03,
			keys = {
				{ t = 0.00, pose = pose({ rx = 0, py = 0 }, { rx = 30, ry = 8, rz = 14 }, { rx = 14, rz = -10 }, { rx = -10, rz = 5 }, { rx = 12, rz = -5 }) },
				{ t = 0.08, ease = "out", pose = pose({ rx = 10, py = -0.25 }, { rx = 40, rz = 25 }, { rx = 40, rz = -25 }, { rx = -35, rz = 8 }, { rx = 40, rz = -8 }) },
				{ t = 0.16, ease = "out", pose = pose({ rx = -6, py = 0.12 }, { rx = -30, rz = 35 }, { rx = -30, rz = -35 }, { rx = 20, rz = 6 }, { rx = -18, rz = -6 }) },
				{ t = 0.34, pose = pose({ rx = -4, py = 0.08 }, { rx = -20, rz = 32 }, { rx = -20, rz = -32 }, { rx = 14, rz = 6 }, { rx = -12, rz = -6 }) },
				{ t = 0.50, ease = "inout", pose = pose({ rx = 0, py = 0 }, { rx = 30, ry = 8, rz = 14 }, { rx = 14, rz = -10 }, { rx = -10, rz = 5 }, { rx = 12, rz = -5 }) },
			},
		},
		-- 궁극기 Big Bang: 서버에 "준비" 이벤트가 없다(던지는 순간 Throw 하나). 준비(들어 올림)·투척·복귀를 한 모션으로 묶고,
		-- 투척 포즈(impact)를 이벤트 직후 0.1초에 둔다. 착지 3초 뒤 폭발은 이 모션과 무관하다.
		BigBangThrow = {
			priority = 5, commit = 0.5, duration = 0.9, fadeOut = 0.3, impact = 0.1, blendIn = 0.03,
			keys = {
				{ t = 0.00, pose = pose({ rx = 8, py = -0.15 }, { rx = -120, rz = 14 }, { rx = 70, ry = -10 }, { rx = -16, rz = 8 }, { rx = 22, rz = -8 }) },
				{ t = 0.10, ease = "out", pose = pose({ ry = -24, rx = -14, py = 0.05 }, { rx = 170, rz = 4 }, { rx = 40, ry = 14 }, { rx = 10 }, { rx = -8 }) },
				{ t = 0.35, pose = pose({ ry = -20, rx = -10, py = 0.02 }, { rx = 150, rz = 6 }, { rx = 36, ry = 12 }, { rx = 6 }, { rx = -4 }) },
				{ t = 0.90, ease = "inout", pose = pose({ ry = -8, rx = 0, py = 0 }, { rx = 30, ry = 8, rz = 14 }, { rx = 14, rz = -10 }, { rx = -10, rz = 5 }, { rx = 12, rz = -5 }) },
			},
		},
	},
	Groups = {
		Idle = { "Idle" }, Run = { "Run" }, TimedBomb = { "TimedThrow" }, BlastGuard = { "BlastGuard" }, ClusterBomb = { "ClusterThrow" },
		RemoteBomb = { "RemotePlace", "RemoteDetonate" }, BlastJump = { "BlastJump" }, BigBang = { "BigBangThrow" },
	},
}

return M
