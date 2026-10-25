--!nonstrict
-- 피해의 유일한 적용 지점. 클라이언트가 보낸 피해량·명중 대상은 받지 않는다(호출자는 서버 코드).
-- 규칙: 일반 피격 무적 없음 / 같은 attackId 중복 피해 방지(rehitInterval 허용 시 예외) /
--       회피 무적 존중 / 동일 공격자 연쇄 폭발 감쇠 / 서버 안전 상한.
local Link = require(script.Parent.Link)

local DamageService = {}
DamageService.__index = DamageService

local function isId(v)
	return type(v) == "string" or type(v) == "number"
end

function DamageService.new(deps)
	deps = deps or {}
	return setmetatable({
		_cfg = deps.config or Link.shared("Config"),
		_status = deps.status,
		_dodge = deps.dodge,
		_ent = {}, -- [id] = { health, maxHealth, alive }
		_hits = {}, -- [attackId] = { touched, targets = { [targetId] = time } }
		_chain = {}, -- [attackerId][targetId] = { times }
		_onDamaged = {},
		_onKilled = {},
		_onEffect = {},
		_blockers = {},
		_protect = {}, -- [id] = 보호 종료 시각(서버 시계)
	}, DamageService)
end

function DamageService:register(id, maxHealth)
	local m = maxHealth or self._cfg.Combat.MaxHealth
	self._ent[id] = { health = m, maxHealth = m, alive = true }
end

function DamageService:remove(id)
	self._ent[id] = nil
	self._protect[id] = nil
	self._chain[id] = nil
end

function DamageService:respawn(id)
	local e = self._ent[id]
	if e then
		e.health, e.alive = e.maxHealth, true
	end
end

-- 부활 보호(서버 권위): untilT 전까지 모든 피해 요청을 거부한다. 처치·점수·피격 이벤트·상태이상 모두 발생하지 않는다.
function DamageService:setProtection(id, untilT)
	if self._ent[id] then
		self._protect[id] = untilT
	end
end

function DamageService:clearProtection(id)
	self._protect[id] = nil
end

function DamageService:isProtected(id, now)
	local u = self._protect[id]
	return u ~= nil and now < u
end

function DamageService:getProtectedUntil(id)
	return self._protect[id]
end

function DamageService:getHealth(id)
	local e = self._ent[id]
	return e and e.health or 0
end

function DamageService:isAlive(id)
	local e = self._ent[id]
	return e ~= nil and e.alive
end

-- 피해 차단 훅(예: 패링). fn(req, now) -> 차단 사유(string) | nil
function DamageService:addBlocker(fn)
	table.insert(self._blockers, fn)
end

function DamageService:onDamaged(fn)
	table.insert(self._onDamaged, fn)
end

-- 상태이상 효과 결과 훅: fn({ targetId, attackerId, effects, now }). 넉백 적용기 등이 구독한다.
function DamageService:onEffect(fn)
	table.insert(self._onEffect, fn)
end

function DamageService:onKilled(fn)
	table.insert(self._onKilled, fn)
end

-- req = { attackerId, targetId, attackId, amount, kind?, strong?, rehitInterval?, allowSelf?, effects? }
-- 반환: { applied=false, reason } | { applied=true, dealt, amount, killed, health, effects }
function DamageService:applyDamage(req, now)
	local c = self._cfg.Combat
	if type(req) ~= "table" or not isId(req.attackerId) or not isId(req.targetId) or not isId(req.attackId) then
		return { applied = false, reason = "bad_request" }
	end
	local amount = req.amount
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return { applied = false, reason = "bad_amount" }
	end
	local target = self._ent[req.targetId]
	if not target then
		return { applied = false, reason = "unknown_target" }
	end
	if not target.alive then
		return { applied = false, reason = "target_dead" }
	end
	if self:isProtected(req.targetId, now) then
		return { applied = false, reason = "spawn_protected" } -- 기록·이벤트 없음: 체력/점수/패시브에 반영되지 않는다
	end
	if req.attackerId == req.targetId and req.allowSelf ~= true then
		return { applied = false, reason = "self_damage" }
	end
	if self._dodge and self._dodge:isInvulnerable(req.targetId, now) then
		return { applied = false, reason = "invulnerable" } -- 중복 기록 안 함: 다음 틱은 다시 판정
	end

	for _, blocker in self._blockers do
		local why = blocker(req, now)
		if why then
			return { applied = false, reason = why }
		end
	end

	-- 중복 피해 방지
	local rec = self._hits[req.attackId]
	local last = rec and rec.targets[req.targetId]
	if last ~= nil then
		local interval = req.rehitInterval or 0
		if not (interval > 0 and now - last >= interval) then
			return { applied = false, reason = "duplicate_hit" }
		end
	end

	-- 동일 공격자 연쇄 폭발 감쇠
	local kind = req.kind or "Direct"
	if kind == "Explosion" then
		local byTarget = self._chain[req.attackerId]
		if not byTarget then
			byTarget = {}
			self._chain[req.attackerId] = byTarget
		end
		local times = byTarget[req.targetId] or {}
		local live = {}
		for _, t in times do
			if now - t <= c.ChainExplosionWindow then
				table.insert(live, t)
			end
		end
		amount *= math.max(c.ChainExplosionMinMult, c.ChainExplosionFalloff ^ #live)
		table.insert(live, now)
		byTarget[req.targetId] = live
	end

	amount = math.min(amount, c.MaxSingleHitDamage)
	local dealt = math.min(amount, target.health)
	target.health -= dealt
	local killed = target.health <= 0
	if killed then
		target.health, target.alive = 0, false
	end

	if not rec then
		rec = { touched = now, targets = {} }
		self._hits[req.attackId] = rec
	end
	rec.targets[req.targetId] = now
	rec.touched = now

	local event = {
		attackerId = req.attackerId,
		targetId = req.targetId,
		attackId = req.attackId,
		kind = kind,
		amount = amount,
		dealt = dealt,
		killed = killed,
		now = now,
	}
	for _, fn in self._onDamaged do
		fn(event)
	end
	local effectResults
	if self._status and req.effects and not killed then
		effectResults = {}
		for i, effect in req.effects do
			if i > 4 then
				break
			end
			local ok, info = self._status:apply(req.targetId, effect, now, { strong = req.strong == true })
			table.insert(effectResults, { type = effect.type, ok = ok, info = info })
		end
		for _, fn in self._onEffect do
			fn({ targetId = req.targetId, attackerId = req.attackerId, effects = effectResults, now = now })
		end
	end
	if killed then
		for _, fn in self._onKilled do
			fn(event)
		end
	end
	return {
		applied = true,
		dealt = dealt,
		amount = amount,
		killed = killed,
		health = target.health,
		effects = effectResults,
	}
end

-- 환경 사망(낙사 등): 피해 없이 즉시 사망 처리. 처치 이벤트의 attackerId는 본인이다.
function DamageService:forceKill(id, now)
	local e = self._ent[id]
	if not e or not e.alive then
		return false
	end
	e.health, e.alive = 0, false
	local event = { attackerId = id, targetId = id, attackId = "env", kind = "Environment", amount = 0, dealt = 0, killed = true, now = now }
	for _, fn in self._onKilled do
		fn(event)
	end
	return true
end

-- 오래된 중복 기록 정리. 주기적으로(예: 1초마다) 호출한다.
function DamageService:prune(now)
	local keep = self._cfg.Combat.HitRecordRetention
	for attackId, rec in self._hits do
		if now - rec.touched > keep then
			self._hits[attackId] = nil
		end
	end
end

return DamageService
