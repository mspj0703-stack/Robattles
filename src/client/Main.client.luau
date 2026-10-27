--!nonstrict
-- 클라이언트 부트스트랩 (Roblox 전용, Studio 실기동 검증 필요).
-- 원칙: 클라이언트는 입력 의사만 서버에 보낸다. 달리기·회피·궁극기·피해의 결과는 서버가 결정하고,
-- 클라이언트는 서버 스냅샷/이벤트로 표시와 이동 연출만 맞춘다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Link = require(script.Parent.Link)
local Config = Link.shared("Config")
local Characters = Link.shared("Data/Characters")
local InputState = require(script.Parent.Logic.InputState)
local KeybindSettings = require(script.Parent.Logic.KeybindSettings)
local MovementModel = require(script.Parent.Logic.MovementModel)
local HudModel = require(script.Parent.Logic.HudModel)
local FeedbackModel = require(script.Parent.Logic.FeedbackModel)
local AimAssist = require(script.Parent.Logic.AimAssist)
local EffectsModel = require(script.Parent.Logic.EffectsModel)
local EffectPlayer = require(script.Parent.EffectPlayer)
local SwordAnimator = require(script.Parent.SwordAnimator)
local CharacterAnimator = require(script.Parent.CharacterAnimator)
local MatchResetModel = require(script.Parent.Logic.MatchResetModel)
local WeaponModels = require(script.Parent.WeaponModels)
local CameraRig = require(script.Parent.CameraRig)
local UIApp = require(script.Parent.UI.App)
local AimView = require(script.Parent.AimView)

local player = Players.LocalPlayer
-- One bootstrap owns input, remotes and the UI. Never layer a second HUD.
if player:WaitForChild("PlayerGui"):FindFirstChild("RoBattlesUI") then return end
local remotes = ReplicatedStorage:WaitForChild("RoBattles"):WaitForChild("Remotes")
local function now() return workspace:GetServerTimeNow() end

local settings = KeybindSettings.new()
local input = InputState.new(settings.binds)
local rig = CameraRig.new(input)
local app = UIApp.new(settings, function(binds) input:setBinds(binds) end)
local hud = app.hud
local effects = EffectPlayer.new(function() return workspace:GetServerTimeNow() end)
local swordAnim = SwordAnimator.new() -- SWORD R6 전투 애니메이션(시각 전용). 판정·이동·Remote 와 무관
local charAnim = CharacterAnimator.new() -- PAINTBALL/SLINGSHOT R6 전투 애니메이션(시각 전용). SWORD 는 별도 모듈 담당
local lastAnimMatch -- charAnim 정리 판단용 직전 match(결과 화면 진입/새 경기)
local board = app.board
local aimView = AimView.new() -- SLINGSHOT RMB Aim Mode 궤적(표시 전용)
local chargeStart -- 클라이언트가 충전 시작을 본 시각(표시용 추정. 실제 충전량은 서버가 정한다)
local lastSnap, lastModel
local lastDodgeAccepted
local dodgeState -- { start, dir }
local dashState -- SWORD Triple Slash/Lunge 서버 확정 전진: { start, dir, speed, duration }
local lastDashAccepted
local myId = player.UserId

local settingsView = app.settings

local function character() return player.Character end
local function hrp() local c = character() return c and c:FindFirstChild("HumanoidRootPart") end

local function aimPayload(kind, range)
	local origin, dir = rig:aim(300)
	if not origin then return nil end
	-- 근접만 약한 방향 보정. 원거리는 수동 조준 그대로(확정).
	if kind == "Melee" then
		local list = {}
		for _, p in Players:GetPlayers() do
			if p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
				local pos = p.Character.HumanoidRootPart.Position
				table.insert(list, { pos = { X = pos.X, Y = pos.Y, Z = pos.Z }, alive = true })
			end
		end
		local o = { X = origin.X, Y = origin.Y, Z = origin.Z }
		local a = AimAssist.adjust("Melee", o, { X = dir.X, Y = dir.Y, Z = dir.Z }, list, range or 7)
		dir = Vector3.new(a.X, a.Y, a.Z)
	end
	return origin, dir
end

local function currentPrimaryKind()
	local id = lastSnap and lastSnap.characterId
	local def = id and Characters[id]
	return def and def.primary.kind, def and def.primary.range
end

