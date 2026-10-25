--!nonstrict
-- SWORD R6 전투 애니메이션 적용 계층 (Roblox 전용, Studio 실기동 검증 필요 — CLI 테스트 불가).
-- 순수 로직(SwordAnimState)이 계산한 포즈를 R6 Motor6D.Transform 에 적용하거나, 정식 에셋이 있으면 Animator 트랙으로 재생한다.
-- 시각 전용: 피해·이동·Remote·서버 로직을 건드리지 않는다. 모든 클라이언트가 FireAllClients 로 받은 Feedback 으로 각자 재생한다.
-- 오류가 나도 전투 처리를 막지 않도록 호출부(Main.client)는 pcall 로 감싼다.
--
-- Animate 스크립트/Animator 와의 충돌 방지:
--   · 절차 포즈는 RenderStepped(Last 우선순위)에서 Motor6D.Transform 을 덮어쓴다(Animator 평가 이후에 적용되는 것이 전제 — Studio 검증 항목).
--   · 에셋 모션 구동 중에는 Transform 을 건드리지 않아 Animator 출력이 그대로 보인다.
--   · SWORD 가 아니거나 R6 가 아니면 아무것도 하지 않는다(다른 4캐릭터·R15 는 기존 동작 그대로).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Link = require(script.Parent.Link)
local Motions = Link.shared("Data/SwordMotions")
local Registry = Link.shared("Data/MotionRegistry")
local SwordAnimState = require(script.Parent.Logic.SwordAnimState)

local BIND_NAME = "RoBattlesSwordAnim"

local SwordAnimator = {}
SwordAnimator.__index = SwordAnimator

local function now()
	return workspace:GetServerTimeNow()
end

-- 관절 이름 → { 부모 파트 이름, Motor6D 이름 }. R6 표준 구조.
local JOINT_DEFS = {
	Root = { "HumanoidRootPart", "RootJoint", "Torso" },
	Neck = { "Torso", "Neck" },
	RArm = { "Torso", "Right Shoulder" },
	LArm = { "Torso", "Left Shoulder" },
	RLeg = { "Torso", "Right Hip" },
	LLeg = { "Torso", "Left Hip" },
}

-- R6 캐릭터에서 6개 Motor6D 를 찾는다. 하나라도 없으면 nil(R15 등 → 비활성).
local function findJoints(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.RigType ~= Enum.HumanoidRigType.R6 then
		return nil
	end
	local joints = {}
	for name, def in JOINT_DEFS do
		local parent = model:FindFirstChild(def[1])
		local motor = parent and parent:FindFirstChild(def[2])
		if not motor or not motor:IsA("Motor6D") then
			return nil
		end
		-- Motor6D 의 C0 회전만 떼어 둔다(축 정의가 관절마다 달라서 몸통 기준 회전을 변환하기 위함)
		local c0 = motor.C0
		joints[name] = { motor = motor, c0rot = c0 - c0.Position }
	end
	return joints, hum
end

-- 몸통(Part0) 공간 회전·오프셋 → Motor6D.Transform.  Transform = C0rot⁻¹ · Offset · R · C0rot  (C0·Transform = C0pos · Offset · R · C0rot)
local function transformFor(j, t)
	local rot = CFrame.Angles(0, math.rad(t.ry), 0) * CFrame.Angles(math.rad(t.rx), 0, 0) * CFrame.Angles(0, 0, math.rad(t.rz))
	local off = CFrame.new(t.px, t.py, t.pz)
	return j.c0rot:Inverse() * off * rot * j.c0rot
end

local function resetJoints(rig)
	if rig.joints then
		for _, j in rig.joints do
			if j.motor.Parent then
				j.motor.Transform = CFrame.new()
			end
		end
	end
end

function SwordAnimator.new()
	local self = setmetatable({ _rigs = {}, _conns = {}, _destroyed = false }, SwordAnimator)
	self._assetFolder = nil
	self:_bindPlayers()
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Last.Value, function()
		self:_step()
	end)
	return self
end

function SwordAnimator:_connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(self._conns, c)
	return c
end

-- 에셋 교체: Assets.Animations.<모션 id>(Animation 인스턴스) 우선, 없으면 레지스트리 assetId.
function SwordAnimator:_animationFor(id)
	local rs = ReplicatedStorage:FindFirstChild("RoBattles")
	local assets = rs and rs:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Animations")
	local inst = folder and folder:FindFirstChild(id)
	if inst and inst:IsA("Animation") and inst.AnimationId ~= "" then
		return inst
	end
	local assetId = Registry.assetIdOf(id)
	if assetId then
		local a = Instance.new("Animation")
		a.AnimationId = assetId
		return a
	end
	return nil
end

function SwordAnimator:_isAssetDriven(id)
	local e = Registry.Entries[id]
	if not e or e.kind == "Locomotion" then
		return false
	end
	return self:_animationFor(id) ~= nil
end

local function stopTracks(rig)
	for _, track in rig.tracks do
		pcall(function()
			track:Stop(0.05)
		end)
	end
	table.clear(rig.tracks)
end

