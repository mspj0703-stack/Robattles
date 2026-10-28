# RoBattles! P2-B — 신규 효과음 에셋 적용 준비

## 현재 상태

- 게임은 여전히 P2-A의 `ReplicatedStorage.RoBattles.Assets.Sounds` 선택형 오버라이드 로더를 사용한다.
- P2-B에서는 11개 샘플 큐의 상대 음색/볼륨만 추가 조정했다.
- **WAV를 Roblox 자산으로 업로드하지 않았다. Roblox SoundId/권한을 확인하지 않았다.**
- 이 파일과 함께 전달되는 WAV는 비공식 원본 프로토타입이며 게임에 자동으로 삽입되지 않는다.

## 작업자 적용 절차

1. ZIP의 `audio_candidates/*.wav` 11종을 들어보고 채택/수정 여부를 결정한다.
2. Roblox Creator Dashboard 또는 적합한 승인된 도구를 이용해 본인/팀 소유 오디오 자산으로 게시하고 사용 권한을 확인한다.
3. 두 Rojo 프로젝트에 이미 선언된 `ReplicatedStorage > RoBattles > Assets > Sounds`에 각 큐 이름과 **정확히 동일한 이름의** `Sound` 객체를 배치한다. 예: `sword.slash`, `paint.fire`, `bomb.explosion`.
4. 각 `Sound.SoundId`에 *실제 게시된* `rbxassetid://<id>`를 설정한다. 임시/임의 ID는 넣지 않는다.
5. 적용할 소리가 없거나 유효하지 않으면 P2-A의 `EffectCatalog.Sounds` 기본 사운드로 폴백한다.
6. 소유권·볼륨·음량 과밀·12인 동시 재생·모바일 음향을 Studio에서 실제 확인한다.

## 구현 위험 및 제한

- 사운드 품질은 청취 테스트 전이며, 원본 WAV를 정식 효과음이라고 볼 수 없다.
- 오디오 업로드·검수·Roblox Studio 플레이는 이 작업에서 실행되지 않았다.
- 공격 타이밍, 판정, 스킬 이벤트 및 애니메이션은 변경되지 않는다.
- `Assets.Effects` 내부에 이미 포함된 Sound는 `EffectPlayer`의 별도 시각 에셋 경로에서 재생되므로 동시 재생 제한은 실기 재검증이 필요하다.
