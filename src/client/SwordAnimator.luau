--!nonstrict
-- SWORD R6 전투 애니메이션 적용 계층 (Roblox 전용, Studio 실기동 검증 필요 — CLI 테스트 불가).
-- 순수 로직(SwordAnimState)이 계산한 포즈를 R6 Motor6D.Transform 에 적용하거나, 정식 에셋이 있으면 Animator 트랙으로 재생한다.
-- 시각 전용: 피해·이동·Remote·서버 로직을 건드리지 않는다. 모든 클라이언트가 FireAllClients 로 받은 Feedback 으로 각자 재생한다.
-- 오류가 나도 전투 처리를 막지 않도록 호출부(Main.client)는 pcall 로 감싼다.
--
-- Animate 스크립트/Animator 와의 충돌 방지:
--   · 절차 포즈는 RunService.PreSimulation 에서 Motor6D.Transform 에 쓴다. Roblox 문서(Task scheduler): Motor6D.Transform 변경은
--     PreSimulation 에서 해야 하며, 그보다 늦은 단계(RenderStepped 등)에서 쓴 값은 Animator 가 덮어쓴다.
--     카메라·입력용 기존 RenderStepped 로직(Main.client/CameraRig)은 건드리지 않는다.
--   · 에셋 모션 구동 중에는 Transform 을 쓰지 않아 Animator 출력이 그대로 보이고, 절차→에셋 전환 시 관절을 한 번 원복한다.
--   · SWORD 가 아니거나 R6 가 아니면 아무것도 하지 않는다(다른 4캐릭터·R15 는 기존 동작 그대로).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Link = require(script.Parent.Link)
local Motions = Link.shared("Data/SwordMotions")
local Registry = Link.shared("Data/MotionRegistry")
local SwordAnimState = require(script.Parent.Logic.SwordAnimState)
local RigStatus = require(script.Parent.Logic.RigStatus)
local AnimationCache = require(script.Parent.Logic.AnimationCache)

local SwordAnimator = {}
SwordAnimator.__index = SwordAnimator

local function now()
	return workspace:GetServerTimeNow()
end

local BACKLOG_SECONDS = 1.0 -- rig 준비 전 이벤트 보류 시간 상한
local BACKLOG_MAX = 16

-- 관절 이름 → { 부모 파트 이름, Motor6D 이름 }. R6 표준 구조.
local JOINT_DEFS = {
	Root = { "HumanoidRootPart", "RootJoint" },
	Neck = { "Torso", "Neck" },
	RArm = { "Torso", "Right Shoulder" },
	LArm = { "Torso", "Left Shoulder" },
	RLeg = { "Torso", "Right Hip" },
	LLeg = { "Torso", "Left Hip" },
}

local function disconnectAll(list)
	for _, c in list do
		c:Disconnect()
	end
	table.clear(list)
end

