# RoBattles! — Alpha Phase 1

Roblox PC 3인칭 FFA 난전 액션. 이 저장소는 Phase 1(공통 전투 시스템)을 단계별로 구축 중이다.

## 진행 상황
- [x] 1단계: 프로젝트 구조, Config, 데이터 스키마(투사체 7종·리모트 페이로드), 테스트 러너
- [x] 2단계: 서버 서비스 Cooldown/Dodge/StatusEffect/Damage/Hitbox/Ultimate + RemoteGate + CombatCore (CLI 테스트 통과, Studio 미검증)
- [x] 2.5단계: ProjectileService(7종), CharacterController(SWORD/PAINTBALL), ServerRouter, 서버 부트스트랩(Main.server.luau, WorldAdapter) — 로직은 CLI 테스트 통과, **Roblox 의존부는 Studio 미검증** (docs/STUDIO_TEST_PLAN.md)
- [x] 3단계: 클라이언트 입력·카메라·이동·회피·HUD·키 설정 + 패링 확정 사양 + 궁극기 자리표시자 게이트. 순수 로직은 CLI 테스트 통과, **Roblox 의존부(Main.client, CameraRig, *View)는 Studio 미검증**
- [~] 4단계(진행): 서버 이동·회피 검증(A41), 전투↔맵 통합(SpawnDirector·integrated.project.json), 임시 전투 연출, 부활 확정 사양(4초 대기·2초 보호), 서버 로드/스폰 패드, 특수 이동 허가 구조. 순수 로직은 CLI 테스트 통과, **Studio 실기동은 전부 미검증** (docs/STUDIO_TEST_PLAN.md S33~S54)

## 설치·실행 (Studio)
1. Rojo 설치 (VS Code 확장 또는 CLI, https://rojo.space)
2. 통합(전투+BRICKYARD 맵): `rojo serve integrated.project.json` / 전투만: `rojo serve` (default.project.json) / 맵만: `brickyard.project.json`
   `rojo serve` 실행 → Studio 플러그인에서 Connect (또는 `rojo build -o RoBattles.rbxlx`)
3. Play 시 서버(Main.server)와 클라이언트(Main.client)가 자동 실행된다. 조작: WASD, Ctrl 달리기 토글, Space 점프, Shift 회피, LMB/RMB, 1·2·3(미구현), F(궁극기: 미구현), R(탄약 캐릭터), Tab 스코어보드, V 시점 전환, F10 키 설정.

## 자동 테스트 (Luau CLI)
```
python3 tools/run_tests.py --luau <luau 경로> --out docs/TEST_RESULTS.md
```
최근 결과는 `docs/TEST_RESULTS.md` 참고. Roblox API(Raycast, Humanoid 등)에 의존하는 항목은 Studio 절차로 별도 검증한다.

## 구조
```
src/shared   Config, Schema, RemoteSpec, ProjectileSpec, Data/
src/server   전투 서비스(순수 로직, 시간은 now 주입), ProjectileService, CharacterController, RemoteGate, ServerRouter, CombatCore, Link
             Main.server.luau / WorldAdapter.luau 는 Roblox 전용(CLI 테스트 제외)
src/client   Logic/(순수 로직: InputState, CameraModel, AimAssist, MovementModel, HudModel, FeedbackModel, Crosshairs, KeybindSettings — CLI 테스트)
             Main.client / CameraRig / HudView / ScoreboardView / SettingsView 는 Roblox 전용(Studio 미검증)
tests        러너와 스펙 (CLI/Studio 공용)
tools        run_tests.py
docs         ASSUMPTIONS.md, TEST_RESULTS.md, STUDIO_TEST_PLAN.md
```

## 별도 모듈: BRICKYARD 맵 생성기
전투 코어와 독립된 맵 생성기가 `src/map`에 있다. 사용법·구조·미검증 항목은 `docs/MAP_BRICKYARD.md`, 테스트는 `python3 tools/run_map_tests.py`.

## Phase 2 Step 1 — SWORD 스킬
SWORD 전체 스킬(3타 콤보, Triple Slash, Lunge, Blade Wave, Blade Storm, Duelist)이 서버/클라이언트에 구현됨(CLI 검증만, Studio 미검증). 수치 구분은 docs/ASSUMPTIONS.md A65~A67, Studio 체크리스트는 docs/STUDIO_TEST_PLAN.md S58~S75. PAINTBALL(HP 95)·SUPERBALL(HP 100) 구현(CLI 검증만; A68~A75, S76~S100). TIMEBOMB·SLINGSHOT 은 다음 Step. src/simulation/ 은 보존만(작업 중단).
