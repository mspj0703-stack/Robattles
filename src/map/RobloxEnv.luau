--!nonstrict
-- Roblox 전용(Studio 미검증): MapBuilder 가 쓰는 env 의 실제 구현.
local CollectionService = game:GetService("CollectionService")

local TAG = "BrickyardMap"
local RobloxEnv = {}

function RobloxEnv.clearExisting(rootName)
	-- 이름이 같은 루트와, 태그가 남은 잔여 인스턴스를 모두 제거한다(여러 번 실행해도 중복 없음).
	for _, inst in CollectionService:GetTagged(TAG) do
		inst:Destroy()
	end
	for _, child in workspace:GetChildren() do
		if child.Name == rootName then
			child:Destroy()
		end
	end
end

function RobloxEnv.createFolder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	if parent == nil then
		CollectionService:AddTag(f, TAG)
	end
	f.Parent = parent or workspace
	return f
end

function RobloxEnv.createPart(spec, parent)
	local p
	if spec.className == "SpawnLocation" then
		p = Instance.new("SpawnLocation")
		p.Neutral = true
		p.AllowTeamChangeOnTouch = false
		p.Duration = 0
		p.Enabled = true
	else
		p = Instance.new("Part")
	end
	p.Name = spec.name
	p.Anchored = true
	p.Size = Vector3.new(spec.size.X, spec.size.Y, spec.size.Z)
	p.Position = Vector3.new(spec.pos.X, spec.pos.Y, spec.pos.Z)
	p.Color = Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
	p.Material = Enum.Material[spec.material]
	p.CanCollide = spec.canCollide
	p.CanQuery = spec.solid
	p.CanTouch = spec.attributes ~= nil and spec.attributes.JumpPad == true
	p.Transparency = spec.transparency
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if spec.attributes then
		for k, v in spec.attributes do
			if type(v) == "table" and v.X ~= nil then
				v = Vector3.new(v.X, v.Y, v.Z)
			end
			p:SetAttribute(k, v)
		end
	end
	p.Parent = parent
	return p
end

return RobloxEnv
