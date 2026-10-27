# 캐릭터 애니메이션 — Phase 1+2 (PAINTBALL, SLINGSHOT, SUPERBALL, TIMEBOMB)

SWORD 애니메이션 시스템을 재사용한 R6 절차 애니메이션. **시각 전용**: 서버 전투·판정·쿨다운·Remote·이동 검증·UI·MatchFlow 규칙은 건드리지 않는다.
기준 통합 커밋 `a598bcb`. 최신 GPT 통합본이 아니므로 **전체 덮어쓰기 금지** — 아래 "병합 방법"의 파일 단위로만 반영한다.

> ⚠ **검증 상태**: 이 환경에는 Luau 실행기가 없어 `CharacterAnim.spec`·`AnimFiveChars.spec`·`SwordAnim.spec` 과 기존 Luau 회귀는 **실행하지 못했다(미검증)**.
> (실행기 설치 시도는 환경 정책으로 거부되어 우회하지 않았다.) 실행한 것은 Python 정적 검사뿐이며, 모션 데이터·이벤트 계약·훅 범위는 Python 으로 직접 확인했다. Studio 실기동도 미검증.

## 구조
| 파일 | 역할 |
|---|---|
| `src/shared/Data/CharacterMotions.luau` | 캐릭터별 Locomotion(조준 자세·달리기)·모션 키프레임·Groups (4캐릭터, 36모션) |
| `src/shared/Data/CharacterMotionRegistry.luau` | 모션 등록·`validate()`·`assetIdOf(캐릭터, 모션)` (정식 에셋 교체 경로) |
| `src/client/Logic/GunLocomotion.luau` | Idle/Run 기본층(조준 자세 유지, `freeArms` 만 흔듦) — SwordAnimState `baseSampler` |
| `src/client/Logic/CharacterAnimState.luau` | `SwordAnimState` 서브클래스: 우선순위·커밋·만료·블렌드·사망 정리 규칙 공유, 이벤트 매핑·장시간 궁극기·충전 해제 처리 |
| `src/client/Logic/TrackBook.luau` | 에셋 트랙 재생/정지 장부(순수): 같은 트랙 중복 재생, 옛 stop 이 새 재생을 끊는 문제 방지 |
| `src/client/Logic/MatchResetModel.luau` | 결과 화면 진입·새 경기(matchId 변경) 판단(순수). `snap.match` 만 읽는다 |
| `src/client/CharacterAnimator.luau` | Roblox 계층(PreSimulation, rig 대기/재시도, 중복 감시·생성 금지, 에셋 트랙, 정리). **SWORD 는 건드리지 않음** |
| `tests/CharacterAnim.spec.luau`, `tests/AnimFiveChars.spec.luau` | 순수 로직 테스트(`run_all` 등록) |
| `tools/check_char_anim.py` | 금지 영역·훅 범위·PreSimulation·모션 데이터·이벤트 계약·블록 균형 정적 검사 |

## 구현된 모션
공통: 모든 캐릭터는 Idle/Run 기본층(조준 자세 유지)을 가지며, 행동 모션은 그 위에 필요한 관절만 덮어쓴다.

