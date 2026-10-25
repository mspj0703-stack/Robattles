--!nonstrict
-- Roblox 전용(Studio 미검증): 임시 HUD. 디자인은 미확정이므로 기능 표시만 한다(ASSUMPTION A43).
-- 표시 내용은 전부 Logic/HudModel 이 서버 스냅샷에서 계산한다.
local Players = game:GetService("Players")

local Crosshairs = require(script.Parent.Logic.Crosshairs)

local HudView = {}
HudView.__index = HudView

local function label(parent, name, pos, size, text)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Position = pos
	l.Size = size
	l.BackgroundTransparency = 0.5
	l.BackgroundColor3 = Color3.new(0, 0, 0)
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamMedium
	l.TextSize = 16
	l.Text = text or ""
	l.Parent = parent
	return l
end

function HudView.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoBattlesHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local self = setmetatable({ gui = gui, toastUntil = 0 }, HudView)
	self.health = label(gui, "Health", UDim2.new(0, 20, 1, -60), UDim2.new(0, 260, 0, 36), "")
	self.bar = Instance.new("Frame")
	self.bar.BackgroundColor3 = Color3.fromRGB(80, 200, 90)
	self.bar.BorderSizePixel = 0
	self.bar.Size = UDim2.fromScale(1, 1)
	self.bar.ZIndex = 0
	self.bar.Parent = self.health
	self.ammo = label(gui, "Ammo", UDim2.new(1, -220, 1, -60), UDim2.new(0, 200, 0, 36), "")
	self.dodge = label(gui, "Dodge", UDim2.new(0, 20, 1, -104), UDim2.new(0, 260, 0, 36), "")
	self.skills = label(gui, "Skills", UDim2.new(0.5, -210, 1, -60), UDim2.new(0, 420, 0, 36), "")
	self.combo = label(gui, "Combo", UDim2.new(0, 20, 1, -148), UDim2.new(0, 300, 0, 32), "")
	self.combo.Visible = false
	self.secondary = label(gui, "Secondary", UDim2.new(0.5, -210, 1, -104), UDim2.new(0, 200, 0, 36), "")
	self.ultimate = label(gui, "Ultimate", UDim2.new(0.5, 10, 1, -104), UDim2.new(0, 200, 0, 36), "")
	self.protect = label(gui, "Protection", UDim2.new(0.5, -120, 0.3, 0), UDim2.new(0, 240, 0, 32), "")
	self.protect.Visible = false
	self.toast = label(gui, "Toast", UDim2.new(0.5, -180, 0.2, 0), UDim2.new(0, 360, 0, 32), "")
	self.toast.Visible = false
	self.cross = label(gui, "Crosshair", UDim2.new(0.5, -4, 0.5, -4), UDim2.new(0, 8, 0, 8), "")
	self.cross.BackgroundTransparency = 0
	return self
end

function HudView:setCrosshair(characterId, visible)
	local def = Crosshairs.get(characterId)
	self.cross.Visible = visible
	self.cross.Size = UDim2.new(0, def.size, 0, def.size)
	self.cross.Position = UDim2.new(0.5, -def.size / 2, 0.5, -def.size / 2)
	self.cross.Text = def.style == "Ring" and "○" or def.style == "Cross" and "+" or ""
	self.cross.BackgroundTransparency = def.style == "Dot" and 0 or 1
end

function HudView:render(m, now)
	if not m then
		return
	end
	self.health.Text = m.healthText
	self.bar.Size = UDim2.fromScale(m.healthFrac, 1)
	self.ammo.Visible = m.ammo ~= nil
	if m.ammo then
		self.ammo.Text = m.ammo.reloading and "재장전..." or m.ammo.text
	end
	if m.dodge then
		self.dodge.Text = string.format("회피 %d/%d%s", m.dodge.charges, m.dodge.max, m.dodge.nextIn and string.format(" (%.1fs)", m.dodge.nextIn) or "")
	end
	local parts = {}
	for i, s in m.skills do
		table.insert(parts, string.format("[%s] %s", s.key, s.label))
	end
	self.skills.Text = table.concat(parts, "  ")
	self.skills.TextSize = 14
	self.skills.Size = UDim2.new(0, 520, 0, 36)
	self.skills.Position = UDim2.new(0.5, -260, 1, -60)
	self.combo.Visible = m.combo ~= nil or m.passive ~= nil
	local extra = {}
	if m.combo then table.insert(extra, "LMB " .. m.combo.text) end
	if m.passive then table.insert(extra, m.passive.text) end
	self.combo.Text = table.concat(extra, "  |  ")
	self.secondary.Visible = m.secondary ~= nil
	if m.secondary then
		self.secondary.Text = m.parryActive and "패링 중!" or (m.secondary.ready and "RMB 준비" or string.format("RMB %.1fs", m.secondary.remaining))
	end
	if m.ultimate then
		self.ultimate.Text = string.format("%d%% %s", m.ultimate.gauge, m.ultimate.label)
	end
	if now > self.toastUntil then
		self.toast.Visible = false
	end
	self.protect.Visible = m.protection ~= nil
	if m.protection then
		self.protect.Text = string.format("부활 보호 %.1fs", m.protection.remaining)
	end
	if self.hitUntil and now > self.hitUntil then
		self.hitUntil = nil
		self.cross.TextColor3 = Color3.fromRGB(255, 255, 255)
		self.cross.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	end
end

-- 타격 확인: 조준점을 잠깐 빨갛게 (임시 피드백, 최종 HUD 아님)
function HudView:showHitMarker(now)
	self.hitUntil = now + 0.15
	self.cross.TextColor3 = Color3.fromRGB(255, 70, 70)
	self.cross.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
end

function HudView:showToast(text, now, seconds)
	self.toast.Text = text
	self.toast.Visible = true
	self.toastUntil = now + (seconds or 2)
end

return HudView
