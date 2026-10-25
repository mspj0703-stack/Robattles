--!nonstrict
-- 임시 전투 연출 렌더러 (Roblox 전용, Studio 실기동 검증 필요 — CLI 테스트 불가).
-- 큐(EffectsModel 출력)를 받아 shared/Data/EffectCatalog 정의대로 코드로 만든 임시 도형을 재생한다.
-- 교체: ReplicatedStorage.RoBattles.Assets.Effects.<cue 이름> 이 있으면 그것을 복제해 재생한다(코드 수정 불필요).
-- 모든 연출은 시각용이며 판정에 영향을 주지 않는다. 오류가 나도 전투 처리를 막지 않도록 pcall 로 격리한다.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Link = require(script.Parent.Link)
local Catalog = Link.shared("Data/EffectCatalog")
local EffectsModel = require(script.Parent.Logic.EffectsModel)

local EffectPlayer = {}
EffectPlayer.__index = EffectPlayer

local function color3(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

function EffectPlayer.new(now)
	local self = setmetatable({ _now = now, _projectiles = {}, _folder = nil }, EffectPlayer)
	local folder = workspace:FindFirstChild("RoBattlesEffects")
	if folder then
		folder:Destroy() -- 스크립트 재실행/재접속 시 이전 연출 잔여물 정리(중복 방지)
	end
	folder = Instance.new("Folder")
	folder.Name = "RoBattlesEffects"
	folder.Parent = workspace
	self._folder = folder
	self._conn = RunService.RenderStepped:Connect(function()
		self:_step()
	end)
	return self
end

function EffectPlayer:destroy()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	if self._folder then
		self._folder:Destroy()
	end
	table.clear(self._projectiles)
end

local function characterOf(playerId)
	local pl = Players:GetPlayerByUserId(playerId)
	return pl and pl.Character
end

local function rootOf(playerId)
	local c = characterOf(playerId)
	return c and c:FindFirstChild("HumanoidRootPart")
end

function EffectPlayer:_asset(cueName)
	local assets = ReplicatedStorage:FindFirstChild("RoBattles") and ReplicatedStorage.RoBattles:FindFirstChild("Assets")
	local effects = assets and assets:FindFirstChild("Effects")
	return effects and effects:FindFirstChild(cueName)
end

function EffectPlayer:_sound(soundName, parent)
	local def = soundName and Catalog.Sounds[soundName]
	if not def or def.id == "" or not parent then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = def.id
	s.Volume = def.volume or 0.5
	s.RollOffMaxDistance = 80
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 3)
end

local function ghostPart(size, cframe, color, transparency)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency or 0.3
	p.Size = size
	p.CFrame = cframe
	return p
end

function EffectPlayer:_fade(part, lifetime, growTo)
	local goal = { Transparency = 1 }
	if growTo then
		goal.Size = growTo
	end
	TweenService:Create(part, TweenInfo.new(lifetime), goal):Play()
	Debris:AddItem(part, lifetime + 0.1)
end

-- 큐 하나를 재생한다. 반환값 없음.
function EffectPlayer:play(cue)
	local ok, err = pcall(function()
		self:_play(cue)
	end)
	if not ok then
		warn("[RoBattles][Effect] " .. tostring(cue and cue.cue) .. " 재생 오류: " .. tostring(err))
	end
end

