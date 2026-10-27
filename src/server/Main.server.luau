--!nonstrict
-- 서버 부트스트랩 (Roblox 전용, CLI 테스트 불가 → Studio 실기동 검증 필요).
-- 역할: RemoteEvent 생성·연결, 서버 시계, 플레이어/캐릭터 수명 연결, Heartbeat 루프.
-- 모든 게임 판정은 이미 CLI로 검증된 서비스(CombatCore/ProjectileService/CharacterController)가 수행한다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Link = require(script.Parent.Link)
local Config = Link.shared("Config")
local RemoteSpec = Link.shared("RemoteSpec")
local Vec = Link.shared("Vec")

local CombatCore = require(script.Parent.CombatCore)
local ProjectileService = require(script.Parent.ProjectileService)
local CharacterController = require(script.Parent.CharacterController)
local RemoteGate = require(script.Parent.RemoteGate)
local ServerRouter = require(script.Parent.ServerRouter)
local MatchSession = require(script.Parent.MatchSession)
local WorldAdapter = require(script.Parent.WorldAdapter)
local MovementValidator = require(script.Parent.MovementValidator)
local SpawnDirector = require(script.Parent.SpawnDirector)
local RespawnScheduler = require(script.Parent.RespawnScheduler)
local CharacterSpawnGate = require(script.Parent.CharacterSpawnGate)
local SpawnPadSpec = require(script.Parent.SpawnPadSpec)
local KnockbackApplier = require(script.Parent.KnockbackApplier)

-- 맵 모듈(선택): 통합 프로젝트에서만 존재한다(ServerScriptService.BrickyardMap). 없으면 스폰 선택은 Roblox 기본 동작에 맡긴다.
local mapFolder = game:GetService("ServerScriptService"):FindFirstChild("BrickyardMap")
local SpawnRegistry = mapFolder and require(mapFolder:WaitForChild("SpawnRegistry"))
local SpawnRisk = mapFolder and require(mapFolder:WaitForChild("SpawnRisk"))
local MapConfig = mapFolder and require(mapFolder:WaitForChild("BrickyardConfig"))
local JumpPadController = mapFolder and require(mapFolder:WaitForChild("JumpPadController"))

-- 서버 시계: 클라이언트 clientTime 은 workspace:GetServerTimeNow() 기준이어야 한다.
local function now()
	return workspace:GetServerTimeNow()
end

-- RemoteEvent 생성 (클라이언트는 ReplicatedStorage.RoBattles.Remotes 에서 찾는다)
local root = ReplicatedStorage:WaitForChild("RoBattles")
local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = root
local remotes = {}
for name in RemoteSpec.Remotes do
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotesFolder
	remotes[name] = r
end
local feedback = Instance.new("RemoteEvent") -- 서버 → 클라이언트 (연출용 이벤트)
feedback.Name = "Feedback"
feedback.Parent = remotesFolder
local stateRemote = Instance.new("RemoteEvent") -- 서버 → 클라이언트 (본인 HUD 스냅샷, StateSyncHz)
stateRemote.Name = "State"
stateRemote.Parent = remotesFolder
local scoreRemote = Instance.new("RemoteEvent") -- 서버 → 클라이언트 (스코어보드, 서버 집계)
scoreRemote.Name = "Scoreboard"
scoreRemote.Parent = remotesFolder

-- 캐릭터 로드는 서버가 직접 한다(A53 개정): 기본 자동 로드는 기본 SpawnLocation 에 한 프레임 나타나므로 끈다.
-- 대신 플레이어별 서버 소유 SpawnLocation("패드")을 선택한 스폰 위치로 옮기고 player.RespawnLocation 으로 지정한 뒤 LoadCharacter 한다.
Players.CharacterAutoLoads = false
local spawnGate = CharacterSpawnGate.new()
local scheduler = RespawnScheduler.new({
	onLog = function(kind, id, detail)
		warn(string.format("[RoBattles][Respawn] %s player=%s %s", kind, tostring(id), game:GetService("HttpService"):JSONEncode(detail)))
	end,
})
local world = WorldAdapter.new()
local core = CombatCore.new()
local characterModels = {} -- [userId] = Model
local movement = MovementValidator.new({
	world = world,
	onLog = function(kind, id, detail)
		warn(string.format("[RoBattles][Move] %s player=%s %s", kind, tostring(id), game:GetService("HttpService"):JSONEncode(detail)))
	end,
})
local matchSession
local applyMatchBoundary -- assigned after map/spawn helpers; never yields
local loadTickets, joined = {}, {}
local function publishScores()
	if matchSession then scoreRemote:FireAllClients(matchSession.flow:standings()) end
