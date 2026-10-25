--!nonstrict
-- BRICKYARD 생성기 진입점(Roblox 전용, Studio 미검증).
-- 사용:
--   local G = require(game.ServerScriptService.BrickyardMap.BrickyardGenerator)
--   G.generate()                              -- 검증 후 생성
--   G.generate({ dummies = true })            -- 테스트 더미 포함
--   G.generate({ config = { MapSize = 200 } }) -- 설정 일부 덮어쓰기
--   G.validate()  /  G.clear()
-- 이벤트(중복 연결 방지: BindableEvent 는 한 번만 만들고 재사용):
--   G.Generated.Event:Connect(function(root) ... end)   -- 맵 생성 직후(root = Workspace.BRICKYARD)
--   G.Cleared.Event:Connect(function() ... end)         -- 맵 제거 직후
-- 기존 전투 코어(RoBattles)에 의존하지 않는다.
local Config = require(script.Parent.BrickyardConfig)
local MapLayout = require(script.Parent.MapLayout)
local MapValidator = require(script.Parent.MapValidator)
local MapBuilder = require(script.Parent.MapBuilder)
local SpawnAnalysis = require(script.Parent.SpawnAnalysis)
local RobloxEnv = require(script.Parent.RobloxEnv)
local JumpPadController = require(script.Parent.JumpPadController)
local DummyFactory = require(script.Parent.DummyFactory)

local Generator = {}

local function event(name)
	local e = script:FindFirstChild(name)
	if not e then
		e = Instance.new("BindableEvent")
		e.Name = name
		e.Parent = script
	end
	return e
end
Generator.Generated = event("Generated")
Generator.Cleared = event("Cleared")

local busy = false

function Generator.validate(overrides)
	local cfg = Config.with(overrides)
	local layout = MapLayout.generate(cfg)
	local report = MapValidator.validate(layout, cfg)
	print("[BRICKYARD] 검증 결과\n" .. MapValidator.format(report))
	return report, layout, cfg
end

-- options: { config, dummies, spawnLocations, force, jumpPads(기본 true) }
function Generator.generate(options)
	options = options or {}
	if busy then
		warn("[BRICKYARD] 이미 생성 중입니다. 요청을 무시합니다.")
		return nil
	end
	busy = true
	local ok, result, report = pcall(function()
		local rep, layout, cfg = Generator.validate(options.config)
		if not rep.ok and not options.force then
			warn("[BRICKYARD] 검증 실패로 생성을 중단했습니다. force=true 로 강제 생성할 수 있습니다.\n" .. table.concat(rep.failures, "\n"))
			return nil, rep
		end
		SpawnAnalysis.annotate(layout)
		local res = MapBuilder.build(layout, cfg, RobloxEnv, { spawnLocations = options.spawnLocations })
		res.root:SetAttribute("BrickyardVersion", 2)
		local pads = options.jumpPads ~= false and JumpPadController.attach(res.root) or 0
		local dummies = options.dummies and #DummyFactory.spawn(layout, res.root) or 0
		print(string.format("[BRICKYARD] 생성 완료: 부품 %d, 점프대 %d, 더미 %d, 스폰 후보 %d", res.partCount, pads, dummies, #layout.spawns))
		Generator.Generated:Fire(res.root)
		return res, rep
	end)
	busy = false
	if not ok then
		warn("[BRICKYARD] 생성 중 오류: " .. tostring(result))
		return nil
	end
	return result, report
end

function Generator.clear()
	JumpPadController.detach()
	RobloxEnv.clearExisting(Config.RootName)
	Generator.Cleared:Fire()
	print("[BRICKYARD] 제거 완료")
end

return Generator
