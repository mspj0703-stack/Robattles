# UI/클라이언트 통합 메모 (별도 UI 작업 브랜치와 합칠 때 충돌 파악용)

기준: 이 저장소의 전투 체크포인트(브랜치 `phase2/combat`)가 서버·클라이언트 **데이터 계약**의 기준이다. UI 작업은 SWORD 까지만 있던 오래된 기준본이 아니라 이 계약을 따라야 한다. 모두 Studio 미검증.

## 1. 이번 Phase 2 에서 수정한 클라이언트/공유 파일 (충돌 가능 지점)
| 파일 | 변경 내용 |
|---|---|
| `src/client/Main.client.luau` | Aim 전송(AimSyncHz), 자동 연사, 충전 주무기 phase(Attack.phase), dash 이벤트의 permit/up 수용, State→`input:setCharacter(..., chargePrimary)` |
| `src/client/HudView.luau` | `setCrosshair` 호출 경로 유지(변경 없음에 가깝다). **HUD 모델이 늘린 필드는 HudModel 로 전달** |
| `src/client/Logic/HudModel.luau` | 스킬 상태 `sliding`, 충전형(`charges/maxCharges/placed`) 라벨, 궁극기 전조(windup) |
| `src/client/Logic/InputState.luau` | `setCharacter(id, hasAmmo, automatic, chargePrimary)`, 주무기 Press/Release, `autoFire`, `aimDue` |
| `src/client/Logic/EffectsModel.luau` | CharSkill 일반 큐, Ball*/Bomb* 이벤트 → 큐, `ballCue/ballPosition` |
| `src/client/Logic/MovementModel.luau` | `dashVelocity(..., permitKind, up)`, CharSkill dash 수용 |
| `src/client/Logic/Crosshairs.luau` | 캐릭터별 조준선 등록(SUPERBALL/TIMEBOMB/SLINGSHOT 추가) |
| `src/client/Logic/AimModel.luau`, `src/client/AimView.luau` | SLINGSHOT RMB Aim Mode 궤적(순수 계산 / Roblox 표시, 표시 전용·Studio 미검증) |
| `src/client/Logic/InputState.luau` | `setCharacter` 5번째 인자 `localAim`: RMB 를 서버로 보내지 않고 로컬 `AimMode` 효과만 발생 |
| `src/client/EffectPlayer.luau` | Beam 스타일, 볼/폭탄 보간·`ball.update` 재기준 |
| `src/shared/Data/EffectCatalog.luau` | 캐릭터별 큐·무기 규격 추가 |
| `src/shared/RemoteSpec.luau` | `Aim` 리모트, `Attack.phase`, `SelectCharacter` oneOf 확장 |

## 2. UI 가 의존해야 하는 서버 데이터 계약
- **HUD 스냅샷**(`State` 리모트, `CharacterController:getHudSnapshot`): `characterId, pendingCharacterId, alive, health{cur,max}, cooldowns{primary,secondary}, dodge, ultimate{gauge,max,active,implemented,name,windupUntil?}, skills[1..3]{implemented,name,readyAt,total,state?,charges?,maxCharges?,placed?}, passive{id,lockedUntil}, ammo?, extra?`. 캐릭터별 `extra`: SUPERBALL `balls/ballCap/chargeFrac/cycloneUntil`, TIMEBOMB `placed/maxPlaced/charges/bombs`, SLINGSHOT `chargeFrac/marks[{targetId,untilT}]`.
- **캐릭터 선택**: `SelectCharacter{characterId}` — 허용 id 는 `RemoteSpec` 의 oneOf 가 유일한 목록(현재 SWORD, PAINTBALL, SUPERBALL, TIMEBOMB, SLINGSHOT). 테스트 전용 `GUNNER` 는 실제 데이터/스키마에 없다(`tests/Helpers.legacyChars` 에서만 생성).
- **입력 프로토콜**: `Attack{action, phase?}`(phase 는 충전형 LMB 의 Press/Release), `Skill{slot, phase?}`(SWORD Lunge, TIMEBOMB Remote Bomb 의 Press/Release), `Aim`(시전 중 조준 갱신).
- **서버→클라이언트 연출 이벤트**: `CharSkill{cue,...}`(카탈로그에 있는 cue 만 재생), `Ball*`(SUPERBALL), `Bomb*`(TIMEBOMB), `Spawned/Ended/Explosion`(투사체), 이동 동반 시 `dash{speed,duration,permit,up?}`.
- 캐릭터 선택 UI/HUD 를 새로 만들 때는 위 목록과 `shared/Data/Characters` 의 `displayName/maxHealth/primary/secondary/skills/ultimate/passive` 만 읽으면 된다(서버 모듈 내부를 참조하지 않는다).