end

local function pose(id)
	local model = characterModels[id]
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return nil
	end
	local look = hrp.CFrame.LookVector
	return {
		pos = hrp.Position,
		forward = look,
		dir = look,
		airborne = hum.FloorMaterial == Enum.Material.Air,
	}
end

local function targets()
	local list = {}
	for id, model in characterModels do
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if hrp then
			table.insert(list, { id = id, pos = hrp.Position, radius = Config.Combat.HitRadius, alive = core.damage:isAlive(id) })
		end
	end
	return list
end

local projectiles = ProjectileService.new({
	damage = core.damage,
	targets = targets,
	world = world,
	getPose = function(id)
		local p = pose(id)
		if not p then
			return nil
		end
		-- 빔은 눈 높이에서 바라보는 방향으로 나간다
		return { pos = Vec.add(p.pos, { X = 0, Y = Config.Combat.EyeHeight, Z = 0 }), dir = p.forward }
	end,
})
local controller = CharacterController.new({
	core = core,
	projectiles = projectiles,
	getPose = pose,
	targets = targets,
	world = world,
	movement = movement,
})
matchSession = MatchSession.new({
	core = core, controller = controller, projectiles = projectiles, scheduler = scheduler,
	onBoundary = function(...) if applyMatchBoundary then applyMatchBoundary(...) end end,
	onTransition = function() publishScores() end,
	onKill = function(e, matchId, healed)
		publishScores()
		if healed and healed>0 then
			local model=characterModels[e.attackerId]
			local hum=model and model:FindFirstChildOfClass("Humanoid")
			if hum then hum.Health=core.damage:getHealth(e.attackerId) end
			local pl=Players:GetPlayerByUserId(e.attackerId)
			if pl then feedback:FireClient(pl,{type="Healed",amount=healed,reason="KO"}) end
		end
		feedback:FireAllClients({type = "KillConfirmed", matchId = matchId, attackerId = e.attackerId,
			targetId = e.targetId, attackId = e.attackId, kind = e.kind, time = e.now, healed = healed or 0})
	end,
})
-- 서버 넉백 적용기(A59): 기본 꺼짐. 켜면 Knockback 효과 결과를 HRP 속도로 적용하고 이동 허가를 발급한다.
KnockbackApplier.new({
	movement = movement,
	setVelocity = function(id, vel)
		local model = characterModels[id]
		local hrp = model and model:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.AssemblyLinearVelocity = Vector3.new(vel.X, vel.Y, vel.Z)
		end
	end,
}):attach(core.damage)
local gate = RemoteGate.new({
	cooldown = core.cooldown,
	selectionAllowed = function(id)
		if matchSession.flow.players[id] then return true end
		return false, "not_registered"
	end,
	getState = function(id)
		local p = pose(id)
		if not p then
			return nil
		end
		local ch = Link.shared("Data/Characters")[controller:getCharacterId(id)]
		return { alive = core.damage:isAlive(id), pos = p.pos, serverTime = now(), character = ch }
	end,
})
local router = ServerRouter.new({ gate = gate, controller = controller, match = matchSession, onActivity = function(id,t) matchSession.recovery:activity(id,t) end })

-- 연출 이벤트를 클라이언트에 전달 (클라이언트 렌더링은 3단계)
projectiles:onEvent(function(e)
	feedback:FireAllClients(e)
end)
controller:onFeedback(function(e)
	feedback:FireAllClients(e)
end)
-- 부활 보호 상태를 모든 클라이언트가 볼 수 있게 캐릭터 속성으로 동기화(표시 전용, 판정은 서버 DamageService)
local function syncProtectionAttribute(id, on)
	local model = characterModels[id]
	if model then
		model:SetAttribute("SpawnProtected", on)
	end
end
controller:onFeedback(function(e)
	if e.type == "Respawned" then
		syncProtectionAttribute(e.playerId, (e.protectedUntil or 0) > 0)
	elseif e.type == "ProtectionEnded" or e.type == "Died" then
		syncProtectionAttribute(e.playerId, false)
	end
end)

