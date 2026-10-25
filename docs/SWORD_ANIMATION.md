# SWORD R6 전투 애니메이션 (phase2/animation)

기준: `phase2/integration` @ `e5ae619`. 브랜치: `phase2/animation`. **시각 전용** — 피해·쿨타임·판정·Remote·서버 로직·UI·경기 진행은 변경하지 않았다.

> ⚠️ **검증 상태**: 이 작업을 한 환경에는 Luau 실행기와 Roblox Studio 가 없었다. 신규 테스트(`tests/SwordAnim.spec.luau`)는 **작성만 했고 실행하지 못했다**. 기존 전투/맵/UI/MatchFlow 회귀도 실행하지 못했다. Python 기반 `check_projects` / `check_remotes` 만 실행해 통과를 확인했다. 아래 "미검증" 항목을 참고.

## 구조

| 파일 | 종류 | 역할 |
|---|---|---|
| `src/shared/Data/SwordMotions.luau` | 신규 | 모션별 타이밍·우선순위·포즈 키프레임(순수 데이터) |
| `src/shared/Data/MotionRegistry.luau` | 신규 | 모션 레지스트리 + `validate()` 누락/오류 검사. 정식 에셋 교체 지점 |
| `src/client/Logic/MotionMath.luau` | 신규 | 포즈 보간·레이어·키프레임 샘플링(순수) |
| `src/client/Logic/LocomotionPose.luau` | 신규 | Idle / Run 절차 포즈(순수) |
| `src/client/Logic/SwordAnimState.luau` | 신규 | 상태기계: 이벤트→모션, 우선순위, 중단·복구, 사망/리스폰 정리(순수) |
| `src/client/SwordAnimator.luau` | 신규 | Roblox 적용 계층: R6 Motor6D.Transform 적용, 에셋 트랙 재생, 캐릭터 감시 |
| `tests/SwordAnim.spec.luau` | 신규 | 위 순수 로직 + 실제 서버 이벤트 연동 테스트 |
| `docs/SWORD_ANIMATION.md` | 신규 | 이 문서 |
| `src/client/Main.client.luau` | **수정(+4/−1줄)** | `SwordAnimator` require/생성, Feedback 수신 첫 줄에 `pcall(onFeedback)`, 종료 시 destroy |
| `tests/run_all.luau` | **수정(+1줄)** | `SwordAnim.spec` 등록 |

동작 원리: 서버가 `FireAllClients` 로 보내는 기존 `Feedback` 이벤트(`Swing`, `SwordSkill`, `Parry`, `ParrySuccess`, `Died`, `Respawned`)를 각 클라이언트가 받아 **자기 화면의 모든 SWORD 캐릭터**에 재생한다. SWORD 판별은 서버가 이미 기록하는 캐릭터 속성 `CharacterId == "SWORD"`, 그리고 `Humanoid.RigType == R6` 일 때만 활성화된다. 다른 4캐릭터·R15 는 기존 동작 그대로다.

## 이벤트 → 모션

| Feedback 이벤트 | 모션 |
|---|---|
| (이벤트 없음, 이동 속도) | Idle / Run 기본 레이어 (항상 아래층) |
| `Swing{step}` | Slash1 / Slash2 / Slash3 |
| `SwordSkill TripleSlash{step}` | TripleSlash1~3 |
| `SwordSkill Lunge Charge{chargeSeconds}` | LungeCharge (길이 = chargeSeconds, 시간 진행에 따라 자세 심화) |
| `SwordSkill Lunge Dash{dash.duration}` | LungeRelease (길이 = 서버 돌진 시간, End 까지 마지막 자세 유지) |
| `SwordSkill Lunge End` / `Cancel` | LungeRecover (Cancel 은 0.2s 로 빠르게) |
| `SwordSkill BladeWave` | BladeWave |
| `SwordSkill BladeStorm Start/Tick/Finisher/End` | StormStart → StormLoop(회전, Tick 마다 팔 펄스) → StormFinisher → StormRecover |
| `Parry` / `ParrySuccess` | ParryGuard / ParryCounter |
| `Died` / `Respawned` | 모든 모션 정리 + 사망 중 무시 / 초기화 |

## 모션별 타이밍 (초, 서버 이벤트 수신 시각 = 0)

`impact` = 타격 포즈 키프레임. 서버는 입력 즉시 판정하므로 **타격 포즈는 이벤트 후 0.05~0.1초 안에** 온다. `commit` 동안은 더 낮은 우선순위가 끊을 수 없다.

