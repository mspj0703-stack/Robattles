--!nonstrict
-- Roblox 전용(Studio 미검증): CameraModel 결과를 workspace.CurrentCamera에 적용한다.
local UserInputService = game:GetService("UserInputService")

local Link = require(script.Parent.Link)
local Config = Link.shared("Config")
local CameraModel = require(script.Parent.Logic.CameraModel)

local CameraRig = {}
CameraRig.__index = CameraRig

local function toV3(t) return Vector3.new(t.X, t.Y, t.Z) end
local function fromV3(v) return { X = v.X, Y = v.Y, Z = v.Z } end

function CameraRig.new(input)
	local self = setmetatable({ model = CameraModel.new(), input = input, character = nil }, CameraRig)
	return self
end

function CameraRig:setCharacter(model)
	self.character = model
end

function CameraRig:setMode(mode)
	self.model:setMode(mode)
end

function CameraRig:onMouseDelta(delta)
	self.model:applyMouseDelta(delta.X, delta.Y, self.input.freeLookHeld)
end

function CameraRig:_castParams()
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = { self.character }
	return p
end

-- 매 프레임. 카메라를 Scriptable로 두고 직접 배치한다(벽 충돌 보정 포함).
function CameraRig:update()
	local cam = workspace.CurrentCamera
	local hrp = self.character and self.character:FindFirstChild("HumanoidRootPart")
	if not cam or not hrp then
		return
	end
	cam.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior[self.model:mouseBehavior(self.input.freeLookHeld)]
	UserInputService.MouseIconEnabled = self.model.mode == "Free"

	local params = self:_castParams()
	local focus = fromV3(hrp.Position + Vector3.new(0, 2, 0))
	local result = self.model:compute(focus, function(from, to, radius)
		local a, b = toV3(from), toV3(to)
		local dir = b - a
		local hit = workspace:Spherecast(a, radius, dir, params)
		if hit then
			return hit.Distance / math.max(dir.Magnitude, 1e-3)
		end
		return nil
	end)
	cam.CFrame = CFrame.lookAt(toV3(result.position), toV3(result.position) + toV3(result.look))
	self.last = result
end

-- 조준 원점/방향. 화면 중앙(Locked) 또는 마우스 위치(Free)로 광선을 쏴 도착점을 향해 발사 방향을 만든다.
function CameraRig:aim(maxRange)
	local cam = workspace.CurrentCamera
	local hrp = self.character and self.character:FindFirstChild("HumanoidRootPart")
	if not cam or not hrp then
		return nil
	end
	local viewport = cam.ViewportSize
	local pos = self.model.mode == "Locked" and Vector2.new(viewport.X / 2, viewport.Y / 2) or UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * (maxRange or 300), self:_castParams())
	local point = hit and hit.Position or (ray.Origin + ray.Direction * (maxRange or 300))
	local origin = hrp.Position + Vector3.new(0, Config.Combat.EyeHeight, 0)
	local dir = (point - origin)
	if dir.Magnitude < 1e-3 then
		dir = ray.Direction
	end
	return origin, dir.Unit
end

return CameraRig