-- 리그 상태 조사. 반환: status("ready"|"pending"|"unsupported"), joints, humanoid
local function probe(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local rigType = nil
	if hum then
		rigType = hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"
	end
	local joints, missing = {}, 0
	if hum and rigType == "R6" then
		for name, def in JOINT_DEFS do
			local parent = model:FindFirstChild(def[1])
			local motor = parent and parent:FindFirstChild(def[2])
			if motor and motor:IsA("Motor6D") then
				-- C0 회전만 떼어 둔다(축 정의가 관절마다 달라서 몸통 기준 회전을 변환하기 위함)
				local c0 = motor.C0
				joints[name] = { motor = motor, c0rot = c0 - c0.Position }
			else
				missing += 1
			end
		end
	end
	local status = RigStatus.classify({ hasHumanoid = hum ~= nil, rigType = rigType, missingJoints = missing })
	if status == "ready" then
		return status, joints, hum
	end
	return status, nil, hum
end

-- 몸통(Part0) 공간 회전·오프셋 → Motor6D.Transform.  Transform = C0rot⁻¹ · Offset · R · C0rot  (C0·Transform = C0pos · Offset · R · C0rot)
local function transformFor(j, t)
	local rot = CFrame.Angles(0, math.rad(t.ry), 0) * CFrame.Angles(math.rad(t.rx), 0, 0) * CFrame.Angles(0, 0, math.rad(t.rz))
	local off = CFrame.new(t.px, t.py, t.pz)
	return j.c0rot:Inverse() * off * rot * j.c0rot
end

local function resetJoints(rig)
	for _, j in rig.joints do
		if j.motor.Parent then
			j.motor.Transform = CFrame.new()
		end
	end
	rig.wrote = false
end

local function stopTracks(rig)
	for _, track in rig.tracks do
		pcall(function()
			track:Stop(0.05)
		end)
	end
	table.clear(rig.tracks)
end

function SwordAnimator.new()
	local self = setmetatable({
		_rigs = {}, -- [model] = rig (SWORD + R6 준비 완료)
		_watched = {}, -- [model] = { conns, pending... } (중복 감시 방지)
		_bound = {}, -- [player] = { conns } (중복 바인딩 방지)
		_globalConns = {},
		_owned = {}, -- 이 모듈이 만든 Animation 인스턴스(Destroy 책임)
		_destroyed = false,
	}, SwordAnimator)
	self._anims = AnimationCache.new(function(id)
		return self:_resolveAnimation(id)
	end)
	self:_bindPlayers()
	self:_watchAssets()
	-- 수정: RenderStepped 가 아니라 PreSimulation (Animator 갱신 이후, 물리 이전)
	self._stepConn = RunService.PreSimulation:Connect(function()
		self:_step()
	end)
	return self
end

-- ── 에셋 해석(캐시됨) ───────────────────────────────────────
-- Assets.Animations.<모션 id>(Animation 인스턴스) 우선, 없으면 레지스트리 assetId 로 Animation 을 한 번만 만든다.
function SwordAnimator:_resolveAnimation(id)
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
		a.Name = id
		a.AnimationId = assetId
		self._owned[a] = true
		return a
	end
	return nil
end

function SwordAnimator:_isAssetDriven(id)
	local e = Registry.Entries[id]
	if not e or e.kind == "Locomotion" then
		return false
	end
	return self._anims:has(id)
end

-- 에셋이 추가/삭제/교체되면 캐시를 비우고, 다음 재생부터 새로 해석한다(이미 로드된 트랙은 anim 비교로 교체).
function SwordAnimator:_dropAnimationCache()
	for _, dropped in self._anims:invalidate() do
		if self._owned[dropped] then
			self._owned[dropped] = nil
			dropped:Destroy()
		end
	end
end

function SwordAnimator:_watchAssets()
	table.insert(self._globalConns, ReplicatedStorage.DescendantAdded:Connect(function(inst)
		if inst:IsA("Animation") then
			self:_dropAnimationCache()
		end
	end))
	table.insert(self._globalConns, ReplicatedStorage.DescendantRemoving:Connect(function(inst)
		if inst:IsA("Animation") then
			self:_dropAnimationCache()
		end
	end))
end

-- ── rig 수명 ────────────────────────────────────────────────
function SwordAnimator:_destroyRig(model)
	local rig = self._rigs[model]
	if not rig then
		return
	end
	self._rigs[model] = nil
	stopTracks(rig)
	for _, cached in rig.trackCache do
		pcall(function()
			cached.track:Destroy()
		end)
	end
	table.clear(rig.trackCache)
	resetJoints(rig)
	disconnectAll(rig.conns)
	rig.state:reset()
end

local function stopPending(w)
	w.pendingToken = nil
	if w.pendingConns then
		disconnectAll(w.pendingConns)
		w.pendingConns = nil
	end
end

function SwordAnimator:_unwatch(model)
	local w = self._watched[model]
	self:_destroyRig(model)
	if w then
		stopPending(w)
		disconnectAll(w.conns)
		self._watched[model] = nil
	end
end

-- 관절이 아직 복제되지 않았을 때: 자식이 추가될 때마다(한 프레임에 한 번으로 묶어) 재시도한다. MAX_WAIT 뒤 포기.
function SwordAnimator:_startPending(model, w)
	if w.pendingConns then
		return -- 이미 대기 중(중복 연결 방지)
	end
	local token = {}
	w.pendingToken = token
	w.pendingConns = {}
	local queued = false
	table.insert(w.pendingConns, model.DescendantAdded:Connect(function()
		if queued then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			if w.pendingToken == token then
				self:_refresh(model)
			end
		end)
	end))
	task.delay(RigStatus.MAX_WAIT, function()
		if w.pendingToken == token and not self._rigs[model] then
			stopPending(w)
			warn("[SwordAnimator] R6 관절이 " .. RigStatus.MAX_WAIT .. "초 안에 준비되지 않아 SWORD 애니메이션을 건너뜁니다: " .. model.Name)
		end
	end)
