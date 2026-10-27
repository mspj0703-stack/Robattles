# RoBattles! First Play UX v1.0 — GPT 오프라인 통합 인계

날짜: 2026-10-26 / 상태: **UI 소스 병합 및 Python 사전검사 완료, Luau·Studio 미검증**

## 기준과 소스
- 대상: `RoBattles_Alpha1_GPT_StudioReady_2026-10-26.zip` (a598bcb 보고 기반 + GPT Storm Tick 보정, StudioReady 문서 단계)
- 공급 UI 변경: `RoBattles_First_Play_UX_v1_2026-10-26.zip` (`6442b53` 기반 UI 증분, 로컬 구현 `68d136c`; Git push 없음)
- 이 결과물은 **오프라인 ZIP**이며 새 Git 커밋을 만들거나 GitHub에 올리지 않았다. 기존 `a598bcb` 정확한 Git SHA 상태와 동일하다는 보장은 하지 않는다.
- `reference_snapshot`은 최신 전체 소스가 아니므로 통째로 교체하지 않았다.

## 소스 변경 (정확히 5개)
- `src/client/HudView.luau`: WAITING/COUNTDOWN 비전투 안내.
- `src/client/UI/App.luau`: 첫 스냅샷 이전 PLAY 진입, 5개 캐릭터 카드 확대, 역할·난이도·소개, 서버 선택/스폰 중 중복 요청 방지, 프리뷰 폴백, 대기 인원 안내.
- `src/client/UI/Catalog.luau`: S5-R1 공식 수치/스킬은 기존 데이터 유지, 역할·난이도 안내만 추가.
- `src/client/UI/Preview.luau`: 프리뷰 생성 실패 시 정적 실루엣.
- `tests_ui/views.spec.luau`: 첫 플레이 UX mock 8개 테스트 추가 (실행하지 않음).

추가 문서: `docs/first-play/`에 명세, 원본 UI 인계서, 이 인계서. 서버, 전투 피해·판정, Remote, MatchFlow, 애니메이션, Main.client 변경 없음.

## 버전 충돌 처리
- UI ZIP의 `BASELINE_HASHES.json`과 현재 StudioReady 소스를 대조한 결과, 변경 5개 중 `Preview`만 원본 UI 기준 해시와 같았다. 나머지 4개는 서로 다른 후속 수정이 존재한다.
- 공급 ZIP의 기준을 **역패치로 정확히 복원한 뒤** 3-way 차이를 비교했으며, `App` 5개, `Catalog` 1개, UI 테스트 1개 충돌을 최신 통합 소스 보존을 전제로 수동 해결했다.
- 결과·설정 자동 복귀, 서버 matchId 킬피드 보류·KO 토스트, 최신 UI 상태, 5캐릭터 스킬/패시브 데이터, 기존 GUI 테스트를 보존했다.
- 최신 상세 화면의 63px 간격 스킬 레이아웃을 유지하고 소개 80px 오프셋을 추가했다(길게 스크롤 가능). 공급 UI의 기존 104px 간격을 그대로 복사하지 않았다.

## GPT 직접 실행한 검사
- ZIP 압축 구조 확인: PASS
- `python3 tools/preflight_offline.py`: rc 0 (`projects` PASS, `remotes` PASS, 현행 sim 27/27)
- 레거시 sim: 21/25, 기존 알려진 4건만 실패, 새 실패 없음 (runner 표기 `NO-NEW-FAILURES`)
- 변경 범위 바이트 검사: 기존 파일 5개만 변경, 나머지 원본 보존 PASS
- Git 없는 ZIP 기준 `check_anim` 변경 범위 검사: 미검증 (`.git` 부재로 검사 실행 시 종료 2)
- Luau 전체 회귀, GUI mock 8개 새 테스트, Luau 컴파일·분석: **NOT RUN** (luau, luau-compile 없음)
- Roblox Studio 렌더/서버/입력/실기 및 12인 성능: **NOT RUN**
- 공급 UI의 1,015 PASS는 공급 측 과거 소스 기준 CLI 보고이며, 이 병합본에서 실행한 수치로 간주하지 않는다.

## 잔여 문제 / 릴리스 차단
1. **P0 MatchFlow 취소 규칙 불일치:** 최신 대상 `src/server/MatchFlow.luau`에서 `lowPopulationEndsAt` 만료 시 `RESULTS`로 전환한다. S5-R1 UX 명세는 `WAITING` 즉시 복귀 + 취소 안내 배너(12초 정상 결과 없음)를 요구한다. 기존 서버 문제이므로 이번 UI 범위에서 바꾸지 않았다. 별도 서버 수정 및 회귀가 필요.
2. **P1 런타임 미검증:** Luau GUI mock 8개를 실제 실행해 UI 생성/선택/스폰 상태 전환을 확인해야 한다. 실제 Studio 16:9 및 작은 화면도 미검증.
3. SWORD 전용 애니메이션까지 포함된 기존 기준본은 유지. 나머지 4캐릭터 애니메이션의 Phase 1/2 개발은 별도 작업이며 이 ZIP에 포함된 것으로 간주하지 않는다.
4. R6 설정은 Studio에서 실제 확인 필요.

## 다음 작업
1. luau/luau-compile 준비 시 기존 `tools/run_match_checks.py` 및 `tools/run_ui_checks.py` 재실행, 특히 신규 UI mock 8개 확인.
2. 서버 경기 취소 경로를 기존 S5-R1 규칙에 맞게 별도 패치 + MatchFlow 회귀 테스트 추가.
3. SWORD 포함 5캐릭터 애니메이션 실제 소스 통합이 확보되면 파일별 차이 분석 후 병합.
4. Studio에서 PLAY→선택→출전, WAITING/COUNTDOWN/RESULTS/CANCELLED, 스폰 실패 재요청, 5개 카드, 640×360까지 확인.

## 패치 적용
`RoBattles_Alpha1_FirstPlayUX_GPT_delta_2026-10-26.patch`는 **이 StudioReady ZIP 버전 전용**. 대상 파일 해시가 다르면 중단하고 3-way 재검토하라. `git apply --check`를 우선 실행한 뒤 `git apply` 또는 ZIP 본문을 사용한다.
