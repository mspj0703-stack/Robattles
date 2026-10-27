--!nonstrict
-- Roblox 전용(Studio 미검증): 테스트용 캐릭터 더미. BRICKYARD 루트 아래 Dummies 폴더에 만들어 맵 재생성 시 함께 제거된다.
local Players = game:GetService("Players")

local DummyFactory = {}

local function simpleDummy(name)
	local m = Instance.new("Model")
	m.Name = name
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Color = Color3.fromRGB(163, 162, 165)
	hrp.Parent = m
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.Color = Color3.fromRGB(245, 205, 48)
	head.CFrame = hrp.CFrame * CFrame.new(0, 1.5, 0)
	head.Parent = m
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = hrp, head
	w.Parent = hrp
	local hum = Instance.new("Humanoid")
	hum.Parent = m
	m.PrimaryPart = hrp
	return m
end

-- 더미 생성. 가능하면 R15 Humanoid 모델을 쓰고(실패 시 단순 모델로 대체).
function DummyFactory.spawn(layout, parentFolder)
	local folder = Instance.new("Folder")
	folder.Name = "Dummies"
	folder.Parent = parentFolder
	local models = {}
	for _, d in layout.dummies do
		local model
		local ok, res = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
		if ok and res then
			model = res
		else
			model = simpleDummy("Dummy")
		end
		model.Name = string.format("TestDummy_%02d", d.index)
		model:SetAttribute("BrickyardDummy", true)
		model:PivotTo(CFrame.new(d.pos.X, d.pos.Y + 3.2, d.pos.Z))
		model.Parent = folder
		table.insert(models, model)
	end
	return models
end

return DummyFactory
