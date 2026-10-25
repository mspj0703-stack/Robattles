--!nonstrict
-- 서버 Feedback 이벤트 → 화면 연출 지시(순수). 알 수 없는 이벤트는 무시하고, 예외를 던지지 않는다.
local FeedbackModel = {}

-- 반환: { kind, ... } 목록. myId는 내 playerId.
function FeedbackModel.translate(event, myId)
	local out = {}
	if type(event) ~= "table" or type(event.type) ~= "string" then
		return out
	end
	local t = event.type
	if t == "Swing" then
		local mine = event.playerId == myId
		table.insert(out, { kind = "SwingEffect", playerId = event.playerId, mine = mine })
		if mine and type(event.hits) == "table" and #event.hits > 0 then
			table.insert(out, { kind = "HitMarker", count = #event.hits })
		end
	elseif t == "SwordSkill" then
		local mine = event.playerId == myId
		if mine and type(event.hits) == "table" and #event.hits > 0 then
			table.insert(out, { kind = "HitMarker", count = #event.hits })
		end
		if mine and event.phase == "Cancel" then
			table.insert(out, { kind = "Toast", text = "Lunge 취소됨" })
		end
	elseif t == "CharSkill" then
		if event.playerId == myId and event.cue == "paint.reload.proc" then
			table.insert(out, { kind = "Toast", text = string.format("Color Reload +%d", event.restored or 0) })
		end
	elseif t == "Duelist" then
		if event.playerId == myId then
			table.insert(out, { kind = "Toast", text = string.format("Duelist +%d", event.bonus or 0) })
		end
	elseif t == "Parry" then
		table.insert(out, { kind = "ParryStart", playerId = event.playerId, mine = event.playerId == myId })
	elseif t == "ParrySuccess" then
		table.insert(out, { kind = "ParrySuccess", playerId = event.playerId, mine = event.playerId == myId, countered = event.countered == true })
		if event.attackerId == myId then
			table.insert(out, { kind = "WasParried" })
		end
	elseif t == "Damaged" then
		if event.targetId == myId then
			table.insert(out, { kind = "DamageTaken", amount = event.amount })
		end
		if event.attackerId == myId then
			table.insert(out, { kind = "HitMarker", count = 1, amount = event.amount })
		end
	elseif t == "Died" then
		table.insert(out, { kind = "Died", playerId = event.playerId, mine = event.playerId == myId })
	elseif t == "Respawned" then
		table.insert(out, { kind = "Respawned", playerId = event.playerId, mine = event.playerId == myId })
	elseif t == "Dodge" then
		table.insert(out, { kind = "DodgeEffect", playerId = event.playerId, mine = event.playerId == myId })
	elseif t == "Reloaded" then
		if event.playerId == myId then
			table.insert(out, { kind = "ReloadDone" })
		end
	elseif t == "Rejected" then
		-- 서버가 거부한 입력. 미구현 기능은 짧은 안내만 띄운다.
		local msg
		if event.reason == "ultimate_not_implemented" then
			msg = "궁극기는 아직 구현되지 않았습니다"
		elseif event.reason == "skill_not_implemented" then
			msg = "이 캐릭터의 스킬은 아직 구현되지 않았습니다"
		elseif event.reason == "no_ammo" then
			msg = "탄약이 부족합니다"
		elseif event.reason == "busy" then
			msg = "다른 동작 중에는 사용할 수 없습니다"
		end
		if msg then
			table.insert(out, { kind = "Toast", text = msg })
		end
	elseif t == "Spawned" or t == "Blocked" or t == "Exploded" or t == "Finished" or t == "Hit" then
		table.insert(out, { kind = "ProjectileEvent", event = event })
	end
	return out
end

return FeedbackModel