end

-- 캐릭터가 SWORD + R6 준비 완료일 때만 rig 를 만든다. CharacterId 변경·관절 추가 시 다시 호출된다. 멱등(중복 rig 없음).
function SwordAnimator:_refresh(model)
	local w = self._watched[model]
	if self._destroyed or not w then
		return
	end
	local isSword = model:GetAttribute("CharacterId") == "SWORD"
	if not isSword then
		self:_destroyRig(model) -- 캐릭터 변경: 재생 중이던 모션 정리
		w.backlog = {}
		stopPending(w)
		w.unsupported = false
		return
	end
	if self._rigs[model] or w.unsupported then
		return
	end
	local status, joints, hum = probe(model)
	if status == "pending" then
		self:_startPending(model, w)
		return
	end
	stopPending(w)
	if status == "unsupported" then
		w.unsupported = true -- R15 등: 영구 미지원(기존 애니메이션 유지). CharacterId 가 바뀌면 다시 판단
		warn("[SwordAnimator] R6 가 아니어서 SWORD 애니메이션을 비활성화합니다(R15?): " .. model.Name)
		return
	end
	local state = SwordAnimState.new(Motions, {
		-- Animator 는 늦게 생길 수 있다. 없는 동안 에셋 구동으로 판정하면 트랙도 절차 포즈도 없어 모션이 통째로 사라지고
		-- 로그가 소비되며 유실된다. Animator 가 있을 때만 에셋 구동으로 보고, 없으면 절차 포즈로 재생한다.
		assetDriven = function(id)
			return hum.Parent ~= nil and hum:FindFirstChildOfClass("Animator") ~= nil and self:_isAssetDriven(id)
		end,
	})
	local rig = { model = model, joints = joints, humanoid = hum, state = state, tracks = {}, trackCache = {}, conns = {}, wrote = false }
	self._rigs[model] = rig
	table.insert(rig.conns, hum.Died:Connect(function()
		state:kill()
		stopTracks(rig)
		resetJoints(rig)
	end))
	-- rig 준비 전에 도착해 보류해 둔 최근 이벤트를 원래 수신 시각으로 재생한다(스폰 직후 Swing/Respawned 유실 방지).
	local backlog = w.backlog
	w.backlog = {}
	local t = now()
	for _, item in backlog do
		if t - item.t <= BACKLOG_SECONDS then
			state:onEvent(item.event, item.t)
		end
	end
end

function SwordAnimator:_watchCharacter(model)
	if self._destroyed or self._watched[model] then
		return -- 같은 캐릭터를 두 번 감시하지 않는다
	end
	local w = { conns = {}, pendingConns = nil, pendingToken = nil, unsupported = false, backlog = {} }
	self._watched[model] = w
	table.insert(w.conns, model:GetAttributeChangedSignal("CharacterId"):Connect(function()
		self:_refresh(model)
	end))
	table.insert(w.conns, model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			self:_unwatch(model)
		end
	end))
	task.defer(function()
		self:_refresh(model)
	end)
end

function SwordAnimator:_bindPlayer(pl)
	if self._bound[pl] or self._destroyed then
		return
	end
	local conns = {}
	self._bound[pl] = conns
	table.insert(conns, pl.CharacterAdded:Connect(function(model)
		self:_watchCharacter(model)
	end))
	table.insert(conns, pl.CharacterRemoving:Connect(function(model)
		self:_unwatch(model)
	end))
	if pl.Character then
		self:_watchCharacter(pl.Character)
	end
end

function SwordAnimator:_bindPlayers()
	for _, pl in Players:GetPlayers() do
		self:_bindPlayer(pl)
	end
	table.insert(self._globalConns, Players.PlayerAdded:Connect(function(pl)
		self:_bindPlayer(pl)
	end))
	table.insert(self._globalConns, Players.PlayerRemoving:Connect(function(pl)
		local conns = self._bound[pl]
		if pl.Character then
			self:_unwatch(pl.Character)
		end
		if conns then
			disconnectAll(conns)
			self._bound[pl] = nil
		end
	end))
end

