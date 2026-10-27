# UI 검증 결과 — 2026-10-25

| 검증 | 결과 |
|---|---|
| 원본 전투/통합 순수 로직 회귀 | 455 / 455 PASS |
| UI 수정본 동일 회귀 | 455 / 455 PASS |
| 신규 UI 상태/시각/선택/퇴장 테스트 | 27 / 27 PASS |
| GUI API 모의 생성·전환·콜백 테스트 | 17 / 17 PASS |
| Luau 컴파일 (src + tests_ui) | 73 / 73 PASS |
| 기존 Rojo 프로젝트 경로 정적 검사 | PASS; Rojo 실제 빌드 아님 |
| Remote 생성/정의/사용 정적 검사 | PASS |
| 보호 대상 server/shared/map/simulation 파일 | 47개 원본과 바이트 일치 |
| Roblox Studio / 실제 2~12인 / 화면 육안 확인 | NOT RUN |
| 원격 브랜치/공통 커밋/실제 최신 Claude 소스 병합 | NOT RUN; Git 저장소 미제공 |

후보 소스 테스트 총계: 499개 PASS (455 + 27 + 17). 원본 455개는 비교 실행으로 별도이며 후보 테스트 수에 중복 합산하지 않았다.

## 재현

공식 Luau CLI 및 luau-compile 실행 파일이 필요하다. Python 표준 라이브러리만 사용한다.

```sh
python3 tools/run_ui_checks.py --luau /absolute/path/luau --compiler /absolute/path/luau-compile
# 원본 디렉터리가 있으면 추가:
python3 tools/run_ui_checks.py --luau /absolute/path/luau --compiler /absolute/path/luau-compile --baseline /absolute/path/original/RoBattles
```

실행한 로그 전체: `UI_TEST_LOG.txt`. 런타임 바이너리는 결과 ZIP에 포함하지 않았다.

## 원본 테스트 하네스 문제

원본 `tests/SwordPhase2.spec.luau`에는 모듈 반환값이 없다. 기존 `tools/run_tests.py` 그대로 실행 시 `module must return a single value`로 중단됐다. UI 작업에서 원본 테스트 파일은 수정하지 않았다. 새 run_ui_checks는 **임시 CLI 사본에만 return true를 추가**하여 동일 테스트 455개를 원본/후보 양쪽에서 실행한다. 로그에 HARNESS로 명시했다. Studio에서 원본 run_all을 require하는 경우도 이 원본 결함을 먼저 검토해야 한다.

## 정적 검사 도구 수정

기존 check_remotes는 모든 WaitForChild 문자열을 Remote로 간주해 PlayerGui까지 오탐했다. remotes:WaitForChild만 읽도록 수정했다. 존재하지 않는 InputModel 대신 실제 InputState의 동적 Remote 이름도 검사하도록 변경했다. Remote 계약은 변경하지 않았다.

## 모의 검증의 한계

GUI 테스트는 제한된 가짜 Roblox API로 객체 생성·문자열 값·버튼 콜백·상태 전환·입력 차단 플래그·SoundGroup 볼륨·할당 수를 검사한다. 실제 엔진에서의 렌더링, 입력 우선순위, TextBounds, 자산 권한, ViewportFrame, 오디오 출력, 네트워크 전달 순서, 프레임 성능을 증명하지 않는다.

640×360 등 배율 검사는 캔버스의 경계 계산만 검증한다. 실제 작은 창의 글자 가독성과 UI 클리핑은 Studio에서 확인해야 한다.
