# RoBattles! Alpha 1.0 — CLI 회귀 검수 보완 (2026-10-26)

## 기준
- `RoBattles_Alpha1_GPT_Stability_v2_2026-10-26.zip` (Git 이력 없는 오프라인 통합본)
- 본 산출물은 해당 ZIP에서 **게임 Luau 소스를 수정하지 않음**.

## 변경 파일
1. `tools/run_match_checks.py`: 이전 커밋의 시뮬레이션이 ZIP의 Git 이력 부재로 SKIPPED 되었어도 PASS로 인쇄하던 상태 분류 오류 수정. SKIPPED / NO-NEW-FAILURES / PASS / FAIL을 구분하며 기존 검사 종료코드 정책은 유지.
2. `tests_py/test_regression_status.py` (신규): 위 상태 분류의 6개 회귀 테스트.
3. `docs/GPT_CLI_REGRESSION_AUDIT_2026-10-26.md` (이 문서).

## 실행 결과 (GPT 직접)
- `python3 -B -m unittest discover -s tests_py -v`: 10/10 PASS (기존 4 + 신규 6)
- `python3 tools/preflight_offline.py`: SOURCE PREFLIGHT PASS
- `python3 tools/run_sim.py current`: 27/27 PASS (preflight 내부 실행)
- `python3 tools/run_sim.py legacy`: 21/25, 알려진 실패 4건, 신규 실패 0 (preflight 내부 실행)
- 프로젝트/Remote/모듈 참조 검사: PASS (preflight 내부 실행)
- 기존 및 신규 Luau 테스트: **미실행** (실행기 미확보)
- Luau 컴파일 / 정적 분석: **미실행**
- Studio 실기: **미실행**

## Luau CLI가 있는 환경에서 재검증
- 공식 Luau 저장소의 release 패키지에서 `luau`, `luau-compile`, `luau-analyze` 바이너리를 확보한다. (로그인/2차 인증 우회 불필요)
- 프로젝트 루트에서 아래 명령을 실행한다.

```sh
python3 tools/preflight_offline.py --luau /absolute/path/luau --compiler /absolute/path/luau-compile
LUAU_ANALYZE=/absolute/path/luau-analyze python3 tools/analyze.py
```

`run_match_checks.py`는 Luau 테스트/맵/UI/GUI mock을 실행하고 로그를 `docs/match-check-logs`에 남긴다. 역사적 Git 커밋이 없는 ZIP은 레거시 원본 재현 검사만 SKIPPED로 기록된다. 이는 게임/실기 검증 성공을 의미하지 않는다.

## 제한 및 향후 작업
- 공식 Luau 바이너리 다운로드는 현 GPT 실행환경에서 DNS 오류로 실패했다.
- Roblox Studio에서 2인 취소/재시작과 5캐릭터 R6 모션, 12인 부하를 직접 확인해야 한다.
- 과거 시뮬레이션 알려진 실패 4건은 유지하며 신규 실패와 분리 기록한다.
