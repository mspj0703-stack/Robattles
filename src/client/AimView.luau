--!nonstrict
-- SLINGSHOT RMB Aim Mode 궤적 표시 (Roblox 전용, Studio 실기동 검증 필요 — S112). 표시 전용: 서버 리모트·상태에 영향 없음, 에임 보조 없음.
-- 궤적 계산은 Logic/AimModel(순수 로직, CLI 테스트)이 한다. 여기서는 작은 구체 점들을 늘어놓을 뿐이다.
local Link = require(script.Parent.Link)
local Characters = Link.shared("Data/Characters")
local AimModel = require(script.Parent.Logic.AimModel)

local AimView = {}
AimView.__index = AimView

local DOTS = 24

function AimView.new()
	return setmetatable({ _folder = nil, _dots = {}, _active = false }, AimView)
end

function AimView:_ensure()
	if self._folder and self._folder.Parent then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "RoBattlesAimMode"
	folder.Parent = workspace.CurrentCamera
	self._folder = folder
	self._dots = {}
	for i = 1, DOTS + 1 do
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(0.35, 0.35, 0.35)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(150, 240, 130)
		p.Transparency = 1
		p.Parent = folder
		self._dots[i] = p
	end
end

function AimView:setActive(active)
	self._active = active == true
	if not self._active then
		self:hide()
	end
end

function AimView:hide()
	for _, p in self._dots do
		p.Transparency = 1
	end
end

-- origin/dir: 카메라 기준 조준(rig:aim), eye: 발사 원점(캐릭터 위치 + EyeHeight), charge: 0~1(클라이언트가 누른 시간으로 추정한 표시용 값)
function AimView:update(eye, dir, charge, characterId)
	if not self._active then
		return
	end
	local def = Characters[characterId]
	if not def or not def.primary.shot then
		self:hide()
		return
	end
	self:_ensure()
	local sp = AimModel.shotParams(def.primary, charge)
	local world = {
		cast = function(p0, p1, r)
			local a = Vector3.new(p0.X, p0.Y, p0.Z)
			local b = Vector3.new(p1.X, p1.Y, p1.Z)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local lp = game:GetService("Players").LocalPlayer
			params.FilterDescendantsInstances = { lp.Character, self._folder }
			local res = workspace:Raycast(a, b - a, params)
			if res then
				local len = (b - a).Magnitude
				return { fraction = len > 0 and (res.Position - a).Magnitude / len or 0 }
			end
			return nil
		end,
	}
	local t = AimModel.trajectory(
		{ X = eye.X, Y = eye.Y, Z = eye.Z }, { X = dir.X, Y = dir.Y, Z = dir.Z }, sp.speed, sp.gravity, sp.lifetime, DOTS, world, 0
	)
	for i, p in self._dots do
		local pt = t.points[i]
		if pt then
			p.Position = Vector3.new(pt.X, pt.Y, pt.Z)
			p.Transparency = 0.2
		else
			p.Transparency = 1
		end
	end
end

return AimView