## 2. 5캐릭터 통합 상태표 (기준 커밋: 이 문서가 들어간 체크포인트)
CLI = 순수 로직/가짜 월드 테스트 통과. Studio = 한 번도 실행하지 않았으므로 **모든 행의 실제 플레이 가능 여부는 미검증**.

| 캐릭터 | HP | LMB | RMB | 스킬 1 / 2 / 3 | 궁극기 | 패시브 | CLI | Studio |
|---|---|---|---|---|---|---|---|---|
| SWORD | 110 | 3타 콤보 | Parry | Triple Slash / Lunge(충전) / Blade Wave | Blade Storm | Duelist | 통과 | 미검증 |
| PAINTBALL | 95 | 자동 연사(탄약) | Paint Burst | Color Bomb / Piercing Shot / Paint Slide | Color Break(빔) | Color Reload | 통과 | 미검증 |
| SUPERBALL | 100 | 충전 던지기(Super Throw) | Bounce Dash(이동기) | Rapid Bounce / Scatter Ball / Recall | Ball Cyclone | Trick Master | 통과 | 미검증 |
| TIMEBOMB | 105 | Timed Bomb | Blast Guard | Cluster / Remote Bomb(누르기) / Blast Jump | Big Bang | Chain Reaction | 통과 | 미검증 |
| SLINGSHOT | 100 | 충전 샷 | Aim Mode(클라 전용) | Triple / Snare / Backstep | Bullseye | Bullseye Mark | 통과 | 미검증 |

HUD `extra`: SUPERBALL `balls/ballCap/chargeFrac/cycloneUntil`, TIMEBOMB `placed/maxPlaced/charges/bombs`, SLINGSHOT `chargeFrac/marks`. 모든 캐릭터는 `skills[1..3].implemented=true`, `ultimate.implemented=true`, `passive.id` 를 가진다(테스트로 확인).

## 3. 통합 안정화 검증 요약 (tests/Integration5.spec.luau, CLI)
- 5캐릭터 HP·선택 목록(RemoteSpec) 일치, 25가지 전환(X→Y) 후 HP·캐릭터·HUD 가 새 캐릭터 기준, 선택은 다음 리스폰부터.
- 키트 전체를 누른 직후 사망/퇴장/전환: 충전형 지연 Release 거부(부활 보호·쿨타임 불변), 감속·궁극기 활성·충전 표시 잔존 없음, 60초 뒤 투사체·볼·폭탄 0.
- 12인 혼합 시나리오(40초 시뮬, 5캐릭터 키트 반복 + 사망/전환/리스폰 6라운드): 이벤트 약 2000건(초당 약 51), 최대 동시 투사체 6·폭탄 8·볼 33, 상한 내, 오류 없음. 이 수치는 **서버 로직의 이벤트 수**이며 네트워크 대역폭·프레임·실제 렌더 부하는 측정하지 않았다(Studio 미검증).

## 4. 다른 브랜치와의 충돌 예상 지점
이번 통합 단계(체크포인트)에서 바꾼 파일: `tests/Integration5.spec.luau`(신규), `tests/run_all.luau`, `docs/*`. 전투/클라이언트 소스는 이 단계에서 수정하지 않았다. 그 앞 Phase 2 단계까지 합치면:
| 브랜치 | 충돌 가능 파일 | 메모 |
|---|---|---|
| UI (GPT Work) | `Main.client.luau`, `HudView.luau`, `Logic/HudModel.luau`, `Logic/InputState.luau`, `Logic/Crosshairs.luau`, `SettingsView.luau` | 위 1절 계약을 따를 것. `InputState.setCharacter` 인자는 5개(`..., chargePrimary, localAim`). `localEffect` 종류에 `AimMode` 추가 |
| 애니메이션 (`phase2/animation`) | `Main.client.luau`(Feedback 수신부), `EffectPlayer.luau`, `Logic/EffectsModel.luau`, `Data/EffectCatalog.luau` | 기준본은 d154560(SLINGSHOT 이전). 합칠 때 `EffectsModel.PROJECTILE_CUES`/`EffectCatalog.Cues` 에 sling.* 가 추가돼 있음 |
| 경기 진행 | `Main.server.luau`, `CharacterController.luau`(respawn/handleDeath 경로), `RemoteSpec.luau` | 캐릭터 선택은 다음 리스폰부터 적용되는 규칙 유지. `SelectCharacter` oneOf 가 유일한 선택 목록 |

## Alpha 1.0 통합 상태 (최신)
UI 는 `src/client/UI/*`(App/State/Catalog/Components/Preview/Tokens)로 통합되었고 `Main.client` 는 단일 `RoBattlesUI` ScreenGui 만 만든다.
상세 연결·충돌 해결·남은 결함은 `docs/INTEGRATION_ALPHA1.md`, 원본 GPT 문서는 `docs/ui-gpt/` 에 보존했다. 위 이전 설명과 충돌하면 통합 문서가 우선한다.
