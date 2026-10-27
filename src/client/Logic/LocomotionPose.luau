--!nonstrict
-- SWORD Idle / Run 절차 포즈 (순수 로직). 공격 모션의 "아래층"으로 항상 계산되고, 행동 모션이 상체만 덮어쓸 수 있다.
-- 상태 loco = { speed, airborne, phase, time } — phase 는 update 마다 누적한다(속도에 비례).
local MotionMath = require(script.Parent.MotionMath)

local LocomotionPose = {}

function LocomotionPose.new()
	return { speed = 0, airborne = false, phase = 0, time = 0, lastNow = nil }
end

-- 시간 진행: dt 만큼 phase/time 을 누적한다. now 가 거꾸로 가거나 dt 가 비정상이면 0.1초로 제한한다.
function LocomotionPose.advance(loco, now, params)
	local dt = 0
	if loco.lastNow ~= nil then
		dt = now - loco.lastNow
		if dt ~= dt or dt < 0 then
			dt = 0
		elseif dt > 0.1 then
			dt = 0.1
		end
	end
	loco.lastNow = now
	loco.time += dt
	loco.phase += dt * loco.speed * params.strideHz * math.pi * 2
end

local function idlePose(loco, p)
	local breath = math.sin(loco.time * p.idleBreathHz * math.pi * 2)
	return {
		Root = { ry = -8, py = breath * p.idleBreathAmp },
		Neck = { ry = 8 },
		RArm = { rx = 38 + breath * 2, ry = 0, rz = 14 },
		LArm = { rx = 10 - breath * 2, rz = -12 },
		RLeg = { rx = -8, rz = 4 },
		LLeg = { rx = 10, rz = -4 },
	}
end

local function runPose(loco, p)
	local s = math.sin(loco.phase)
	local bob = math.abs(math.cos(loco.phase)) * p.runBob
	return {
		Root = { rx = p.runLean, ry = -s * 5, py = bob },
		Neck = { rx = -p.runLean * 0.6 },
		-- 검을 든 오른팔은 준비 자세 유지(작게 흔들림), 왼팔은 크게 흔든다
		RArm = { rx = 48 + s * 6, ry = 0, rz = 10 },
		LArm = { rx = s * p.runArmSwing, rz = -8 },
		RLeg = { rx = s * p.runLegSwing, rz = 3 },
		LLeg = { rx = -s * p.runLegSwing, rz = -3 },
	}
end

-- 현재 loco 상태의 Idle↔Run 혼합 포즈를 반환한다. 공중이면 Idle 에 다리를 살짝 접은 포즈.
function LocomotionPose.sample(loco, params)
	local idle = idlePose(loco, params)
	if loco.airborne then
		idle.RLeg = { rx = -18, rz = 6 }
		idle.LLeg = { rx = 24, rz = -6 }
		return MotionMath.copy(idle)
	end
	local w = MotionMath.clamp((loco.speed - params.runStartSpeed) / math.max(params.runFullSpeed - params.runStartSpeed, 1e-6), 0, 1)
	if w <= 0 then
		return MotionMath.copy(idle)
	end
	return MotionMath.lerpPose(idle, runPose(loco, params), w, false)
end

return LocomotionPose