### PAINTBALL (10)
| 모션 | 트리거 | 비고 |
|---|---|---|
| PaintFire | `Spawned` defId=`paint_shot` | 자동 연사 3/s, 0.16초 반동 |
| PaintReload / PaintReloadDone | 로컬 재장전 시작 / `Reloaded` | 시작은 본인 화면 전용(서버 이벤트 없음) |
| PaintBurst, BombThrow, PierceFire | `paint.burst` / `paint.bomb.throw` / `paint.pierce.fire` | |
| PaintSlide | `paint.slide` | 길이 = `dash.duration` |
| ColorBreak 전조→빔→복귀 | `paint.ult.windup` → `Tick`(마다 연장) → `End` | 궁극 잠금 |
### SLINGSHOT (8)
| 모션 | 트리거 | 비고 |
|---|---|---|
| SlingCharge → SlingRelease | `sling.charge` → `sling.shot` | 해제 이벤트·로컬 해제·최대 5.5초 중 먼저 오는 것으로 풀림 |
| SlingTriple / SlingSnare / SlingBackstep | `sling.triple` / `sling.snare` / `sling.backstep` | |
| Bullseye 조준→발사→(중단 시)복귀 | `sling.ult.windup` → `sling.ult.fire` → `sling.ult.end` | |
### SUPERBALL (11)
| 모션 | 트리거 | 비고 |
|---|---|---|
| BallCharge | `ball.charge` | 길이 = chargeSeconds, 던지기 이벤트·로컬 해제·최대 4.5초(서버 정리 시각과 동일) |
| BallThrow / BallThrowCharged | `ball.throw` / `ball.throw.charged` | 충전 중이면 충전 모션을 끊고 연결 |
| BounceDash | `ball.dash` | 길이 = `dash.duration`, 웅크린 구르기 |
| RapidBounce / ScatterBall / Recall | `ball.rapid` / `ball.scatter` / `ball.recall` | |
| Ball Cyclone | `ball.cyclone.start`(duration) → `ball.cyclone.shot` 마다 CycloneShot → `ball.cyclone.end` | Start 웅크림→팔 번쩍 → Spin(몸 회전, **서버가 알려 준 duration 동안**) ⇄ Shot → Recover |
### TIMEBOMB (7)
| 모션 | 트리거 | 비고 |
|---|---|---|
| TimedThrow | `bomb.throw` | |
| BlastGuard | `bomb.guard` | 양손 밀기 + 반동 |
| ClusterThrow | `bomb.cluster` | 오버핸드 |
| RemotePlace / RemoteDetonate | `bomb.remote`(설치) / `bomb.detonate`(길게 눌러 전체 기폭) | 누르는 동안 이벤트가 없어 Release 이벤트 시각에 재생 |
| BlastJump | `bomb.jump` | 길이 = `dash.duration` |
| BigBangThrow | `bomb.bigbang`(Throw) | 준비(들어 올림)·투척·복귀를 한 모션으로 묶음 — 서버에 "준비" 이벤트가 없다 |

**서버 폭발 시각 vs 모션 시각**: 폭발(`BombLand/BombExplode/BombEnd`, 퓨즈 1·3초 뒤)은 모션을 만들지도 끊지도 않는다. 모션은 던지기·설치·기폭 "입력 이벤트" 시각에만 맞춘다(테스트 포함).

## 정리·만료 규칙
- `Died` → 모든 모션·궁극 잠금·대기 해제·에셋 트랙 정리, 이후 이벤트 무시. `Respawned`/캐릭터 변경/rig 제거 → 처음 상태.
- 모든 모션에 만료가 있다. 궁극기 종료 이벤트가 유실돼도: ColorBreak/Bullseye 는 hold 최대 시간·잠금 3.8초, **Cyclone 은 `duration+1초`** 뒤 잠금·자세가 스스로 풀린다.
- **충전 입력 해제(로컬)**: `Main.client` 가 Release 입력 때 `charAnim:onLocalRelease()` 를 부르면, 서버 발사 이벤트가 0.4초 안에 안 올 때(서버가 해제를 거부한 경우 등) 충전 자세를 푼다. 이벤트가 더 늦게 와도 정상 재생된다.
- **경기 종료·재시작**: `Main.client` 의 State 핸들러가 `MatchResetModel.shouldReset(직전 match, 현재 match)` 로 **RESULTS 진입 시 한 번 / matchId 변경 시 한 번** `charAnim:resetAll()` 을 호출한다(같은 상태에서 매 스냅샷 반복 호출 없음). `snap.match`(없으면 `snap.ui.match`)만 읽고 MatchFlow 는 건드리지 않는다.
  - SWORD(`SwordAnimator`)에는 resetAll 이 없다 — "기존 SWORD 동작 불변" 때문에 추가하지 않았다. 필요하면 GPT 방에서 같은 모델의 `shouldReset` 로 `rig.state:reset()` 을 호출하는 메서드를 얹으면 된다.
