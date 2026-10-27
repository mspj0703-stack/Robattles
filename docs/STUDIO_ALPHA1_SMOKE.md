# RoBattles! Alpha 1.0 — Studio 최초 실행 P0 스모크 테스트

> 기준: 사용자 제공 `a598bcb` ZIP + GPT Blade Storm Tick 패치. **오프라인 산출물**이며 새 Git 커밋이 아니다. 이 문서의 테스트는 **전부 미실행**. 상세 절차는 `STUDIO_TEST_PLAN.md`의 S1~S136, A1~A12, P1~P8을 참고한다.

## 준비

1. Roblox Studio와 호환되는 Rojo를 준비한다. `rojo serve integrated.project.json` 후 Studio Rojo 플러그인에서 연결한다. 에셋·맵 확인은 `Workspace.BRICKYARD`, `ReplicatedStorage.RoBattles.Remotes`를 기준으로 한다.
2. **Studio의 Avatar Type은 R6로 선택**한다. 프로젝트 JSON에는 R6 강제 설정이 없다. R15를 사용하면 SWORD 전용 애니메이션이 비활성화된다.
3. Output, Developer Console을 열고 서버/클라이언트 오류를 별도로 기록한다. UI mock이나 Luau CLI의 PASS로 Studio 완료를 대체하지 않는다.
4. 1클라이언트 기동 → 2~3클라이언트 Local Server → 가능할 때 12인으로 확대한다. 12명 Studio 동시 기동이 어렵다면 미검증으로 남긴다.

## P0 첫 실행 (순서대로)

| 차례 | 테스트 ID | 절차 | 합격 조건 | 상태 |
|---|---|---|---|---|
| 1 | S33 | 통합 프로젝트 첫 Play | BRICKYARD 1개 생성, 서버/클라이언트 오류 없음, Remote 생성 | 미실행 |
| 2 | S125~S126 | 입장 후 캐릭터 선택 전·후 확인 | 선택 전 메뉴, 선택 후 스폰·HP 110/95/100/105/100 | 미실행 |
| 3 | A1/A4/A5/A6 | SWORD로 이동·공격·스폰 직후 공격 | R6 모션, PreSimulation 포즈, 지연 리그 재시도, 임시 모션 폴백 | 미실행 |
| 4 | S136/A2/A3 | SWORD LMB 3타, 패링·Lunge·Storm 및 PAINTBALL Aim·충전 조작 | 서버 판정 유지, 모션 연결, 입력 오류 없음 | 미실행 |
| 5 | S36~S39/A7 | 전투에서 사망·리스폰 | 4초 부활, 2초 보호, HP 및 포즈 정리 | 미실행 |
| 6 | S127/S134 | 2명 입장, COUNTDOWN→ACTIVE→RESULTS | 5초 카운트다운, 7분 경기, 12초 결과, 결과 중 입력 차단 | 미실행 |
| 7 | S130/S128 | 실제 KO·낙사·동점 발생 | 서버 기준 킬 피드·KO 토스트·공동 순위 | 미실행 |
| 8 | S131~S133/P4/A9 | 공·폭탄·Bullseye·Storm 진행 중 경기 종료 | 다음 경기 오브젝트·모션·표식 잔존 없음 | 미실행 |
| 9 | S135/P6 | ACTIVE 중 새 플레이어 선택·스폰 | **중도 참가 가능**, 기록 혼합·리그 누수 없음 | 미실행 |
| 10 | P1~P3/P5 | 12인 혼합 전투 및 3경기 반복 | 입력/서버 안정, 프레임·메모리 큰 악화 없음 | 미실행 |

## 현재 설정·수치 대조표

- 캐릭터 HP: SWORD **110**, PAINTBALL **95**, SUPERBALL **100**, TIMEBOMB **105**, SLINGSHOT **100** (`src/shared/Data/Characters.luau`).
- PAINTBALL LMB: 피해 **7**, 탄창 **16**. 과거 Phase 1 문서의 피해 4/탄창 30은 현재 기준이 아니다.
- 경기: 최대 **12명**, 최소 **2명**, 카운트다운 **5초**, 경기 **420초**, 결과 **12초**, 참가자 1명 이하 **20초 유예** (`src/shared/Config.luau`).
- SWORD Blade Storm: **8 × 5 + 25**, 서버 틱 간격 기본 **0.3초**. 클라이언트 Loop는 Tick마다 만료를 연장하며, Studio에서 Tick 간격이 커지는 상황은 미검증.
- `MatchFlow:spawned()`는 ACTIVE 중에도 참가자로 등록하므로, 중도 선택·스폰 가능. 기존 S135 문구의 '다음 라운드 전 참가 불가'는 최신 구현과 모순되어 정정했다.

## 오류 기록

| ID | 실행 환경(Studio/Rojo, 인원) | PASS/FAIL/미검증 | 재현 절차 | Output / 스크린샷 |
|---|---|---|---|---|
| | | 미검증 | | |

**릴리스 차단:** 이 문서의 P0 실패 또는 미실행, 기존 계획의 핵심 S·A·P 실기 항목 미검증은 Alpha 1.0 릴리스 완료로 표시하지 않는다.

## ZIP에서 실행할 수 있는 검사

```sh
python3 tools/preflight_offline.py
# Luau 실행 파일을 별도로 확보한 경우:
python3 tools/preflight_offline.py --luau /path/to/luau --compiler /path/to/luau-compile
```

기본 모드는 기존 프로젝트·Remote 정적 검사와 현행/레거시 Python 시뮬레이션만 실행한다. Luau/Studio를 실행했다고 주장하지 않는다. Git 기록 없는 ZIP에서 `check_anim.py`의 변경 범위 검사는 미실행으로 표시한다.
