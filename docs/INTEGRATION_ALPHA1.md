# Alpha 1.0 — UI & Match Flow 통합 기록

브랜치 `phase2/integration`, **실제 기준 커밋 `30dcad2`**(`phase2/combat` HEAD, 5캐릭터 전투). 애니메이션(`phase2/animation`)은 건드리지 않았다.
GPT ZIP(`RoBattles_Alpha_MatchFlow_Implementation`)은 `snapshot/ui-integration`(5572f63) → `phase2/match-flow`(2049bbd) 로컬 스냅샷 계보이며 전투 계보와 **공통 조상이 없다.** 그래서 브랜치 병합을 하지 않고 파일별로 비교·이식했다.
`docs/` 와 ZIP 원본은 별도 디렉터리에 보존했다(`docs/ui-gpt/`, `docs/match-flow-logs/`).

## 1. Phase 0 — 계보·충돌 분석

| 영역 | 방식 | 결과 |
|---|---|---|
| 서버 `MatchFlow/MatchScope/MatchSession` | 신규 파일 복사 | 충돌 없음 |
| `Config`, `CharacterController`, `CombatCore`, `DamageService`, `UltimateService`, `ProjectileService`, `RemoteGate`, `ServerRouter`, `RespawnScheduler`, `CharacterSpawnGate`, `ScoreboardService` | `git merge-file` 3-way (base = GPT 스냅샷 원본, ours = 전투 HEAD, theirs = 경기 흐름) | 모두 깨끗이 병합 |
| `Main.server.luau` | 3-way, 충돌 1곳 수작업 | 아래 §2 |
| 클라이언트 `Main.client/HudView/ScoreboardView/SettingsView/EffectPlayer` | UI 쪽에 base 가 없어 **전투 최신 쪽을 기준**으로 수작업 이식 | §3 |
| 가져오지 않은 것 | `SwordCombat.luau`, Step1a 서버/클라이언트, `PHASE2_SWORD_STEP1A.md`, GPT 의 `tests/run_all.luau` 전체 교체 | 구(舊) 전투 계보 |
| `tests/SwordPhase2.spec.luau` | 가져오지 않음 | 전투 쪽은 `Sword.spec` 사용(반환값 문제도 없음) |

## 2. 충돌 해결 로그

1. **`Main.server.luau` 스폰 블록** — 전투: `scheduler:onSpawned` + `controller:respawn` + `hum.MaxHealth = Config.Combat.MaxHealth` 대신 캐릭터별 HP. 경기 흐름: `matchSession:spawned(id, ticket, now)`.
   해결: 이동 보정(`movement:teleported`)·ForceField 가드(전투) → `matchSession:spawned`(내부에서 scheduler/respawn/flow 처리) → `hum.MaxHealth/Health = controller:getMaxHealth(id)`(전투, 5캐릭터 HP 110/95/100/105/100) → `CharacterId` 속성 기록(전투).
2. **`tests/run_all.luau`** — 전투 쪽 `Integration5.spec` 유지 + `MatchFlow.spec`, `MatchSession.spec`, 신규 `MatchBoundary5.spec` 등록.
3. **`tools/check_remotes.py`** — GPT 수정 채택(전투 쪽은 stale 경로 `InputModel.luau`를 보고 있어 동적 Remote 검사가 비어 있었고, `PlayerGui` WaitForChild 오탐 가능).
4. **`MatchSession.spec` 픽스처** — GPT 가 구(舊) 전투를 가정한 값을 최신 확정 데이터로 정정했다. **기대를 약화하거나 삭제한 것이 아니라 가정 데이터를 갱신:**
   SLINGSHOT 은 이제 지원 캐릭터(거부 테스트는 존재하지 않는 id 로), SWORD HP 100→`Characters.SWORD.maxHealth`(110), PAINTBALL 탄창 30→16·HP 95, 궁극기 게이지 40→킬 40 + 실제 가한 피해(110)×`GainPerDamage`, placeholder 스킬 `skill_not_implemented` 단언은 더 이상 placeholder 가 없어 "여전히 그 값이 아님"으로 교체.