- 플레이어 퇴장(`PlayerRemoving`/`CharacterRemoving`/`AncestryChanged`) → 연결 해제·Transform 원복.

## Animator·Motor6D 중복 처리 방지
- `SwordAnimator` 는 `CharacterId == "SWORD"` 만, `CharacterAnimator` 는 그 외 지원 캐릭터만 다룬다 → 한 모델의 관절을 두 모듈이 동시에 쓰지 않는다. 캐릭터가 바뀌면 이전 모듈이 Transform 을 원복하고 새 모듈이 다음 PreSimulation 부터 쓴다(최악 1프레임 어긋남).
- `CharacterAnimator.new()` 는 싱글턴 가드(두 번 호출해도 PreSimulation 연결·트랙이 두 벌 생기지 않음). 캐릭터/플레이어 중복 감시 금지, 트랙은 `TrackBook` + id 별 캐시(재생마다 LoadAnimation 안 함), `Animation` 인스턴스는 캐시되는 resolve 안에서만 생성.
- 에셋 모션 구동 중에는 Transform 을 쓰지 않고(procedural→asset 전환 시 1회 원복), Animator 가 없으면 절차 포즈로 폴백.
- 12인 환경: 상태기계·rig·`TrackBook` 은 플레이어(모델)마다 독립이고 전역 상태는 `_watched/_bound/_rigs` 표뿐이다. 순수 로직 수준의 12인 테스트는 있으나 **실제 12인 접속의 연결/트랙 누수는 Studio 에서 확인해야 한다**(미검증).

## 병합 방법 (구버전 전체 덮어쓰기 금지)
1. **신규 파일 11개는 그대로 추가**: `CharacterAnimator`, `Logic/{CharacterAnimState,GunLocomotion,TrackBook,MatchResetModel}`, `shared/Data/{CharacterMotions,CharacterMotionRegistry}`, 두 spec, `docs/CHARACTER_ANIMATION.md`, `tools/check_char_anim.py`.
2. **기존 파일은 줄 단위로만**:
   - `src/client/Logic/SwordAnimState.luau`: `new()` 에 `_baseSampler = opts.baseSampler,` 1줄, `update()` 의 `local base = ...` 1줄(아래 참조).
   - `src/client/Main.client.luau`: require 2줄, `charAnim`/`lastAnimMatch` 선언, destroy 에 `charAnim:destroy()`, Release 훅 1줄, State 핸들러의 재장전 시작 훅 1줄 + match 정리 블록, Feedback 의 `charAnim:onFeedback` 1줄.
   - `tests/run_all.luau`: spec 2줄 등록. `tools/check_anim.py`: 허용 목록에 새 파일 접두어 추가.
3. 병합 후 `python3 tools/check_char_anim.py <기준>` 과 `check_anim.py` 를 실행하고, Luau 실행기가 있는 환경에서 `run_all` 을 돌린다.

## SwordAnimState `baseSampler` 변경 호환성
- 변경은 `new()` 의 옵션 1줄과 `update()` 의 base 계산 1줄(`baseSampler` 가 없으면 기존 `LocomotionPose.sample` 그대로)뿐이다. SWORD 는 옵션을 안 넘기므로 동작이 같고, `AnimFiveChars.spec` 이 SWORD Idle 자세(`Root.ry=-8`, `RArm.rx=38`)를 단언한다(미실행).
- `CharacterAnimState` 는 `SwordAnimState` 의 비공개 멤버(`_play`, `_clearAction`, `_storm`, `_action`, `_expired`, `_loco`, `_data`)를 사용한다 → **SwordAnimState 의 이 이름들을 바꾸면 캐릭터 애니메이션이 깨진다.** 이름 변경 시 함께 수정해야 한다.

