--!nonstrict
-- SWORD 외 캐릭터(PAINTBALL, SLINGSHOT …) R6 전투 애니메이션 적용 계층 (Roblox 전용, Studio 실기동 검증 필요 — CLI 테스트 불가).
-- 구조·규칙은 SwordAnimator 와 동일하다(PreSimulation 에서 Motor6D.Transform 기록, rig 준비 대기/재시도, 중복 감시 금지,
-- 에셋 우선 재생, 사망/리스폰/캐릭터 변경/종료 시 정리). 달라진 점은 캐릭터마다 모션 데이터·상태기계를 고른다는 것뿐이다.
-- SWORD 는 SwordAnimator 가 맡으므로 이 모듈은 SWORD 모델을 절대 건드리지 않는다(같은 관절을 두 모듈이 쓰는 일 없음).
-- 시각 전용: 피해·이동·Remote·서버 로직을 건드리지 않는다. 호출부(Main.client)는 pcall 로 감싼다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Link = require(script.Parent.Link)
local Registry = Link.shared("Data/CharacterMotionRegistry")
local CharacterAnimState = require(script.Parent.Logic.CharacterAnimState)
local RigStatus = require(script.Parent.Logic.RigStatus)
local AnimationCache = require(script.Parent.Logic.AnimationCache)
local TrackBook = require(script.Parent.Logic.TrackBook)

local CharacterAnimator = {}
CharacterAnimator.__index = CharacterAnimator

local BACKLOG_SECONDS = 1.0 -- rig 준비 전 이벤트 보류 시간 상한
local BACKLOG_MAX = 16

local JOINT_DEFS = {
	Root = { "HumanoidRootPart", "RootJoint" },
	Neck = { "Torso", "Neck" },
	RArm = { "Torso", "Right Shoulder" },
	LArm = { "Torso", "Left Shoulder" },
	RLeg = { "Torso", "Right Hip" },
	LLeg = { "Torso", "Left Hip" },
}

local function now()
	return workspace:GetServerTimeNow()
end

local function disconnectAll(list)
	for _, c in list do
		c:Disconnect()
	end
	table.clear(list)
end

-- 이 모듈이 담당하는 캐릭터인가(SWORD 는 제외, 모션 데이터가 있는 캐릭터만)
local function supported(cid)
	return type(cid) == "string" and cid ~= "SWORD" and Registry.Entries[cid] ~= nil
end

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

-- 몸통 공간 회전·오프셋 → Motor6D.Transform (SwordAnimator 와 같은 식)
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

local function stopTrack(track, fade)
	pcall(function()
		track:Stop(fade)
	end)
end

local function stopTracks(rig)
	rig.book:stopAll({ stop = stopTrack })
end

local active = nil -- 살아 있는 인스턴스(중복 생성 방지: PreSimulation 연결·트랙이 두 벌 생기지 않게 한다)

function CharacterAnimator.new()
	if active ~= nil and not active._destroyed then
		warn("[CharacterAnimator] 이미 생성되어 있어 기존 인스턴스를 재사용합니다")
		return active
	end
	local self = setmetatable({
		_rigs = {}, -- [model] = rig (지원 캐릭터 + R6 준비 완료)
		_watched = {}, -- [model] = { conns, pending... }
		_bound = {}, -- [player] = { conns }
		_globalConns = {},
		_owned = {},
		_destroyed = false,
	}, CharacterAnimator)
	-- 캐시 키는 "<캐릭터>/<모션 id>"
	self._anims = AnimationCache.new(function(key)
		return self:_resolveAnimation(key)
	end)
	self:_bindPlayers()
	self:_watchAssets()
	self._stepConn = RunService.PreSimulation:Connect(function()
		self:_step()
	end)
	active = self
	return self
end

local function splitKey(key)
	local cid, id = string.match(key, "^([^/]+)/(.+)$")
	return cid, id
end

function CharacterAnimator:_resolveAnimation(key)
	local cid, id = splitKey(key)
	if cid == nil then
		return nil
	end
	local rs = ReplicatedStorage:FindFirstChild("RoBattles")
	local assets = rs and rs:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Animations")
	local charFolder = folder and folder:FindFirstChild(cid)
	local inst = charFolder and charFolder:FindFirstChild(id)
	if inst and inst:IsA("Animation") and inst.AnimationId ~= "" then
		return inst
	end
	local assetId = Registry.assetIdOf(cid, id)
	if assetId then
		local a = Instance.new("Animation")
		a.Name = key
		a.AnimationId = assetId
		self._owned[a] = true
		return a
	end
	return nil
