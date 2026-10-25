# BRICKYARD 맵 자동 생성기

전투 코어(`src/shared|server|client`)와 **독립**된 모듈이다(`src/map`, 별도 Rojo 프로젝트). 기존 전투 코드·테스트는 수정하지 않았다. 회색 블록아웃이며 Alpha 맵은 BRICKYARD 1종뿐이다(맵 투표 없음).

> S01~S20 은 사용자가 제공한 **원본 설계안 좌표**를 그대로 적용했다(초기 설계안이므로 이후 구조 변경 시 재검증 필요). 좌표를 바꾸면 검증기가 충돌·간격·도달성·회피·교전 공간을 다시 검사한다.

## 구성
| 파일 | 역할 | 테스트 |
|---|---|---|
| `BrickyardConfig.luau` | 크기·좌표·건물·엄폐물·점프대·스폰·구역 목표·색 (`Config.with{...}`) | CLI |
| `MapLayout.luau` | 설정 → 직육면체 + 스폰 정보 (순수, 결정적) | CLI |
| `MapValidator.luau` | 겹침·경계·스폰·계단·도달성·통로·구역 폭·입구/계단·회피·교전 공간·점프대 궤적 | CLI |
| `SpawnAnalysis.luau` | 스폰 정적 노출도·엄폐물 거리·시야(선분-상자) | CLI |
| `SpawnRegistry.luau` | Spawns 폴더 속성 계약 읽기/정규화 | 정규화 CLI, 폴더 읽기 Studio 미검증 |
| `SpawnRisk.luau` | 스폰 위험도 계산·선택(적 위치·시야 함수 주입) | CLI |
| `MapBuilder.luau` | 레이아웃 → 인스턴스(env 주입), 재생성 시 기존 제거 | CLI(가짜 env) |
| `RobloxEnv / JumpPadController / DummyFactory / BrickyardGenerator / GenerateBrickyard.server / CombatSpawnBridge` | Roblox 전용 | **Studio 미검증** |

## 맵 구조 (원점 중심, 지면 윗면 y=0)
- 지면 180×180, 광장 76×76, 외곽 벽 높이 20(안쪽 면 88).
- 폭 구성: 광장 끝 38 + **연결부 8** + 건물 26 + **외곽 주 통로 16** = 88.
- 건물 4개 `PP PN NN NP`: 26×26, 중심 (±59,±59), 벽 높이 12 + 옥상 2 = **옥상 윗면 Y=14**. 광장 쪽 두 면에 출입구(8×9). 계단 14단(높이 1·깊이 1.25·폭 6)이 바깥 벽을 따라 옥상으로 올라가며 머리 닿는 구간은 옥상 개구부로 비움.
- 광장 엄폐물 9, 옥상 엄폐물 건물당 2.
- 계층: `Workspace.BRICKYARD/{Ground, Perimeter, Cover, Buildings/<ID>/{Walls,Roof,Stairs,RoofCover}, JumpPads, Spawns, Dummies}`

## 스폰 20개 (원본 설계안 좌표 그대로, 중심을 바라봄)
좌표 기준: **북쪽 = -Z, 남쪽 = +Z, 동쪽 = +X, 서쪽 = -X** (맵·전투 전체 통일). yaw 0 = 북(-Z), 양수 = 왼쪽(반시계).

| ID | 구역 | X | Y | Z | yaw° |
|---|---|---|---|---|---|
| S01 | Edge_W | -80 | 0 | -30 | 249.4 |
| S02 | Edge_W | -80 | 0 | 0 | 270.0 |
| S03 | Edge_W | -80 | 0 | 30 | 290.6 |
| S04 | Edge_N | -30 | 0 | -80 | 200.6 |
| S05 | Edge_N | 0 | 0 | -80 | 180.0 |
| S06 | Edge_N | 30 | 0 | -80 | 159.4 |
| S07 | Edge_E | 80 | 0 | -30 | 110.6 |
| S08 | Edge_E | 80 | 0 | 0 | 90.0 |
| S09 | Edge_E | 80 | 0 | 30 | 69.4 |
| S10 | Edge_S | -30 | 0 | 80 | 339.4 |
| S11 | Edge_S | 0 | 0 | 80 | 0.0 |
| S12 | Edge_S | 30 | 0 | 80 | 20.6 |
| S13 | Connector_NW | -40 | 0 | -40 | 225.0 |
| S14 | Connector_NE | 40 | 0 | -40 | 135.0 |
| S15 | Connector_SW | -40 | 0 | 40 | 315.0 |
| S16 | Connector_SE | 40 | 0 | 40 | 45.0 |
| S17 | Roof_NN | -60 | 14 | -60 | 225.0 |
| S18 | Roof_PN | 60 | 14 | -60 | 135.0 |
| S19 | Roof_NP | -60 | 14 | 60 | 315.0 |
| S20 | Roof_PP | 60 | 14 | 60 | 45.0 |

**검증 결과: 수정한 좌표 0개.** 20개 모두 검증기(충돌·간격·도달성·통로 폭·회피 방향·교전 공간·옥상 접근) 통과. 수정이 필요해지면 `Spawns.Adjusted` 에 { id, from, reason } 으로 기록한다(현재 비어 있음). 광장 내부 스폰 없음, 지상 16 + 옥상 4, 옥상은 `Spawns.RoofEnabled=false` 로 비활성(마커는 남고 Enabled=false).

