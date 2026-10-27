# RoBattles! Alpha 1.0 — GPT 전체 CLI 실행 경로 정비

## 기준 소스

`RoBattles_Alpha1_GPT_CLI_Audit_2026-10-26.zip` (210개 파일, Git 기록 없는 ZIP).
이 결과물은 기존 210개 원본 파일을 변경하지 않고 4개 파일을 추가했다. Roblox Studio 실기는 미수행.

## 신규 파일

- `tools/run_full_local.py` — Python 사전검사를 실행하고 `luau`/`luau-compile`/`luau-analyze`가 있으면 전체 CLI 회귀 및 정적 분석 실행. 실행기가 없으면 `MISSING LUAU`, 종료코드 2.
- `tests_py/test_full_local.py` — 실행기 탐색 및 PASS/FAIL/미실행 판정 단위 테스트 6개.
- `docs/CLI_EXECUTION_HANDOFF.md` — Windows/Linux/macOS 실행 명령과 공식 Luau CMake 빌드 절차.
- `docs/GPT_LOCAL_CLI_RUNNER_2026-10-26.md` — 이 기록.

## GPT 직접 실행 결과

- 최신 ZIP 압축 무결성: PASS.
- `python -B -m unittest discover -s tests_py -v`: 16/16 PASS (기존 10 + 신규 6).
- `python -B tools/run_full_local.py --offline-only`: 종료코드 0, Python 소스 사전검사 PASS, 현행 시뮬레이션 27/27 PASS.
- `python -B tools/run_full_local.py` (Luau 실행기 미제공): 종료코드 **2**, `MISSING LUAU`, 전체 Luau 미실행으로 표시.
- 레거시 Python 시뮬레이션: 21/25, 기존 stale 실패 4건, 신규 실패 0.
- 전체 Luau 회귀, Luau 컴파일/분석, Roblox Studio: **미실행**.

## 주의

- 이번 작업은 실행 경로와 증빙을 만든 것이지 Luau 전체 회귀 PASS를 얻은 것은 아니다.
- 공식 배포물과 빌드 도구는 `https://github.com/luau-lang/luau`에서 확인할 수 있다. 이 환경은 github.com DNS 조회가 실패하여 실행기를 다운로드하지 못했다.
- `run_full_local.py`의 도구 자체 테스트는 모의 도구를 사용하며, 실제 Luau 실행 성공 증거가 아니다.
- Studio 첫 실행과 12인 성능·실제 R6 재생은 별도로 검증해야 한다.
