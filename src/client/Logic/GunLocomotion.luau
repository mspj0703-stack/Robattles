--!nonstrict
-- 캐릭터별 Idle/Run 절차 포즈(순수 로직). SwordAnimState 의 baseSampler 로 쓴다.
-- params = CharacterMotions[캐릭터].Locomotion: stance(조준 자세, 관절별 오프셋), freeArms(달릴 때 흔드는 팔), runArmSwing 등.
-- 사격 캐릭터는 달리는 중에도 총/새총을 든 자세를 유지하고, freeArms 에 든 팔만 흔든다.
local MotionMath = require(script.Parent.MotionMath)

local GunLocomotion = {}

local function stanceJoint(params, name)
	local s = params.stance[name]
	return {
		rx = s and s.rx or 0, ry = s and s.ry or 0, rz = s and s.rz or 0,
		px = s and s.px or 0, py = s and s.py or 0, pz = s and s.pz or 0,
	}
end

local function idlePose(loco, p)
	local breath = math.sin(loco.time * p.idleBreathHz * math.pi * 2)
	local pose = {}
	for _, name in { "Root", "Neck", "RArm", "LArm", "RLeg", "LLeg" } do
		pose[name] = stanceJoint(p, name)
	end
	pose.Root.py += breath * p.idleBreathAmp
	pose.RArm.rx += breath * (p.armBob or 2) * 0.5
	pose.LArm.rx -= breath * (p.armBob or 2) * 0.5
	return pose
end

local function runPose(loco, p)
	local s = math.sin(loco.phase)
	local bob = math.abs(math.cos(loco.phase)) * p.runBob
	local pose = idlePose(loco, p)
	pose.Root.rx += p.runLean
	pose.Root.ry += -s * 4
	pose.Root.py += bob
	pose.Neck.rx += -p.runLean * 0.6
	pose.RLeg.rx += s * p.runLegSwing
	pose.LLeg.rx += -s * p.runLegSwing
	for _, arm in p.freeArms or {} do
		-- 자유로운 팔은 다리와 반대로 흔든다
		pose[arm].rx += (arm == "RArm" and -s or s) * (p.runArmSwing or 30)
		pose[arm].rz *= 0.5
	end
	-- 총을 든 팔도 아주 작게 흔들려 달리는 느낌을 준다
	for _, arm in { "RArm", "LArm" } do
		local free = false
		for _, f in p.freeArms or {} do
			free = free or f == arm
		end
		if not free then
			pose[arm].rx += s * 2
		end
	end
	return pose
end

-- loco(LocomotionPose 상태)와 캐릭터 Locomotion 파라미터로 Idle↔Run 혼합 포즈를 만든다. 공중이면 다리를 살짝 접는다.
function GunLocomotion.sample(loco, params)
	local idle = idlePose(loco, params)
	if loco.airborne then
		idle.RLeg.rx += -8
		idle.LLeg.rx += 12
		return idle
	end
	local w = MotionMath.clamp((loco.speed - params.runStartSpeed) / math.max(params.runFullSpeed - params.runStartSpeed, 1e-6), 0, 1)
	if w <= 0 then
		return idle
	end
	return MotionMath.lerpPose(idle, runPose(loco, params), w, false)
end

return GunLocomotion
