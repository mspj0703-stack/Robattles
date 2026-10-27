# UI 데이터 계약 및 서버 변경 제안

**서버/공유 계약 파일은 수정하지 않았다.** 아래의 기존 계약만 실제 연결돼 있다. 제안 확장은 Claude 전투/경기 담당자가 검토 후 제공해야 한다.

## 현재 연결된 계약

| 경로 | 용도 |
|---|---|
| `Remotes.State` | 본인 스냅샷. t, characterId, pendingCharacterId, alive, health.cur/max, canAct, cooldowns.primary/secondary.readyAt, dodge, ultimate, skills, ammo, protectedUntil 등 |
| `Remotes.Scoreboard` | `{id,name,kills,deaths}` 배열. 순위는 서버 배열 순서 그대로 |
| `Remotes.Feedback` / Swing | 본인 swingIndex를 최근 확정 콤보 타격 알림으로 표시; 지속 중 콤보 추정 아님 |
| Feedback / DuelistProc | 본인 bonus 발동 알림; 다음 발동 가능 시각이나 누적 히트 수를 추정하지 않음 |
| Feedback / Damaged | 실제 피해량으로 적중/피해 숫자 표시. killer/최종 타격으로 추정 금지 |
| Feedback / Died | playerId, time. 사망자 피드, 본인 부활 대기 |
| Feedback / Respawned | 본인 사망 상태 및 일시적 피드백 정리. 다음 State를 우선 |
| Feedback / Rejected | SelectCharacter 요청 거부 안내 |
| `Remotes.SelectCharacter` | `{characterId=id}`. 현재 RemoteSpec.validate로 허용된 SWORD/PAINTBALL만 요청 |
| `Remotes.SetRun` | UI 모달 진입 시 기존 달리기 해제 요청. 새 Remote 아님 |

사망 카운트다운 = 기존 서버 Died.time + Config.Match.RespawnSeconds(현재 4) − workspace:GetServerTimeNow(). 0 이하일 때 UI만으로 부활시키지 않는다. 스냅샷만 죽음 상태로 받았다면 시간을 발명하지 않고 서버 부활 정보 대기라고 표시한다.

원본은 SelectCharacter 성공 응답을 별도 전송하지 않는다. 요청 이후의 State에서 선택 예약/현재 캐릭터가 일치하는 것으로 UI 확인한다. 궁극기 게이지·사망 감쇠·캐릭터 교체 정책은 기존 UltimateService/CharacterController를 그대로 따른다.

## 제안 A — UI에서 이미 수용 가능한 선택적 확장 (서버 미구현)

새 Remote를 강제 생성하지 않고 기존 State에 선택적 ui 필드를 추가하는 방안이다. ui.version이 1일 때만 읽는다. 다음 예는 계약 예시이며 현재 게임의 값/진행 상태가 아니다.

```luau
ui = {
    version = 1,
    match = {
        phase = "Playing", -- Playing / Results; 다음 경기에서 Playing으로 전환
        endsAt = serverTimestamp, -- 서버 시계. 없으면 TIME —
        results = { -- Results에서 서버가 확정한 순서와 수치
            { id = userId, name = displayName, kills = koCount, deaths = deathCount },
        },
        nextStartsAt = serverTimestamp, -- 선택. 없으면 서버 안내 대기
    },
    characterState = { -- 현재 캐릭터에 해당하는 필드만, 없는 상태는 nil
        combo = confirmedComboStep,
        duelist = confirmedProgressText,
        lungeCharge = confirmedChargeText,
        colorReload = confirmedColorReloadText,
        activeBalls = confirmedCount,
        throwCharge = confirmedChargeText,
        cyclone = confirmedStateText,
        remoteCharges = confirmedCount,
        placedBombs = confirmedCount,
        chargedShot = confirmedChargeText,
        aimMode = confirmedStateText,
        bullseyeMark = confirmedMarkText,
    },
}
-- 숫자 스킬의 기존 skills[i] 확장:
skills[i] = { implemented = true, readyAt = serverTimestamp }
```

- 실제 순위 산정·승자·제한시간·경기 전환은 서버 담당 범위다. UI는 재정렬/점수 계산하지 않는다.
- 각 필드는 서버에서 확정된 원시 값 또는 짧은 표시 문자열만 공급한다. 효과 발생 여부를 UI가 역산하지 않는다.
- skills에 implemented=true만 있고 readyAt이 없으면 `상태 연동 대기`. 준비 완료로 추측하지 않는다.
- 실서비스 연동 전 matchId/lifeId/sequence 등을 계약에 포함하고 UI 수명 경계를 함께 검토할 것을 권장한다. 현재는 기존 t와 생명 이벤트 시각으로 정리한다.

## 제안 B — 추가 UI 연결 작업이 필요한 계약

다음 항목은 **현 UI에 연결됐다고 주장하지 않는다.** 서버 담당자와 계약을 확정한 후 UI 어댑터를 추가해야 한다.

1. `KillConfirmed`: eventId, attackerId/Name, victimId/Name, attackLabel, serverTime, matchId. 정확한 킬 피드와 처치자 화면에 필요하다. 환경 사망도 구분.
2. `respawnAt` / `spawnPhase` / `lifeId`: 스폰 재시도·지연·실패 사유 표시. 현재 4초는 최초 서버 스케줄 기준이며 실제 모델 로딩 완료를 보장하지 않는다.
3. 캐릭터별 최대 HP 및 5종 허용 목록: 현재 HP 100과 두 캐릭터만 지원한다. RemoteSpec 및 Characters 확장은 전투 담당자 소유.
4. 안정된 캐릭터/스킬 메타데이터: 표시 이름, 설명, 패시브와 스킬 지원 여부. 현재 Catalog의 미정 항목을 기획 확정본으로 교체해야 한다.
5. 궁극기/스킬/보조 공격의 disabledReason, charges/maxCharges, charge01 등 구조화된 상태. 현재 확장 슬롯은 숫자 스킬 readyAt만 지원하며 전체 충전 게이지 위젯은 추가 연결이 필요하다.
6. 서버 설정 영구 저장 및 Play 전 로비/관전 상태: 메뉴는 로컬 화면이며 서버 스폰/경기는 그대로 진행한다.

이 제안은 요청서다. 서버 코드·피해 판정·이동 검증·캐릭터 스킬·쿨타임 규칙을 UI 작업에서 재구현하지 않는다.
