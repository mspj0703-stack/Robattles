--!nonstrict
-- 클라이언트 입력 상태 기계(순수 로직). 키 이름(Enum.KeyCode.Name / UserInputType.Name) → 서버로 보낼 명령.
-- 이 모듈은 "의사 전달"만 만든다. 달리기·회피·궁극기의 실제 결과는 서버가 결정한다.
local Link = require(script.Parent.Parent.Link)
local Config = Link.shared("Config")
local Keybinds = Link.shared("Keybinds")

local InputState = {}
InputState.__index = InputState

function InputState.new(binds, config)
	local cfg = config or Config
	local resolved = binds or Keybinds.defaults(cfg)
	local self = setmetatable({
		_cfg = cfg,
		_binds = resolved,
		_byKey = {},
		running = false, -- 클라이언트가 요청한 달리기 상태(서버 스냅샷으로 보정)
		_runRequestedAt = nil,
		scoreboardHeld = false,
		freeLookHeld = false,
		held = {}, -- 눌린 키 이름 집합(이동 입력용)
		mode = cfg.Camera.InitialMode,
		hasAmmo = false, -- 현재 캐릭터가 탄약을 쓰는지(R 키 전송 여부)
		uiBlocking = false, -- 설정창 등이 열려 있으면 전투 입력을 막는다
	}, InputState)
	self:setBinds(resolved)
	return self
end

function InputState:setBinds(binds)
	self._binds = binds
	self._byKey = {}
	for action, key in binds do
		self._byKey[key] = action
	end
end

function InputState:setCharacter(characterId, hasAmmo)
	self.hasAmmo = hasAmmo == true
end

function InputState:actionOf(keyName)
	return self._byKey[keyName]
end

-- 키/버튼이 눌렸을 때. 반환: 서버 전송 명령 목록 [{ remote=..., ... }] 와 로컬 효과 목록 [{ local_=... }]
function InputState:press(keyName, now)
	local cmds = {}
	self.held[keyName] = true
	if self.uiBlocking then
		return cmds
	end
	local action = self._byKey[keyName]
	if action == nil then
		return cmds
	end
	if action == "CameraToggle" then
		self.mode = self.mode == "Locked" and "Free" or "Locked"
		table.insert(cmds, { localEffect = "CameraMode", mode = self.mode })
	elseif action == "RunToggle" then
		self.running = not self.running
		self._runRequestedAt = now
		table.insert(cmds, { remote = "SetRun", enabled = self.running })
	elseif action == "Dodge" then
		table.insert(cmds, { remote = "Dodge" })
	elseif action == "Ultimate" then
		table.insert(cmds, { remote = "Ultimate" })
	elseif action == "Primary" or action == "Secondary" then
		-- Free 모드에서도 RMB는 항상 보조 공격이다(자유 시점 회전은 별도 FreeLook 버튼).
		table.insert(cmds, { remote = "Attack", action = action })
		if self.running then
			-- 공격하면 달리기가 해제된다(서버도 동일 규칙으로 해제). 클라이언트는 즉시 낙관적으로 반영.
			self.running = false
		end
	elseif action == "Reload" then
		if self.hasAmmo then
			table.insert(cmds, { remote = "Reload" })
		end
	elseif action == "Skill1" then
		table.insert(cmds, { remote = "Skill", slot = 1 })
	elseif action == "Skill2" then
		table.insert(cmds, { remote = "Skill", slot = 2, phase = "Press" })
		self.skill2Held = true
	elseif action == "Skill3" then
		table.insert(cmds, { remote = "Skill", slot = 3 })
	elseif action == "Scoreboard" then
		self.scoreboardHeld = true
		table.insert(cmds, { localEffect = "Scoreboard", visible = true })
	elseif action == "FreeLook" then
		self.freeLookHeld = true
	end
	return cmds
end

function InputState:release(keyName)
	local cmds = {}
	self.held[keyName] = nil
	local action = self._byKey[keyName]
	if action == "Scoreboard" and self.scoreboardHeld then
		self.scoreboardHeld = false
		table.insert(cmds, { localEffect = "Scoreboard", visible = false })
	elseif action == "FreeLook" then
		self.freeLookHeld = false
	elseif action == "Skill2" and self.skill2Held then
		-- 충전형 스킬(SWORD Lunge): 키를 떼면 서버에 발사 의사를 보낸다. 충전 중이 아니면 서버가 거부한다.
		self.skill2Held = false
		table.insert(cmds, { remote = "Skill", slot = 2, phase = "Release" })
	end
	return cmds
end

-- 포커스 상실·창 전환 시 눌림 상태 정리(스코어보드가 켜진 채 남는 문제 방지)
function InputState:releaseAll()
	local cmds = {}
	if self.scoreboardHeld then
		self.scoreboardHeld = false
		table.insert(cmds, { localEffect = "Scoreboard", visible = false })
	end
	if self.skill2Held then
		self.skill2Held = false
		table.insert(cmds, { remote = "Skill", slot = 2, phase = "Release" })
	end
	self.freeLookHeld = false
	self.held = {}
	return cmds
end

-- 서버 스냅샷으로 달리기 상태를 보정한다. 서버 값이 항상 우선이며,
-- 방금 보낸 요청(RunReconcileTimeout 이내)은 서버가 아직 반영하지 못했을 수 있어 잠시 유예한다.
function InputState:reconcileRun(serverRunning, now)
	if self._runRequestedAt and now - self._runRequestedAt < self._cfg.Hud.RunReconcileTimeout then
		if self.running == serverRunning then
			self._runRequestedAt = nil
		end
		return self.running
	end
	self._runRequestedAt = nil
	self.running = serverRunning
	return self.running
end

function InputState:setUiBlocking(blocking)
	self.uiBlocking = blocking
end

-- 이동 입력 벡터(카메라 기준 로컬 축): x=오른쪽, z=앞쪽. 대각선 정규화.
function InputState:moveVector()
	local x, z = 0, 0
	if self.held["D"] then x += 1 end
	if self.held["A"] then x -= 1 end
	if self.held["W"] then z += 1 end
	if self.held["S"] then z -= 1 end
	local l = math.sqrt(x * x + z * z)
	if l < 1e-9 then
		return { x = 0, z = 0 }
	end
	return { x = x / l, z = z / l }
end

return InputState
