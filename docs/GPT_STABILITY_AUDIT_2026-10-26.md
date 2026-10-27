# RoBattles! Alpha 1.0 — GPT 안정화 점검 (2026-10-26)

## 기준
- 기준 ZIP: `RoBattles_Alpha1_MatchCancel_GPT_integrated_2026-10-26.zip` (Git 이력 없는 오프라인 통합본)
- 이번 산출물: 원본 ZIP + 증분 수정. 원격 GitHub 브랜치와 자동 동기화되지 않음.
- 기획·전투 수치·Remote 계약 및 R6/R15 지원 범위 변경 없음.

## 변경 내용
1. `src/client/Logic/MatchResetModel.luau`: 경기 취소 직후 10Hz State 스냅샷이 WAITING을 건너뛰어, ACTIVE → COUNTDOWN(동일 matchId)로 보이는 경우 애니메이션 1회 초기화. 원래 RESULTS, ACTIVE → WAITING 취소, matchId 변경 감지는 유지.
2. `tests/AnimFiveChars.spec.luau`: 스냅샷 생략 상황에서 5캐릭터 상태기계의 이전 경기 잔존 모션 초기화와 중복 초기화 방지 시나리오 추가. **작성했으나 Luau 실행기를 확보하지 못하여 미실행**.
3. `tools/check_requires.py`: `require(script.Parent...)` 정적 참조, `Link.shared("...")`, `mapFolder:WaitForChild` 참조에 대응하는 파일 존재 검사. 소스의 정적 구조만 검증(실제 Roblox require/실행 성공을 보증하지 않음).
4. `tests_py/test_check_requires.py`: 검사기 양성/음성 검증 4건.
5. `tools/preflight_offline.py`: 새 requires 검사와 자체 테스트를 ZIP 사전점검에 포함.

## 직접 실행
- `tools/check_projects.py`: PASS
- `tools/check_remotes.py`: PASS
- `tools/check_requires.py`: PASS (로컬 154·공유 68·맵 4개의 정적 참조 대상 존재). 기타/dynamic require 3곳은 검증 범위 밖.
- `python3 -m unittest discover -s tests_py`: **4/4 PASS**
- `tools/run_sim.py current`: **27/27 PASS**. 이 Python 시뮬레이션은 MatchResetModel/Roblox 엔진을 실행하지 않음.
- `tools/run_sim.py legacy`: **21/25**, 과거 기준값에 따른 알려진 실패 4건, 신규 실패 없음.
- `tools/preflight_offline.py`: SOURCE PREFLIGHT PASS. Luau/Studio 제외한 검사만 의미.

## 미실행 / 제한
- Luau `AnimFiveChars.spec`의 추가 테스트와 기존 919+ 기타 Luau 테스트: 실행기 미확보로 미실행.
- Luau 컴파일·정적 분석: 미실행.
- Roblox Studio R6 포즈·재접속·경기 전환·12인 성능: 미실행.
- 체크 코드는 require 대상 **파일 존재만** 확인하고 동적 require 또는 모듈 반환값은 실행하지 않음.

## 다음 우선순위
1. Luau CLI를 사용할 수 있는 환경에서 전체 전투/경기/UI/애니메이션 회귀 및 신규 스냅샷 생략 테스트 실행.
2. Studio 2인으로 경기 취소 전후 UI·모션 초기화 및 재시작 테스트.
3. 5캐릭터 R6 모션, 12인 성능·반복 경기 확인.
4. 회복 시스템은 기획방 확정 후 별도 브랜치/패치로 반영.
