# RoBattles! Alpha 1.0 — 전체 CLI 검증 인계

## 현재 상태

- 기준: `RoBattles_Alpha1_GPT_CLI_Audit_2026-10-26.zip` + 로컬 실행 도구 보완
- 이 문서 작성 환경에는 `luau`, `luau-compile`, `luau-analyze` 없음. 실제 Luau 회귀/컴파일/분석은 **미실행**.
- Roblox Studio도 **미실행**. Python 결과를 Studio PASS로 기록하지 말 것.
- 기존 게임 `src/` Luau 파일은 이 단계에서 수정하지 않았음.

## 가장 간단한 사용법 (Windows / Linux / macOS)

1. `RoBattles` 폴더에 최신 ZIP을 압축 해제한다.
2. 공식 Luau 배포물에서 `luau`, `luau-compile`, `luau-analyze` 실행 파일을 얻고 `RoBattles/tools/luau-bin/`에 넣는다. Windows라면 각 `.exe` 파일을 넣는다. **GitHub 계정 로그인은 필수가 아니다.**
3. `RoBattles` 루트에서 명령 실행:

```sh
python tools/run_full_local.py
```

실행 파일을 다른 폴더에 둔 경우:

```sh
python tools/run_full_local.py --bin-dir /absolute/path/to/luau-binaries
```

Windows에서 `python` 명령이 없다면 `py tools/run_full_local.py`로 대체.

## 공식 Luau 소스에서 직접 빌드하는 경우

공식 저장소: https://github.com/luau-lang/luau

공식 소스 디렉터리에서 (CMake, C++ 컴파일러 필요):

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release --target Luau.Repl.CLI Luau.Compile.CLI Luau.Analyze.CLI
```

빌드된 `luau`, `luau-compile`, `luau-analyze` 실행 파일을 `RoBattles/tools/luau-bin/`에 복사한 뒤 실행한다. Windows에서는 선택한 빌드 구성의 하위 디렉터리에 있을 수 있다.

## 자동 검증 범위

`tools/run_full_local.py`는 (1) 프로젝트/Remote/require/Python 시뮬레이션 사전검사, (2) 전투·경기·애니메이션, 맵, UI mock, 현행 시뮬레이션 등을 포함한 Luau 회귀, (3) Luau 정적 분석을 실행한다.

- Luau 바이너리가 없으면 결과를 `MISSING LUAU`로 기록하고 종료 코드 **2**를 반환한다. Python 사전검사가 통과해도 전체 PASS가 아니다.
- Python 검사만 원할 때는 `python tools/run_full_local.py --offline-only`. 이 경우 Luau·Studio `NOT RUN`을 분명히 출력한다.
- Luau 전체 회귀 결과 로그는 `docs/match-check-logs/`에 저장된다.
- 레거시 시뮬레이션은 기존 4건 실패를 `NO-NEW-FAILURES`로 구분하며, Git 이력 없는 ZIP의 옛 커밋 재현은 `SKIPPED`다.
- Luau 분석기의 Roblox 전역 미지원 경고와 기존 TypeError는 별도 기록한다. 이 스크립트의 PASS도 Studio 실제 동작 보장을 의미하지 않는다.

## Studio 우선 검사

`docs/STUDIO_ALPHA1_SMOKE.md` 지침대로 R6 설정 후 1인 기동 → 2인 로컬 서버에서 PLAY/선택/출전, 스킬, 부활, 인원 부족 취소를 확인하고 12인 성능은 별도 기록한다. Output 로그를 저장한다.
