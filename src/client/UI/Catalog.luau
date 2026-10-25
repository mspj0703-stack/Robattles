--!nonstrict
-- Descriptive UI copy built from the confirmed shared character data (Data/Characters). No separate balance numbers live here.
local Link = require(script.Parent.Parent.Link)
local Characters = Link.shared("Data/Characters")
local Catalog = {}
Catalog.Order = {"SWORD","PAINTBALL","SUPERBALL","TIMEBOMB","SLINGSHOT"}

local TAGS = {
	SWORD = "근접 · 3타 콤보 · 패링", PAINTBALL = "원거리 · 탄약 관리", SUPERBALL = "튕기는 공 · 충전 투척",
	TIMEBOMB = "폭탄 설치 · 원격 기폭", SLINGSHOT = "충전 사격 · 정밀 조준",
}

local function skillLine(s)
	if not s then return "—" end
	local out = s.name or s.id or "—"
	if s.cooldown then out ..= " · 쿨타임 " .. tostring(s.cooldown) .. "s" end
	if s.damage then out ..= " · 피해 " .. tostring(s.damage) end
	return out
end

local function primaryLine(def)
	local p = def.primary
	if not p then return "—" end
	if p.combo then return "기본 공격 · " .. #p.combo.damages .. "타 콤보 " .. table.concat(p.combo.damages, "/") end
	if p.minDamage and p.maxDamage then return "충전 사격 · 피해 " .. p.minDamage .. "~" .. p.maxDamage .. " (충전 " .. tostring(p.chargeSeconds) .. "s)" end
	if def.ammo then return "연사 · 탄창 " .. tostring(def.ammo.magazine) end
	return "기본 공격" .. (p.damage and (" · 피해 " .. tostring(p.damage)) or "")
end

local function secondaryLine(def)
	local s = def.secondary
	if not s then return "보조 공격 없음" end
	if s.clientOnly then return (s.name or "Aim Mode") .. " · 탄도 표시(서버 쿨타임 없음)" end
	if s.kind == "Parry" then return "패링 · 쿨타임 " .. tostring(s.cooldown) .. "s · 반격 " .. tostring(s.counterDamage) end
	return skillLine(s)
end

local function passiveLine(def)
	local p = def.passive
	if not p then return "없음" end
	if p.id == "Duelist" then return "Duelist — 연속 " .. p.consecutiveHits .. "회 적중 시 추가 피해 +" .. p.bonusDamage .. " (재발동 " .. p.lockSeconds .. "s)"
	elseif p.id == "ColorReload" then return "Color Reload — 탄약 " .. p.ammoRestore .. " 회복 (재발동 " .. p.lockSeconds .. "s)"
	elseif p.id == "TrickMaster" then return "Trick Master — 쿨타임 " .. p.reduceSeconds .. "s 감소 (재발동 " .. p.lockSeconds .. "s)"
	elseif p.id == "ChainReaction" then return "Chain Reaction — 폭발 연쇄 반경 " .. p.radius .. " · 최대 " .. p.maxStages .. "단계"
	elseif p.id == "BullseyeMark" then return "Bullseye Mark — " .. p.hitsToMark .. "회 적중 시 " .. p.markSeconds .. "초 표식, 표식 대상 추가 피해 +" .. p.bonusDamage end
	return p.id
end

Catalog.Items = {}
for _, id in Catalog.Order do
	local def = Characters[id]
	if def then
		Catalog.Items[id] = {
			tag = TAGS[id] or "", passive = passiveLine(def),
			skills = {
				primaryLine(def), secondaryLine(def),
				skillLine(def.skills and def.skills[1]), skillLine(def.skills and def.skills[2]), skillLine(def.skills and def.skills[3]),
				skillLine(def.ultimate),
			},
		}
	end
end
return Catalog