-- RemoteEvent 연결: 모든 입력은 router → gate 검증을 거친다. 예외는 요청 단위로 격리한다.
for name, remote in remotes do
	remote.OnServerEvent:Connect(function(player, payload)
		local ok, accepted, info = pcall(router.dispatch, router, player.UserId, name, payload, now())
		if not ok then
			warn(string.format("[RoBattles] %s 처리 중 오류: %s", name, tostring(accepted)))
			return
		end
		if not accepted then
			feedback:FireClient(player, { type = "Rejected", remote = name, reason = tostring(info) })
		end
	end)
end

-- Humanoid 체력은 DamageService 체력의 표시용 사본이다(서버가 단방향으로 동기화).
-- 피격/타격 피드백은 관련 플레이어(피격자·공격자)에게만 보낸다(양 수치는 서버가 확정한 값).
core.damage:onDamaged(function(e)
	local ev = { type = "Damaged", attackerId = e.attackerId, targetId = e.targetId, amount = e.dealt, kind = e.kind }
	for _, uid in { e.targetId, e.attackerId } do
		local pl = Players:GetPlayerByUserId(uid)
		if pl then
			feedback:FireClient(pl, ev)
		end
		if e.attackerId == e.targetId then
			break
		end
	end
	local model = characterModels[e.targetId]
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = core.damage:getHealth(e.targetId)
	end
end)
core.damage:onKilled(function(e)
	local model = characterModels[e.targetId]
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = 0
	end
end)

-- 스폰 선택: 맵의 Spawns 폴더(SpawnRegistry) + SpawnRisk 위험도 + 전투 쪽 안전 필터(SpawnDirector).
-- 매 호출마다 폴더를 다시 읽으므로 맵을 재생성해도 별도 갱신이 필요 없다.
local director
if SpawnRegistry and SpawnRisk then
	director = SpawnDirector.new({
		risk = SpawnRisk,
		getSpawns = function()
			local list = SpawnRegistry.fromWorkspace(MapConfig.RootName)
			return list
		end,
		getEnemies = function(id)
			local list = {}
			for otherId, model in characterModels do
				local hrp = model:FindFirstChild("HumanoidRootPart")
				if otherId ~= id and hrp then
					table.insert(list, { pos = { X = hrp.Position.X, Y = hrp.Position.Y - 3, Z = hrp.Position.Z }, alive = core.damage:isAlive(otherId) })
				end
			end
			return list
		end,
		los = function(a, b)
			return world.lineOfSight(a, b)
		end,
		rng = function(lo, hi)
			return math.random(lo, hi)
		end,
		onLog = function(kind, id, detail)
			warn(string.format("[RoBattles][Spawn] %s player=%s %s", kind, tostring(id), game:GetService("HttpService"):JSONEncode(detail)))
		end,
	})
end
if JumpPadController then
	-- 점프대 발사는 서버가 허용한 이동이다: 이동 검증기에 한시적 허용량을 알린다.
	JumpPadController.setLaunchListener(function(character, velocity)
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			local horizontal = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
			local ok, why = movement:issue(player.UserId, "JumpPad", now(), { duration = 0.8, speed = horizontal, up = math.max(0, velocity.Y) })
			if not ok then
				warn("[RoBattles][Move] 점프대 허가 거부: " .. tostring(why))
			end
		end
	end)
end

local warnedNoSpawns = false
local chosen = {} -- [userId] = LoadCharacter 직전에 선택한 스폰 결과(도착 확인용, 한 번만 사용)
local pads = Instance.new("Folder")
pads.Name = "RoBattlesSpawnPads"
do
	local old = workspace:FindFirstChild("RoBattlesSpawnPads")
	if old then
		old:Destroy() -- 스크립트 재실행 시 이전 패드 정리(중복 방지)
	end
	pads.Parent = workspace
end

local function padFor(player)
	local pad = pads:FindFirstChild("Pad_" .. player.UserId)
	if pad then
		return pad
	end
	pad = Instance.new("SpawnLocation")
	pad.Name = "Pad_" .. player.UserId
	pad.Size = Vector3.new(4, 0.4, 4)
	SpawnPadSpec.apply(pad) -- Duration=0(ForceField 없음), Neutral, Enabled, 비충돌 등 규격을 한 곳에서 적용
	pad.Parent = pads
	return pad
