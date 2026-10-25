--!nonstrict
-- Roblox 전용(Studio 미검증): Tab 홀드 스코어보드. 데이터는 서버 집계(Scoreboard 리모트)만 사용한다.
local Players = game:GetService("Players")

local ScoreboardView = {}
ScoreboardView.__index = ScoreboardView

function ScoreboardView.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoBattlesScoreboard"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local frame = Instance.new("TextLabel")
	frame.Size = UDim2.new(0, 420, 0, 360)
	frame.Position = UDim2.new(0.5, -210, 0.5, -180)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.35
	frame.TextColor3 = Color3.new(1, 1, 1)
	frame.Font = Enum.Font.Code
	frame.TextSize = 16
	frame.TextXAlignment = Enum.TextXAlignment.Left
	frame.TextYAlignment = Enum.TextYAlignment.Top
	frame.Text = ""
	frame.Parent = gui
	return setmetatable({ gui = gui, frame = frame, rows = {} }, ScoreboardView)
end

function ScoreboardView:setRows(rows)
	self.rows = rows
	local lines = { string.format("%-18s %5s %5s", "이름", "킬", "데스") }
	for _, r in rows do
		table.insert(lines, string.format("%-18s %5d %5d", tostring(r.name), r.kills, r.deaths))
	end
	self.frame.Text = table.concat(lines, "\n")
end

function ScoreboardView:setVisible(v)
	self.gui.Enabled = v
end

return ScoreboardView
