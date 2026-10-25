# 변경 파일 및 병합 인계

## 기준과 분리 브랜치

- 기준: `RoBattles_Alpha_UI_Integration.zip`.
- 원본 ZIP SHA-256: `dede5ed0093dad4260a1df7cebad0f4987bcde9420cf70ae3704c09a6c2dc2c6`.
- 이 소스의 전투 기반: `RoBattles_Phase2_Sword_Step1a.zip`.
- 원래 작업 공간과 ZIP에는 Git 이력이 없었다. 실제 Claude 저장소·미커밋 변경·원격 최신 커밋은 확인할 수 없었다.
- 파일을 별도 디렉터리에 추출하고 로컬 기준 커밋 `5572f639108496bca5ea3fadea0183cb7f21a272`로 기록했다.
- 기준 브랜치: `snapshot/ui-integration`. 작업 브랜치: `phase2/match-flow`.
- **이 기준 커밋은 로컬 스냅샷을 기록한 것이며 Claude 저장소의 공통 조상 커밋이 아니다.** 원본 ZIP과 이전 UI 작업 디렉터리를 덮어쓰지 않았다.

## 변경된 기존 파일

| 파일 | 변경 | 동시 작업 충돌 |
|---|---|---|
| src/shared/Config.luau | Match에 2인/420초/5초/12초/20초 상수 추가 | 중간. 다른 설정 덮어쓰기 금지 |
| src/server/Main.server.luau | 자동 최초 스폰 제거, 선택→스폰, 경기 세션 연결, 로드 ticket, 맵 준비 대기, 상태/점수 전송, 배치 경계 | **높음**. 최신 전투 bootstrap에 수동 통합 필요 |
| src/server/CharacterController.luau | 지원 캐릭터 조회, 경기 일시 상태 정리/시작 메서드 추가 | **높음**. 기존 공격/스킬 본문은 변경하지 않음 |
| src/server/CombatCore.luau | resetMatch에 선택적 준비 여부 predicate 전달 | 높음. 기존 기본 호출 동작 유지 |
| src/server/DamageService.luau | 피해·환경 사망의 선택적 match policy | 높음. 기존 피해 공식 변경 없음 |
| src/server/UltimateService.luau | 게이지/연습 정책, 죽은 플레이어 pending 보존, 종료 콜백 오류 격리 | 높음. 기존 ACTIVE 소비/이월 규칙 보존 |
| src/server/ProjectileService.luau | cancelOwner 추가. 기존 발사/충돌/피해 함수 수정 없음 | 중간. 최신 설치물/탄환 목록도 같은 경계에 연결 필요 |
| src/server/RemoteGate.luau | 스키마·rate limit 후 메뉴/사망 캐릭터 선택 예외 | 중간 |
| src/server/ServerRouter.luau | 선택적 match session의 단계/참가/행동 검증 | 높음. 신규 Phase 2 Remote도 정책 연결 필요 |
| src/server/RespawnScheduler.luau | inFlight를 유지하는 취소/재개, 로드 상태/시도 소진 및 명시적 재시도 | 높음. 실제 LoadCharacter 동작 P0 검증 필요 |
| src/server/CharacterSpawnGate.luau | 재접속 시 epoch 재사용 방지 | 중간 |
| src/server/ScoreboardService.luau | 공동 rank, 연결 여부, reset/조회 | 중간. UI의 r.rank 연결 필요 |
| tests/SwordPhase2.spec.luau | 반환값만 추가, 기존 테스트 내용 보존 | 낮음 |
| tests/run_all.luau | 신규 2개 spec 등록 | 낮음 |

신규 코드: `MatchFlow.luau`, `MatchSession.luau`, `MatchScope.luau`, 테스트 2개, `tools/run_match_checks.py`, 경기 문서/로그.

## 보존 확인

- src/client **23개 파일 모두 바이트 동일** — 이전 UI, 입력, HUD, 효과 렌더러 그대로.
- src/shared/Data 3개, src/map 13개, src/simulation 2개 파일 동일.
- SwordCombat, MovementValidator, RemoteSpec 동일.
- CharacterController 기존 공격/패링/스킬/회피 메서드 본문 그대로. 경기 경계 메서드만 추가.
- 기존 테스트는 run_all 등록과 SwordPhase2의 return 외에는 동일. Phase 1 manifest 검사도 그대로 유지.

제공된 소스에는 나머지 3종의 완성 스킬이 없으므로 그 구현과의 충돌 여부는 미확인이다. 최신 소스를 받으면 그들의 타이머·시전/설치물 레지스트리를 MatchScope에 연결해야 한다.

## 실제 Claude 브랜치에 반영하는 순서

1. 실제 저장소에서 `git status --short --branch`로 미커밋 변경부터 보존하고 HEAD/원격/공통 조상을 기록한다.
2. 로컬 스냅샷 기준과 실제 전투 checkpoint를 비교한다. UI 포함 전체 소스를 덮어쓰지 않는다.
3. 별도 worktree/브랜치에서 `match-flow.patch`를 검사한다. 높은 충돌 위험 파일은 최신 구현을 기준으로 필요한 메서드/호출만 옮긴다.
4. 모든 피해 경로를 match policy에, 모든 지연 스킬 작업을 scope.guard/track에 연결한다. cleanup 콜백은 yield 없이 끝내며, yield 이후에는 토큰을 다시 검사한다.
5. UI 담당자는 MATCH_FLOW_UI_CONTRACT.md의 신규 필드 표시를 연결한다. 특히 공동 순위는 행 번호가 아니라 r.rank다.
6. 전체 CLI를 다시 실행하고 기존 manifest 실패를 별도 관리한다. 테스트 삭제/완화로 green을 만들지 않는다.
7. Studio P0를 실행한 뒤 실제 release 여부를 판단한다.

Git bundle은 이 로컬 스냅샷/작업 브랜치의 이력을 보존하기 위한 것이다. 원격 공통 조상이 없으므로 무조건 merge하는 대신 patch/수동 병합에 사용한다. 서버 publish/deploy는 수행하지 않았다.