end

-- 캐릭터 로드 함수 선택: 문서상 LoadCharacter 는 Deprecated, LoadCharacterAsync 가 대체(yield). 사용 가능하면 Async 를 쓰고
-- 없으면 LoadCharacter 로 되돌아간다(둘 다 Studio 에서 실제 동작 미검증).
local function callLoad(player)
	local hasAsync = pcall(function()
		return player.LoadCharacterAsync
	end)
	if hasAsync then
		player:LoadCharacterAsync()
	else
		player:LoadCharacter()
	end
end

local warnedBadPad = false

-- 안전한 BRICKYARD 스폰을 골라 패드를 옮기고 캐릭터를 로드한다(yield 가능: task.spawn 으로 호출). 성공 여부 반환.
-- 겹침 방지는 스케줄러가 보장한다: due() 가 시도 ID 를 발급하고, 이 호출이 반환해 finishCall 이 불릴 때까지 같은 플레이어의 새 로드를 시작하지 않는다.
local function loadCharacterFor(player)
	local id = player.UserId
	chosen[id] = nil
	player.RespawnLocation = nil
	if director then
		local result, why = director:choose(id, now())
		if result then
			local p, f = result.position, result.facing or { X = 0, Z = -1 }
			local pad = padFor(player)
			local floorPos = Vector3.new(p.X, result.spawn.pos.Y - pad.Size.Y / 2, p.Z)
			pad.CFrame = CFrame.lookAt(floorPos, floorPos + Vector3.new(f.X, 0, f.Z))
			-- RespawnLocation 은 Workspace 하위의 유효한 SpawnLocation(Enabled, Neutral, Duration=0)이어야 한다. 아니면 규격을 다시 적용하고 재검사한다.
			local valid, problems = SpawnPadSpec.validate(SpawnPadSpec.inspect(pad))
			if not valid then
				SpawnPadSpec.apply(pad)
				valid, problems = SpawnPadSpec.validate(SpawnPadSpec.inspect(pad))
			end
			if valid then
				player.RespawnLocation = pad
				chosen[id] = result
			elseif not warnedBadPad then
				warnedBadPad = true
				warn("[RoBattles][Spawn] 스폰 패드가 유효하지 않아 RespawnLocation 을 쓰지 않습니다: " .. table.concat(problems, ", "))
			end
		elseif not warnedNoSpawns then
			warnedNoSpawns = true
			warn("[RoBattles][Spawn] 스폰을 찾지 못했습니다(" .. tostring(why) .. "). 기본 스폰을 사용합니다.")
		end
	end
	local ok, err = pcall(callLoad, player)
	if not ok then
		warn("[RoBattles][Respawn] 캐릭터 로드 실패: " .. tostring(err))
	end
	return ok
end

-- 캐릭터가 선택한 스폰에 실제로 도착했는지 확인하고, 엔진이 다른 곳에 두었으면 한 번만 옮긴다(중복 이동 방지).
local function verifyPlacement(player, model)
	local id = player.UserId
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local result = chosen[id]
	chosen[id] = nil -- 한 번만 사용
	if not result and director then
		-- 서버가 로드하지 않은 캐릭터(스크립트 시작 전에 이미 있던 캐릭터 등): 지금 한 번 배치한다.
		result = director:choose(id, now())
	end
	if not result then
		return
	end
	local p = result.position
	local cur = { X = hrp.Position.X, Y = hrp.Position.Y, Z = hrp.Position.Z }
	if SpawnDirector.needsCorrection(cur, p, 6) then
		local f = result.facing or { X = 0, Z = -1 }
		local pos = Vector3.new(p.X, p.Y, p.Z)
		model:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(f.X, 0, f.Z)))
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
end

applyMatchBoundary = function(previous, phase, t)
	table.clear(chosen)
	for id, model in characterModels do
		local pl = joined[id]
		local hum = model:FindFirstChildOfClass("Humanoid")
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if hum and hrp then
			model:SetAttribute("SpawnProtected", controller:isProtected(id, t))
			if phase == "ACTIVE" and pl and hum.Health > 0 then
				verifyPlacement(pl, model)
				hum.Health = core.damage:getHealth(id)
				model:SetAttribute("CharacterId", controller:getCharacterId(id))
			end
			hrp.AssemblyLinearVelocity = Vector3.zero
			movement:teleported(id, {X = hrp.Position.X, Y = hrp.Position.Y, Z = hrp.Position.Z}, t)
			if pl then feedback:FireClient(pl, {type = "Correct", pos = {X=hrp.Position.X,Y=hrp.Position.Y,Z=hrp.Position.Z}, time=t, reason="match_boundary"}) end
		end
	end