-- Main.client 의 Feedback 수신부에서 호출. 이벤트의 playerId 에 해당하는 SWORD rig 에만 전달한다.
function SwordAnimator:onFeedback(event)
	if self._destroyed or type(event) ~= "table" or event.playerId == nil then
		return
	end
	local pl = Players:GetPlayerByUserId(event.playerId)
	local model = pl and pl.Character
	local rig = model and self._rigs[model]
	if rig then
		rig.state:onEvent(event, now())
		return
	end
	-- 아직 rig 가 없다(속성/관절/Animator 대기): SWORD 이거나 아직 알 수 없는 감시 대상이면 잠시 보류한다.
	local w = model and self._watched[model]
	if w and not w.unsupported then
		local cid = model:GetAttribute("CharacterId")
		if cid == nil or cid == "SWORD" then
			local t = now()
			table.insert(w.backlog, { event = event, t = t })
			while #w.backlog > BACKLOG_MAX or (w.backlog[1] and t - w.backlog[1].t > BACKLOG_SECONDS) do
				table.remove(w.backlog, 1)
			end
		end
	end
end

-- ── 에셋 트랙 재생/정지 (SwordAnimState 로그 소비) ───────────
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
			local anim = self._anims:get(entry.id)
			local cached = rig.trackCache[entry.id]
			if cached and cached.anim ~= anim then
				pcall(function()
					cached.track:Destroy() -- 에셋이 교체됨: 이전 트랙 폐기
				end)
				cached = nil
				rig.trackCache[entry.id] = nil
			end
			if anim and not cached then
				local ok, track = pcall(function()
					return animator:LoadAnimation(anim)
				end)
				if ok and track then
					track.Priority = Enum.AnimationPriority.Action4
					track.Looped = Motions.Motions[entry.id].hold == true
					cached = { anim = anim, track = track }
					rig.trackCache[entry.id] = cached -- 재생마다 LoadAnimation 하지 않고 재사용
				end
			end
			if cached then
				-- 같은 트랙을 가리키던 이전 serial 매핑 제거(옛 stop 이 새 재생을 끊지 않도록)
				for serial, t in rig.tracks do
					if t == cached.track then
						rig.tracks[serial] = nil
					end
				end
				cached.track:Play(0.05, 1, entry.speed or 1)
				rig.tracks[entry.serial] = cached.track
			end
		end
	end
end

function SwordAnimator:_step()
	for model, rig in self._rigs do
		if not model.Parent then
			self:_unwatch(model)
		else
			local ok, err = pcall(function()
				local hrp = model:FindFirstChild("HumanoidRootPart")
				local speed = 0
				if hrp then
					local v = hrp.AssemblyLinearVelocity
					speed = Vector3.new(v.X, 0, v.Z).Magnitude
				end
				rig.state:setLocomotion(speed, rig.humanoid.FloorMaterial == Enum.Material.Air)
				local pose = rig.state:update(now())
				serveAssetLog(self, rig)
				if pose == nil then
					-- 사망 또는 에셋 구동 중: Transform 을 쓰지 않는다. 직전에 절차 포즈를 썼다면 잔여물이 남지 않도록 한 번 원복.
					if rig.wrote then
						resetJoints(rig)
					end
					return
				end
				for name, j in rig.joints do
					local t = pose[name]
					if t then
						j.motor.Transform = transformFor(j, t)
					end
				end
				rig.wrote = true
			end)
			if not ok then
				warn("[SwordAnimator] " .. tostring(err))
			end
		end
	end
end

-- 경기 RESULTS 진입·새 경기 시작 시 SWORD 모션/잠금/관절을 즉시 정리한다.
-- 캐릭터 감시와 Rig 는 유지하므로 다음 경기 첫 Feedback 은 정상 수신한다.
function SwordAnimator:resetAll()
	if self._destroyed then return end
	for _, w in self._watched do
		w.backlog = {} -- 관절 준비 전 보류된 직전 경기 이벤트 제거
	end
	for _, rig in self._rigs do
		rig.state:reset()
		stopTracks(rig)
		resetJoints(rig)
	end
end

function SwordAnimator:destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	if self._stepConn then
		self._stepConn:Disconnect()
		self._stepConn = nil
	end
	disconnectAll(self._globalConns)
	for _, conns in self._bound do
		disconnectAll(conns)
	end
	table.clear(self._bound)
	local models = {}
	for model in self._watched do
		table.insert(models, model)
	end
	for _, model in models do
		self:_unwatch(model)
	end
	for inst in self._owned do
		inst:Destroy()
	end
	table.clear(self._owned)
end

return SwordAnimator
