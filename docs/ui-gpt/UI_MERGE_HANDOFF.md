# phase2/ui 병합 인계

## 공통 기준 확인

현재 결과는 Git 커밋이 아닌 검증된 ZIP 스냅샷 기반이다. 실제 저장소를 받으면 먼저 다음을 수행한다.

1. `git status --short --branch`, 현재 HEAD, remote, Claude Phase 2 브랜치 HEAD를 기록한다.
2. 미커밋 파일을 읽고 보존한다. 자동 reset/clean/stash/pop을 하지 않는다.
3. 실제 공통 커밋을 `git merge-base`로 확인하고 `baseline.sha256`와 파일 내용을 비교한다.
4. 공통 커밋이 확인된 뒤 기존 phase2/ui가 있으면 보존해 사용하거나, 없으면 그 기준에서 격리 worktree에 생성한다.
5. `git apply --check /path/to/ui.patch`로 패치 가능 여부부터 확인한다. 이 ZIP 기준으로는 통과했으나 Claude의 현재 브랜치에 대한 보장은 아니다.
6. 충돌 시 아래 2개 통합 접점을 수동 이식한다. 서버나 shared 파일을 예전 버전으로 되돌리지 않는다.

## 변경 및 충돌 가능성

| 기존 파일 | 변경 | 동시 작업 충돌 가능성 |
|---|---|---|
| src/client/Main.client.luau | 기존 UI 생성 교체, UI 입력 차단, State/Feedback/Scoreboard 전달, 캐릭터 수명 정리, HUD 20Hz | **높음**: Claude의 입력/차징/이동 스킬 전송 변경과 수동 병합 필요 |
| src/client/EffectPlayer.luau | 기본 Sound를 RoBattlesSFX 그룹에 할당하는 1줄 | **높음**: 캐릭터 VFX/SFX 확장 시 이 1줄만 이식 |
| src/client/HudView.luau | 아케이드 HUD 교체 | 중간: Claude가 HUD에 직접 추가한 부분은 UI 어댑터에 재연결 |
| src/client/ScoreboardView.luau | 12행 재사용, 내 기록 강조 | 중간 |
| src/client/SettingsView.luau | 설정·기존 키 재지정 화면 교체 | 중간 |
| tools/check_remotes.py | Remote wait 검사 범위를 remotes로 한정, InputState 동적 이름 검사 | 낮음: 기존 도구가 PlayerGui까지 Remote로 오인하는 문제 수정 |

새 파일: src/client/UI 6개 모듈, tests_ui 3개, tools/run_ui_checks.py 및 run_ui_smoke.py, UI 문서들.

**변경 0개:** src/server 전체, src/shared 전체, src/map 전체, src/simulation 전체. 특히 CharacterController, CombatCore, DamageService, CooldownService, MovementValidator, RemoteSpec은 수정하지 않았다. 기존 테스트 스펙도 변경하지 않았다.

## 통합 접점

- App 생성 후 `app.hud`, `app.board`, `app.settings`를 기존 객체 대신 사용한다.
- UI는 자체 InputBegan/RenderStepped/Remote 구독을 추가하지 않는다. Main의 기존 경로를 유지한다.
- State 수신 시 `app:setSnapshot`으로 오래된 데이터를 거르고, 승인된 데이터만 기존 HudModel로 변환한다.
- Feedback은 `app:onFeedback`, 순위는 `app:setRows`로 전달한다.
- 마우스 delta에 로컬 sensitivity를 곱한다. CameraRig/CameraModel 내부는 변경하지 않는다.
- 메뉴 진입 시 InputState.releaseAll, setUiBlocking, 기존 SetRun(false)를 호출한다.
- 모달 동안 Humanoid 이동 입력을 0으로 전달하며 Space/WASD를 ContextActionService에서 소비한다. 서버 이동 검증은 그대로다.
- CharacterRemoving/Added에서 app:awaitSnapshot; 스크립트 해제 시 app:destroy를 호출한다.

동시 개발 중인 차징/스킬 입력을 변경된 Main 전체로 덮어쓰지 말고, 위 UI 부분만 실제 최신 Main에 이식해야 한다.