end

function CharacterAnimator:_isAssetDriven(cid, id)
	local e = Registry.Entries[cid] and Registry.Entries[cid][id]
	if not e or e.kind == "Locomotion" then
		return false
	end
	return self._anims:has(cid .. "/" .. id)
end

function CharacterAnimator:_dropAnimationCache()
	for _, dropped in self._anims:invalidate() do
		if self._owned[dropped] then
			self._owned[dropped] = nil
			dropped:Destroy()
		end
	end
end

function CharacterAnimator:_watchAssets()
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
function CharacterAnimator:_destroyRig(model)
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

function CharacterAnimator:_unwatch(model)
	local w = self._watched[model]
	self:_destroyRig(model)
	if w then
		stopPending(w)
		disconnectAll(w.conns)
		self._watched[model] = nil
	end
end

function CharacterAnimator:_startPending(model, w)
	if w.pendingConns then
		return
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
			warn("[CharacterAnimator] R6 관절이 " .. RigStatus.MAX_WAIT .. "초 안에 준비되지 않아 애니메이션을 건너뜁니다: " .. model.Name)
		end
	end)
end

-- 지원 캐릭터 + R6 준비 완료일 때만 rig 를 만든다. CharacterId 변경·관절 추가 시 다시 호출된다. 멱등.
function CharacterAnimator:_refresh(model)
	local w = self._watched[model]
	if self._destroyed or not w then
		return
	end
	local cid = model:GetAttribute("CharacterId")
	local existing = self._rigs[model]
	if not supported(cid) then
		self:_destroyRig(model) -- 캐릭터 변경(SWORD 포함): 재생 중이던 모션 정리
		w.backlog = {}
		stopPending(w)
		w.unsupported = false
		w.cid = nil
		return
	end
	if existing and existing.cid ~= cid then
		self:_destroyRig(model) -- 지원 캐릭터끼리 바뀜: 이전 상태기계를 버리고 새로 만든다
		w.backlog = {}
		w.unsupported = false
		existing = nil
	end
	if existing or (w.unsupported and w.cid == cid) then
		return
	end
	w.unsupported = false
	w.cid = cid
	local status, joints, hum = probe(model)
	if status == "pending" then
		self:_startPending(model, w)
		return
	end
	stopPending(w)
	if status == "unsupported" then
		w.unsupported = true
		warn("[CharacterAnimator] R6 가 아니어서 " .. cid .. " 애니메이션을 비활성화합니다(R15?): " .. model.Name)
		return
	end
	local state = CharacterAnimState.new(cid, Registry.Data[cid], {
		-- Animator 가 없는 동안에는 에셋 구동으로 보지 않고 절차 포즈로 재생한다(SwordAnimator 와 같은 이유)
		assetDriven = function(id)
			return hum.Parent ~= nil and hum:FindFirstChildOfClass("Animator") ~= nil and self:_isAssetDriven(cid, id)
		end,
	})
	local rig = { model = model, cid = cid, joints = joints, humanoid = hum, state = state, book = TrackBook.new(), trackCache = {}, conns = {}, wrote = false }
	self._rigs[model] = rig
	table.insert(rig.conns, hum.Died:Connect(function()
		state:kill()
		stopTracks(rig)
		resetJoints(rig)
	end))
	local backlog = w.backlog
	w.backlog = {}
	local t = now()
	for _, item in backlog do
		if t - item.t <= BACKLOG_SECONDS then
			state:onEvent(item.event, item.t)
		end
	end
end

function CharacterAnimator:_watchCharacter(model)
	if self._destroyed or self._watched[model] then
		return
	end
	local w = { conns = {}, pendingConns = nil, pendingToken = nil, unsupported = false, cid = nil, backlog = {} }
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

function CharacterAnimator:_bindPlayer(pl)
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

function CharacterAnimator:_bindPlayers()
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

