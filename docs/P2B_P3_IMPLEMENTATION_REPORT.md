# RoBattles! P2-B(에셋 연결 준비) + P3(타격·KO HUD) 구현 보고

작성일: 2026-10-28
작업 기준: QA4 → P1-A/B/C/D → P2-A (`39ab7b9`)

## 완료된 코드 수정

1. `src/shared/Data/SfxProfiles.luau`: 11개 SFX 후보 cue별 상대 재생 속도·볼륨 미세 조정. 기존 가족별 믹싱·동시 재생 제한·SoundGroup·fallback 유지. 신규 자산 ID는 미지정.
2. `src/client/HudView.luau`: 실제 피해 연타 0.16초 묶음 표시(피해 총합+횟수), 들어온 피해 별도 표시, KO/HP 회복 강조 레이어, 라운드 경계 UI 초기화.
3. `src/client/UI/App.luau`: 서버 `Damaged`에서만 숫자 갱신, 자신이 받은 피해는 별도 표기, 서버 `KillConfirmed`의 라운드 필터를 통과한 KO만 배너로 표시. UI 토글 연동.
4. `src/client/Main.client.luau`: Swing/SwordSkill 명중 힌트는 선행 hitmarker 생성에 사용하지 않고, 서버 `Damaged`의 양수 금액만 hitmarker로 표시. 기존 피해 토스트 중복 제거.
5. `src/client/Logic/FeedbackModel.luau`: 자해 또는 0 이하 피해에 대한 hitmarker 억제. 외부에 전달되는 원래 DamageTaken/Swing 번역 구조는 유지.

## 변경하지 않은 코드

- `src/server` 전체, 캐릭터 수치/전투 판정, `EffectCatalog`, 기존 캐릭터 애니메이션, 원격 이벤트 형식, 경기 점수·KO 규칙.
- 기존 음원 override가 없는 경우 P2-A에서 사용하던 기본 사운드로 폴백.

## P2-B 업로드 필요

`audio_candidates`의 WAV 11종은 프로토타입으로, Roblox에 업로드되거나 게임 자산으로 등록된 것이 아님. 작업자는 적법한 계정/권한으로 업로드하고 `ReplicatedStorage.RoBattles.Assets.Sounds` 폴더에 cue와 정확히 같은 이름의 Sound를 배치해야 함. 세부 절차는 `P2B_AUDIO_ASSET_INSTALLATION.md` 참조.

## 검증

- 관련 Python + 신규 계약 테스트 **52/52 통과**.
- 기존 전체 Python 74건을 선별하지 않고 돌리면, P2-A 이전 소스와 `App`·`Main`의 완전 동일성을 강제하는 역사적 변경-범위 테스트 **6개 실패 / 68개 통과**. 이 실패는 새 P3 UI 변경을 예외에 포함하지 않는 과거 테스트 제약 때문. 새 P2B/P3 보호 계약은 서버/전투/애니메이션 파일의 실제 동일성을 검사함.
- `git diff --check`: 통과.
- Luau CLI 컴파일, Roblox Studio 실제 실행/렌더링/오디오·12인 실기: **미실행**.
- 새 구현을 Roblox에 게시하거나 GitHub에 푸시하지 않음.

## 권장 후속

정식 음원 권한/재생 검증(P2-B 배포 완성) → Studio에서 P3 HUD 위치·연타/KO 확인 → P4 전체 메뉴/UI 레이아웃 개편.
