# RoBattles! Alpha 1.0 — GPT 5캐릭터 애니메이션 오프라인 통합 인계

날짜: 2026-10-26

## 기준 자료 및 버전

- 실제 파일 기준: `RoBattles_Alpha1_FirstPlayUX_GPT_integrated_2026-10-26.zip`
  - 이전 `a598bcb` 인계 소스 + GPT Blade Storm Tick 패치 + StudioReady 문서 + 첫 플레이 UX 병합본
- 추가 입력: `RoBattles_Animation_Phase1plus2_vs_a598bcb.patch`, `RoBattles_Animation_Phase1plus2_FULL.zip`
  - Claude 보고 작업 커밋: `acf8874` (Git 이력 없는 ZIP·패치, 해당 HEAD는 독립 검증 불가)
- 새 산출물: ZIP 기반 GPT 오프라인 수정본, **GitHub 업로드·새 원격 커밋 없음**.
- `SwordAnimState`는 기존 GPT Blade Storm Tick 연동 코드를 보존하고, `baseSampler` 선택 옵션만 추가함. ZIP 전체 덮어쓰기 하지 않음.

## 통합 변경

1. 4캐릭터 애니메이션: PAINTBALL, SLINGSHOT, SUPERBALL, TIMEBOMB (`CharacterAnimator`, 모션 데이터, 상태기계 등 신규 모듈).
2. `Main.client`: 새 애니메이터, Feedback, 로컬 재장전·충전 입력 해제, 서버 match 스냅샷 기반 경기 경계 초기화 연결.
3. `SwordAnimState`: 기존 SWORD 로직 유지, `baseSampler` 확장 2곳만 적용.
4. **GPT 추가 보정**: `SwordAnimator:resetAll()`을 만들어 RESULTS 진입·새 matchId 시 SWORD도 정리. SWORD/4캐릭터 모두 rig 준비 전 보류된 이전 경기 이벤트 backlog를 비움.
5. 신규 Luau 테스트 2개 등록 및 정적 검사 스크립트 갱신. `check_char_anim.py`는 SWORD `resetAll`을 정확히 허용하되 서버·Remote 변경을 금지하도록 유지.

## 실행 검사 (이 환경에서 직접 실행)

| 검사 | 결과 | 근거/한계 |
| --- | --- | --- |
| ZIP 압축 무결성·패치 적용 | PASS | 실제 소스 파일에 patch clean 적용 |
| `python tools/check_projects.py` | PASS | Rojo 경로 정적 검사 |
| `python tools/check_remotes.py` | PASS | Remote 정적 계약 검사 |
| `python tools/check_anim.py <로컬_비교기준>` | 실패 0 | 임시 Git 저장소의 **첫 플레이 UX ZIP 기준** 변경 범위, 구조 검사. 원격 Git 기록 독립 검증 아님 |
| `python tools/check_char_anim.py <로컬_비교기준>` | 실패 0 | 36개 데이터 모션·25개 이상 cue/phase/훅 휴리스틱 검사. **Luau 컴파일 아님** |
| `python tools/run_sim.py current` | 27/27 PASS | Python 근사 시뮬레이션 |
| `python tools/preflight_offline.py` | Source PREFLIGHT PASS | Luau/Studio 부분은 미실행 |
| 레거시 Python sim | 21/25 (기존 stale 4건) | 신규 실패 0, PASS라고 표기하지 않음 |
| `CharacterAnim.spec`, `AnimFiveChars.spec`, 기존 Luau 통합 회귀 | **미실행** | `luau`, `luau-compile` 없음 |
| Luau analyzer 및 Roblox Studio | **미실행** | 실행 환경 부재 |

## 위험 및 출시 차단

- **P0, 기존 문제(이번 수정 대상 아님)**: `MatchFlow:update`는 참가 인원 부족 20초 유예 후 `RESULTS`로 전환(`insufficient_players`). 확정 규칙의 경기 취소와 정상 결과를 구분하는 요구사항에 어긋나므로 별도 서버 수정·회귀 필요.
- **P1**: `CharacterAnimState`가 `SwordAnimState`의 `_storm`, `_play`, `_clearAction` 등에 의존. 이후 SWORD 상태기계 변경 시 4캐릭터 회귀 필요.
- **P1**: 신규 Luau 테스트·실제 R6 Motor6D/PreSimulation 애니메이션·다른 플레이어 렌더·12인 부하·클라이언트 경기 경계 미검증.
- **P1**: 오래된 Feedback 이벤트에는 매치 식별자가 없을 수 있어 경기 전환 직후 지연 이벤트가 애니메이션을 재생할 여지 존재; 실기 검증 필요.
- **P2**: R6는 Studio에서 별도 설정 필요. R15 지원 여부는 기획방 결정 사항.
- 기본 공격 서버 즉시 판정으로 짧은 예고 동작, 일부 Aim/충전 모션 없음, 포즈 추정치는 기존 미결 사항.

## 다음 단계

1. 별도 소스 수정으로 `MatchFlow` 인원 부족 취소 경로를 P0로 수정하고 해당 테스트 작성·실행.
2. Luau 실행 가능한 PC에서 전체 5캐릭터 애니메이션 및 전투·UI·경기 회귀 재검증.
3. Studio R6 설정 후 S1~S136, A1~A12, P1~P8 및 새 4캐릭터 모션 실기 테스트.
4. GitHub 통합이 필요하면 ZIP 기준 콘텐츠 diff로 이식; 원격 `a598bcb` 등 과거 커밋과 동일하다고 간주하지 말 것.