| 모션 | 우선순위 | commit | 길이 | impact | fadeOut | 비고 |
|---|---|---|---|---|---|---|
| Slash1 / Slash2 | 2 | 0.12 | 0.50 | 0.06 | 0.16 | 서버 쿨타임 0.55 안에 회복 |
| Slash3 | 2 | 0.20 | 0.78 | 0.07 | 0.22 | 서버 3타 후딜 0.8 안에 회복 |
| TripleSlash1 / 2 | 3 | 0.12 | 0.34 | 0.05 | 0.10 | 서버 stepInterval 0.3 |
| TripleSlash3 | 3 | 0.20 | 0.60 | 0.07 | 0.20 | 가장 큰 마무리 |
| LungeCharge | 4 | 0 | chargeSeconds(1.0) | – | – | hold, 최대 chargeSeconds+1.2 |
| LungeRelease | 4 | 0.28 | dash.duration(0.28) | 0.10 | – | hold, 최대 0.6 |
| LungeRecover | 1 | 0 | 0.28 | – | 0.20 | 어떤 모션이든 끊을 수 있음 |
| BladeWave | 3 | 0.30 | 0.58 | 0.07 | 0.20 | |
| StormStart | 5 | 0.30 | 0.30 | – | – | 끝나면 StormLoop 자동 전환 |
| StormLoop | 5 | 0 | hold | – | – | 480°/s 회전, 최대 3.4s |
| StormFinisher | 5 | 0.30 | 0.50 | 0.07 | – | hold, 최대 1.2 |
| StormRecover | 1 | 0 | 0.32 | – | 0.22 | |
| ParryGuard | 4 | 0.40 | 0.52 | 0.07 | 0.14 | 가드 유지 구간 ≥ 패링 창 0.4 |
| ParryCounter | 4 | 0.20 | 0.38 | 0.05 | 0.14 | |

## 우선순위 · 중단 · 복구 규칙

- 새 모션 priority ≥ 현재 → 항상 재생. 낮으면 현재 모션의 `commit` 이 지난 뒤에만 끊는다.
- Blade Storm 중에는 priority 5 미만 모션을 전부 거부한다(서버도 시전 중 다른 행동은 busy).
- **모든 모션에 만료가 있다**(`duration`, hold 모션은 `maxDuration`). 종료 이벤트(`End`/`Cancel`)가 유실돼도 자세가 고착되지 않고, Storm 잠금도 3.8초 뒤 해제된다.
- 상체 오버레이: 공격 모션은 보통 Root/팔만 정의해 하체는 Run 이 유지된다(달리며 베기).
- Idle/Run 은 항상 아래층에서 계산되고, 행동 모션이 위에 가중치로 덮는다 → 공격 중 Idle/Run 이 모션을 덮지 않는다.
- 전환은 직전 출력 포즈에서 새 포즈로 `blendIn`(기본 0.04s) 동안 최단 경로로 섞는다.
- 사망(`Died` 또는 `Humanoid.Died`): 모션·Storm 잠금 정리, 출력 nil(Transform 미적용 → 기본 사망 애니메이션 그대로), 이후 이벤트 무시. `Respawned`/캐릭터 파괴/`CharacterId` 변경: 완전 초기화 + Transform 원복.

## 이동 스킬: 위치 보정 vs 시각 움직임

서버 이동(Triple Slash 전진 4 / Lunge 돌진 16)과 클라이언트의 `dashState` 속도 적용은 **전혀 건드리지 않았다**. 애니메이션은 몸통 기울기·팔다리 각도(그리고 `py` 로 몸통만 낮춤)만 바꾸며 HumanoidRootPart 위치·속도는 읽기만 한다(Run 속도 계산).

## 정식 애니메이션 에셋으로 교체

코드 수정 없이 두 가지 중 하나:
1. `MotionRegistry.Entries.<모션 id>.assetId = "rbxassetid://..."`
2. `ReplicatedStorage.RoBattles.Assets.Animations.<모션 id>` 에 `Animation` 인스턴스 배치(우선). 폴더는 직접 만들면 된다(Rojo 프로젝트 파일은 건드리지 않았다).

에셋이 지정된 모션은 절차 포즈 출력이 꺼지고 `Animator` 트랙(`Action4`)이 재생된다. 타이밍·우선순위·중단·사망 정리·트랙 stop 은 계속 상태기계가 관리한다(교체되는 모션의 트랙도 stop). 에셋 재생 속도는 `기본 길이 / 실제 길이`.

## 시각 설계 노트 (읽어 둘 것)

