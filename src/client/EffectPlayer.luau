--!nonstrict
-- 전투 연출 렌더러 (Roblox 전용, Studio 실기동 검증 필요).
-- P1-A: 기존 공통 명중/검격/버스트를 짧은 카툰 아케이드 섬광으로 개선.
-- 모든 명중 cue 는 기존 서버 Damage/Feedback 에서만 도착한다. 서버 전투 판정은 변경하지 않는다.
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
	s.SoundGroup = game:GetService("SoundService"):FindFirstChild("RoBattlesSFX") -- UI 효과음 볼륨 설정과 연동
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

-- 화면에서 멀리 떨어진 장식 효과를 생략한다. 내 공격은 거리에 관계없이 유지한다.
-- 이 조건은 순수한 시각 최적화이며 게임 판정/시야/서버 이벤트를 바꾸지 않는다.
local function visibleAt(position, mine, limit)
	if mine then
		return true
	end
	local camera = workspace.CurrentCamera
	return not camera or (camera.CFrame.Position - position).Magnitude <= limit
end

local function cuePosition(cue)
	local point = cue.pos
	if type(point) == "table" and type(point.X) == "number" and type(point.Y) == "number" and type(point.Z) == "number" then
		return Vector3.new(point.X, point.Y, point.Z)
	end
	return nil
end

-- 얇은 네온 선분. 시각 연출만 생성하며 CanTouch/CanQuery/CanCollide 는 모두 false.
local function sparkSegment(a, b, width, color, transparency)
	local distance = (b - a).Magnitude
	if distance < 0.01 then
		return nil
	end
	return ghostPart(Vector3.new(width, width, distance), CFrame.lookAt(a, b) * CFrame.new(0, 0, -distance / 2), color, transparency)
end

-- 타격 위치에 작은 별형 섬광을 표시한다. 캐릭터 전체를 덮는 거대 구형 이펙트를 사용하지 않는다.
function EffectPlayer:_hitImpact(cue, def, color)
	local target = cue.targetId and rootOf(cue.targetId)
	local point = cuePosition(cue) or (target and (target.Position + Vector3.new(0, 0.8, 0)))
	if not point or not visibleAt(point, cue.mine, 105) then
		return
	end
	local lifetime = math.min(def.lifetime, 0.22)
	local core = ghostPart(Vector3.one * 0.42, CFrame.new(point), Color3.fromRGB(255, 250, 225), 0.08)
	core.Shape = Enum.PartType.Ball
	core.Parent = self._folder
	self:_fade(core, lifetime * 0.75, Vector3.one * 0.13)

	-- 카메라를 향한 평면의 짧은 방향성 파편: 플레이어를 가리지 않는 4개 선분.
	local camera = workspace.CurrentCamera
	local right = camera and camera.CFrame.RightVector or Vector3.xAxis
	local up = camera and camera.CFrame.UpVector or Vector3.yAxis
	for i = 1, 4 do
		local angle = (i - 1) * math.pi / 2 + math.pi / 4
		local direction = right * math.cos(angle) + up * math.sin(angle)
		local from = point + direction * 0.22
		local to = point + direction * (0.48 + math.min(def.size, 4) * 0.1)
		local ray = sparkSegment(from, to, 0.10, color, 0.08)
		if ray then
			ray.Parent = self._folder
			self:_fade(ray, lifetime)
		end
	end
	self:_sound(def.sound, target or core)
end