function EffectPlayer:_play(cue)
	local name = cue.cue
	if name == "projectile.end" then
		local p = self._projectiles[cue.projectileId]
		if p then
			p.part:Destroy()
			self._projectiles[cue.projectileId] = nil
		end
		return
	end
	if name == "ball.update" then -- 튕김/모드 전환: 서버가 준 새 기준점으로 교체(이미 사라진 볼이면 무시)
		local p = self._projectiles[cue.projectileId]
		if p then
			for k, v in cue do
				if k ~= "cue" and v ~= nil then
					p.cue[k] = v
				end
			end
		end
		return
	end
	local def = Catalog.Cues[name]
	if not def then
		return
	end
	local col = color3(def.color)
	local root = (cue.playerId and rootOf(cue.playerId)) or (cue.targetId and rootOf(cue.targetId))
	local override = self:_asset(name)

	if def.style == "Projectile" then
		local part = override and override:Clone() or ghostPart(Vector3.one * def.size * 2, CFrame.new(cue.pos.X, cue.pos.Y, cue.pos.Z), col, 0)
		if part:IsA("Model") then
			part = part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart")
		end
		part.Shape = part:IsA("Part") and Enum.PartType.Ball or part.Shape
		part.Parent = self._folder
		self._projectiles[cue.projectileId] = { cue = cue, part = part }
		return
	end

	if override and def.style ~= "Highlight" then
		local clone = override:Clone()
		local at = root and root.CFrame or (cue.pos and CFrame.new(cue.pos.X, cue.pos.Y, cue.pos.Z)) or CFrame.new()
		if clone:IsA("Model") then
			clone:PivotTo(at)
		elseif clone:IsA("BasePart") then
			clone.CFrame = at
			clone.Anchored = true
		end
		clone.Parent = self._folder
		Debris:AddItem(clone, def.lifetime + 0.5)
		self:_sound(def.sound, root or clone)
		return
	end

	if def.style == "Highlight" then
		local ch = characterOf(cue.targetId)
		if ch then
			local h = Instance.new("Highlight")
			h.FillColor = col
			h.FillTransparency = 0.3
			h.OutlineTransparency = 1
			h.Parent = ch
			Debris:AddItem(h, def.lifetime)
		end
	elseif def.style == "Arc" and root then
		local cf = root.CFrame * CFrame.new(0, 0.5, -def.size / 2 - 1)
		local part = ghostPart(Vector3.new(def.size, 0.2, def.size * 0.5), cf, col, 0.2)
		part.Parent = self._folder
		self:_fade(part, def.lifetime, Vector3.new(def.size * 1.4, 0.2, def.size * 0.8))
		self:_sound(def.sound, root)
	elseif def.style == "Ring" and root then
		local part = ghostPart(Vector3.new(def.size, 0.2, def.size), root.CFrame * CFrame.new(0, -2.5, 0), col, 0.3)
		part.Shape = Enum.PartType.Cylinder
		part.CFrame = root.CFrame * CFrame.new(0, -2.5, 0) * CFrame.Angles(0, 0, math.rad(90))
		part.Size = Vector3.new(0.2, def.size, def.size)
		part.Parent = self._folder
		self:_fade(part, def.lifetime, Vector3.new(0.2, def.size * 2, def.size * 2))
		self:_sound(def.sound, root)
	elseif def.style == "Burst" or def.style == "Poof" then
		local target = rootOf(cue.targetId or cue.playerId or 0)
		-- 위치가 지정된 큐(폭발 등)는 그 위치에, 아니면 대상 몸 위치에 재생. 반경이 있으면 크기에 반영.
		local pos = (cue.pos and Vector3.new(cue.pos.X, cue.pos.Y, cue.pos.Z)) or (target and target.Position)
		if pos then
			local size = (type(cue.radius) == "number" and cue.radius > 0) and cue.radius * 2 or def.size
			local part = ghostPart(Vector3.one * size * 0.4, CFrame.new(pos), col, 0.2)
			part.Shape = Enum.PartType.Ball
			part.Parent = self._folder
			self:_fade(part, def.lifetime, Vector3.one * size)
			self:_sound(def.sound, target or part)
		end
	elseif def.style == "Muzzle" then
		local pos = cue.pos and Vector3.new(cue.pos.X, cue.pos.Y, cue.pos.Z) or (root and root.Position)
		if pos then
			local part = ghostPart(Vector3.one * def.size, CFrame.new(pos), col, 0.1)
			part.Shape = Enum.PartType.Ball
			part.Parent = self._folder
			self:_fade(part, def.lifetime, Vector3.one * def.size * 0.3)
			self:_sound(def.sound, root or part)
		end
	elseif def.style == "Beam" and cue.origin and cue.tip then
		-- 빔 한 틱: 서버가 확정한 시작~끝 선분을 얇은 네온 막대로 그린다(시각 전용)
		local a = Vector3.new(cue.origin.X, cue.origin.Y, cue.origin.Z)
		local b = Vector3.new(cue.tip.X, cue.tip.Y, cue.tip.Z)
		local len = (b - a).Magnitude
		if len > 0.1 then
			local part = ghostPart(Vector3.new(def.size, def.size, len), CFrame.lookAt(a, b) * CFrame.new(0, 0, -len / 2), col, 0.2)
			part.Parent = self._folder
			self:_fade(part, def.lifetime)
			self:_sound(def.sound, part)
		end
	elseif def.style == "Splat" and cue.pos then
		local part = ghostPart(Vector3.new(def.size, 0.1, def.size), CFrame.new(cue.pos.X, cue.pos.Y, cue.pos.Z), col, 0.1)
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.1, def.size, def.size)
		part.CFrame = CFrame.new(cue.pos.X, cue.pos.Y, cue.pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		part.Parent = self._folder
		self:_fade(part, def.lifetime)
	elseif def.style == "Afterimage" and root then
		local origin = cue.origin or { X = root.Position.X, Y = root.Position.Y, Z = root.Position.Z }
		local pts = EffectsModel.afterimagePoints(origin, cue.dir or { X = 0, Z = 0 }, cue.distance or 0, def.count or 3)
		for i, p in pts do
			-- 임시 잔상: 캐릭터 몸통 크기의 반투명 상자(최종 잔상은 캐릭터 모델 복제로 교체 예정)
			local part = ghostPart(Vector3.new(2, 5, 1), CFrame.new(p.X, p.Y, p.Z), col, 0.4 + 0.1 * i)
			part.Parent = self._folder
			self:_fade(part, def.lifetime * (1 - (i - 1) / (#pts + 1)))
		end
		self:_sound(def.sound, root)
	end
end

-- 매 프레임: 시각용 탄 이동(서버 Ended 가 오지 않아도 수명이 끝나면 제거)
function EffectPlayer:_step()
	local t = self._now()
	for id, p in self._projectiles do
		local pos
		if p.cue.ball then
			local root = p.cue.playerId and rootOf(p.cue.playerId)
			pos = EffectsModel.ballPosition(p.cue, t, root and { X = root.Position.X, Y = root.Position.Y, Z = root.Position.Z } or nil)
		else
			pos = EffectsModel.projectilePosition(p.cue, t)
		end
		if not pos or not p.part.Parent then
			p.part:Destroy()
			self._projectiles[id] = nil
		else
			p.part.Position = Vector3.new(pos.X, pos.Y, pos.Z)
		end
	end
end

return EffectPlayer
