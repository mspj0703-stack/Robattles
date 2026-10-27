> 통합 전(GPT 단독) 기준 결과다. 통합 후 결과는 `docs/INTEGRATION_ALPHA1.md` 를 본다.

# 검증 결과 — 2026-10-25

**전체: 634 PASS / 1 FAIL. 전체 회귀가 모두 통과한 상태는 아니다.** Studio/실제 엔진 검증은 NOT RUN.

| 검증 | 결과 | 설명 |
|---|---|---|
| 기존 전투·통합 순수 로직 | 455/455 PASS | 기존 테스트의 assertion 삭제/완화 없음 |
| 신규 MatchFlow/MatchScope/MatchSession | 53/53 PASS | 실제 순수 전투 서비스와 연결한 경기·부활·정리 테스트 |
| BRICKYARD 맵 | 58/58 PASS | 기존 전체 맵 suite |
| 기존 UI 상태 | 27/27 PASS | UI 소스 변경 없음 |
| 기존 GUI 모의 테스트 | 17/17 PASS | Roblox 엔진이 아닌 제한된 API mock |
| 기존 Python 시뮬레이션 | 24/25 PASS | Phase 1 소스 해시 동일성 검사 1개 실패 |
| Luau 전체 구문/컴파일 | 110/110 PASS | src/tests/tests_ui/tests_map |
| Rojo 프로젝트 경로/Remote 정적 검사 | PASS | 실제 Rojo build/Studio 실행 아님 |
| git diff --check | PASS | 공백/패치 기본 검사 |

## 실패한 검사 — 숨기지 않고 보존

`tests_sim/test_step1.py::SourceRules.test_phase1_manifest`

이 검사는 `sim_baseline/phase1_manifest.sha256`의 Phase 1 파일들이 현재 소스와 완전히 같은지 검사한다. 기준 UI 체크포인트에서도 먼저 `src/client/EffectPlayer.luau` 해시 불일치로 동일하게 실패했다. 경기 작업에서도 해당 클라이언트 파일을 바꾸지 않았음을 별도로 바이트 비교했다.

- 기준 UI 소스: Python 24 PASS / 1 FAIL.
- 경기 구현 소스: Python 24 PASS / 1 FAIL.
- Phase 1 고정 해시 목록과 해당 테스트는 수정하지 않았다.
- 경기 구현은 의도적으로 서버 파일을 변경하므로 현재 소스 전체가 Phase 1과 동일하다는 조건을 충족하지 않는다.
- 실패하는 검사를 skip하거나 manifest를 새 소스로 덮어써 전체 통과로 표시하지 않았다. 후속 단계에서는 원본 Phase 1 보관본의 무결성 검사와 개발 버전의 변경 허용 목록 검사를 별개로 설계해야 한다.

로그: `match-flow-logs/simulation.txt`, `match-flow-logs/baseline_simulation.txt`.

## 기존 테스트 반환값 수정

`tests/SwordPhase2.spec.luau`는 원래 모듈 반환값이 없어 직접 CLI/ModuleScript require가 중단됐다. 이전 UI 작업에서는 임시 CLI 사본에만 return true를 추가했다. 이번에는 **기존 모든 테스트 본문을 그대로 보존한 채 파일 끝에 return true만 추가**하여 표준 `tools/run_tests.py`로 직접 실행 가능하게 했다. 테스트 삭제나 assertion 완화가 아니다.

## 신규 53개 테스트 범위

`MatchFlow.spec`: 확정 상수, 개인 Menu, 최소 인원, 스폰 완료 조건, 5초 시작/취소/재시작, 12슬롯, 중도 참가, 사망자 인원 포함, 1명/0명 유예, 회복/재유예, 7분 종료, 지연 tick의 경계 우선순위, 마감 시각 피해 차단, 12초 결과, 자동 다음 경기, 공동 순위, 결과 불변성, 점수 초기화, 재접속 기록, 연습/결과 점수 차단, 행동 제한.

`MatchScope`: 구 라운드 콜백 차단, 재접속 토큰 분리, 취소 함수 오류 격리, 퇴장자 소유 작업만 취소.

`MatchSession.spec`: 메뉴 선택 전 자동 스폰 차단, 미스폰/사망 선택의 스키마 검증, 실제 연습 피해·게이지 0, 패링 부작용 전 차단, 연습 궁극기 정책, 연습 낙사, 실제 KO와 게이지, 4초/2초 부활, 사망 중 변경과 40 이월, 시작 초기화, 설치 폭탄 무폭발 정리, 늦은 LoadCharacter 격리, RESULTS 행동/피해/게이지 차단, 유예 경계 합류, 접속/스폰 epoch 충돌 방지, UI 계약, 결과 중 최초 선택, 이전 시전 차단, 오류 있는 종료 콜백, 로드 재시도 상한, 라운드 경계의 예약 캐릭터, 동기 사망 반영 중 중복 점수 방지, 스폰 ticket 1회 사용.

기존 테스트 코드에는 생략/skip을 추가하지 않았으며 신규 실패를 기대값 변경으로 숨기지 않았다. 설치 폭탄 테스트의 최초 fixture가 잘못된 API 키(template)를 사용해 실패했을 때 실제 기존 API(def)와 기존 ProjectileTemplates.Placed로 fixture를 교정했다.

## 재현 명령

공식 Luau CLI와 Python 3가 필요하다. 런타임 바이너리는 산출물에 포함하지 않았다.

```sh
python3 tools/run_tests.py --luau /absolute/path/luau
python3 tools/run_map_tests.py --luau /absolute/path/luau
/absolute/path/luau tests_ui/state.spec.luau
python3 tools/run_ui_smoke.py --luau /absolute/path/luau
python3 -m unittest discover -s tests_sim -v
python3 tools/check_projects.py
python3 tools/check_remotes.py
```

위 개별 명령은 실제 실행했다. 새 통합 실행기 `tools/run_match_checks.py`도 제공한다. 모든 그룹의 로그를 저장하고 **하나라도 실패하면 종료 코드 1**을 반환하며, 알려진 Phase 1 manifest 실패를 예외 처리하지 않는다.

```sh
python3 tools/run_match_checks.py --luau /absolute/path/luau --compiler /absolute/path/luau-compile
```

전체 원문 로그는 `docs/match-flow-logs/`에 있다. 컴파일 통과는 Roblox 타입/API·실제 엔진·모델 로드·시각적 UI 연결을 검증한 것이 아니다.
