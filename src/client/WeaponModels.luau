--!nonstrict
-- 임시 무기 모델 (Roblox 전용, Studio 실기동 검증 필요). 코드로 만든 단순 도형이며 최종 모델링이 아니다.
-- 교체: ReplicatedStorage.RoBattles.Assets.Weapons.<CharacterId> (Model 또는 BasePart; 손잡이 위치에 맞춰 Handle 이라는 BasePart 권장)가
-- 있으면 그것을 복제해 오른손에 붙인다. 다른 플레이어 캐릭터에도 같은 방식으로 붙여 서로의 무기가 보이게 한다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Link = require(script.Parent.Link)
local Catalog = Link.shared("Data/EffectCatalog")

local WeaponModels = {}

local TAG = "RoBattlesWeapon"

local function color3(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function part(name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Plastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	return p
end

local function build(characterId)
	local spec = Catalog.Weapons[characterId]
	if not spec then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = TAG
	if spec.kind == "Sword" then
		local handle = part("Handle", Vector3.new(0.3, 1.1, 0.3), color3(spec.handleColor))
		local blade = part("Blade", Vector3.new(0.25, spec.length, 0.6), color3(spec.color), Enum.Material.Metal)
		blade.CFrame = handle.CFrame * CFrame.new(0, 0.55 + spec.length / 2, 0)
		local guard = part("Guard", Vector3.new(1.3, 0.25, 0.4), color3(spec.handleColor))
		guard.CFrame = handle.CFrame * CFrame.new(0, 0.6, 0)
		for _, p in { handle, blade, guard } do
			p.Parent = model
		end
		local function weld(a, b)
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = a, b
			w.Parent = a
		end
		weld(handle, blade)
		weld(handle, guard)
		model.PrimaryPart = handle
	else
		local handle = part("Handle", Vector3.new(0.4, 0.9, 0.6), color3(spec.color))
		local barrel = part("Barrel", Vector3.new(0.35, 0.35, spec.length), color3(spec.color), Enum.Material.Metal)
		barrel.CFrame = handle.CFrame * CFrame.new(0, 0.5, -spec.length / 2)
		local hopper = part("Hopper", Vector3.new(0.5, 0.5, 0.5), color3(spec.accent))
		hopper.Shape = Enum.PartType.Ball
		hopper.CFrame = handle.CFrame * CFrame.new(0, 0.9, -0.2)
		for _, p in { handle, barrel, hopper } do
			p.Parent = model
		end
		for _, p in { barrel, hopper } do
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = handle, p
			w.Parent = handle
		end
		model.PrimaryPart = handle
	end
	return model
end

local function template(characterId)
	local assets = ReplicatedStorage:FindFirstChild("RoBattles") and ReplicatedStorage.RoBattles:FindFirstChild("Assets")
	local weapons = assets and assets:FindFirstChild("Weapons")
	local custom = weapons and weapons:FindFirstChild(characterId)
	if custom then
		return custom:Clone()
	end
	return build(characterId)
end

-- 캐릭터의 기존 임시 무기를 제거한다.
function WeaponModels.clear(character)
	for _, c in character:GetChildren() do
		if c.Name == TAG then
			c:Destroy()
		end
	end
end

-- 캐릭터 오른손에 characterId 무기를 붙인다(이미 있으면 교체). 성공 여부 반환.
function WeaponModels.attach(character, characterId)
	WeaponModels.clear(character)
	local spec = Catalog.Weapons[characterId]
	if not spec then
		return false
	end
	local hand
	for _, name in spec.attach do
		hand = character:FindFirstChild(name)
		if hand then
			break
		end
	end
	if not hand then
		return false
	end
	local model = template(characterId)
	if not model then
		return false
	end
	model.Name = TAG
	local handle = model:IsA("Model") and (model:FindFirstChild("Handle") or model.PrimaryPart) or model
	if not handle then
		model:Destroy()
		return false
	end
	model.Parent = character
	-- 손 기준 위치: 손바닥 쪽(−Y)으로 조금 내리고 앞을 향하게 한다.
	local cf = hand.CFrame * CFrame.new(0, -0.5, -0.2) * CFrame.Angles(math.rad(-90), 0, 0)
	if model:IsA("Model") then
		model:PivotTo(cf)
	else
		handle.CFrame = cf
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = handle
	weld.Parent = handle
	return true
end

return WeaponModels