local function send(cmd)
	if cmd.localEffect == "CameraMode" then
		rig:setMode(cmd.mode)
	elseif cmd.localEffect == "Scoreboard" then
		board:setVisible(cmd.visible and not app:isBlocking())
	elseif cmd.localEffect == "AimMode" then
		aimView:setActive(cmd.active)
	elseif cmd.remote == "Attack" or cmd.remote == "Skill" then
		if cmd.phase == "Release" then pcall(function() charAnim:onLocalRelease() end) end
		local kind, range = "Projectile", nil
		if cmd.action == "Primary" then kind, range = currentPrimaryKind() end
		local origin, dir = aimPayload(kind or "Projectile", range)
		if origin then
			local payload = { aimOrigin = origin, aimDirection = dir, clientTime = now() }
			if cmd.remote == "Attack" then
				payload.action = cmd.action
				payload.phase = cmd.phase -- 충전형 주무기(SUPERBALL)의 Press/Release
			else
				payload.slot = cmd.slot
				payload.phase = cmd.phase -- 충전형 스킬(SWORD Lunge)의 Press/Release. 서버가 충전 상태를 검증한다.
			end
			remotes[cmd.remote]:FireServer(payload)
		end
	elseif cmd.remote == "Aim" then
		local origin, dir = rig:aim(300)
		if origin then
			remotes.Aim:FireServer({ aimOrigin = origin, aimDirection = dir, clientTime = now() })
		end
	elseif cmd.remote == "Dodge" then
		local c = workspace.CurrentCamera
		local h = hrp()
		if c and h then
			local mv = input:moveVector()
			local look, right = rig.model:lookDirection(), rig.model:rightVector()
			local f = h.CFrame.LookVector
			local d = MovementModel.dodgeDirection(mv, look, right, { X = f.X, Y = f.Y, Z = f.Z })
			remotes.Dodge:FireServer({ direction = Vector3.new(d.X, d.Y, d.Z) })
		end
	elseif cmd.remote == "SetRun" then
		remotes.SetRun:FireServer({ enabled = cmd.enabled })
	elseif cmd.remote == "Ultimate" then
		remotes.Ultimate:FireServer({})
	elseif cmd.remote == "Reload" then
		remotes.Reload:FireServer({})
	end
end

local function sendAll(cmds)
	for _, c in cmds do send(c) end
end

-- UI integration seam only. No skill/cooldown/damage implementation lives here.
-- Opening a menu / dying / results: release every held button (server rejects late Release safely) and stop sprint.
app:setCallbacks({
	select = function(id) remotes.SelectCharacter:FireServer({ characterId = id }) end,
	blocking = function(open)
		sendAll(input:releaseAll())
		input:setUiBlocking(open)
		if open then
			aimView:setActive(false)
			if input.running then
				input.running = false
				remotes.SetRun:FireServer({ enabled = false })
			end
		end
	end,
})
script.Destroying:Connect(function() app:destroy(); effects:destroy(); swordAnim:destroy(); charAnim:destroy() end)

local function nameOf(inputObj)
	if inputObj.KeyCode ~= Enum.KeyCode.Unknown then return inputObj.KeyCode.Name end
	return inputObj.UserInputType.Name
end

UserInputService.InputBegan:Connect(function(obj, processed)
	if obj.KeyCode == Enum.KeyCode.F9 then
		app:toggleMenu()
		return
	end
	if obj.KeyCode == Enum.KeyCode.F10 then
		settingsView:setOpen(not settingsView:isOpen())
		return
	end
	if settingsView:handleInput(obj) then return end
	if (processed and obj.UserInputType == Enum.UserInputType.Keyboard) or app:isBlocking() then return end
	sendAll(input:press(nameOf(obj), now()))
end)
UserInputService.InputEnded:Connect(function(obj)
	sendAll(input:release(nameOf(obj)))
end)
UserInputService.WindowFocusReleased:Connect(function()
	sendAll(input:releaseAll())
end)
UserInputService.InputChanged:Connect(function(obj)
	if obj.UserInputType == Enum.UserInputType.MouseMovement and not app:isBlocking() then
		rig:onMouseDelta(obj.Delta * app.state.preferences.sensitivity)
	end
end)

