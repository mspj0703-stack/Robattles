# RoBattles! P1-E 검증 + P2-A 사운드 라우팅 구현 보고

- 작업 기준: QA4 `39c42fc` → P1-A `9585841` → P1-B `3c75e36` → P1-C `4fe2575` → P1-D `a69519a` → P2-A (로컬 커밋 참조)
- GitHub 원격 반영 없음. Roblox Studio / Luau CLI 실행 없음.

## 1. P1-E 결과

- P1-D 기준 Python 소스 테스트 **40/40 통과**.
- 프로젝트 / require / Remote 매핑 검사 통과.
- 전투 시뮬레이션(현재 데이터) **27/27 통과**.
- Phase 1 레거시 시뮬레이션의 **기존 실패 4개 유지**, 새 실패 0개.
- 확인하지 못한 사항: 실제 화면 출력, 파티클 에셋 권한, Luau 컴파일·실행, 12인 플레이 FPS, 모바일 음향·렌더링. 이 상태는 P1-E 전체 완료가 아니라 **정적 검증 완료/실기 검증 대기**.

## 2. P2-A 소스 변경 (기본 SFX 라우팅)

- `src/shared/Data/SfxProfiles.luau` 신규: SWORD / PAINTBALL / SUPERBALL / TIMEBOMB / SLINGSHOT / 일반 명중별 PlaybackSpeed·볼륨·가청 거리·동시 소리 제한 정책.
- `src/client/EffectPlayer.luau` 수정: 큐 이름을 기존 카탈로그 사운드 재생에 전달, 전용 Sound 객체 교체 경로, 에셋 누락 시 기존 ID fallback, `RoBattlesSFX` 볼륨 그룹 유지.
- 같은 종류의 사운드가 군중 전투에서 지나치게 겹치는 것을 완화하고 동시 재생 음성을 최대 18개 수준으로 제한. 자신의 연출은 우선하되 기존 음성 하나를 교체.
- 경기 전환 `clear()`에서 P2-A로 생성한 미완료 소리 정리.
- `default.project.json`/`integrated.project.json`에 선택적 `ReplicatedStorage.RoBattles.Assets.Sounds` 폴더 마운트 추가.
- 스킬 판정·피해·쿨타임·모션·Remote 이벤트 및 기존 카탈로그 cue 정의는 변경하지 않음.

## 3. 선택적 새 음원 샘플

- `sfx_prototypes/` WAV 파일 11개: 독립적으로 합성한 짧은 프로토타입 음원.
- 아직 Roblox Audio 자산으로 게시된 것이 **아님**. 프로토타입을 SoundId로 자동 변환·업로드하지 않았음.
- Roblox Studio 또는 제작 담당자가 오디오를 업로드하고 `Assets.Sounds` 폴더에 이름을 cue와 일치시키는 `Sound` 객체를 두어야 실제 게임에서 사용됨. 이 전까지 기존 Roblox 기본 SFX가 재생되며, PlaybackSpeed/볼륨은 새 설정이 적용될 수 있음.
- `Assets.Effects` 오버라이드 모델 내부에 이미 넣어진 Sound는 기존 P1-D 경로를 이용하므로 P2-A 기본 사운드 재생 제한과는 별개임. 이 경우 런타임 중복/음량은 추후 실기로 검증할 것.

## 4. 검사

- P2-A Python 소스/계약 검사: **47/47 통과**.
- 전투 시뮬레이션(현재): **27/27 통과**.
- 프로젝트·Remote·require·git diff --check: **통과**.
- 레거시 시뮬레이션: 알려진 기존 실패 4개 유지.
- Luau parser/compiler/analyzer, Studio 실기, 실시간 음향 테스트: **미실행**.
- 파일 비교상 기존 서버·전투 데이터·애니메이션 소스는 P1-D와 동일.

## 5. 적용

- 전체 ZIP은 QA4→P1-A~D→P2-A 누적본.
- Git patch는 **P1-D `a69519a`** 위에만 적용. Git 번들은 누적 이력을 포함. 현재 GitHub main에 반영하거나 force push하지 말 것.
- Audio WAV는 미리듣기용이며 게임 실행에 자동으로 포함되지 않음.

## 6. 다음

- P1-E 실기 테스트(별도 Studio 환경) → P2-B 정식 사운드 자산 선정·업로드 → 모바일/12인 음량 밸런스 → P3 명중 및 KO UI.
