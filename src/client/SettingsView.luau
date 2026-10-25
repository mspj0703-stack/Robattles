--!nonstrict
-- Roblox 전용(Studio 미검증): 키 설정 임시 UI. 검증은 Logic/KeybindSettings → 공유 Keybinds.resolve.
-- 열기: 기본 F10 (고정, 재지정 불가). 항목을 클릭한 뒤 새 키를 누르면 변경. 영구 저장 미구현(A45).
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Link = require(script.Parent.Link)
local Keybinds = Link.shared("Keybinds")

local SettingsView = {}
SettingsView.__index = SettingsView

local LABELS = {
	CameraToggle = "시점 전환", RunToggle = "달리기 토글", Dodge = "회피", Ultimate = "궁극기", Primary = "기본 공격",
	Secondary = "보조 공격", Reload = "재장전", FreeLook = "자유 시점 회전", Skill1 = "스킬 1", Skill2 = "스킬 2",
	Skill3 = "스킬 3", Scoreboard = "스코어보드",
}

function SettingsView.new(settings, onChanged, onToggle)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoBattlesSettings"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 360, 0, 480)
	frame.Position = UDim2.new(0.5, -180, 0.5, -240)
	frame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
	frame.Parent = gui
	local msg = Instance.new("TextLabel")
	msg.Size = UDim2.new(1, 0, 0, 28)
	msg.BackgroundTransparency = 1
	msg.TextColor3 = Color3.new(1, 1, 0.6)
	msg.Text = "키 설정 (항목 클릭 후 새 키 입력)"
	msg.Parent = frame

	local self = setmetatable({ gui = gui, settings = settings, buttons = {}, waiting = nil, msg = msg, onChanged = onChanged, onToggle = onToggle }, SettingsView)
	for i, action in Keybinds.Actions do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -20, 0, 28)
		b.Position = UDim2.new(0, 10, 0, 32 + (i - 1) * 32)
		b.Parent = frame
		b.MouseButton1Click:Connect(function()
			self.waiting = action
			self.msg.Text = LABELS[action] .. ": 새 키를 누르세요 (Esc 취소)"
		end)
		self.buttons[action] = b
	end
	self:refresh()
	return self
end

function SettingsView:refresh()
	for action, b in self.buttons do
		b.Text = string.format("%s : %s", (LABELS[action] or action), self.settings.binds[action])
	end
end

function SettingsView:setOpen(open)
	self.gui.Enabled = open
	self.waiting = nil
	if self.onToggle then
		self.onToggle(open)
	end
end

function SettingsView:isOpen()
	return self.gui.Enabled
end

-- 키 대기 중이면 입력을 소비하고 true 반환
function SettingsView:handleInput(input)
	if not self.waiting then
		return false
	end
	local name = input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode.Name or input.UserInputType.Name
	if name == "Escape" then
		self.waiting = nil
		self.msg.Text = "취소됨"
		return true
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Focus then
		return true
	end
	local ok, err = self.settings:set(self.waiting, name)
	self.msg.Text = ok and "변경됨" or ("거부: " .. tostring(err))
	if ok and self.onChanged then
		self.onChanged(self.settings.binds)
	end
	self.waiting = nil
	self:refresh()
	return true
end

return SettingsView
