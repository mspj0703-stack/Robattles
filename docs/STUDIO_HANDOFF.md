# RoBattles! Phase 1 — Studio 인계 패키지

> 상태: **Studio 미실행.** 아래 S33~S57 은 전부 "미검증"이다. 이 문서의 어떤 항목도 PASS 가 아니다. 결과는 직접 실행한 사람이 기록한다.
> 항목 상세(조작·기대 결과)는 `docs/STUDIO_TEST_PLAN.md` 의 표를 따른다.

## 1. 필수 설치·설정
- Roblox Studio (최신), Rojo 7.x CLI + Studio용 Rojo 플러그인(버전 일치). 이 프로젝트에서 Rojo/Studio 호환성은 검증되지 않았다.
- 프로젝트 루트(`integrated.project.json` 이 있는 폴더)를 연다.
- 새 Baseplate 플레이스를 준비한다. **기본 SpawnLocation 은 지우지 않는다**(S34: 기본 스폰 한 프레임 문제 확인용).
- Game Settings → Security: 필요한 권한 변경 없음(서버 스크립트만 사용).

## 2. 실행 순서
1. `rojo serve integrated.project.json`
2. Studio → Plugins → Rojo → Connect (빈 Baseplate 에 동기화).
3. Output 창과 Explorer 를 열어 둔다. 시작 직후 **빨간 에러·노란 경고**를 모두 복사해 둔다(기록 양식 §6).
4. 서버 쪽 확인(Explorer): `ReplicatedStorage.RoBattles.Remotes` 에 Attack, Skill, Reload, Dodge, Ultimate, SelectCharacter, SetRun, Feedback, State, Scoreboard 존재 / `Workspace.RoBattlesSpawnPads` 존재.

## 3. BRICKYARD 자동 생성 확인 (S33)
- Output 에 `[BRICKYARD] 생성 완료` 가 1회 나온다.
- Workspace 에 BRICKYARD 맵(광장·건물 4개·옥상·점프대·스폰 마커)이 보인다. 북쪽 = -Z.
- 맵에 SpawnLocation 마커가 별도로 생기지 않는다(전투 시스템이 있으면 생성기가 건너뜀).

## 4. 2~3인 Local Server
- Test 탭 → Clients and Servers → Players 2~3, **Start**(Local Server). 서버 창의 Output 과 각 클라이언트 창 Output 을 따로 본다.
- 서버 로그 필터: `[RoBattles]`. 로드/리스폰: `[Respawn]`, 이동 보정: `[Move]`, 스폰: `[Spawn]`.

## 5. 검증 절차 (요약)
| 구간 | 확인 | 계획 ID |
|---|---|---|
| 입장 | 선택된 스폰에 한 번에 도착, 기본 스폰에 보였다 이동하지 않음 | S34, S35 |
| 이동 | 걷기·달리기·점프·계단·점프대·회피에서 `[Move] correct` 오탐 없음 / 벽 앞 회피 | S43, S44, S45, S46 |
| 공격 | SWORD LMB/RMB(패링), PAINTBALL LMB·R, 연출·HUD | S48, S54 |
| 사망→부활 | 4초 뒤 부활, 무한 반복 없음, 동시 사망, 퇴장/재입장 | S36, S40, S41 |
| 부활 보호 | 2초 무피해·무처치, 공격 시작 시 해제, HUD 동기화, 파란 막 없음 | S37, S38, S39, S51 |
| 로드 경쟁 | `respawn_load_slow` 시 중복 호출 없음, 로드 중 퇴장/사망 시 에러 없음 | S52, S53, S55, S56 |
| ForceField | Duration=0 패드에서 생성 안 됨 / 식별 불가 ForceField 는 경고만 | S51, S57 |
| 종합 | 2~3인 플레이, 스코어보드 | S49 |

로드 지연 재현(S55): 서버 Command bar 에서 `game.Players.<이름>:LoadCharacterAsync()` 를 사용자 정의로 지연시키는 방법은 없으므로, 로그의 `respawn_load_slow` / `respawn_load_hung` 이 실제로 나타나는지만 관찰한다. 나타나지 않으면 "재현 못 함(미검증)" 으로 기록한다.

## 6. 결과 기록 양식 (항목마다 복사)
```
ID: S__
날짜/실행자:
Studio/Rojo 버전:
결과: PASS | FAIL | 재현 못 함(미검증) | 미실행
관찰: (기대 결과와 다른 점)
Output(서버): (붙여넣기)
Output(클라이언트): (붙여넣기)
재현 절차: 1) 2) 3)
빈도: 항상 / 가끔 / 1회
스크린샷·영상:
```
- PASS 는 해당 항목을 **실제로 실행해 기대 결과를 모두 확인했을 때만** 표시한다. 일부만 확인했으면 "부분 확인" 으로 서술한다.

## 7. 오류 로그·재현 절차 수집
1. Output 창 우클릭 → Copy All(서버/클라이언트 각각). 필터 `[RoBattles]` 적용본도 함께.
2. 이동 보정이 의심되면 같은 구간을 3회 반복해 `[Move]` 로그 개수를 센다.
3. 스폰/로드 문제는 `[Spawn]`, `[Respawn]` 줄과 직전 행동(사망·퇴장·맵 재생성)을 시간순으로 적는다.
4. 가능하면 Test 탭의 같은 인원 수·순서로 재현하고, 재현 절차를 3~5단계로 적는다.
5. CLI 회귀 확인: `python3 tools/run_tests.py`, `python3 tools/run_map_tests.py`, `python3 tools/check_projects.py`, `python3 tools/check_remotes.py` (Studio 와 무관한 정적/단위 검증).

## 8. 현재 CLI 검증 범위 (Studio 아님)
- 전투 450/450 (기존 448 + 이번 점검 2), 맵 58/58, 프로젝트 파일 정적 검사, RemoteEvent 이름 정적 검사.
- 순수 로직(스케줄러·게이트·분류·검증기)만 검증. Roblox 엔진 동작(LoadCharacterAsync, SpawnLocation, ForceField, 물리, 렌더링, 네트워크)은 모두 미검증.
