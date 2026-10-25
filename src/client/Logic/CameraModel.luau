--!nonstrict
-- 카메라 순수 계산: 시점 모드, 요/피치, 마우스 동작, 궤도 위치와 벽 충돌 보정, 조준 방향.
-- Roblox Camera 적용은 CameraRig(Studio 전용)가 이 모델의 결과를 사용한다.
local Link = require(script.Parent.Parent.Link)
local Config = Link.shared("Config")
local Vec = Link.shared("Vec")

local CameraModel = {}
CameraModel.__index = CameraModel

function CameraModel.new(config)
	local cfg = config or Config
	return setmetatable({
		_cfg = cfg,
		mode = cfg.Camera.InitialMode, -- "Locked"(기본) | "Free"
		yaw = 0, -- 도
		pitch = 10,
	}, CameraModel)
end

function CameraModel:setMode(mode)
	if mode == "Locked" or mode == "Free" then
		self.mode = mode
	end
end

function CameraModel:toggle()
	self.mode = self.mode == "Locked" and "Free" or "Locked"
	return self.mode
end

-- Locked: 마우스를 화면 중앙에 고정하고 이동량으로 항상 회전.
-- Free: 마우스 커서가 보이고(기본 동작), 회전은 FreeLook 버튼을 누르고 있을 때만. RMB는 회전과 무관.
function CameraModel:mouseBehavior(freeLookHeld)
	if self.mode == "Locked" then
		return "LockCenter"
	end
	return freeLookHeld and "LockCurrentPosition" or "Default"
end

function CameraModel:rotates(freeLookHeld)
	return self.mode == "Locked" or freeLookHeld == true
end

-- 마우스 이동(픽셀) 적용. 유효하지 않은 값(NaN/무한대)은 무시한다.
function CameraModel:applyMouseDelta(dx, dy, freeLookHeld)
	if not self:rotates(freeLookHeld) then
		return
	end
	if dx ~= dx or dy ~= dy or math.abs(dx) == math.huge or math.abs(dy) == math.huge then
		return
	end
	local c = self._cfg.Camera
	self.yaw = (self.yaw - dx * c.SensitivityDegreesPerPixel) % 360
	self.pitch = math.clamp(self.pitch - dy * c.SensitivityDegreesPerPixel, c.PitchMinDegrees, c.PitchMaxDegrees)
end

-- 카메라가 바라보는 방향(월드). yaw 0 = -Z 방향(Roblox 기본 전방), 양의 yaw는 왼쪽 회전.
function CameraModel:lookDirection()
	local y, p = math.rad(self.yaw), math.rad(self.pitch)
	return Vec.normalize({
		X = -math.sin(y) * math.cos(p),
		Y = math.sin(p),
		Z = -math.cos(y) * math.cos(p),
	})
end

function CameraModel:rightVector()
	local y = math.rad(self.yaw)
	return { X = math.cos(y), Y = 0, Z = -math.sin(y) }
end

-- 카메라 위치 계산. castFn(origin, target, radius) → 막히면 충돌 지점까지의 비율(0~1) 또는 nil.
-- 반환: { position, distance, look } — 벽 안으로 들어가지 않도록 거리를 줄인다.
function CameraModel:compute(focus, castFn)
	local c = self._cfg.Camera
	local look = self:lookDirection()
	local right = self:rightVector()
	local anchor = focus
	if self.mode == "Locked" then
		anchor = Vec.add(focus, Vec.scale(right, c.ShoulderOffset))
	end
	local desired = Vec.sub(anchor, Vec.scale(look, c.Distance))
	local dist = c.Distance
	if castFn then
		local frac = castFn(anchor, desired, c.CollisionRadius)
		if frac ~= nil then
			dist = math.max(c.MinDistance, c.Distance * math.clamp(frac, 0, 1))
		end
	end
	return { position = Vec.sub(anchor, Vec.scale(look, dist)), distance = dist, look = look, anchor = anchor }
end

-- 조준: 화면 중앙 광선의 도착 지점을 향해 캐릭터(발사 원점)에서 쏜다.
-- 수동 조준만 사용하며 원거리에는 자동 보정이 없다(확정).
function CameraModel:aimFrom(origin, camera, hitPoint, maxRange)
	local target = hitPoint
	if target == nil then
		target = Vec.add(camera.position, Vec.scale(camera.look, maxRange or 200))
	end
	local d = Vec.normalize(Vec.sub(target, origin))
	return d or camera.look
end

return CameraModel