## GPT Blade Storm Tick 패치(f219c33, 최신 통합본에 포함 추정)와의 충돌 지점
패치는 `SwordAnimState` 의 폭풍 잠금을 바꾼다: `_storm = { start, lastTick, lastActivity }`, 잠금 해제 = `lastActivity + 2.0`(기존 `start + 3.8`), StormLoop 만료를 Tick 마다 연장.
1. **`lastActivity` 필드(수정 완료)**: 패치된 `update()` 는 `self._storm.lastActivity` 를 읽는다. Phase 1 초안은 이 필드 없이 `_storm` 을 만들어 병합 시 nil 연산 오류 위험이 있었다. 지금은 모든 궁극기 잠금을 `newStorm()`(lastActivity 포함)으로 만들고, 틱·발사·Cyclone 구간에서 갱신한다. 현재 기준(a598bcb)에서는 읽히지 않는 여분 필드다.
2. **2초 무활동 해제**: PAINTBALL ColorBreak(틱 0.25초 간격), SLINGSHOT Bullseye(0.9초), SUPERBALL Cyclone(12초 — `update()` 가 매 프레임 lastActivity 를 현재로 갱신)은 영향 없다. 전조(Windup) 후 첫 Tick/Fire 가 2초 넘게 늦으면 잠금이 먼저 풀린다(정상 서버 값: 0.7~0.8초).
3. **Cyclone 의 잠금 갱신은 `_storm.start/lastTick/lastActivity` 를 직접 쓴다**(`CharacterAnimState:update`). 패치가 `_storm` 구조를 더 바꾸면(필드 이름 변경 등) 이 3줄을 맞춰야 한다. SWORD 의 `def.spin/pulse` 는 Cyclone 에 쓰지 않는다(`bodySpin` 은 CharacterAnimState 자체 후처리).
4. 패치의 `SwordMotions.StormLoop.tickExtend` 같은 SWORD 데이터 변경은 캐릭터 데이터와 무관하다.
5. 패치의 `tests/SwordAnim.spec.luau`·`docs/SWORD_ANIMATION.md` 는 이 브랜치와 겹치지 않는다(신규 spec/doc 은 별도 파일).

## 정식 에셋 교체
`CharacterMotionRegistry.Entries[캐릭터][모션].assetId` 또는 `ReplicatedStorage.RoBattles.Assets.Animations.<캐릭터>.<모션 id>`(Animation) 지정 시 그 모션만 Animator 트랙으로 재생되고 타이밍·우선순위·정리는 그대로 상태기계가 관리한다.

## 알려진 한계
1. R6 는 프로젝트가 강제하지 않는다(`StarterPlayer.GameAvatarType = R6` 필요). R15 는 감지해 비활성화하고 경고한다.
2. PreSimulation 의 Transform 우선 적용, 관절 축 부호, 포즈 값(추정치)은 Studio 확인 필요.
3. 기본 공격 예비 동작은 서버가 즉시 판정하므로 매우 짧다. Big Bang 은 서버에 준비 이벤트가 없어 준비 동작이 모션 앞 0.1초로 압축돼 있다.
4. SLINGSHOT RMB Aim Mode(클라이언트 전용)와 TIMEBOMB Remote Bomb "누르는 중"(서버 이벤트 없음)은 모션이 없다.
5. 충전 중 회피/피격으로 서버가 충전을 취소하는 경우는 서버에도 취소 이벤트가 없다(회피는 충전을 취소하지 않음). 로컬 해제 또는 최대 시간(5.5/4.5초)으로 풀린다.
6. 재장전 시작 모션은 본인 화면에서만 나온다. SWORD 에는 경기 종료 resetAll 이 없다.
7. Cyclone 진행 중에는 궁극 잠금 때문에 Bounce Dash 등 낮은 우선순위 모션이 재생되지 않는다(이동 자체는 서버가 처리하며 회전 자세가 유지된다).
