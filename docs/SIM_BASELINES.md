# 근사 시뮬레이션 기준선 (과거 Phase 1 / 현행)

두 스위트 모두 **Python 근사**다. Luau 서버 코드를 실행하지 않고, Roblox Studio 결과도 아니다. 전투 검증은 `tests/`(Luau CLI)가 담당한다.
시뮬레이션 범위: SWORD 기본 공격+패링, PAINTBALL 주무기만. 스킬·궁극기·나머지 3캐릭터는 **시뮬레이션하지 않는다.**

| | 과거(보존) | 현행 |
|---|---|---|
| 테스트 | `tests_sim/test_step1.py` (25건, 원본 그대로) | `tests_sim_current/test_current.py` (27건) |
| 엔진 | `tools/sim_step1.py` (원본) | `tools/sim_current.py` (엔진 동일, 규칙 로딩·캐릭터별 HP만 다름) |
| 규칙 로더 | `tools/sim_rules.py` (원본) | `tools/sim_rules_current.py` |
| 실행 | `python3 tools/run_sim.py legacy` | `python3 tools/run_sim.py current` |
| 과거 시점 재현 | `python3 tools/run_sim.py legacy --at d1f03e6` | — |
| 통합 검사 그룹 | `sim_legacy`, `sim_legacy_at_d1f03e6` (별도 보고) | `sim_current` (**게이트**) |

## 과거 스위트 상태 (숨기지 않음)
- **현재 소스 기준 25건 중 4건 실패**: `test_actors_and_hp`(HP 100·탄창 30), `test_reload_amount`(30발), `test_actual_phase1_numbers`(PAINTBALL 피해 4, HP 100), `test_phase1_manifest`(고정 해시). 모두 Phase 1 수치/파일 해시를 단언한다.
- **`d1f03e6`(Phase 1 freeze + SWORD 완료) 기준 재현: 25건 중 24건 통과**, 실패 1건은 `test_phase1_manifest`. 이 manifest(`sim_baseline/phase1_manifest.sha256`)는 이 저장소 이력에 없는 더 이전의 Phase 1 동결본 해시라 **어느 커밋에서도 재현되지 않는다.**
- `run_sim.py legacy` 는 실패 목록을 전부 출력한다. 종료 코드는 "알려진 실패 집합에 없는 **새 실패**"가 있을 때만 1이다. 알려진 집합: 현재 4건 / `d1f03e6` 1건.
- `--at` 은 git 이력이 필요하다. 이력이 없는 ZIP 에서는 `SKIPPED` 로 명시 출력한다(통과로 위장하지 않음).

## 현행 스위트가 유지한 동작/경계
과거 25건의 동작 검증(지오메트리, 엄폐 차단, 스폰 보호 경계 1.999/2.0, 공격 시 보호 해제, 회피 무적 경계, 패링 전/후방·공격자당 1회 반격·SWORD 한정, 발사자 사망 후 투사체, 투사체-보호 통과, 킬·리스폰, 행동 발생, 스타일, 100회 배치 결정성, 잘못된 인자)를 그대로 가져왔다.
바꾼 것은 수치 기대값뿐이며 근거는 `Characters.luau` 확정 주석이다: HP SWORD 110 / PAINTBALL 95 / SUPERBALL 100 / TIMEBOMB 105 / SLINGSHOT 100, SWORD 14·0.55s·패링 18, PAINTBALL 피해 7·초당 3발·탄창 16·재장전 1.2s·탄속 220(임시), 회피 14, 리스폰 4s·보호 2s.
교체/추가한 것: Phase 1 해시 manifest 대신 규칙 소스 파일 존재 검사, 5캐릭터 HP 로딩 검사, **나눗셈 리터럴 회귀 검사**.

## 발견한 결함: Phase 1 로더의 `1 / 3` 오독
`Characters.PAINTBALL.primary.fireInterval = 1 / 3`(초당 3발)을 Phase 1 로더는 `1.0`으로 읽는다(정규식이 `1`만 캡처). 과거 스위트는 이 값을 단언하지 않아 통과했다. 현행 로더는 `a / b` 를 계산하며(`1/3`), 과거 로더가 1.0을 반환한다는 사실도 테스트로 고정했다(`test_division_literal_regression`).