## 점프대 (개정)
이전: 비행 0.8초, 최고점 약 +26 (옥상 13 기준) → **개정**: 비행 0.6초, 옥상 Y=14.
| | PadA | PadB |
|---|---|---|
| 위치 | (33, 0, 33) | (-33, 0, -33) |
| 목표 건물/착지 | PP / (51, 17.5, 51)=HRP 높이 | NN / (-51, 17.5, -51) |
| 수평 거리 | 25.5 | 25.5 |
| 속도 벡터 | (30, 82.0, 30) | (-30, 82.0, -30) |
| 최고점 | 발사 지점 +17.1 (절대 Y≈20.7) | 동일 |
| 착지 하강 속도 | 약 36 studs/s | 동일 |
이유: 옥상이 14로 높아져 같은 비행시간이면 더 높이 뜨므로 시간을 줄여 체공·최고점을 낮췄고, 광장 모서리를 (34→33)로 약간 안쪽에 두어 엄폐물 블록과 간격을 확보했다. 궤적은 외곽 벽(안쪽 면 88)과 멀고, 건물 모서리 위를 6.8 이상 여유로 통과한다. 점프대는 속도만 설정하고 이동·공격 입력을 막는 상태 변경을 하지 않는다(공중 방향 전환·공격 허용; **실동작 Studio 미검증**).

## 검증 항목 (`MapValidator.validate`)
지면 면적·광장·건물/점프대/스폰 수, 외곽 16 + 옥상 4, 광장 내부 스폰 없음, ID·정보 완비, 경계, 이름 중복, 겹침, 스폰 충돌·바닥·간격, 계단 규격·머리 여유, 도달성, 통로 폭 ≥5, **구역 폭(외곽 주 통로 14~18 / 연결부 8~10 / 출입구 ≥6)**, **입구↔계단 접근·진입 여유**, **스폰 회피(14) 방향 ≥2**, **교전 공간(반경 12, 넓이 ≥200, 여유 원 반지름 3)**, 점프대(충돌·여유 1·착지·최고점 ≤+20·체공 ≤0.8·수평 ≤35), 더미.
기본 맵 결과: 전부 통과, 실측 외곽 주 통로 16 / 연결부 8 / 출입구 8, 보장 지상 통로 폭 8.

## 전투 시스템 통합 준비
- **Spawns 폴더 계약**: `SpawnRegistry` 주석에 속성 목록을 정의했다(SpawnId, SpawnKind, Zone, Height, Enabled, FacingYaw, Facing, Exposure, NearestCover). 전투 쪽은 `SpawnRegistry.fromWorkspace()` → `SpawnRegistry.active()` → `SpawnRisk.pick(spawns, enemies, {los=..., recent=...})` 로 사용한다.
- **위험도**: `SpawnRisk` 는 순수 함수이며 적 위치·시야 함수를 주입받는다(가중치 임시, M12).
- **선택적 브리지**: `CombatSpawnBridge.install()` 이 CharacterAdded 때 위험도 낮은 스폰으로 캐릭터를 옮긴다(기본 미설치, Studio 미검증). 전투 코드는 변경하지 않았다.
- **이벤트 중복 방지**: `JumpPadController.attach` 는 이전 연결을 모두 끊고 다시 연결, `Generator.Generated/Cleared` 는 BindableEvent 를 한 번만 생성해 재사용, `clear()` 는 점프대 연결 해제.
- **자동 실행 중복 방지**: `GenerateBrickyard` 는 `workspace` 속성 `BrickyardAutoRunClaimed` 로 한 번만 실행, `BrickyardConfig.AutoRun` 으로 제어, `generate` 는 재진입 잠금.
- **통합 Rojo 초안**: `integrated.project.json` (기존 `default.project.json` + `src/map`). `python3 tools/check_projects.py` 로 JSON·경로만 정적 점검(Rojo 미실행). 통합 시 `AutoRun.SpawnLocations=false` 권장(전투 쪽 스폰과 중복).

## Studio 실행 방법
1. 단독: `rojo serve brickyard.project.json` → Connect, 기본 Baseplate `SpawnLocation` 삭제, Play(자동 생성). 편집 모드: 명령 바 `require(game.ServerScriptService.BrickyardMap.BrickyardGenerator).generate({dummies=true})`.
2. 통합(초안): `rojo serve integrated.project.json`. `BrickyardConfig.AutoRun.SpawnLocations=false` 로 두고 필요하면 `require(...CombatSpawnBridge).install()`.
3. 검증만: `.validate()`, 제거: `.clear()`.

## 테스트
```
python3 tools/run_map_tests.py --luau <luau> --out docs/MAP_TEST_RESULTS.md   # 맵
python3 tools/run_tests.py --luau <luau>                                      # 전투 회귀
python3 tools/check_projects.py                                               # Rojo 프로젝트 정적 점검
```

## 미검증 (Studio 확인 필요 — PASS 아님)
- Roblox 전용 전부(RobloxEnv, JumpPadController, DummyFactory, BrickyardGenerator, GenerateBrickyard, CombatSpawnBridge, SpawnRegistry.fromFolder/fromWorkspace). 문법만 `luau-analyze`.
- `integrated.project.json` 의 Rojo 동기화·Studio 호환성(Rojo 미실행).
- 검증기는 근사 모델: 실제 Humanoid 계단 오르기(단 높이 1·깊이 1.25), 캡슐 충돌, 점프 높이, 카메라 충돌.
- 점프대 서버 속도 설정의 반영(네트워크 소유권), 착지 감각, 공중 조작/공격 허용 여부.
- 이벤트 중복 연결 방지·자동 실행 중복 방지의 실제 동작(재생성 반복, 스크립트 복제).
- 스폰 위험도의 실제 시야(Raycast) 연동, 브리지의 캐릭터 이동 타이밍(전투 쪽 respawn 과의 순서).
- 구역 폭 정의(M09)·스폰 좌표(M07)는 원본 설계안 적용 완료.
