# 서버 ↔ UI 계약

신규 Remote 이름을 만들지 않았다. 기존 `State`, `Scoreboard`, `Feedback`, `SelectCharacter`를 재사용한다. 클라이언트가 phase/점수/참가 여부/순위를 결정할 수 있는 요청은 없다.

## 클라이언트 → 서버

`SelectCharacter:FireServer({characterId = "SWORD"})`

- 최초 정상 선택: 출전 슬롯 확보 및 최초 모델 로드 예약.
- 이후 선택: 기존 pendingCharacterId에 예약. 사망 중에도 허용.
- RESULTS: 선택/예약은 허용하지만 최초 모델 로드는 결과 종료 이후.
- 최대 시도를 소진한 스폰: 같은 선택 재요청으로 명시적 재시도 가능. 진행 중 엔진 호출은 취소/중복하지 않음.
- 현재 RemoteSpec은 SWORD/PAINTBALL만 허용. 다른 3종은 전투 담당자가 정의/스키마를 확장한 뒤 동일 경로로 연결한다.
- 실패는 기존 Feedback `{type="Rejected",remote="SelectCharacter",reason=...}` 경로. match_full, unsupported_character, not_registered 또는 기존 schema/rate_limit 사유.
- MENU 표시/숨김 자체는 로컬 UI 상태. 이를 통해 서버 참가/피해 권한이 바뀌지 않는다.

## State 스냅샷 추가 필드

기존 체력/스킬/탄약/캐릭터 필드를 유지하고 `snap.match`를 추가한다. 시간은 모두 `workspace:GetServerTimeNow()` 기준이다.

```luau
match = {
    version = 1,
    phase = "WAITING", -- WAITING / COUNTDOWN / ACTIVE / RESULTS
    matchId = 0, -- ACTIVE 진입마다 증가
    epoch = 0, -- 상태 전환마다 증가
    serverTime = 0,
    endsAt = nil,             -- ACTIVE 종료 시각
    remainingSeconds = nil,  -- 스냅샷 시점의 경기 잔여 시간
    countdownEndsAt = nil,    -- COUNTDOWN 종료 시각
    countdown = nil,          -- 스냅샷 시점 올림 초
    resultsEndsAt = nil,      -- RESULTS 종료 시각
    lowPopulationEndsAt = nil,-- 20초 인원 유예, 회복 시 nil
    reason = nil,             -- time_limit / insufficient_players 등
    cancelled = false,     -- 인원 부족 취소 직후 WAITING 에서만 true (정상 RESULTS 와 구분)
    participantCount = 0,
    selectedCount = 0,
    maxPlayers = 12,
    standings = {},
    results = nil,            -- RESULTS 동안 고정된 최종 기록 사본
    player = {
        state = "Menu",      -- Menu / Selected / Participating / Dead
        selected = false,
        participating = false,
        characterSelectionAllowed = true,
        respawnAt = nil,
        respawnRemaining = nil,
        respawnPaused = false,-- RESULTS 동안 true
        spawnStatus = "Menu",-- Menu / Pending / Loading / Ready / Failed / Hung
        kills = 0,
        deaths = 0,
        rank = nil,
    },
}
```

- 최소 인원은 WAITING/COUNTDOWN에서 실제 살아 있는 준비 인원 기준. ACTIVE/RESULTS의 participantCount에는 연결된 사망 참가자도 포함한다.
- 남은 시간은 표시용 보간만 가능하다. 클라이언트가 0초를 보고 경기 시작/종료/부활을 확정해서는 안 된다.
- respawnAt은 최초 재로드 가능 시각이다. 실제 로드 지연/실패 때문에 즉시 부활하지 않을 수 있다.
- alive는 실제 선택·스폰·생존 상태와 기존 전투 상태를 함께 반영한다. Menu 사용자에게 가짜 활성 전투 HUD를 표시하지 않는다.
- canAct는 RESULTS/미스폰/미선택 상태에서 false다. 서버가 모든 행동을 별도로 검증한다.
- 개인 최고 순위/점수는 UI가 다시 정렬하지 말고 제공된 rank/kills/deaths를 사용한다.

