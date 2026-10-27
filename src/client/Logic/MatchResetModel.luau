--!nonstrict
-- 애니메이션 정리 시점 판단(순수 로직). 서버 스냅샷의 match({ phase, matchId })만 읽는다. MatchFlow 규칙·UI 와 무관.
-- 정리해야 하는 순간: ① 결과 화면(RESULTS)에 들어갈 때 ② 새 경기(matchId 변경)가 시작될 때.
local MatchResetModel = {}

local function phaseOf(m)
	if type(m) ~= "table" then
		return nil
	end
	local p = m.phase
	if type(p) ~= "string" then
		return nil
	end
	return string.upper(p) -- "Results"/"RESULTS" 두 표기 모두 허용
end

-- 스냅샷에서 match 를 꺼낸다(State.luau 와 같은 우선순위: snap.match, 없으면 snap.ui.match). 없으면 nil.
function MatchResetModel.matchOf(snap)
	if type(snap) ~= "table" then
		return nil
	end
	if type(snap.match) == "table" then
		return snap.match
	end
	local ui = snap.ui
	if type(ui) == "table" and type(ui.match) == "table" then
		return ui.match
	end
	return nil
end

-- prev/cur 는 직전·현재 snap.match(없으면 nil). 정리해야 하면 true, 이유 문자열을 함께 돌려준다.
function MatchResetModel.shouldReset(prev, cur)
	if type(cur) ~= "table" then
		return false
	end
	local pPhase, cPhase = phaseOf(prev), phaseOf(cur)
	if cPhase == "RESULTS" and pPhase ~= "RESULTS" then
		return true, "results"
	end
	-- A low-population cancellation has no RESULTS phase. Reset all five animators once
	-- when the server moves directly from ACTIVE to WAITING.
	if cPhase == "WAITING" and cur.reason == "insufficient_players"
		and (pPhase ~= "WAITING" or (type(prev) == "table" and prev.reason ~= "insufficient_players")) then
		return true, "cancelled"
	end
	-- A cancellation can move ACTIVE -> WAITING -> COUNTDOWN between two 10 Hz snapshots.
	-- The client then never observes WAITING, so clear the previous round's animations
	-- before entering the new countdown. Keep the same-matchId condition to distinguish
	-- this from the regular new-match reset below.
	if pPhase == "ACTIVE" and cPhase == "COUNTDOWN"
		and type(prev) == "table" and type(prev.matchId) == "number"
		and type(cur.matchId) == "number" and prev.matchId == cur.matchId then
		return true, "cancelled_snapshot_skipped"
	end
	if type(cur.matchId) == "number" and type(prev) == "table" and type(prev.matchId) == "number" and cur.matchId ~= prev.matchId then
		return true, "newMatch"
	end
	return false
end

return MatchResetModel