-- 전방에 휘어진 5개 선분을 짧게 그려 단일 네온 판 대신 검격 궤적을 표현한다.
-- 실제 공격 충돌 영역을 표시하는 것이 아니라 검 휘두르기 동작의 장식 연출이다.
function EffectPlayer:_slashArc(cue, def, root, color)
	if not visibleAt(root.Position, cue.mine, 110) then
		return
	end
	local radius = math.clamp(def.size * 0.32, 1.7, 4.2)
	local forward = -math.clamp(def.size * 0.17, 1.1, 2.8)
	local near = visibleAt(root.Position, cue.mine, 55)
	local segments = near and 5 or 3
	local lifetime = math.min(def.lifetime, 0.35)
	for i = 1, segments do
		local a = -1.0 + 2 * (i - 1) / segments
		local b = -1.0 + 2 * i / segments
		local function arcPoint(angle)
			return root.CFrame:PointToWorldSpace(Vector3.new(
				math.sin(angle) * radius,
				0.55 + math.cos(angle) * radius * 0.36,
				forward
			))
		end
		local from, to = arcPoint(a), arcPoint(b)
		local stroke = sparkSegment(from, to, 0.15, color, 0.18)
		if stroke then
			stroke.Parent = self._folder
			self:_fade(stroke, lifetime)
		end
		if near then
			local highlight = sparkSegment(from, to, 0.055, Color3.fromRGB(255, 255, 245), 0.04)
			if highlight then
				highlight.Parent = self._folder
				self:_fade(highlight, lifetime * 0.72)
			end
		end
	end
	self:_sound(def.sound, root)
end

-- 폭발/강타의 기존 거대 사각/구형 도형을 작은 섬광 + 짧은 파편으로 대체한다.
-- radius 가 전달된 폭발은 서버가 알려준 반경 안에서만 보여야 한다.
function EffectPlayer:_burst(cue, def, fallbackRoot, color)
	local target = cue.targetId and rootOf(cue.targetId)
	local point = cuePosition(cue) or (target and target.Position) or (fallbackRoot and fallbackRoot.Position)
	if not point or not visibleAt(point, cue.mine, 105) then
		return
	end
	local radius = (type(cue.radius) == "number" and cue.radius > 0) and cue.radius or nil
	local extent = radius or (def.size * 0.5)
	local lifetime = math.min(def.lifetime, 0.55)
	local coreSize = math.min(2.0, extent * 0.55)
	local core = ghostPart(Vector3.one * math.max(0.2, coreSize), CFrame.new(point), color, 0.25)
	core.Shape = Enum.PartType.Ball
	core.Parent = self._folder
	self:_fade(core, lifetime, Vector3.one * math.max(0.4, extent * 1.5))
	-- 최대 반경에 해당하는 시각 표시를 넘지 않는 짧은 외향 파편.
	if visibleAt(point, cue.mine, 60) then
		local rays = 4
		for i = 1, rays do
			local angle = (i - 1) * math.pi / 2 + math.pi / 4
			local direction = Vector3.new(math.cos(angle), 0.15, math.sin(angle)).Unit
			local from = point + direction * math.min(extent * 0.16, 1.0)
			local to = point + direction * math.min(extent * 0.6, 3.5)
			local ray = sparkSegment(from, to, 0.11, Color3.fromRGB(255, 250, 225), 0.2)
			if ray then
				ray.Parent = self._folder
				self:_fade(ray, lifetime * 0.8)
			end
		end
	end
	self:_sound(def.sound, target or fallbackRoot or core)
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
			h.FillTransparency = 0.82
			h.OutlineTransparency = 0.45
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Parent = ch
			Debris:AddItem(h, def.lifetime)
		end
	elseif def.style == "Arc" and root then
		self:_slashArc(cue, def, root, col)
	elseif def.style == "Ring" and root then
		local part = ghostPart(Vector3.new(def.size, 0.2, def.size), root.CFrame * CFrame.new(0, -2.5, 0), col, 0.3)
		part.Shape = Enum.PartType.Cylinder
		part.CFrame = root.CFrame * CFrame.new(0, -2.5, 0) * CFrame.Angles(0, 0, math.rad(90))
		part.Size = Vector3.new(0.2, def.size, def.size)
		part.Parent = self._folder
		self:_fade(part, def.lifetime, Vector3.new(0.2, def.size * 2, def.size * 2))
		self:_sound(def.sound, root)
	elseif name == "hit.impact" then
		-- 서버 Damaged 이벤트에서만 생성되는 별형 타격 효과.
		self:_hitImpact(cue, def, col)
	elseif def.style == "Burst" or def.style == "Poof" then
		self:_burst(cue, def, root, col)
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
