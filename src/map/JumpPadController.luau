--!nonstrict
-- Roblox 전용(Studio 미검증): 점프대 발동. 전투 코어와 독립.
-- 서버에서 Touched 시 HumanoidRootPart 속도만 설정한다. PlatformStand/Anchored/상태 강제 변경을 하지 않으므로
-- 공중에서 방향 전환(Humanoid:Move)과 공격 입력은 막지 않는다(실제 동작은 Studio 확인 필요).
-- 플레이어 캐릭터는 클라이언트가 물리 소유권을 가지므로 서버 설정이 반영/보정되는지는 미검증이다.
--
-- 중복 연결 방지: attach 는 항상 이전 연결을 먼저 모두 끊는다(맵 재생성 시 이벤트가 쌓이지 않음).
local Players = game:GetService("Players")

local JumpPadController = {}

local connections = {}
local launchListener -- function(character, velocity) : 전투 쪽이 이동 검증 허용량을 갱신하는 데 쓴다
local last = {} -- [Model] = 마지막 발동 시각(os.clock)

function JumpPadController.detach()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	table.clear(last)
end

function JumpPadController.setLaunchListener(fn)
	launchListener = fn
end

function JumpPadController.connectionCount()
	return #connections
end

function JumpPadController.attach(root)
	JumpPadController.detach()
	local count = 0
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") and inst:GetAttribute("JumpPad") == true then
			count += 1
			table.insert(connections, inst.Touched:Connect(function(hit)
				local char = hit.Parent
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if not hum or not hrp or hum.Health <= 0 then
					return
				end
				if hit ~= hrp and hit.Name ~= "LeftFoot" and hit.Name ~= "RightFoot" and hit.Name ~= "Left Leg" and hit.Name ~= "Right Leg" then
					return
				end
				local now = os.clock()
				if last[char] and now - last[char] < (inst:GetAttribute("Cooldown") or 0.6) then
					return
				end
				last[char] = now
				local velocity = inst:GetAttribute("LaunchVelocity")
				if launchListener then
					launchListener(char, velocity) -- 속도 적용 전에 알려 허용량이 먼저 준비되게 한다
				end
				hrp.AssemblyLinearVelocity = velocity
			end))
		end
	end
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			last[player.Character] = nil
		end
	end))
	return count
end

return JumpPadController
