--!nonstrict
-- 선택적 자동 실행 스크립트(Play 시작 시 맵 생성). 필요 없으면 삭제/Disabled.
-- 중복 방지: 같은 서버에서 이 스크립트가 두 번 로드되어도(복제·재동기화) 한 번만 실행한다.
-- 동작은 BrickyardConfig.AutoRun 으로 제어한다(통합 시 SpawnLocations=false 권장).
local Config = require(script.Parent.BrickyardConfig)
local Generator = require(script.Parent.BrickyardGenerator)

if not Config.AutoRun.Enabled then
	return
end
if workspace:GetAttribute("BrickyardAutoRunClaimed") then
	return
end
workspace:SetAttribute("BrickyardAutoRunClaimed", true)

-- 전투 시스템(ServerScriptService.RoBattles)이 함께 있으면 SpawnLocation 을 만들지 않는다:
-- 스폰은 전투 쪽 SpawnDirector 가 Spawns 폴더로 고르므로 Roblox 기본 SpawnLocation 과 충돌하지 않게 한다.
local combatPresent = game:GetService("ServerScriptService"):FindFirstChild("RoBattles") ~= nil
Generator.generate({
	dummies = Config.AutoRun.Dummies,
	spawnLocations = Config.AutoRun.SpawnLocations and not combatPresent,
})