end

local function onCharacter(player, model)
	local id = player.UserId
	local ticket = loadTickets[id]
	if ticket and ticket.accepted and characterModels[id] == model then return end -- duplicate signal for accepted model
	local function valid()
		return joined[id] == player and player.Parent ~= nil and model.Parent ~= nil
			and player.Character == model and matchSession:validLoad(ticket)
	end
	local function discard()
		if characterModels[id] == model then characterModels[id] = nil; world.removeIgnore(model) end
		matchSession:discardLoad(ticket)
		if model.Parent ~= nil then model:Destroy() end
	end
	if not valid() then discard(); return end
	local epoch = spawnGate:begin(id, model)
	if not epoch then return end
	local hum = model:WaitForChild("Humanoid", 10)
	local hrp = model:WaitForChild("HumanoidRootPart", 10)
	matchSession:updatePhase(now())
	if not hum or not hrp or not valid() or spawnGate:isStale(id, epoch) then discard(); return end
	-- No yields after the final identity/epoch checks.
	verifyPlacement(player, model)
	if not spawnGate:commit(id, epoch, model) then discard(); return end
	local previous = characterModels[id]
	if previous and previous ~= model then world.removeIgnore(previous) end
	characterModels[id] = model
	world.addIgnore(model)
	local hrpNow = model:FindFirstChild("HumanoidRootPart")
	if hrpNow then
		movement:teleported(id, { X = hrpNow.Position.X, Y = hrpNow.Position.Y, Z = hrpNow.Position.Z }, now())
	end
	-- Roblox 기본 ForceField 가 붙어 2초 보호 규칙이 연장/중복되지 않게 제거한다(보호 판정은 서버 DamageService 만).
	SpawnPadSpec.guardForceField(model, Config.Spawn.ForceFieldGuardSeconds, function(verdict)
		if verdict == "removed" then
			warn("[RoBattles][Spawn] 엔진 스폰 ForceField 로 식별되어 제거했습니다(스폰 패드 Duration 설정 확인)")
		else
			warn("[RoBattles][Spawn] 식별 불가 ForceField 감지: 제거하지 않았습니다(의도된 보호 효과인지 확인)")
		end
	end)
	-- 경기 세션이 로드 ticket 을 확인한 뒤 scheduler:onSpawned + controller:respawn + flow:spawned 를 한 번에 수행한다.
	if not matchSession:spawned(id, ticket, now()) then discard(); return end
	-- 캐릭터별 최대 체력(확정): 부활 시 선택된 캐릭터의 HP 로 표시용 Humanoid 를 맞춘다(판정은 DamageService).
	hum.MaxHealth = controller:getMaxHealth(id)
	hum.Health = controller:getMaxHealth(id)
	model:SetAttribute("CharacterId", controller:getCharacterId(id)) -- 클라이언트 임시 무기 모델용(읽기 전용 정보)
	hum.Died:Connect(function()
		if joined[id] == player and spawnGate:acceptsDeath(id, epoch, model) then
			matchSession:environmentDeath(id, now())
		end
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil and characterModels[id] == model then
			characterModels[id] = nil
			world.removeIgnore(model)
			if joined[id] == player then matchSession:environmentDeath(id, now()) end
		end
	end)
end

local function onPlayerAdded(player)
	if joined[player.UserId] or player.Parent == nil then return end
	joined[player.UserId] = player
	controller:addPlayer(player.UserId, "SWORD") -- internal default only; NOT permission to spawn/participate
	matchSession:register(player.UserId, player.DisplayName)
	player.CharacterAdded:Connect(function(model) onCharacter(player, model) end)
	-- Menu selection is mandatory even when the script encounters an existing avatar.
	if player.Character then player.Character:Destroy() end
	publishScores()
end

