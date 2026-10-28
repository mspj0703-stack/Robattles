# RoBattles! P4 — 공통 UI/HUD 시각 개선 보고서

- 작성: 2026-10-28
- 기준: P2-B/P3 누적 커밋 `8c7f75b` (QA4 → P1A~D → P2A/B → P3)
- 상태: **UI 코드 수정 완료 / 정적 검사 통과 / Roblox Studio 렌더링 미검증**

## 목표 및 적용 범위

기존 게임의 **카툰 아케이드 70% + 클래식 Roblox 30%** 시각 방향을 유지하면서, 1280×720 기준 전투 HUD와 메뉴/캐릭터 선택 UI의 가독성 및 정보 계층을 정리했다. 기존 화면 이동 흐름, 서버 승인 캐릭터 선택, 키 설정·스코어보드·피해/KO 이벤트는 그대로 사용한다.

| 파일 | 변경 |
|---|---|
| `src/client/UI/Tokens.luau` | 통일된 어두운 패널/보조 배경, 캐릭터별 강조 색상, 텍스트 대비 조정. 외부 이미지 ID 추가 없음 |
| `src/client/UI/Components.luau` | 공통 패널/버튼 테두리 두께와 모서리 변경. 기존 입력 이벤트·호버/눌림 스케일 유지 |
| `src/client/UI/App.luau` | 메인 메뉴 타이틀/부제/배치, 설정된 스코어보드 키 표시, 캐릭터 선택 카드의 선택 색·윤곽선 명확화 |
| `src/client/HudView.luau` | 상단 경기 정보 헤더, 하단 HP/5스킬/궁극기 크기와 위치 정리, READY/사용 불가 상태 시인성 개선 |
| `src/client/ScoreboardView.luau` | 순위 행 교대 배경색 및 자기 행 강조. 순위·점수는 기존 서버 값 사용 |
| `src/client/SettingsView.luau` | 제목과 안내 문구 정리. 실제 설정 처리 변경 없음 |

## 유지/제외

- 서버 소스(`src/server/`), `Data/Characters`, 전투/애니메이션/카메라 로직, `RemoteSpec`, `EffectPlayer`, `HudModel`, `UI/State`, `Main.client`, 경기 규칙 **변경 없음**.
- 최신 P3의 서버 확정 피해 숫자·연타 합산·KO/HP 회복 표시 유지.
- 신규 캐릭터·맵·이미지/사운드 Roblox 업로드나 GitHub 배포 **미실시**.
- **이번 변경은 PC 1280×720 UI 기준 1차 개편**. 휴대폰/태블릿 화면의 터치 최적화 및 실제 접근성은 검증되지 않았으며 후속 단계에서 다뤄야 한다.

## 검증

- `pytest tests_py/test_p4_ui_contract.py tests_py/test_p2b_p3_contract.py tests_sim_current/test_current.py -k 'not test_no_unexpected_source_modifications'`: **46 passed, 1 deselected**.
- `check_projects.py`, `check_remotes.py`, `check_requires.py`: 통과 (동적 require 3개는 검사 대상 밖).
- `git diff --check`: 통과.
- 전체 구형 `tests_py`: **60 passed, 7 failed**. 이 7개는 QA4/P1/P2/P3 시대의 특정 파일 완전 동일성·변경 허용 목록을 현 P4까지 적용해서 발생한다. 이는 Luau 실행 검증을 대체하거나, 모든 가능성을 배제하는 증거가 아니다. 기존 P3 보고서에서도 과거 변경 범위 검사 실패가 보고되었다.
- **Luau CLI / Roblox Studio 실제 플레이·렌더링·입력 검증 미실행.** 게임 출시 기준의 완료 아님.

## 후속 작업

1. 실제 Roblox Studio 테스트 가능 환경에서 글자 잘림, 해상도/안전 영역, 메뉴·입력·키변경·스코어보드 토글·죽음/결과 화면을 확인한다.
2. P4-B로 작은 화면·모바일 터치 반응형 레이아웃 정리. 필요하면 전투 HUD 별도 UIScale 설정.
3. 신규 오디오 자산은 권한이 있는 Roblox 계정으로 업로드 후 실기에서 확인.
