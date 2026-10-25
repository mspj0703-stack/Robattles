--!nonstrict
-- 서비스들을 한 번에 조립하고 이벤트를 연결한다. (사망 → 궁극기 종료·상태 해제, 피해/처치 → 궁극기 충전)
local Link = require(script.Parent.Link)
local CooldownService = require(script.Parent.CooldownService)
local DodgeService = require(script.Parent.DodgeService)
local StatusEffectService = require(script.Parent.StatusEffectService)
local DamageService = require(script.Parent.DamageService)
local UltimateService = require(script.Parent.UltimateService)
local HitboxService = require(script.Parent.HitboxService)

local CombatCore = {}

function CombatCore.new(config)
	local cfg = config or Link.shared("Config")
	local core = {
		config = cfg,
		cooldown = CooldownService.new(cfg),
		dodge = DodgeService.new(cfg),
		status = StatusEffectService.new(cfg),
		ultimate = UltimateService.new(cfg),
		hitbox = HitboxService,
	}
	core.damage = DamageService.new({ config = cfg, status = core.status, dodge = core.dodge })

	core.damage:onDamaged(function(e)
		if e.attackerId ~= e.targetId then
			core.ultimate:addDamage(e.attackerId, e.dealt)
		end
	end)
	core.damage:onKilled(function(e)
		core.ultimate:handleDeath(e.targetId)
		core.status:clear(e.targetId)
		if e.attackerId ~= e.targetId then
			core.ultimate:addKill(e.attackerId)
		end
	end)

	function core:addPlayer(id, characterId, maxHealth)
		self.damage:register(id, maxHealth)
		self.dodge:register(id)
		self.ultimate:register(id, characterId)
	end
	-- 캐릭터 변경은 다음 리스폰부터 적용된다(UltimateService가 이월 규칙 처리).
	function core:setCharacter(id, characterId)
		return self.ultimate:setCharacter(id, characterId)
	end
	-- 새 경기: 체력·회피·상태·쿨타임·궁극기 게이지 전부 초기화.
	function core:resetMatch(isReady)
		for id in self.damage._ent do
			self.damage:respawn(id)
			self.dodge:reset(id)
			self.status:clear(id)
			self.cooldown:clearEntity(id)
		end
		self.ultimate:resetMatch(isReady)
	end
	function core:removePlayer(id)
		self.damage:remove(id)
		self.dodge:remove(id)
		self.ultimate:remove(id)
		self.status:clear(id)
		self.cooldown:clearEntity(id)
	end
	function core:respawn(id)
		self.damage:respawn(id)
		self.dodge:reset(id)
		self.status:clear(id)
		self.ultimate:respawn(id)
		self.cooldown:clearEntity(id)
	end
	return core
end

return CombatCore