- **큰 준비 동작의 한계**: 서버가 요청 즉시 판정·`Swing` 이벤트를 보내므로, 이벤트 이후에 준비 동작을 길게 넣으면 판정과 화면이 어긋난다. 그래서 타격 포즈를 0.05~0.1s 안에 두고, "큰 준비"는 Idle 자세(검을 든 자세)와 이전 타격의 회복 구간, 그리고 서버가 사전 이벤트를 주는 스킬(Lunge 충전, Storm 시작, Parry)에 담았다. 기본 콤보/Triple Slash/Blade Wave 의 **사전 예고는 약하다**. 더 길게 예고하려면 클라이언트가 입력 시점에 선재생하는 예측(서버 계약 변경 없이 가능, 단 취소 처리 필요)이 필요하다 — 별도 결정 사항.
- Storm 회전 480°/s 는 "불필요한 과도한 회전 금지" 기준과 충돌할 수 있다. `SwordMotions.StormLoop.spin.degPerSec` 한 줄로 조정한다. 화면 흔들림은 넣지 않았다(Lunge 충전 미세 떨림은 몸통 롤 ±1.6° 뿐).
- 포즈 값은 문서 규칙(몸통 기준 오른손 법칙)대로 계산한 **추정치**이며 실제 모양은 Studio 에서 다듬어야 한다. 값은 모두 `SwordMotions.luau` 데이터에 있다.

## 통합 충돌 위험

- `src/client/Main.client.luau` — UI 브랜치(GPT UI)도 이 파일을 수정할 가능성이 높다. 본 브랜치 변경은 4개의 독립된 줄이라 수동 병합이 쉽다(require 1, 생성 1, destroy 1, Feedback 첫 줄 1).
- `tests/run_all.luau` — 다른 브랜치가 spec 을 추가하면 같은 구간에서 줄 충돌 가능(1줄 추가).
- 그 외는 전부 신규 파일이라 충돌 없음. `src/server/*`, `RemoteSpec`, `Characters`, UI/MatchFlow 파일, `*.project.json` 은 수정하지 않았다.
- 같은 `Feedback` 이벤트를 `EffectPlayer` 도 소비한다(독립 렌더링, 상호 의존 없음).

## 미검증 (Studio / 실행 필요)

CLI: `SwordAnim.spec` 실행 · 기존 전체 전투/맵/UI/MatchFlow CLI 회귀 · `tools/analyze.py` 정적 분석. 둘 다 **이 환경에서 실행하지 못했다**.

Studio 체크리스트:
- [ ] SWORD 선택 후 R6 캐릭터에서 Idle(검 든 자세) / Run 이 보이는가, 다른 4캐릭터는 기존 애니메이션 그대로인가
- [ ] **Animate/Animator 출력 위에 Motor6D.Transform 이 덮이는가**(RenderPriority.Last 적용 시점이 맞는지). 안 맞으면 포즈가 깜빡이거나 기본 걷기와 섞임
- [ ] 각 관절 축/부호가 의도대로인가(팔이 앞으로 들리는지, 좌우 비틂 방향, 몸통 숙임 방향). 틀리면 `SwordAnimator.transformFor` 와 데이터 부호 확인
- [ ] Slash1→2→3 연속 입력, 달리며 베기(하체 유지), 마지막 후딜 후 Idle 복귀
- [ ] Triple Slash 3회 입력, 서버 전진과 시각 기울기가 어긋나지 않는가
- [ ] Lunge: 충전 자세 심화 → 방출 → 회복, 충전 중 피격/회피/사망 취소 시 자세가 즉시 풀리는가
- [ ] Blade Wave, Blade Storm 전 구간(회전, Tick 펄스, 마무리, 종료 후 복귀), Storm 중 다른 입력 무시
- [ ] Parry 가드 0.4s, 성공 시 반격 모션, 실패 시 복귀
- [ ] 사망/부활/캐릭터 변경(SWORD↔다른 캐릭터) 직후 자세·Transform 잔여물 없음, `Humanoid.Died` 시 기본 사망 연출
- [ ] 12인 동시 사용 시 프레임 영향(SWORD 캐릭터마다 프레임당 6 Motor6D 갱신), 원거리 플레이어 이벤트 동기
- [ ] 에셋 교체 경로(Animation 인스턴스 배치 시 절차 포즈가 꺼지고 트랙이 재생/정지되는지)
- [ ] 이벤트 지연이 큰 환경에서 모션 시작이 판정/타격음과 어긋나지 않는지(MaxCatchUp 0.12s)

## 알려진 한계

- 기본 콤보/Triple/Wave 의 사전 예고가 짧다(위 설계 노트).
- R15 는 미지원(R6 전용, R15 면 비활성).
- 피격 반응·Dodge·점프/낙하 전용 모션은 범위 밖(공중은 Idle+다리 접힘 정도).
- Blade Storm 종료 때 회전 각도에서 복귀 자세로 최단 경로 블렌드(최대 180° 보정이 0.12s 에 일어날 수 있음) — Studio 에서 어색하면 Finisher 의 `blendIn` 을 늘린다.