-- 서버 → 클라이언트
remotes:WaitForChild("State").OnClientEvent:Connect(function(snap)
	if not app:setSnapshot(snap, now()) then return end -- stale / malformed snapshots never reach input or HUD
	if EffectsModel.reloadStarted(lastSnap, snap, now()) then
		effects:play({ cue = "reload.start", playerId = myId, mine = true })
		pcall(function() charAnim:onLocalReloadStart() end)
	end
	pcall(function()
		local m = MatchResetModel.matchOf(snap)
		if MatchResetModel.shouldReset(lastAnimMatch, m) then
			charAnim:resetAll()
			swordAnim:resetAll() -- SWORD 포함 5캐릭터 동일 경기 경계 정리
		end
		lastAnimMatch = m
	end)
	lastSnap = snap
	local charDef = Characters[snap.characterId]
	input:setCharacter(snap.characterId, snap.ammo ~= nil, charDef ~= nil and charDef.primary.automatic == true, charDef ~= nil and charDef.primary.chargeSeconds ~= nil, charDef ~= nil and charDef.secondary ~= nil and charDef.secondary.clientOnly == true)
	if not snap.alive or charDef == nil or charDef.secondary == nil or charDef.secondary.clientOnly ~= true then
		aimView:setActive(false) -- 사망·캐릭터 변경 시 궤적 표시 정리
	end
	input:reconcileRun(snap.running, now())
	hud:setCrosshair(snap.characterId, snap.alive)
end)
remotes:WaitForChild("Scoreboard").OnClientEvent:Connect(function(rows)
	app:setRows(rows)
end)
local lastCorrection
remotes:WaitForChild("Feedback").OnClientEvent:Connect(function(event)
	pcall(function() swordAnim:onFeedback(event) end) -- 애니메이션 오류가 전투 처리를 막지 않도록 격리
	pcall(function() charAnim:onFeedback(event) end)
	app:onFeedback(event, now())
	-- 서버 위치 보정(A41): 서버가 되돌린 위치로 즉시 이동하고 진행 중이던 회피는 취소한다.
	if MovementModel.acceptCorrection(event, now(), lastCorrection, 1) == "snap" then
		lastCorrection = event.time
		local h = hrp()
		if h then
			h.AssemblyLinearVelocity = Vector3.zero
			h.CFrame = CFrame.new(event.pos.X, event.pos.Y, event.pos.Z) * (h.CFrame - h.CFrame.Position)
		end
		dodgeState = nil
		dashState = nil
		return
	end
	-- SWORD 스킬 전진/돌진: 서버가 이동 허가를 발급한 뒤 보낸 이벤트만 따른다.
	if MovementModel.acceptDashEvent(event, myId, now(), lastDashAccepted, 1) then
		lastDashAccepted = event.time
		dashState = { start = now(), dir = event.direction, speed = event.dash.speed, duration = event.dash.duration, permit = event.dash.permit, up = event.dash.up }
		dodgeState = nil
	elseif (event.type == "SwordSkill" or event.type == "CharSkill") and event.playerId == myId and event.phase == "Cancel" then
		dashState = nil
	end
	if MovementModel.acceptDodgeEvent(event, myId, now(), lastDodgeAccepted, 1) then
		dashState = nil
		lastDodgeAccepted = event.time
		dodgeState = { start = now(), dir = event.info and event.info.direction, distance = event.info and event.info.distance }
	end
	for _, fx in FeedbackModel.translate(event, myId) do
		if fx.kind == "Toast" then
			hud:showToast(fx.text, now(), 2)
		elseif fx.kind == "ParrySuccess" and fx.mine then
			hud:showToast("패링 성공!", now(), 1)
		elseif fx.kind == "WasParried" then
			hud:showToast("패링당함!", now(), 1)
		elseif fx.kind == "DamageTaken" then
			if app.state.preferences.damageNumbers then hud:showToast(string.format("-%d", fx.amount or 0), now(), 0.5) end
		elseif fx.kind == "HitMarker" then
			hud:showHitMarker(now())
		end
	end
	-- 임시 연출(시각 전용): 최종 아트는 Assets 폴더 교체로 바꾼다.
	for _, cue in EffectsModel.translate(event, myId) do
		if cue.cue == "dodge.afterimage" and not cue.origin then
			local r = cue.playerId == myId and hrp() or nil
			if r then cue.origin = { X = r.Position.X, Y = r.Position.Y, Z = r.Position.Z } end
		end
		effects:play(cue)
	end
end)

-- 임시 무기 모델: 서버가 캐릭터에 기록한 CharacterId 속성을 따라 모든 플레이어 오른손에 붙인다.
local function watchWeapon(pl)
	local function bind(model)
		local function refresh()
			local cid = model:GetAttribute("CharacterId")
			if cid then
				WeaponModels.attach(model, cid)
			end
		end
		model:GetAttributeChangedSignal("CharacterId"):Connect(refresh)
		task.defer(refresh)
	end
	pl.CharacterAdded:Connect(bind)
	if pl.Character then bind(pl.Character) end
end
-- 부활 보호 표시(다른 플레이어 포함): 서버가 캐릭터에 기록한 SpawnProtected 속성을 따라 청록 하이라이트를 켜고 끈다(표시 전용).
local function watchProtection(pl)
	local function bind(model)
		local function refresh()
			local existing = model:FindFirstChild("RoBattlesProtect")
			if model:GetAttribute("SpawnProtected") == true then
				if not existing then
					local h = Instance.new("Highlight")
					h.Name = "RoBattlesProtect"
					h.FillColor = Color3.fromRGB(80, 220, 255)
					h.FillTransparency = 0.7
					h.OutlineColor = Color3.fromRGB(80, 220, 255)
					h.Parent = model
				end
			elseif existing then
				existing:Destroy()
			end
		end
		model:GetAttributeChangedSignal("SpawnProtected"):Connect(refresh)
		refresh()
	end
	pl.CharacterAdded:Connect(bind)
	if pl.Character then bind(pl.Character) end
