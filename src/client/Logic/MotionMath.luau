--!nonstrict
-- 애니메이션 포즈 수학 (순수 로직, CLI 테스트 가능). Roblox API 를 쓰지 않는다.
-- 포즈 = { [관절이름] = { rx, ry, rz, px, py, pz } } (각도는 도(degree), 위치는 stud). 빠진 필드는 0.
-- 관절 이름: Root(HRP↔Torso), Neck, RArm, LArm, RLeg, LLeg. 각도 기준과 적용 순서는 docs/SWORD_ANIMATION.md.
local MotionMath = {}

MotionMath.JOINTS = { "Root", "Neck", "RArm", "LArm", "RLeg", "LLeg" }
MotionMath.ROT = { "rx", "ry", "rz" }
MotionMath.POS = { "px", "py", "pz" }
MotionMath.FIELDS = { "rx", "ry", "rz", "px", "py", "pz" }

local JOINT_SET = {}
for _, j in MotionMath.JOINTS do
	JOINT_SET[j] = true
end
function MotionMath.isJoint(name)
	return JOINT_SET[name] == true
end

function MotionMath.clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

-- 이징: linear / in / out / inout. 알 수 없는 이름은 linear.
function MotionMath.ease(kind, k)
	k = MotionMath.clamp(k, 0, 1)
	if kind == "in" then
		return k * k
	elseif kind == "out" then
		return 1 - (1 - k) * (1 - k)
	elseif kind == "inout" then
		return k * k * (3 - 2 * k)
	end
	return k
end

-- 각도 차이를 [-180, 180] 로 정규화(최단 경로 보간용)
function MotionMath.wrap180(d)
	return ((d + 180) % 360) - 180
end

function MotionMath.neutralJoint()
	return { rx = 0, ry = 0, rz = 0, px = 0, py = 0, pz = 0 }
end

function MotionMath.neutral()
	local p = {}
	for _, j in MotionMath.JOINTS do
		p[j] = MotionMath.neutralJoint()
	end
	return p
end

local function fullJoint(src)
	local out = MotionMath.neutralJoint()
	if src then
		for _, f in MotionMath.FIELDS do
			local v = src[f]
			if type(v) == "number" then
				out[f] = v
			end
		end
	end
	return out
end

function MotionMath.copy(pose)
	local out = {}
	for j, v in pose do
		out[j] = fullJoint(v)
	end
	return out
end

-- a→b 보간. 한쪽에만 있는 관절은 그대로 복사(= 변화 없음). shortest=true 이면 회전 필드를 최단 경로로 보간한다.
function MotionMath.lerpPose(a, b, k, shortest)
	local out = {}
	for j, ja in a do
		local jb = b[j]
		if jb == nil then
			out[j] = fullJoint(ja)
		else
			local fa, fb = fullJoint(ja), fullJoint(jb)
			local r = {}
			for _, f in MotionMath.ROT do
				if shortest then
					r[f] = fa[f] + MotionMath.wrap180(fb[f] - fa[f]) * k
				else
					r[f] = fa[f] + (fb[f] - fa[f]) * k
				end
			end
			for _, f in MotionMath.POS do
				r[f] = fa[f] + (fb[f] - fa[f]) * k
			end
			out[j] = r
		end
	end
	for j, jb in b do
		if a[j] == nil then
			out[j] = fullJoint(jb)
		end
	end
	return out
end

-- base 위에 overlay 를 가중치 w(0~1)로 덮는다. overlay 에 없는 관절은 base 그대로(= 상체 오버레이 가능).
function MotionMath.layer(base, overlay, w)
	if w <= 0 then
		return MotionMath.copy(base)
	end
	local out = MotionMath.copy(base)
	for j, jo in overlay do
		local fb = out[j] or MotionMath.neutralJoint()
		out[j] = MotionMath.lerpPose({ [j] = fb }, { [j] = jo }, math.min(w, 1), false)[j]
	end
	return out
end

-- offsets = { [관절] = { 필드 = 가산값 } } 를 scale 배로 더한다(in-place, pose 반환).
function MotionMath.addOffsets(pose, offsets, scale)
	for j, add in offsets do
		local cur = pose[j]
		if cur == nil then
			cur = MotionMath.neutralJoint()
			pose[j] = cur
		end
		for f, v in add do
			if cur[f] ~= nil and type(v) == "number" then
				cur[f] += v * scale
			end
		end
	end
	return pose
end

-- 키프레임 샘플링. keys = { { t, pose, ease? } ... } (t 오름차순). ease 는 "그 키로 향하는 구간"의 이징.
-- t 가 범위를 벗어나면 처음/끝 키로 고정한다. 반환 포즈는 모든 키에 등장한 관절을 포함한다.
function MotionMath.sampleKeys(keys, t)
	local n = #keys
	if n == 0 then
		return {}
	end
	if t <= keys[1].t then
		return MotionMath.copy(keys[1].pose)
	end
	if t >= keys[n].t then
		return MotionMath.copy(keys[n].pose)
	end
	for i = 2, n do
		local k1 = keys[i]
		if t <= k1.t then
			local k0 = keys[i - 1]
			local span = k1.t - k0.t
			local k = span > 1e-9 and (t - k0.t) / span or 1
			return MotionMath.lerpPose(k0.pose, k1.pose, MotionMath.ease(k1.ease, k), false)
		end
	end
	return MotionMath.copy(keys[n].pose)
end

-- NaN/inf 방어: 포즈에 비정상 수가 있으면 true
function MotionMath.hasBadNumber(pose)
	for _, jt in pose do
		for _, f in MotionMath.FIELDS do
			local v = jt[f]
			if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
				return true
			end
		end
	end
	return false
end

return MotionMath