5. **`tests_ui/state.spec` 1건** — 구 placeholder 문구("최근 콤보 —")를 단언하던 것을, 서버 스냅샷 기반 HudModel 문구로 바뀐 설계에 맞게 교체(`Swing` 이벤트가 서버 근거로만 combo 를 만든다는 단언은 유지).
6. 테스트를 삭제하거나 PASS 수를 맞추려고 약화한 것은 없다. (857→858: 추가만 있음)

## 3. Phase 1 — UI 연결

- 화면 구조(`src/client/UI/*`)는 GPT 것을 사용하고 **입력·충전·Aim·AimMode·자동 연사·대시/회피 배선은 전투 `Main.client` 를 유지**했다(5인자 `InputState.setCharacter`, `aimView`, `Aim` 리모트 포함).
- 메뉴/차단: 메뉴·설정·사망·결과 중에는 `app:isBlocking()` → 입력 차단, 눌린 버튼은 `releaseAll()` 후 Release 를 서버로 보냄(서버는 RESULTS/미스폰에서 안전하게 거부, 경계에서 충전 상태는 이미 정리됨).
- **상태 구분** (`State:status`): `Connecting / Stale / Results / Menu(캐릭터 미선택) / Spawning(선택했으나 아직 스폰 전) / Dead / Alive`. Menu 와 Dead 를 서로 다른 화면으로 처리한다(Menu 에서는 KNOCKED OUT 패널이 뜨지 않음). 서버 `snap.match.player.state` 가 우선, 구 `snap.ui.match` 는 폴백.
- **경기 단계**: HUD 상단이 `WAITING`(준비/최소 인원), `COUNTDOWN`(남은 초), `ACTIVE`(TIME·RANK·KO·PLAYERS, 인원 부족 유예 표시), `RESULTS`(결과 패널, `resultsEndsAt` 기반 다음 경기 안내, 인원 부족 종료 표시)를 서버 값으로 그린다.
- **순위**: 서버 행의 `rank` 를 그대로 표시(동점은 같은 순위). 클라이언트가 재계산하지 않는다. 퇴장 행은 `(퇴장)` 표시.
- **12행 초과**: 스코어보드/결과표는 12행 풀 + 스크롤. 서버가 더 많은 행을 보내면 풀이 늘어난다.
- **KillConfirmed**: 킬 피드 `A ▶ B`, 내가 처치하면 `KO!` 토스트, 사망 패널에 처치자 이름. 환경 사망(`Died` 만 있음)은 처치자 없음으로 표시하며 마지막 피격자를 추측하지 않는다. `Died`/`KillConfirmed` 중복은 합친다.
- **리스폰**: 서버 `respawnAt` 기준 카운트다운, 로드 지연/실패(`spawnStatus`) 문구.
- **5캐릭터 선택**: `Catalog` 를 `Data/Characters` 확정 데이터에서 생성(HP·쿨타임·피해·패시브 수치, "미정/대기" 문구 제거). 첫 선택은 "이 캐릭터로 시작", 이후는 "다음 리스폰에 선택", 정원 초과(`characterSelectionAllowed=false`)는 비활성.
- **HUD**: 스킬 슬롯 이름·상태(콤보 단계/충전%/설치 수/돌진 등)는 전투 `HudModel` 의 서버 스냅샷 라벨을 사용. SLINGSHOT RMB 는 `Aim Mode` 표시 전용으로 표기.
- 효과음 볼륨 그룹(`RoBattlesSFX`) 1줄을 `EffectPlayer` 에 이식.

## 4. Phase 2 — 경기 경계 정리 × 5캐릭터

`MatchSession:_transition` 순서: `scope:invalidate` → 각 플레이어 `scheduler:cancel` + `controller:clearMatchTransient` → `projectiles:clearAll` → **`controller:clearMatchObjects`(신규)** → ACTIVE 면 `controller:beginMatch`.