local function destroyRig(self, model)
	local rig = self._rigs[model]
	if not rig then
		return
	end
	self._rigs[model] = nil
	stopTracks(rig)
	resetJoints(rig)
	for _, c in rig.conns do
		c:Disconnect()
	end
	rig.state:reset()
end

-- 캐릭터가 SWORD + R6 일 때만 rig 를 만든다. CharacterId 가 바뀌면 호출되어 정리/재생성한다.
function SwordAnimator:_refresh(model)
	if self._destroyed then
		return
	end
	local isSword = model:GetAttribute("CharacterId") == "SWORD"
	local rig = self._rigs[model]
	if rig and not isSword then
		destroyRig(self, model) -- 캐릭터 변경: 재생 중이던 모션 정리
		return
	end
	if rig or not isSword then
		return
	end
	local joints, hum = findJoints(model)
	if not joints then
		return -- R15 등: 기존 애니메이션 유지
	end
	local state = SwordAnimState.new(Motions, {
		assetDriven = function(id)
			return self:_isAssetDriven(id)
		end,
	})
	rig = { model = model, joints = joints, humanoid = hum, state = state, tracks = {}, conns = {} }
	self._rigs[model] = rig
	table.insert(rig.conns, hum.Died:Connect(function()
		state:kill()
		stopTracks(rig)
		resetJoints(rig)
	end))
	table.insert(rig.conns, model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			destroyRig(self, model)
		end
	end))
end

function SwordAnimator:_watchCharacter(model)
	self:_connect(model:GetAttributeChangedSignal("CharacterId"), function()
		self:_refresh(model)
	end)
	task.defer(function()
		self:_refresh(model)
	end)
end

function SwordAnimator:_bindPlayers()
	local function bindPlayer(pl)
		self:_connect(pl.CharacterAdded, function(model)
			self:_watchCharacter(model)
		end)
		self:_connect(pl.CharacterRemoving, function(model)
			destroyRig(self, model)
		end)
		if pl.Character then
			self:_watchCharacter(pl.Character)
		end
	end
	for _, pl in Players:GetPlayers() do
		bindPlayer(pl)
	end
	self:_connect(Players.PlayerAdded, bindPlayer)
end

-- Main.client 의 Feedback 수신부에서 호출. 이벤트의 playerId 에 해당하는 SWORD rig 에만 전달한다.
function SwordAnimator:onFeedback(event)
	if self._destroyed or type(event) ~= "table" or event.playerId == nil then
		return
	end
	local pl = Players:GetPlayerByUserId(event.playerId)
	local model = pl and pl.Character
	local rig = model and self._rigs[model]
	if not rig then
		-- 사망 이벤트는 CharacterId 와 무관하게 rig 가 있으면 처리되도록 위에서 이미 걸러짐(rig 없음 = 할 일 없음)
		return
	end
	rig.state:onEvent(event, now())
end

-- 에셋 트랙 재생/정지 (SwordAnimState 로그 소비)
local function serveAssetLog(self, rig)
	local log = rig.state:drain()
	if #log == 0 then
		return
	end
	local animator = rig.humanoid:FindFirstChildOfClass("Animator")
	for _, entry in log do
		if entry.kind == "stopAll" then
			stopTracks(rig)
		elseif entry.kind == "stop" then
			local track = rig.tracks[entry.serial]
			if track then
				pcall(function()
					track:Stop(0.1)
				end)
				rig.tracks[entry.serial] = nil
			end
		elseif entry.kind == "play" and animator and self:_isAssetDriven(entry.id) then
			local anim = self:_animationFor(entry.id)
			if anim then
				local ok, track = pcall(function()
					return animator:LoadAnimation(anim)
				end)
				if ok and track then
					track.Priority = Enum.AnimationPriority.Action4
					track.Looped = Motions.Motions[entry.id].hold == true
					track:Play(0.05, 1, entry.speed or 1)
					rig.tracks[entry.serial] = track
				end
			end
		end
	end
end

function SwordAnimator:_step()
	for model, rig in self._rigs do
		if not model.Parent then
			destroyRig(self, model)
		else
			local ok, err = pcall(function()
				local hrp = model:FindFirstChild("HumanoidRootPart")
				local speed, airborne = 0, false
				if hrp then
					local v = hrp.AssemblyLinearVelocity
					speed = Vector3.new(v.X, 0, v.Z).Magnitude
				end
				airborne = rig.humanoid.FloorMaterial == Enum.Material.Air
				rig.state:setLocomotion(speed, airborne)
				local pose = rig.state:update(now())
				serveAssetLog(self, rig)
				if pose == nil then
					return -- 사망 또는 에셋 구동 중: Transform 을 건드리지 않는다
				end
				for name, j in rig.joints do
					local t = pose[name]
					if t then
						j.motor.Transform = transformFor(j, t)
					end
				end
			end)
			if not ok then
				warn("[SwordAnimator] " .. tostring(err))
			end
		end
	end
end

function SwordAnimator:destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	pcall(function()
		RunService:UnbindFromRenderStep(BIND_NAME)
	end)
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	local models = {}
	for model in self._rigs do
		table.insert(models, model)
	end
	for _, model in models do
		destroyRig(self, model)
	end
end

return SwordAnimator
