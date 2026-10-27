# GPT Alpha 1.0 — 인원 부족 경기 취소 경계 수정 (2026-10-26)

## 소스 기준
- 입력: `RoBattles_Alpha1_Anim5_GPT_integrated_2026-10-26.zip` (204 files, ZIP 작업본; Git SHA 아님)
- 이 패치는 `a598bcb` 이후의 GPT Blade Storm/첫 플레이 UX/5캐릭터 애니메이션 통합본에만 적용.
- GitHub push / Roblox Studio 실행은 수행하지 않음.

## 규칙
- ACTIVE 참가자가 1명 이하로 20초 지속되면 `WAITING`으로 바로 취소 전환. `match.reason="insufficient_players"`, `match.cancelled=true`.
- 이 경로에서는 12초 `RESULTS`와 결과표를 생성하지 않음. 대기 HUD에 경기 취소 안내를 표시.
- 7분 정상 종료가 유예 만료보다 빠르거나 같으면 기존 `RESULTS` 12초 유지.
- 전환 시 기존 `MatchSession:_transition`에서 모든 임시 전투 상태/투사체/폭탄/볼/스케줄러 정리.
- 5캐릭터 애니메이션은 `MatchResetModel`이 `ACTIVE -> WAITING` 인원 부족 취소도 1회 정리.
- 추가 인원이 출전하여 준비 상태가 충족되면 별도의 온전한 5초 카운트다운부터 다시 시작.

## 수정 파일
- 서버: `src/server/MatchFlow.luau` (상태 전환, cancelled snapshot)
- 클라이언트: `src/client/UI/App.luau`, `src/client/Logic/MatchResetModel.luau`
- 회귀: `tests/MatchFlow.spec.luau`, `tests/MatchSession.spec.luau`, `tests/AnimFiveChars.spec.luau`, `tests_ui/views.spec.luau`
- 문서: `docs/MATCH_FLOW_IMPLEMENTATION.md`, `docs/MATCH_FLOW_UI_CONTRACT.md`, `docs/MATCH_FLOW_STUDIO_P0.md`, `docs/STUDIO_TEST_PLAN.md`, 이 문서

## 검증 한계
- Python 시뮬레이션은 전체 경기 상태기계를 직접 실행하지 않음.
- Luau CLI / GUI mock / Roblox Studio 실기 테스트는 실행기 확보 전까지 미검증으로 기록.
- 기존 레거시 시뮬레이션 실패 4건은 변경하지 않음.