| 캐릭터 | 경계에서 정리되는 것 |
|---|---|
| SWORD | 콤보·Lunge 충전·Triple Slash/Blade Wave 지연 단계·Blade Storm(`forceEnd`) — `clearMatchTransient` → `reset`/`forceEnd` |
| PAINTBALL | 탄약/재장전/Color Break·Paint Slide 지연 상태 — `reset`, 투사체는 `clearAll` |
| SUPERBALL | 모든 볼(`BallService:clearAll`, 신규 `SuperballSkills:clearAll`), 충전, Cyclone |
| TIMEBOMB | **던져 비행 중인 폭탄 + 설치 폭탄**을 폭발 없이 제거, 충전(`_charges`), 누르기(`_hold`), Blast Jump 예약(`_jumpAt`) — 신규 `TimebombSkills:clearAll` |
| SLINGSHOT | **비행 중 Bullseye 탄**, 충전, 표식·카운트·태그, 이동 감속, 생애 번호 증가(`SlingshotSkills:clearAll`) |

기존 `clearMatchTransient` 만으로는 TIMEBOMB 의 날아가는 폭탄과 SLINGSHOT 의 비행 탄이 라운드를 넘어갈 수 있었다. 이번 통합에서 닫았다. 전투 피해·쿨타임·판정 수치는 변경하지 않았다.

검증(CLI): `MatchBoundary5.spec`(5캐릭터 전 스킬 입력 후 경계 → 폭탄/볼/탄/투사체 0, 이후 시간이 흘러도 효과 이벤트 0, 늦은 Release 무효, 반복 호출 안전) + `MatchSession.spec` 의 "5캐릭터 RESULTS 모든 리모트 거부" 및 기존 중도 입장·사망·선택·라운드 이월 테스트.

## 5. 남은 결함 / 위험 (정직한 목록)

- **Roblox Studio 실행 검증 없음.** 모든 UI·서버 흐름 결과는 CLI 순수 로직 + 제한된 GUI mock 이다. mock 은 Studio 가 아니다.
- `Died` 이벤트 자체에 처치자가 없다. 처치자는 `KillConfirmed` 가 먼저/나중에 도착해야 표시된다(두 순서 모두 테스트). 네트워크 순서 역전·누락 시 "환경 / 정보 없음"으로 표시된다.
- `SwordSkills` 는 레거시 `_sword` 경로라 `clearAll` 이 없다(경계 정리는 `reset`/`forceEnd` 의존, 테스트 통과). 추후 모듈 인터페이스 통일 시 정리 대상.
- PAINTBALL/TIMEBOMB 주무기는 `phase` 를 무시하는 일반 공격이라 경계 직후 도착한 Primary 는 정상 공격으로 처리된다(RESULTS 에서는 `canAct` 가 거부; WAITING→ACTIVE 직후는 살아 있는 참가자의 정당한 공격).
- 스코어보드 `Scoreboard` 리모트는 비참가 행을 포함할 수 있다(`connected=false` 표시). 정렬은 서버 책임이다.
- UI 에셋(로고·초상화·스킬 아이콘)은 비어 있다(`Tokens.Assets`). 임시 블록 3D 프리뷰.
- 12행 초과 UI 는 mock 으로만 확인했고 실제 스크롤 감각은 미검증.

## 6. Studio 필수 테스트 (모두 **미검증**)

기존 목록 그대로 유지: `docs/MATCH_FLOW_STUDIO_P0.md`(P0-1~), `docs/ui-gpt/UI_STUDIO_CHECKLIST.md`, `docs/STUDIO_TEST_PLAN.md` S1~S124. 이번 통합에서 추가: **S125~S136** (`docs/STUDIO_TEST_PLAN.md`).
최소 2클라이언트로 시작해 12클라이언트까지 확장한다.

## 7. 후속 수정 (GPT 검수 반영)
- 시뮬레이션 기준선 분리: `docs/SIM_BASELINES.md`.
- 결과 화면은 메뉴/설정/캐릭터 화면이 열려 있어도 RESULTS 진입 시 표시되고, 종료 후 원래 화면으로 복귀한다.
- `KillConfirmed.matchId`: 이전 경기 → 폐기, 같은 경기/`matchId` 없음 → 즉시 적용, **미래 경기 → 해당 경기 스냅샷 도착까지 보류(최대 8건, 5초)**. 경기 전환 시 킬 피드·처치자 초기화. KO! 토스트는 `State` 가 확정한 이벤트로만 표시.