## Scoreboard 및 최종 결과 행

```luau
{ id = userId, name = displayName, kills = 0, deaths = 0, rank = 1, connected = true }
```

정렬은 KO 내림차순, 데스 오름차순이다. 둘 다 같으면 **같은 rank**를 제공한다. 이름/id 정렬은 동률 행의 안정적 배치만을 위한 것이며 순위를 나누지 않는다. 예: `1, 1, 3`.

재접속으로 데스 기록을 초기화할 수 없도록 현재 라운드의 이탈 기록은 connected=false로 보존한다. 재접속 시 같은 UserId의 기존 라운드 기록을 이어 쓴다. 최종 결과는 종료 순간 확정한 복사본이므로 이후 퇴장/접속/외부 테이블 변경으로 바뀌지 않는다.

**중도 이탈/합류가 반복되면 라운드 전체 기록은 12행을 넘을 수 있다.** 동시 출전은 12명 제한이지만 역사적 참가자가 더 많을 수 있다. 기존 UI의 12행 고정 화면은 connected 필터 또는 스크롤/페이지를 연결해야 한다. 서버는 기록을 임의 삭제하거나 공동 순위를 깨지 않는다.

## Feedback 확장 이벤트

기존 Feedback Remote로 확정 처치 시 아래 메시지를 보낸다.

```luau
{ type="KillConfirmed", matchId=matchId, attackerId=attackerId,
  targetId=targetId, attackId=attackId, kind=damageKind, time=serverTime }
```

이 이벤트는 피해 없는 연습에서 발생하지 않는다. 환경 사망은 attackerId==targetId, kind=="Environment"다. attackId는 공격 인스턴스 식별자이며 현 소스가 정식 스킬 표시 이름을 보내지는 않는다. UI는 attackerId/targetId를 처치자/피해자로 사용하고, kind를 임의로 특정 스킬명으로 번역하지 말 것.

Died/Respawned/Correct 등 기존 이벤트도 그대로 유지한다. UI의 수명/결과 판단은 State.match를 최종 기준으로 삼는다.

## 이전 UI 구현과의 호환 및 해야 할 연결

서버는 이전 UI를 위해 `snap.ui.version=1`, `snap.ui.match.phase="Playing"|"Results"`, endsAt/results/resultsEndsAt/state 등을 추가 제공한다. 기존 ui.characterState 등의 형제 필드는 보존한다. 이 호환 필드의 Playing은 WAITING/COUNTDOWN/ACTIVE를 포괄하므로 **정확한 상태는 반드시 snap.match.phase로 판단**해야 한다.

UI 담당 수정 목록 (이번 작업에서는 UI 파일 변경 0개):

1. 최초 PLAY는 선택된 characterId를 전송하고, selected/spawnStatus를 확인해 메뉴를 닫는 흐름으로 연결.
2. WAITING/COUNTDOWN/ACTIVE/RESULTS 표시와 5초/7분/12초, 20초 유예 안내 연결.
3. 기존 행 인덱스 순위 표시를 서버 r.rank로 교체. 개인 순위도 match.player.rank 사용.
4. Menu/Selected/Dead와 spawnStatus를 분리. 선택 전을 사망으로 표시하지 말 것.
5. KillConfirmed를 킬 피드·처치자 정보에 연결한다. 인원 부족 취소는 즉시 WAITING으로 복귀하며 결과 패널 대신 대기 HUD에 취소 안내를 표시한다.
6. 12행 초과의 이탈 기록 처리, resultsEndsAt 이후 서버 상태를 기다리는 전환, 연결 지연 안내.

이 목록은 데이터 공급 완료와 화면 연결 완료를 구분하기 위한 것이다. 실제 최신 UI 브랜치와 합쳐 실행했다고 주장하지 않는다.