-- 이벤트 소유자 id: 대부분 playerId, 발사체 Spawned 는 ownerId
local function ownerOf(event)
	return event.playerId or event.ownerId
end

function CharacterAnimator:_deliver(userId, event)
	local pl = Players:GetPlayerByUserId(userId)
	local model = pl and pl.Character
	local rig = model and self._rigs[model]
	if rig then
		rig.state:onEvent(event, now())
		return
	end
	-- rig 가 아직 없다: 지원 캐릭터이거나 아직 알 수 없는 감시 대상이면 잠시 보류한다.
	local w = model and self._watched[model]
	if w and not w.unsupported then
		local cid = model:GetAttribute("CharacterId")
		if cid == nil or supported(cid) then
			local t = now()
			table.insert(w.backlog, { event = event, t = t })
			while #w.backlog > BACKLOG_MAX or (w.backlog[1] and t - w.backlog[1].t > BACKLOG_SECONDS) do
				table.remove(w.backlog, 1)
			end
		end
	end
end

-- Main.client 의 Feedback 수신부에서 호출.
function CharacterAnimator:onFeedback(event)
	if self._destroyed or type(event) ~= "table" then
		return
	end
	local owner = ownerOf(event)
	if owner == nil then
		return
	end
	self:_deliver(owner, event)
end

-- 본인 재장전 시작(서버 이벤트 없음: 로컬 State 스냅샷에서 감지). 본인 화면에만 재장전 모션이 나온다.
function CharacterAnimator:onLocalReloadStart()
	if self._destroyed then
		return
	end
	local me = Players.LocalPlayer
	if me then
		self:_deliver(me.UserId, { type = "ReloadStart", playerId = me.UserId })
	end
end

-- 본인 충전 입력 해제(로컬). 서버가 해제를 받아들이지 않아 종료 이벤트가 없어도 충전 자세가 남지 않게 한다.
function CharacterAnimator:onLocalRelease()
	if self._destroyed then
		return
	end
	local me = Players.LocalPlayer
	if me then
		self:_deliver(me.UserId, { type = "LocalRelease", playerId = me.UserId })
	end
end

-- 결과 화면 진입/새 경기 시작 등: 모든 rig 의 재생 중 모션과 관절 잔여물을 정리한다(rig 는 유지).
function CharacterAnimator:resetAll()
	if self._destroyed then return end
	for _, w in self._watched do
		w.backlog = {} -- 이전 경기의 rig 준비 전 이벤트도 함께 비움
	end
	for _, rig in self._rigs do
		rig.state:reset()
		stopTracks(rig)
		resetJoints(rig)
	end
end

local function serveAssetLog(self, rig)
	local log = rig.state:drain()
	if #log == 0 then
		return
	end
	local cid = rig.cid
	local motions = Registry.Data[cid].Motions
	local animator = rig.humanoid:FindFirstChildOfClass("Animator")
	-- 재생/정지 중복 방지는 TrackBook(순수 로직)이 맡고, 여기서는 Roblox 트랙 로드/캐시만 한다.
	rig.book:apply(log, {
		isAsset = function(id)
			return animator ~= nil and self:_isAssetDriven(cid, id)
		end,
		acquire = function(id)
			local anim = self._anims:get(cid .. "/" .. id)
			local cached = rig.trackCache[id]
			if cached and cached.anim ~= anim then
				pcall(function()
					cached.track:Destroy() -- 에셋이 교체됨: 이전 트랙 폐기
				end)
				cached = nil
				rig.trackCache[id] = nil
			end
			if anim and not cached then
				local ok, track = pcall(function()
					return animator:LoadAnimation(anim)
				end)
				if ok and track then
					track.Priority = Enum.AnimationPriority.Action4
					track.Looped = motions[id].hold == true
					cached = { anim = anim, track = track }
					rig.trackCache[id] = cached -- 재생마다 LoadAnimation 하지 않고 재사용
				end
			end
			return cached and cached.track or nil
		end,
		play = function(track, speed)
			track:Play(0.05, 1, speed)
		end,
		stop = stopTrack,
	})
end

function CharacterAnimator:_step()
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
				warn("[CharacterAnimator] " .. tostring(err))
			end
		end
	end
end

function CharacterAnimator:destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	if active == self then
		active = nil
	end
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

return CharacterAnimator