Players.PlayerAdded:Connect(onPlayerAdded)
-- 스크립트 시작 전에 이미 입장한 플레이어도 같은 경로로 처리
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerRemoving:Connect(function(player)
	if joined[player.UserId] ~= player then return end
	joined[player.UserId] = nil
	matchSession:remove(player.UserId, now())
	loadTickets[player.UserId] = nil
	controller:removePlayer(player.UserId, now())
	movement:remove(player.UserId)
	scheduler:remove(player.UserId)
	spawnGate:remove(player.UserId) -- 진행 중이던 CharacterAdded 처리는 모두 stale 이 된다
	chosen[player.UserId] = nil
	local pad = pads:FindFirstChild("Pad_" .. player.UserId)
	if pad then
		pad:Destroy()
	end
	if director then
		director:removePlayer(player.UserId)
	end
	characterModels[player.UserId] = nil
	publishScores()
end)

-- 서버 루프: 투사체·재장전·궁극기·이동 속도 갱신
local stateAccum, scoreAccum = 0, 0
RunService.Heartbeat:Connect(function(dt)
	local t = now()
	matchSession:tick(t) -- transitions before damage/ultimate timers; end boundary cannot leak a combat tick
	if matchSession.flow.phase=="ACTIVE" then
		for id, model in characterModels do
			local hum=model:FindFirstChildOfClass("Humanoid")
			if hum and core.damage:isAlive(id) then hum.Health=core.damage:getHealth(id) end
		end
	end
	stateAccum += dt
	scoreAccum += dt
	if stateAccum >= 1 / Config.Hud.StateSyncHz then
		stateAccum = 0
		for _, player in Players:GetPlayers() do
			local snap = controller:getHudSnapshot(player.UserId, t)
			if snap then
				stateRemote:FireClient(player, matchSession:augmentSnapshot(player.UserId, snap, t))
			end
		end
	end
	if scoreAccum >= Config.Hud.ScoreboardSyncSeconds then
		scoreAccum = 0
		publishScores()
	end
	controller:update(t, dt)
	for _, uid in matchSession:due(t) do
		local pl = Players:GetPlayerByUserId(uid)
		if not pl then
			scheduler:remove(uid)
		else
			-- LoadCharacterAsync 는 yield 하므로 별도 스레드에서 호출한다. 성공 시 CharacterAdded → scheduler:onSpawned,
			-- 실패 시 onLoadFailed(재시도 상한 적용), 응답이 없으면 스케줄러의 로드 타임아웃이 처리한다(중복 로드 방지).
			local attemptId = scheduler:getAttempt(uid)
			local ticket = matchSession:captureLoad(uid)
			loadTickets[uid] = ticket
			task.spawn(function()
				if MapConfig and not workspace:FindFirstChild(MapConfig.RootName) then
					if not workspace:WaitForChild(MapConfig.RootName, 10) then
						scheduler:finishCall(uid, attemptId, false, now()); return
					end
				end
				if joined[uid] ~= pl or not matchSession:validLoad(ticket) then
					matchSession:discardLoad(ticket); scheduler:finishCall(uid, attemptId, false, now()); return
				end
				local ok = loadCharacterFor(pl)
				-- 이 시도의 완료만 반영: 퇴장·교체·오래된 시도의 늦은 반환은 finishCall 이 무시한다.
				scheduler:finishCall(uid, attemptId, ok, now())
			end)
		end
	end
	for id, model in characterModels do
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = matchSession.flow.phase == "RESULTS" and 0 or controller:getMoveSpeed(id, t)
			-- 서버 이동 검증(A41): 살아 있는 캐릭터만. 이상 이동이면 마지막 유효 위치로 되돌리고 클라이언트에 알린다.
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if hrp and core.damage:isAlive(id) and hum.Health > 0 then
				local pos = { X = hrp.Position.X, Y = hrp.Position.Y, Z = hrp.Position.Z }
				local res = movement:observe(id, pos, t, { airborne = hum.FloorMaterial == Enum.Material.Air })
				if res.status == "correct" then
					local to = res.correctTo
					hrp.AssemblyLinearVelocity = Vector3.zero
					model:PivotTo(CFrame.new(to.X, to.Y, to.Z) * (hrp.CFrame - hrp.CFrame.Position))
					local pl = Players:GetPlayerByUserId(id)
					if pl then
						feedback:FireClient(pl, { type = "Correct", pos = to, time = t, reason = res.reason })
					end
				end
			end
		end
	end
end)