end
for _, pl in Players:GetPlayers() do watchProtection(pl) end
Players.PlayerAdded:Connect(watchProtection)
for _, pl in Players:GetPlayers() do watchWeapon(pl) end
Players.PlayerAdded:Connect(watchWeapon)

player.CharacterRemoving:Connect(function()
	lastSnap, lastModel = nil, nil
	app:awaitSnapshot()
end)

player.CharacterAdded:Connect(function(model)
	lastSnap, lastModel = nil, nil
	app:awaitSnapshot()
	rig:setCharacter(model)
	input.running = false
	dodgeState = nil
	dashState = nil
end)
if player.Character then rig:setCharacter(player.Character) end

-- 매 프레임: 카메라, 회피 이동(서버 확인 후), 달리기 속도 표시, HUD
local uiElapsed = 0
RunService.RenderStepped:Connect(function(dt)
	local blocking = app:isBlocking()
	if not blocking then
		rig:update()
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	local h = hrp()
	-- SLINGSHOT Aim Mode 궤적: 충전 표시용 추정값(누른 시간 / chargeSeconds). 서버 판정과 무관.
	if input.primaryHeld then
		chargeStart = chargeStart or now()
	else
		chargeStart = nil
	end
	if input.aimHeld and h and lastSnap then
		local o, d = rig:aim(300)
		local def = Characters[lastSnap.characterId]
		if o and def and def.primary.chargeSeconds then
			local charge = chargeStart and math.clamp((now() - chargeStart) / def.primary.chargeSeconds, 0, 1) or 0
			local p = h.Position
			aimView:update({ X = p.X, Y = p.Y + Config.Combat.EyeHeight, Z = p.Z }, { X = d.X, Y = d.Y, Z = d.Z }, charge, lastSnap.characterId)
		end
	end
	if h and dodgeState and dodgeState.dir then
		local d = dodgeState.dir
		local v = MovementModel.dodgeVelocity(dodgeState.start, { X = d.X, Y = d.Y, Z = d.Z }, now(), nil, dodgeState.distance)
		if v then
			h.AssemblyLinearVelocity = Vector3.new(v.X, h.AssemblyLinearVelocity.Y, v.Z)
		else
			dodgeState = nil
		end
	end
	if h and dashState then
		local v = MovementModel.dashVelocity(dashState.start, dashState.dir, dashState.speed, dashState.duration, now(), nil, dashState.permit, dashState.up)
		if v then
			h.AssemblyLinearVelocity = Vector3.new(v.X, v.Y or h.AssemblyLinearVelocity.Y, v.Z)
		else
			dashState = nil
		end
	end
	-- 이동 방향은 카메라 기준으로 Humanoid에 전달(WalkSpeed는 서버가 설정)
	local c = character()
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if hum then
		local mv = blocking and { x = 0, z = 0 } or input:moveVector()
		local look, right = rig.model:lookDirection(), rig.model:rightVector()
		local fx, fz = look.X, look.Z
		local fl = math.sqrt(fx * fx + fz * fz)
		if fl > 1e-6 then fx, fz = fx / fl, fz / fl end
		hum:Move(Vector3.new(right.X * mv.x + fx * mv.z, 0, right.Z * mv.x + fz * mv.z), false)
		if input.mode == "Locked" and h and (mv.x ~= 0 or mv.z ~= 0 or input.held["MouseButton1"]) then
			hum.AutoRotate = false
			h.CFrame = CFrame.lookAt(h.Position, h.Position + Vector3.new(fx, 0, fz))
		else
			hum.AutoRotate = input.mode == "Free"
		end
	end
	if lastSnap and lastSnap.alive and not blocking then
		-- 자동 연사: LMB 를 누르고 있는 동안 서버에 반복 발사 의사를 보낸다(간격·탄약은 서버가 판정)
		local def = Characters[lastSnap.characterId]
		if def and def.primary.fireInterval then
			local cmd = input:autoFire(now(), def.primary.fireInterval)
			if cmd then send(cmd) end
		end
		-- 빔 시전 중 조준 갱신(PAINTBALL Color Break): 시전 중에만 일정 주기로 전송
		local ult = lastSnap.ultimate
		if input:aimDue(now(), ult ~= nil and ult.active == true and lastSnap.characterId == "PAINTBALL", 1 / Config.Hud.AimSyncHz) then
			send({ remote = "Aim" })
		end
	end
	uiElapsed += dt
	if uiElapsed >= 0.05 then
		uiElapsed = 0
		lastModel = lastSnap and HudModel.build(lastSnap, now()) or nil
		app:render(lastModel, now())
	end
end)

