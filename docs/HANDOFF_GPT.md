# RoBattles! 인계 자료 (Claude → GPT 개발방)

> **버전 주의(2026-10-26):** 이 문서는 `d66f8ba` 당시 작성된 인계 이력을 보존한 것이다. 현재 사용자 제공 소스 명칭은 `a598bcb`, 이를 기반으로 GPT Blade Storm Tick 패치를 적용한 **Git 없는 오프라인 ZIP**이 후속 작업 기준이다. 현재 Studio 점검은 `docs/STUDIO_ALPHA1_SMOKE.md`를 참고한다. 본문에 기재된 수치는 당시에 실행되었다고 **보고된** 결과이며 이번 ZIP에서 Luau CLI를 재실행했다는 뜻은 아니다.

## 기준
- 브랜치 `phase2/integration` HEAD `d66f8ba` (= `phase2/merge-animation`). 작업 트리 깨끗, 원격 푸시 완료.
- 5663d1c(전투 보고 커밋)는 이 HEAD 의 조상이다. `phase2/combat`/`main` 은 `30dcad2` 로 유지(변경 없음), `phase2/animation` 은 `e2faeb2`.
- 계보: combat 30dcad2 → integration ac6d48f(UI·경기 흐름) → +SWORD 애니메이션 병합 03f142a → +Storm End 시각 수정 d66f8ba.
- Studio: **전부 미검증**.

## 마지막 변경(ac6d48f → d66f8ba, 17파일)
애니메이션 신규 모듈(`src/client/SwordAnimator.luau`, `src/client/Logic/{AnimationCache,LocomotionPose,MotionMath,RigStatus,SwordAnimState}`, `src/shared/Data/{MotionRegistry,SwordMotions}`), `tests/SwordAnim.spec.luau`, `tools/check_anim.py`, `docs/SWORD_ANIMATION.md`; 수정: `Main.client.luau`(+4/-1), `tests/run_all.luau`, `tests/Sword.spec.luau`, `src/server/SwordSkills.luau`, `src/server/CharacterController.luau`(Storm End 시각), `docs/STUDIO_TEST_PLAN.md`.

## 테스트 명령 (CLI, 저장소 루트)
    L=<luau-bin 경로>
    python3 tools/run_match_checks.py --luau $L/luau --compiler $L/luau-compile   # 전체 묶음
    python3 tools/run_tests.py --luau $L/luau          # 전투·경기·SwordAnim
    python3 tools/run_map_tests.py --luau $L/luau
    $L/luau tests_ui/state.spec.luau
    python3 tools/run_ui_smoke.py --luau $L/luau
    python3 tools/run_sim.py current | legacy
    python3 tools/check_projects.py; python3 tools/check_remotes.py; python3 tools/check_anim.py
    python3 tools/analyze.py

## 결과 (d66f8ba)
통과: 전투·경기·SwordAnim 919/919, 맵 58/58, UI 상태 53/53, GUI mock 34/34(Studio 아님), sim_current 27/27, check_projects/remotes/anim, Luau 컴파일 135/135, 분석 SyntaxError 0.
알려진 실패(숨기지 않음): 레거시 시뮬 25건 중 4건 stale(`test_actors_and_hp`, `test_actual_phase1_numbers`, `test_phase1_manifest`, `test_reload_amount`), `d1f03e6` 시점 1건. 새 실패 없음. 분석기 기타 TypeError 12(기존).
미실행: Studio 전부(S1~S136, A1~A12, P1~P8).

## 알려진 위험·미결정
- R6 미강제: Studio Avatar Type=R6 필요, R15 는 SWORD 애니메이션만 비활성(로직 테스트만). R15 장기 지원은 기획 결정.
- 애니메이션은 Roblox 전용 부분(PreSimulation Transform, Animator, 관절)이 CLI 로 검증 불가 → Studio 필수. Animate 스크립트와의 충돌 가능성 미확인.
- `check_anim.py` 는 서버 수정 예외를 3개 파일(SwordSkills, CharacterController, Sword.spec)에 한해 허용.
- 레거시 sim(`tests_sim`, `tools/sim_step1.py`, `tools/sim_rules.py`)은 수정 금지(보존).

## UI·애니메이션과 충돌 가능한 파일
`src/client/Main.client.luau`(Feedback 핸들러·생성/파괴), `src/client/UI/{App,State,Catalog,Components,Preview,Tokens}`(결과 화면·KO 토스트·KillConfirmed matchId), `src/client/SwordAnimator.luau`, `tests/run_all.luau`, `src/shared/Data/Characters.luau`(수치, 애니메이션 데이터는 별도).

## 향후 수정 위치
- Storm 이벤트 시각: `src/server/SwordSkills.luau` `endStorm`/`_lastNow`.
- 이벤트 → 모션 매핑: `src/client/Logic/SwordAnimState.luau` `onEvent`, 모션 데이터 `src/shared/Data/SwordMotions.luau`.
- Animator 지연/backlog: `src/client/SwordAnimator.luau` `onFeedback`/`_refresh`.
- Studio 체크리스트: `docs/STUDIO_TEST_PLAN.md`.

## 2026-10-26 GPT 오프라인 애니메이션 Phase 1+2 통합

이 파일의 기존 커밋 및 테스트 결과는 **과거 인계 기록**이다. 이후 FirstPlayUX + BladeStormTick 오프라인 기준본에 PAINTBALL, SLINGSHOT, SUPERBALL, TIMEBOMB 애니메이션을 추가했다. 경기 경계에서 SWORD를 포함한 5캐릭터 모션·대기 이벤트를 초기화한다. 최신 작업내역, 실제 검사 및 미실행·위험 사항은 `docs/GPT_ANIM5_INTEGRATION_2026-10-26.md` 참조. 새 GitHub HEAD 또는 Studio 검증 완료를 뜻하지 않는다.
