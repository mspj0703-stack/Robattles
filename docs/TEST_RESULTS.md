# 자동 테스트 결과 (Luau CLI, 순수 로직)

실행 시각: 2026-10-25 14:33
종료 코드: 0

```
PASS  Config: 확정 규칙 > 이동 속도 17/23, 1단 점프
PASS  Config: 확정 규칙 > 회피 2회·충전 5초·무적 0.15초·공중 허용
PASS  Config: 확정 규칙 > 키 설정: Ctrl 달리기 / Shift 회피 / F 궁극기
PASS  Config: 확정 규칙 > 피격 무적 없음·기본 공격 경직 없음·원거리 조준 보정 없음
PASS  Config: 확정 규칙 > 궁극기 게이지 0~100, 자발적 취소 불가
PASS  Config: 확정 규칙 > 카메라 초기 모드와 전환키는 설정값으로 존재
PASS  Config: 확정 규칙 > 12인 매치
PASS  Schema > number: NaN/inf/범위/정수 검사
PASS  Schema > object: 알 수 없는 필드와 누락 필드 거부
PASS  Schema > optional
PASS  Schema > vector3: 단위 벡터·NaN 검사
PASS  Schema > string 길이 제한 / oneOf
PASS  Schema > array: 길이 제한과 비배열 거부
PASS  RemoteSpec: 비정상 RemoteEvent 입력 거부 > 정상 Attack 페이로드 통과
PASS  RemoteSpec: 비정상 RemoteEvent 입력 거부 > 피해량을 실어 보내면 거부 (알 수 없는 필드)
PASS  RemoteSpec: 비정상 RemoteEvent 입력 거부 > 명중 대상을 실어 보내면 거부
PASS  RemoteSpec: 비정상 RemoteEvent 입력 거부 > 알 수 없는 action 거부
PASS  RemoteSpec: 비정상 RemoteEvent 입력 거부 > NaN / inf 방향·원점 거부
PASS  RemoteSpec: 비정상 RemoteEvent 입력 거부 > 단위 벡터가 아닌 방향 거부
PASS  RemoteSpec: 비정상 RemoteEvent 입력 거부 > 잘못된 타입 / nil / 알 수 없는 리모트 거부
PASS  RemoteSpec: 비정상 RemoteEvent 입력 거부 > 정상 Dodge / SetRun / Reload / Ultimate 통과
PASS  ProjectileSpec > 템플릿 통과: Linear
PASS  ProjectileSpec > 템플릿 통과: Arc
PASS  ProjectileSpec > 템플릿 통과: Bounce
PASS  ProjectileSpec > 템플릿 통과: Pierce
PASS  ProjectileSpec > 템플릿 통과: Explosion
PASS  ProjectileSpec > 템플릿 통과: Beam
PASS  ProjectileSpec > 템플릿 통과: Placed
PASS  ProjectileSpec > PAINTBALL 투사체 데이터 통과
PASS  ProjectileSpec > Hitscan은 allowHitscan 없이 거부, 명시하면 허용(확장 지점)
PASS  ProjectileSpec > Linear + gravity 거부 / Arc gravity 0 거부
PASS  ProjectileSpec > 타입별 필수 블록 누락 거부
PASS  ProjectileSpec > 타입에 맞지 않는 블록 거부
PASS  ProjectileSpec > 수명 0·음수 속도·NaN 거부
PASS  ProjectileSpec > Ray는 radius 0, Spherecast는 radius>0
PASS  ProjectileSpec > Beam은 사망 시 종료, Placed는 사망 후 유지 (확정 규칙 반영)
PASS  Keybinds > 기본 바인딩: 확정 키
PASS  Keybinds > 카메라 전환키를 다른 키로 변경 가능
PASS  Keybinds > 중복 키 / 알 수 없는 액션 / 잘못된 키 이름 거부
PASS  CooldownService > 쿨타임 중 재사용 거부, 끝나면 허용
PASS  CooldownService > 남은 시간 계산
PASS  CooldownService > 키·엔티티별 독립
PASS  CooldownService > 잘못된 duration(NaN/음수) 거부
PASS  CooldownService > clearEntity로 초기화
PASS  CooldownService > 요청 빈도 제한: 초당 30회 초과 시 거부, 1초 뒤 회복
PASS  DodgeService > 최대 2회, 3회째는 충전 없음
PASS  DodgeService > 충전은 5초마다 1회씩 순차 회복
PASS  DodgeService > 0.15초 무적: 시작 직후만
PASS  DodgeService > 회피 지속 중 중복 회피 거부
PASS  DodgeService > 공중 회피 허용(확정), 설정으로 끄면 거부
PASS  DodgeService > 행동 불가 상태에서는 회피 불가
PASS  DodgeService > 미등록 엔티티 거부 / reset은 충전 복구
PASS  StatusEffectService > 둔화: 가장 강한 하나만, 만료 후 복구
PASS  StatusEffectService > 위치 노출(Reveal)
PASS  StatusEffectService > 기본 공격은 경직 불가, 강한 공격만 경직
PASS  StatusEffectService > 연속 경직 저항: 지속시간 절반씩 감소, 창 밖이면 초기화
PASS  StatusEffectService > 기절: 상한 1.5초, 종료 후 면역
PASS  StatusEffectService > 넉백 속도 계산 / 잘못된 방향 거부
PASS  StatusEffectService > 잘못된 효과·NaN 지속시간·잘못된 배율 거부
PASS  StatusEffectService > clear로 모든 상태 해제
PASS  StatusEffectService 둔화 규칙 회귀 (확정 기획) > 동시 둔화는 가장 강한 하나만: 합산·곱셈 없음
PASS  StatusEffectService 둔화 규칙 회귀 (확정 기획) > 가장 강한 둔화 종료 후 남은 둔화가 승계
PASS  StatusEffectService 둔화 규칙 회귀 (확정 기획) > 강한 둔화가 있어도 슬롯이 가득 차면 가장 먼저 끝나는 약한 둔화부터 제거
PASS  StatusEffectService 둔화 규칙 회귀 (확정 기획) > 둔화 중에도 기본 공격 경직 없음, 행동 가능, 속도는 0이 되지 않음
PASS  StatusEffectService 둔화 규칙 회귀 (확정 기획) > 둔화 적용 자체는 경직을 만들지 않음
PASS  DamageService > 기본 피해 적용과 체력 감소
PASS  DamageService > 일반 피격 무적 없음: 서로 다른 공격은 연속 적중
PASS  DamageService > 동일 attackId 중복 피해 방지
PASS  DamageService > rehitInterval이 있으면 간격 후 재적중 허용
PASS  DamageService > 회피 무적 중 피해 무효, 무적 종료 후 적중 가능(기록 안 남음)
PASS  DamageService > 사망한 대상 / 미등록 대상 / 자기 피해 거부
PASS  DamageService > 비정상 피해량(NaN/음수/0/inf) 거부, 과도한 값은 상한으로 제한
PASS  DamageService > 잘못된 요청 구조 거부
PASS  DamageService > 동일 공격자 연쇄 폭발 감쇠 (×0.5, 최소 ×0.25)
PASS  DamageService > 다른 공격자의 폭발은 감쇠 영향 없음, 윈도우 경과 시 초기화
PASS  DamageService > 처치 이벤트와 체력 0 고정
PASS  DamageService > 피해 적용 시 상태이상 동시 적용 (강한 공격만 경직)
PASS  DamageService > prune: 오래된 중복 기록 정리 후 같은 attackId 재사용 가능
PASS  DamageService > respawn: 체력 복구 후 다시 피해 가능
PASS  HitboxService > 조준 원점 검증: 서버 위치와 멀면 거부
PASS  HitboxService > 근접 사거리: 범위 안 통과, 허용 오차 밖 거부 (공격 거리 검증)
PASS  HitboxService > 부채꼴: 뒤쪽·옆 대상 거부
PASS  HitboxService > 대상 선택: 자기 자신·사망자 제외, 거리순, maxTargets, 벽 차단
PASS  HitboxService > 범위 폭발: 반지름 안만 포함, 거리순, 벽 차단
PASS  HitboxService > 폭발 피해 배율: 중심 1.0, 가장자리 falloffMin, 밖 0
PASS  HitboxService > 원거리는 조준 보정 없음 (입력 방향 그대로)
PASS  HitboxService > 근접 방향 보정: 약하게 회전, 콘 밖이면 그대로
PASS  UltimateService > 피해·처치·시간으로 충전, 100에서 고정
PASS  UltimateService > 게이지 100 미만이면 발동 불가
PASS  UltimateService > 발동 시 게이지 소모, 중복 발동 거부, 발동 중 충전 없음
PASS  UltimateService > 자발적 취소 불가
PASS  UltimateService > 행동 불가 상태에서는 발동 불가
PASS  UltimateService > 사망 시 연결된 지속 공격만 종료, 비연결 오브젝트는 유지
PASS  UltimateService > 외부 강제 중단 / 정상 종료
PASS  UltimateService > respawn 후 다시 충전 가능
PASS  UltimateService 게이지 규칙 회귀 (확정 기획) > 사망해도 게이지 유지
PASS  UltimateService 게이지 규칙 회귀 (확정 기획) > 같은 캐릭터로 부활하면 기존 게이지 그대로
PASS  UltimateService 게이지 규칙 회귀 (확정 기획) > 캐릭터 변경: 리스폰 전에는 적용 안 됨, 리스폰 시 min(게이지,40) 이월
PASS  UltimateService 게이지 규칙 회귀 (확정 기획) > 게이지가 40 미만이면 변경해도 그대로 이월
PASS  UltimateService 게이지 규칙 회귀 (확정 기획) > 변경 후 원래 캐릭터로 되돌리면 대기 취소: 이월 제한 없음
PASS  UltimateService 게이지 규칙 회귀 (확정 기획) > 정상 사용 시 게이지 100% 소모
PASS  UltimateService 게이지 규칙 회귀 (확정 기획) > 새 경기 시작 시 게이지 초기화, 대기 캐릭터는 이월 없이 적용
PASS  UltimateService 게이지 규칙 회귀 (확정 기획) > 사망 중에는 충전하지 않고 게이지는 유지
PASS  RemoteGate (서버 진입 검증) > 정상 요청 통과
PASS  RemoteGate (서버 진입 검증) > 피해량·명중 대상 필드가 있으면 거부
PASS  RemoteGate (서버 진입 검증) > 알 수 없는 리모트 / 쓰레기 페이로드 거부
PASS  RemoteGate (서버 진입 검증) > 과도한 요청 빈도 거부
PASS  RemoteGate (서버 진입 검증) > 사망/캐릭터 없음 거부
PASS  RemoteGate (서버 진입 검증) > 시각 편차·조준 원점 위조 거부
PASS  RemoteGate (서버 진입 검증) > 재장전은 탄약이 있는 캐릭터만
PASS  CombatCore 통합 > 12인 동시 공격: 모두 적중, 처치 1회, 마지막 일격이 처치 인정
PASS  CombatCore 통합 > 서로 동시에 공격(난전): 각자 독립적으로 피해
PASS  CombatCore 통합 > 피해와 처치가 궁극기 게이지를 충전, 피해자는 사망 시 초기화
PASS  CombatCore 통합 > 사망 시 연결된 궁극기 효과 종료·상태이상 해제
PASS  CombatCore 통합 > 회피 무적 중 12인 동시 공격도 무효, 무적 직후엔 적중
PASS  CombatCore 통합 > respawn: 체력·회피·궁극기·쿨타임 초기화
PASS  CombatCore 통합 > removePlayer 후 피해 요청은 unknown_target
PASS  CombatCore: 궁극기 상태 관리 회귀 (확정 기획) > 사망·같은 캐릭터 리스폰에서 게이지 유지
PASS  CombatCore: 궁극기 상태 관리 회귀 (확정 기획) > 새 경기 시작(resetMatch): 게이지·체력·회피·쿨타임 전부 초기화
PASS  ProjectileService: 직선(Linear) > 직선 투사체가 실제로 이동해 명중, 서버가 피해 적용
PASS  ProjectileService: 직선(Linear) > 빗나가면 수명 종료로 자연 소멸
PASS  ProjectileService: 직선(Linear) > maxRange 도달 시 소멸
PASS  ProjectileService: 직선(Linear) > 벽에 막히면 뒤의 대상은 피해 없음 (투사체 벽 충돌)
PASS  ProjectileService: 직선(Linear) > 초고속 투사체도 터널링 없이 얇은 벽/대상 판정 (스윕)
PASS  ProjectileService: 직선(Linear) > 소유자는 자기 투사체에 맞지 않음
PASS  ProjectileService: 직선(Linear) > 회피 무적 중인 대상은 통과하고 뒤의 대상을 맞춤
PASS  ProjectileService: 포물선(Arc) > 중력으로 낙하: t=0.5s 에서 y≈-9, z≈35
PASS  ProjectileService: 포물선(Arc) > 낙하 경로 위의 대상 명중 / 바닥에 닿으면 소멸
PASS  ProjectileService: 반사(Bounce) > 벽에 반사된 뒤 대상 명중, 반사당 피해 배율 적용
PASS  ProjectileService: 반사(Bounce) > 최대 반사 횟수 이후 소멸
PASS  ProjectileService: 관통(Pierce) > maxHits까지만 관통, 대상당 1회만 피해
PASS  ProjectileService: 관통(Pierce) > 재적중 간격이 있으면 같은 대상을 간격 후 다시 맞출 수 있음
PASS  ProjectileService: 범위 폭발(Explosion) > 즉시 폭발: 거리 감쇠, 반경 밖 무피해, 소유자 제외
PASS  ProjectileService: 범위 폭발(Explosion) > 벽 뒤 대상은 폭발 피해 없음
PASS  ProjectileService: 범위 폭발(Explosion) > 폭발 넉백 속도가 이벤트로 전달됨
PASS  ProjectileService: 범위 폭발(Explosion) > friendlyOwnerDamage=true면 소유자도 피해
PASS  ProjectileService: 범위 폭발(Explosion) > 같은 폭발이 같은 대상에 두 번 피해를 주지 않음
PASS  ProjectileService: 지속형 빔(Beam) > 틱 간격마다 피해(재적중 0.25초), 시작 즉시 1틱
PASS  ProjectileService: 지속형 빔(Beam) > 소유자 사망 시 빔 종료, 이후 피해 없음
PASS  ProjectileService: 지속형 빔(Beam) > 벽에서 빔 길이 절단
PASS  ProjectileService: 지속형 빔(Beam) > 소유자 자세를 따라감
PASS  ProjectileService: 설치형 폭탄(Placed) > 퓨즈 시간 후 폭발
PASS  ProjectileService: 설치형 폭탄(Placed) > 장전 전 기폭 불가, 장전 후 가능
PASS  ProjectileService: 설치형 폭탄(Placed) > 소유자가 사망해도 남은 수명 동안 유지되고 자연 폭발 (피해 귀속은 소유자)
PASS  ProjectileService: 설치형 폭탄(Placed) > survivesOwnerDeath=false 설치물은 사망 시 폭발 없이 제거
PASS  ProjectileService: 설치형 폭탄(Placed) > 동일 소유자의 연쇄 폭발은 감쇠 (×1, ×0.5, ×0.25)
PASS  ProjectileService: 설치형 폭탄(Placed) > 발사 후 원본 데이터가 바뀌어도 스냅샷으로 동작 (부활·캐릭터 변경 후 오참조 방지)
PASS  ProjectileService: 히트스캔(선택 구조) > allowHitscan=true 개별 공격은 즉시 판정
PASS  ProjectileService: 히트스캔(선택 구조) > 히트스캔도 벽에 막힘
PASS  ProjectileService: 히트스캔(선택 구조) > allowHitscan 없이는 거부 (기본은 히트스캔 아님)
PASS  ProjectileService: 소유자 생애·제한·입력 검증 > 발사자 사망 후에도 이미 날아간 투사체는 명중 (피해 귀속 유지)
PASS  ProjectileService: 소유자 생애·제한·입력 검증 > 플레이어 퇴장 후에도 투사체는 남은 수명 동안 유지
PASS  ProjectileService: 소유자 생애·제한·입력 검증 > 소유자당 활성 투사체 상한
PASS  ProjectileService: 소유자 생애·제한·입력 검증 > 잘못된 spawn 입력 거부
PASS  ProjectileService: 소유자 생애·제한·입력 검증 > 12인 동시 발사: 같은 순간 11발 명중, 처치 1회, 중복 피해 없음
PASS  CharacterController: SWORD > 전방 부채꼴 대상만 피해, 뒤쪽·사거리 밖 제외 (공격 거리 검증)
PASS  CharacterController: SWORD > 쿨타임 0.55초: 도중 재공격 거부, 이후 허용
PASS  CharacterController: SWORD > 기본 공격은 경직 없음, 피격자는 계속 행동 가능
PASS  CharacterController: SWORD > 벽 뒤 대상은 근접 공격 불가
PASS  CharacterController: SWORD > 여러 대상 동시 적중, 사망자 제외
PASS  CharacterController: SWORD > 패들볼 캐릭터는 보조 공격 없음
PASS  CharacterController: PAINTBALL (자동 연사·탄약·재장전) > 연사 간격 0.12초 제한, 탄약 소모
PASS  CharacterController: PAINTBALL (자동 연사·탄약·재장전) > 탄약 0이면 자동 재장전 시작, 장전 중 발사 불가, 1.8초 후 가득
PASS  CharacterController: PAINTBALL (자동 연사·탄약·재장전) > 수동 재장전: 가득이면 거부, 일부 소모 시 허용
PASS  CharacterController: PAINTBALL (자동 연사·탄약·재장전) > SWORD는 재장전 불가
PASS  CharacterController: PAINTBALL (자동 연사·탄약·재장전) > 투사체가 날아가 명중, 서버가 피해(4) 계산
PASS  CharacterController: PAINTBALL (자동 연사·탄약·재장전) > 원거리 자동 조준 보정 없음: 15도 빗나간 조준은 명중하지 않음
PASS  CharacterController: PAINTBALL (자동 연사·탄약·재장전) > 발사 후 사망해도 이미 발사한 투사체는 유지되어 명중, 장전은 취소
PASS  CharacterController: 이동·회피·궁극기·캐릭터 변경 > 이동 속도: 걷기 17 / 달리기 23 / 둔화·공격 보정
PASS  CharacterController: 이동·회피·궁극기·캐릭터 변경 > 회피 2회, 3회째 거부, 회피 중 무적으로 피해 무효, 공중 회피 허용
PASS  CharacterController: 이동·회피·궁극기·캐릭터 변경 > 사망 후에는 회피·공격·재장전 불가
PASS  CharacterController: 이동·회피·궁극기·캐릭터 변경 > 궁극기: 게이지 부족 거부, 가득이면 발동·100% 소모
PASS  CharacterController: 이동·회피·궁극기·캐릭터 변경 > 캐릭터 변경은 다음 리스폰부터, 게이지 min(기존, 40) 이월, 같은 캐릭터면 유지
PASS  CharacterController: 이동·회피·궁극기·캐릭터 변경 > 환경 사망(낙사)도 동일 경로로 처리, 궁극기 충전 없음
PASS  CharacterController: 이동·회피·궁극기·캐릭터 변경 > 12인 동시 근접 공격: 피해자 p1의 처치는 정확히 1회, 체력 0 고정
PASS  ServerRouter: 비정상 RemoteEvent 요청 거부 > 정상 요청은 컨트롤러까지 도달해 피해 적용
PASS  ServerRouter: 비정상 RemoteEvent 요청 거부 > 클라이언트가 보낸 피해량/명중 대상은 무시되지 않고 요청 자체를 거부
PASS  ServerRouter: 비정상 RemoteEvent 요청 거부 > 쓰레기·NaN·비단위벡터·알 수 없는 리모트·잘못된 캐릭터 거부, 상태 불변
PASS  ServerRouter: 비정상 RemoteEvent 요청 거부 > 시각 위조·조준 원점 위조·사망 상태·재장전 불가 캐릭터 거부
PASS  ServerRouter: 비정상 RemoteEvent 요청 거부 > 요청 폭주(초당 30회 초과)는 거부되어 서버 상태 영향 제한
PASS  ServerRouter: 비정상 RemoteEvent 요청 거부 > SelectCharacter는 다음 리스폰까지 대기
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > RMB 패링은 0.4초 창, 쿨타임 10초
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 전방 근접 공격 차단 + 자동 반격 18 (실제 근접 공격 경로)
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 후방 공격은 차단하지 않고 반격도 없음
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 180° 경계: 정확히 옆(90°)은 차단, 옆-뒤(약 104°)는 차단 안 함
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 창 경계: 0.39초는 차단, 0.4초 이후는 피해
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 중복 반격 방지: 같은 패링에서 같은 공격자는 한 번만 반격, 다른 공격자는 각각 한 번
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 새 패링(10초 후)에서는 같은 공격자에게 다시 반격 가능
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 반격은 방어 불가·재반격 없음: 서로 패링 중이어도 무한 반격 없이 1회씩
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 유효 사거리 밖 공격자에게는 반격하지 않음
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 사망한 공격자에게는 반격하지 않음
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 환경 피해·일반 광역 폭발은 차단하지 않음
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 방어 가능한 투사체(원거리): 전방에서 오면 차단·소멸, 멀리 있는 공격자에게 원격 반격 없음
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 근거리에서 쏜 방어 가능 투사체는 차단 + 자동 반격
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 후방에서 온 투사체는 차단되지 않음
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > blockable=false 로 정의된 투사체는 차단되지 않음
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 차단된 공격의 상태이상(넉백 등)은 적용되지 않음
PASS  패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초 > 패링 방향·성공은 서버 자세로 판정: 클라이언트가 보낸 조준 방향은 영향 없음
PASS  궁극기 자리표시자: 실플레이에서는 게이지 소모 금지 > 개발용 모의 허용 설정은 기본 false
PASS  궁극기 자리표시자: 실플레이에서는 게이지 소모 금지 > 미구현 궁극기(PAINTBALL)는 F를 눌러도 거부되고 게이지가 유지됨
PASS  궁극기 자리표시자: 실플레이에서는 게이지 소모 금지 > PAINTBALL도 동일
PASS  궁극기 자리표시자: 실플레이에서는 게이지 소모 금지 > 테스트 전용 모의 실행 옵션을 켠 경우에만 실행·소모(미구현 PAINTBALL)
PASS  궁극기 자리표시자: 실플레이에서는 게이지 소모 금지 > HUD 스냅샷이 미구현 상태를 알려줌(PAINTBALL), SWORD 는 구현됨, 게이지 충전은 그대로 동작
PASS  3단계 서버 지원: 달리기 해제·공중 공격·스킬 미구현·스냅샷 > 공격 시 달리기 해제 (근접·원거리·패링)
PASS  3단계 서버 지원: 달리기 해제·공중 공격·스킬 미구현·스냅샷 > 실패한 공격(쿨타임)은 달리기를 해제하지 않음
PASS  3단계 서버 지원: 달리기 해제·공중 공격·스킬 미구현·스냅샷 > 공중에서도 공격 가능 (공중 공격 허용)
PASS  3단계 서버 지원: 달리기 해제·공중 공격·스킬 미구현·스냅샷 > 미구현 캐릭터(PAINTBALL)의 숫자 스킬은 거부되며 쿨타임·상태를 소모하지 않음
PASS  3단계 서버 지원: 달리기 해제·공중 공격·스킬 미구현·스냅샷 > HUD 스냅샷: SWORD는 탄약 없음, PAINTBALL은 탄약·쿨타임·회피 정보
PASS  ScoreboardService > 킬/데스 집계와 정렬(킬↓, 데스↑, 이름)
PASS  ScoreboardService > 환경 사망·자살은 킬이 오르지 않고 데스만 증가
PASS  ScoreboardService > CombatCore 처치 이벤트와 연결
PASS  ScoreboardService > 퇴장한 플레이어는 목록에서 제거
PASS  입력 매핑 (WASD 제외 액션 키) > LMB/RMB는 Attack(Primary/Secondary)로 매핑되고 서버 스키마를 통과
PASS  입력 매핑 (WASD 제외 액션 키) > 숫자 1·2·3 → Skill 슬롯, Shift → Dodge, F → Ultimate
PASS  입력 매핑 (WASD 제외 액션 키) > R은 탄약 캐릭터에서만 Reload 전송
PASS  입력 매핑 (WASD 제외 액션 키) > 정의되지 않은 키는 무시
PASS  입력 매핑 (WASD 제외 액션 키) > Tab 홀드: 누르면 표시, 떼면 숨김, releaseAll(포커스 상실)도 숨김
PASS  입력 매핑 (WASD 제외 액션 키) > UI(설정창) 열림 중에는 전투 입력 차단
PASS  입력 매핑 (WASD 제외 액션 키) > 이동 벡터는 대각선 정규화
PASS  Ctrl 토글 달리기 > Ctrl을 누를 때마다 토글, SetRun 전송
PASS  Ctrl 토글 달리기 > 누르고 있는 동안만이 아니라 뗀 후에도 유지(홀드 아님)
PASS  Ctrl 토글 달리기 > 공격하면 달리기 해제(클라이언트 낙관 반영)
PASS  Ctrl 토글 달리기 > 서버-클라이언트 불일치: 서버 값이 우선(유예 시간 이후)
PASS  Ctrl 토글 달리기 > 서버가 달리기를 해제(공격/기절)하면 클라이언트도 해제
PASS  Ctrl 토글 달리기 > 서버 이동속도 스냅샷은 비정상 값을 안전 범위로 제한
PASS  카메라 시점 전환 입력과 재지정 > 기본 시작은 Locked(마우스 고정 전투 시점)
PASS  카메라 시점 전환 입력과 재지정 > V 키로 Locked ↔ Free 전환
PASS  카메라 시점 전환 입력과 재지정 > 전환키를 다른 키로 바꾸면 V는 더 이상 동작하지 않고 새 키가 동작
PASS  카메라 시점 전환 입력과 재지정 > 모드별 마우스 동작: Locked=LockCenter, Free=Default(커서 표시)
PASS  카메라 시점 전환 입력과 재지정 > Free 모드에서 RMB는 회전을 일으키지 않고 항상 보조 공격(입력 충돌 없음)
PASS  카메라 시점 전환 입력과 재지정 > Free 모드: FreeLook(MMB) 홀드 중에만 회전
PASS  카메라 시점 전환 입력과 재지정 > Locked 모드는 항상 회전, 피치는 설정 범위로 제한
PASS  카메라 시점 전환 입력과 재지정 > 비정상 마우스 입력(NaN/무한대)은 무시
PASS  카메라 시점 전환 입력과 재지정 > Free 전환은 모드만 바꾼다(설정값 InitialMode와 분리)
PASS  카메라 벽 충돌 > 장애물이 없으면 설정 거리 유지
PASS  카메라 벽 충돌 > 벽이 막으면 거리를 줄이고 최소 거리 아래로는 내려가지 않음
PASS  카메라 벽 충돌 > Locked는 어깨 오프셋을 적용하고 Free는 중심 추적
PASS  조준: 원거리 수동, 근접만 약한 보정 > 화면 중앙 광선의 도착점을 향해 발사 방향 계산
PASS  조준: 원거리 수동, 근접만 약한 보정 > 원거리(Projectile/Beam)는 대상이 근처에 있어도 보정하지 않음
PASS  조준: 원거리 수동, 근접만 약한 보정 > 근접은 최대 보정각 이내에서만, 범위·사망 대상 제외
PASS  조준: 원거리 수동, 근접만 약한 보정 > RangedAimAssist 설정은 false로 고정(확정)
PASS  키 설정(재지정) > 허용된 키로 변경, 이전 키는 해제
PASS  키 설정(재지정) > 이동/점프/취소 예약 키, 중복 키, 알 수 없는 액션, 잘못된 키 이름은 거부하고 기존 값 유지
PASS  키 설정(재지정) > 초기화와 저장 데이터 불러오기(잘못된 데이터는 기본값으로 복구)
PASS  회피: 방향·서버 확인 후 이동·공중 회피·충전 > 이동 입력이 있으면 카메라 기준 방향, 없으면 후방
PASS  회피: 방향·서버 확인 후 이동·공중 회피·충전 > 회피 이동은 서버가 확인한 이벤트만 수용 (내 ID, 최근, 중복 아님)
PASS  회피: 방향·서버 확인 후 이동·공중 회피·충전 > 회피 이동 속도 = 거리/시간, 지속시간 후 종료
PASS  회피: 방향·서버 확인 후 이동·공중 회피·충전 > 공중 회피: 서버가 허용하고 충전 소모
PASS  회피: 방향·서버 확인 후 이동·공중 회피·충전 > 충전 2회 → 3번째 거부 → 5초 후 1회 충전
PASS  회피: 방향·서버 확인 후 이동·공중 회피·충전 > 회피 무적 0.15초는 서버가 판정 (클라이언트 주장 불필요)
PASS  회피: 방향·서버 확인 후 이동·공중 회피·충전 > 클라이언트가 보낸 방향이 비정상(비단위 벡터)이면 서버 스키마가 거부
PASS  비정상 클라이언트 입력 > 알 수 없는 Attack action·Skill 슬롯·음수 시간·추가 필드·잘못된 타입 모두 거부
PASS  비정상 클라이언트 입력 > 연타 입력은 서버 쿨타임이 판정하며 클라이언트 명령 수는 제한 없이 생성되어도 안전
PASS  HUD 모델과 궁극기 미구현 표시 > SWORD: 탄약 없음, 보조 공격 쿨타임 표시
PASS  HUD 모델과 궁극기 미구현 표시 > GUNNER(구현 모듈 없는 공통 경로): 탄약·재장전 진행, 보조 공격 없음
PASS  HUD 모델과 궁극기 미구현 표시 > 궁극기 미구현(GUNNER)이면 게이지가 가득이어도 ready=false이고 미구현 문구 표시
PASS  HUD 모델과 궁극기 미구현 표시 > 숫자 스킬 3칸은 미구현 캐릭터(GUNNER)에서 모두 미구현 표시
PASS  HUD 모델과 궁극기 미구현 표시 > 회피 충전 표시 및 비정상 스냅샷은 nil
PASS  HUD 모델과 궁극기 미구현 표시 > 패링 활성 표시
PASS  피드백 이벤트 번역 > 패링 성공: 내가 패링하면 ParrySuccess, 내가 막힌 공격자면 WasParried
PASS  피드백 이벤트 번역 > 피해: 피격자에게 DamageTaken, 공격자에게 HitMarker
PASS  피드백 이벤트 번역 > 서버 거부(미구현 궁극기/스킬)는 안내 토스트, 그 외 거부는 조용히 무시
PASS  피드백 이벤트 번역 > 알 수 없거나 깨진 이벤트는 예외 없이 빈 결과
PASS  조준선 확장 구조 > 캐릭터별 조준선, 미등록은 기본값, 새 캐릭터 등록 가능, 잘못된 등록 거부
PASS  MovementValidator: 일반 이동은 막지 않는다 > 달리기 속도(23)로 30Hz 샘플 3초 이동: 보정 없음
PASS  MovementValidator: 일반 이동은 막지 않는다 > 프레임 지터·0.3초 끊김 뒤 몰아서 도착해도 허용(지연 여유)
PASS  MovementValidator: 일반 이동은 막지 않는다 > 점프(상승 50스터드/초, 0.2초)와 낙하는 허용
PASS  MovementValidator: 일반 이동은 막지 않는다 > 제자리 정지·미세 이동은 항상 ok
PASS  MovementValidator: 일반 이동은 막지 않는다 > 같은 시각 중복 표본·과거 시각 표본은 무시
PASS  MovementValidator: 일반 이동은 막지 않는다 > 미등록 플레이어는 검사하지 않는다(오차단 방지)
PASS  MovementValidator: 비정상 이동 탐지 > 속도 2배(46)로 2초 이동: 보정, 마지막 유효 위치로 되돌림
PASS  MovementValidator: 비정상 이동 탐지 > 보정 후 되돌린 위치가 새 기준이 된다
PASS  MovementValidator: 비정상 이동 탐지 > 순간이동(100스터드)은 누적 없이 즉시 보정
PASS  MovementValidator: 비정상 이동 탐지 > 상승 속도 과다(비행): 보정
PASS  MovementValidator: 비정상 이동 탐지 > 벽 관통(얇은 벽을 한 표본에 가로지름): 보정
PASS  MovementValidator: 비정상 이동 탐지 > 벽에 붙어 서는 것은 정상(관통 아님)
PASS  MovementValidator: 비정상 이동 탐지 > 보정 남발은 로그(correction_storm)로 남는다
PASS  MovementValidator: 비정상 이동 탐지 > teleported(): 서버가 옮긴 뒤에는 기준이 새로 잡혀 오탐이 없다
PASS  MovementValidator: 회피 > 벽이 없으면 회피 거리 14, 방향은 수평 단위 벡터로 정규화
PASS  MovementValidator: 회피 > 벽 앞 회피는 벽 직전에서 멈추도록 거리가 줄어든다
PASS  MovementValidator: 회피 > 벽에 붙은 채 회피하면 거리 0(무적만 적용)
PASS  MovementValidator: 회피 > 정상 회피(14스터드/0.25초)는 보정되지 않는다
PASS  MovementValidator: 회피 > 회피 지연 도착(네트워크 지연 0.2초 뒤 한꺼번에 14 이동)도 허용
PASS  MovementValidator: 회피 > 회피 허용량을 크게 넘는 이동(40스터드)은 보정
PASS  MovementValidator: 회피 > 회피를 이용한 벽 통과(벽 앞에서 회피한 뒤 벽 너머 도착): 보정
PASS  MovementValidator: 회피 > 잘못된 방향(0벡터·비테이블)은 계획 거부
PASS  MovementValidator: 공중 회피 > 공중에서 1회는 허용, 착지 전 2회째는 air_dodge_limit
PASS  MovementValidator: 공중 회피 > 착지(지면 확인)하면 공중 회피 횟수 복구
PASS  MovementValidator: 공중 회피 > 클라이언트가 지면이라고 속여도 발 아래 지면이 없으면 공중으로 판정
PASS  MovementValidator: 공중 회피 > AllowAirborne=false 설정이면 공중 회피 거부
PASS  MovementValidator: 점프대·충격 허용 > 허용 충격 없이 0.5초에 60스터드 수평 이동: 보정
PASS  MovementValidator: 점프대·충격 허용 > 점프대 충격 허용 중에는 같은 이동도 보정하지 않는다
PASS  MovementValidator: 점프대·충격 허용 > 충격 허용은 시간이 지나면 만료
PASS  CharacterController + MovementValidator 연동 > 벽 앞 회피: Dodge 이벤트 distance 가 줄어들고 blocked=true
PASS  CharacterController + MovementValidator 연동 > 벽이 없으면 기본 거리·정규화된 방향
PASS  CharacterController + MovementValidator 연동 > 공중 회피 2회째는 거부되고 충전이 소비되지 않는다
PASS  CharacterController + MovementValidator 연동 > movement 가 없어도(기존 동작) 회피는 그대로 동작
PASS  이동 허가 발급 규칙 > 정의된 모든 종류는 상한 이내에서 발급 가능
PASS  이동 허가 발급 규칙 > 알 수 없는 종류·미등록 플레이어·잘못된 인자 거부
PASS  이동 허가 발급 규칙 > 종류별 상한 초과(속도·상승·시간)는 exceeds_cap
PASS  이동 허가 발급 규칙 > 방향 허가 종류는 dir 필수
PASS  이동 허가 발급 규칙 > 같은 종류 재발급은 minInterval 이후에만(빈도 제한)
PASS  이동 허가 발급 규칙 > 동시 활성 허가 개수 상한
PASS  허가에 따른 이동 허용/거부 > 허가 없는 고속 이동은 어떤 종류 이름이어도 보정된다
PASS  허가에 따른 이동 허용/거부 > Lunge 허가: 방향 +X 로 허가량 안의 전진은 허용, 옆(+Z) 이동은 허가를 쓸 수 없어 보정
PASS  허가에 따른 이동 허용/거부 > 허가 총량 초과·만료 후 이동은 보정(허가가 무한정 늘지 않는다)
PASS  허가에 따른 이동 허용/거부 > 각 예약 종류(TripleSlash/PaintSlide/BounceDash/BlastJump)가 자기 상한 안에서 허용
PASS  허가에 따른 이동 허용/거부 > BlastJump 상승 허가: 허가 없는 수직 급상승은 보정, 허가가 있으면 허용
PASS  허가에 따른 이동 허용/거부 > 일반 회피도 같은 구조: 회피 방향 성분만 허용(옆으로 순간이동 불가)
PASS  허가에 따른 이동 허용/거부 > 보정이 일어나면 남은 허가는 모두 폐기
PASS  위조 요청 방어: 클라이언트는 이동 허가를 만들 수 없다 > RemoteSpec 에 이동/허가 관련 원격이 없다
PASS  위조 요청 방어: 클라이언트는 이동 허가를 만들 수 없다 > 알려지지 않은 원격 이름은 모두 거부
PASS  위조 요청 방어: 클라이언트는 이동 허가를 만들 수 없다 > Dodge/SetRun/Attack 페이로드에 가짜 이동 필드를 붙이면 스키마에서 거부
PASS  위조 요청 방어: 클라이언트는 이동 허가를 만들 수 없다 > 서버 라우터: 위조된 원격 이름·페이로드는 허가를 만들지 않는다
PASS  위조 요청 방어: 클라이언트는 이동 허가를 만들 수 없다 > 서버가 스키마를 통과한 Dodge 라도 거리·속도는 서버 값만 사용(payload 의 distance 무시)
PASS  위조 요청 방어: 클라이언트는 이동 허가를 만들 수 없다 > Dodge 로 얻은 허가를 다른 종류로 재사용할 수 없다(Dodge 는 issue 대상이 아님)
PASS  서버 넉백 적용 인터페이스(KnockbackApplier) > 기본 설정(꺼짐)에서는 속도를 적용하지 않고 허가도 발급하지 않는다
PASS  서버 넉백 적용 인터페이스(KnockbackApplier) > 켜면 피격 효과 결과가 속도로 적용되고 Knockback 허가가 발급된다
PASS  서버 넉백 적용 인터페이스(KnockbackApplier) > 넉백으로 밀려난 이동은 보정되지 않지만, 허가량을 넘는 이동은 보정
PASS  서버 넉백 적용 인터페이스(KnockbackApplier) > 보호 중/회피 무적 대상은 피해가 없으므로 넉백도 없다
PASS  서버 넉백 적용 인터페이스(KnockbackApplier) > 상한 초과 속도·잘못된 벡터는 적용하지 않는다
PASS  서버 넉백 적용 인터페이스(KnockbackApplier) > 미등록(퇴장한) 대상에는 적용하지 않는다
PASS  부활 확정 사양 값 > 사망 후 4초 뒤 부활, 부활 후 2초 보호
PASS  부활 보호: 서버 권위 피해 면역 > 부활 직후 2초 동안 보호, 2초 시점에 만료
PASS  부활 보호: 서버 권위 피해 면역 > 보호 중 근접 공격: 체력 불변, 적중 목록 비어 있음, 피격 이벤트 없음
PASS  부활 보호: 서버 권위 피해 면역 > 보호 중 적용 거부 사유는 spawn_protected 이고 체력·처치·점수·궁극기 충전에 반영되지 않는다
PASS  부활 보호: 서버 권위 피해 면역 > 보호 중 같은 attackId 는 기록되지 않아 보호 만료 후 정상 적중 가능
PASS  부활 보호: 서버 권위 피해 면역 > 보호 중 투사체는 대상을 통과하고 피해 없음
PASS  부활 보호: 서버 권위 피해 면역 > 보호 만료 후에는 정상 피해
PASS  부활 보호: 서버 권위 피해 면역 > 환경 사망(낙사 등)은 보호와 무관하게 처리되고 보호 상태가 정리된다
PASS  부활 보호 해제: 공격 행동 시작 / 만료 (서버 판정) > 근접 공격 시작 시 즉시 해제 + ProtectionEnded(Attack) 이벤트
PASS  부활 보호 해제: 공격 행동 시작 / 만료 (서버 판정) > 원거리(PAINTBALL) 첫 발사 시 해제
PASS  부활 보호 해제: 공격 행동 시작 / 만료 (서버 판정) > 실패한 공격 시도(쿨타임·재장전·사거리 밖 아님)는 해제하지 않는다
PASS  부활 보호 해제: 공격 행동 시작 / 만료 (서버 판정) > 패링·회피·달리기 전환은 공격 행동이 아니므로 해제하지 않는다
PASS  부활 보호 해제: 공격 행동 시작 / 만료 (서버 판정) > 스킬·궁극기 미구현 거부는 해제하지 않는다 / 모의 궁극기 성공 시에는 해제
PASS  부활 보호 해제: 공격 행동 시작 / 만료 (서버 판정) > 2초 경과 시 update 가 한 번만 ProtectionEnded(Expired)
PASS  부활 보호 해제: 공격 행동 시작 / 만료 (서버 판정) > 재부활하면 보호가 새로 시작된다(이전 만료 시각 무시)
PASS  부활 보호 클라이언트 동기화(HUD 스냅샷) > 스냅샷에 protectedUntil·protectSeconds, 해제 후에는 nil
PASS  부활 보호 클라이언트 동기화(HUD 스냅샷) > HudModel: 남은 시간·비율 표시, 만료/해제 시 표시 없음
PASS  부활 보호 클라이언트 동기화(HUD 스냅샷) > 서버 시각 기준: 클라이언트 now 가 만료 시각을 지나면 서버 스냅샷이 남아 있어도 표시 안 함
PASS  RespawnScheduler: 4초 대기·중복·무한 리스폰 방지 > 사망 4초 후에 로드 대상이 되고, 로드 중 재통지는 무시
PASS  RespawnScheduler: 4초 대기·중복·무한 리스폰 방지 > 대기 중 중복 사망 통지는 대기 시각을 늘리지 않는다
PASS  RespawnScheduler: 4초 대기·중복·무한 리스폰 방지 > 동시 사망 12명: 같은 틱에 모두 로드 대상, 정렬된 결정적 순서
PASS  RespawnScheduler: 4초 대기·중복·무한 리스폰 방지 > 첫 입장은 대기 없이 즉시 로드 대상
PASS  RespawnScheduler: 4초 대기·중복·무한 리스폰 방지 > 로드 실패: 1초 뒤 재시도, 상한(5회) 이후 포기(무한 재시도 없음)
PASS  RespawnScheduler: 4초 대기·중복·무한 리스폰 방지 > 짧은 시간에 로드가 반복되면(즉시 재사망 루프) 상한 후 지연·로그
PASS  RespawnScheduler: 4초 대기·중복·무한 리스폰 방지 > remove: 이후 due 에 나타나지 않는다(퇴장)
PASS  동시 리스폰 + 스폰 선택 + 보호 (실제 BRICKYARD 스폰) > 12명이 같은 틱에 리스폰: 서로 다른 스폰, 각자 독립적으로 2초 보호
PASS  동시 리스폰 + 스폰 선택 + 보호 (실제 BRICKYARD 스폰) > 한 명이 공격을 시작해도 다른 플레이어의 보호는 유지
PASS  동시 리스폰 + 스폰 선택 + 보호 (실제 BRICKYARD 스폰) > 사망→4초→리스폰→보호 전체 타임라인
PASS  스폰 도착 확인(중복 이동 방지) > 목표 6 스터드 이내면 이동 불필요, 벗어나면 보정
PASS  스폰 패드 규격 / RespawnLocation 유효성 (ForceField 방지) > 규격 값: Duration=0 명시, Neutral, Enabled, 팀 변경 없음
PASS  스폰 패드 규격 / RespawnLocation 유효성 (ForceField 방지) > 유효한 패드는 통과
PASS  스폰 패드 규격 / RespawnLocation 유효성 (ForceField 방지) > 각 결함을 개별 탐지: SpawnLocation 아님 / Workspace 밖 / Disabled / Neutral 아님 / Duration≠0 / Duration 없음
PASS  스폰 패드 규격 / RespawnLocation 유효성 (ForceField 방지) > 기본 ForceField 시간(예: 10)이 남아 있으면 검증 실패 → 호출부가 규격을 다시 적용
PASS  보호 경계: 서버 보호 종료 후 정상 피해 / 보호 중 거부 (ForceField 와 무관) > 보호 종료 직전(1.999초)은 거부, 종료 시각(2.0초)부터 피해 적용
PASS  보호 경계: 서버 보호 종료 후 정상 피해 / 보호 중 거부 (ForceField 와 무관) > 보호는 2초에서 연장되지 않는다: 만료 이벤트 이후 update 를 반복해도, 외부 스폰 설정과 무관하게 피해 적용
PASS  보호 경계: 서버 보호 종료 후 정상 피해 / 보호 중 거부 (ForceField 와 무관) > 보호 중 거부 → 만료 직후 같은 공격자의 새 공격은 허용(거부가 기록·쿨다운을 남기지 않음)
PASS  보호 경계: 서버 보호 종료 후 정상 피해 / 보호 중 거부 (ForceField 와 무관) > 보호가 공격 시작으로 해제된 직후에도 정상 피해
PASS  ActionPolicy: 공격 행동 분류 (안전한 기본값) > 실제 캐릭터 데이터: 기본 공격·궁극기는 공격, 패링은 비공격
PASS  ActionPolicy: 공격 행동 분류 (안전한 기본값) > 공격형 일반 스킬·공격형 보조 기술·지연 공격(설치·기폭)은 공격
PASS  ActionPolicy: 공격 행동 분류 (안전한 기본값) > 판정 없는 이동기·패링·회피·달리기·유틸은 비공격
PASS  ActionPolicy: 공격 행동 분류 (안전한 기본값) > 이동기에 피해·효과·히트박스가 있으면 공격 (Lunge/BlastJump/Bounce Dash 가 판정을 가질 때)
PASS  ActionPolicy: 공격 행동 분류 (안전한 기본값) > 데이터가 offensive=false 라고 선언해도 판정 필드가 있으면 우회 불가
PASS  ActionPolicy: 공격 행동 분류 (안전한 기본값) > 알 수 없는 종류·kind 없음·잘못된 입력은 공격으로 취급(보호 악용 방지)
PASS  공통 공격 시작 처리 (approveAction) > 공격형 행동 승인 시 보호 즉시 해제, 이벤트 1회, 이후 중복 호출은 무시
PASS  공통 공격 시작 처리 (approveAction) > 피해가 적중하지 않아도(허공) 승인된 공격 시작이면 해제
PASS  공통 공격 시작 처리 (approveAction) > 비공격 행동(패링 정의·순수 이동기)은 보호 유지
PASS  공통 공격 시작 처리 (approveAction) > LMB 쿨타임으로 거부된 요청은 보호를 해제하지 않는다
PASS  공통 공격 시작 처리 (approveAction) > 탄약 부족·재장전 중 거부는 보호를 해제하지 않는다
PASS  공통 공격 시작 처리 (approveAction) > RMB 패링은 유지 / (PAINTBALL) 스킬 1·2·3 거부(미구현)·궁극기 거부는 유지
PASS  공통 공격 시작 처리 (approveAction) > 궁극기 승인 시 해제(모의 궁극기, 게이지 100)
PASS  공통 공격 시작 처리 (approveAction) > 사망/미등록 플레이어의 승인 요청은 무시
PASS  지연 공격(설치·원격 기폭) 보호 악용 방지 > 설치 승인은 공격 시작 → 보호 해제
PASS  지연 공격(설치·원격 기폭) 보호 악용 방지 > 설치 후 사망·재부활(새 보호)한 상태에서 원격 기폭 명령을 내리면 그 시점에 보호가 해제된다
PASS  지연 공격(설치·원격 기폭) 보호 악용 방지 > 타이머/조건으로 스스로 터지는 기존 설치물은 소유자 행동이 아니므로 승인 처리 없이 보호를 해제하지 않는다(문서화된 동작)
PASS  캐릭터 로드: 타임아웃·중복·재시도 (RespawnScheduler) > 호출이 반환했는데 CharacterAdded 가 없으면 타임아웃 후 실패 처리, 재시도는 1초 뒤
PASS  캐릭터 로드: 타임아웃·중복·재시도 (RespawnScheduler) > 반환 후 타임아웃이 반복돼도 재시도 상한 후 포기(영구 반복 없음)
PASS  캐릭터 로드: 타임아웃·중복·재시도 (RespawnScheduler) > 성공 응답(onSpawned) 후 늦게 도착한 타임아웃 검사는 영향 없음
PASS  로드 경쟁 상태: 시도 ID · 겹침 금지 · 오래된 완료 무시 > 호출이 반환하지 않으면 타임아웃이 지나도 새 로드를 시작하지 않는다(타임아웃 플래그 초기화는 수정이 아님)
PASS  로드 경쟁 상태: 시도 ID · 겹침 금지 · 오래된 완료 무시 > 오래 걸린 호출이 늦게 반환: 같은 시도면 반영, 반환 전에는 재호출 없음
PASS  로드 경쟁 상태: 시도 ID · 겹침 금지 · 오래된 완료 무시 > 오래된 시도 ID 의 완료는 현재 시도 상태를 바꾸지 않는다
PASS  로드 경쟁 상태: 시도 ID · 겹침 금지 · 오래된 완료 무시 > 중복 finishCall 은 두 번째부터 무시
PASS  로드 경쟁 상태: 시도 ID · 겹침 금지 · 오래된 완료 무시 > CharacterAdded 가 호출 반환보다 먼저 와도(onSpawned 선행) 호출이 끝나기 전까지 새 호출을 막고, 끝나면 재시도 없음
PASS  로드 경쟁 상태: 시도 ID · 겹침 금지 · 오래된 완료 무시 > 늦은 캐릭터(타임아웃 후 도착)도 재시도를 취소하고 상태를 정리한다
PASS  로드 경쟁 상태: 시도 ID · 겹침 금지 · 오래된 완료 무시 > 퇴장(remove) 후 도착한 완료는 무시, 재입장하면 새 상태(시도 ID 불일치)
PASS  로드 경쟁 상태: 시도 ID · 겹침 금지 · 오래된 완료 무시 > hung(60초 무응답): 재시도 중단 로그, 이후 캐릭터가 도착하면 정상 복구
PASS  로드 경쟁 상태: 시도 ID · 겹침 금지 · 오래된 완료 무시 > 같은 틱에 여러 플레이어: 시도 ID 는 전역 고유
PASS  CharacterAdded 게이트: 중복 · 교체 · 퇴장 > 같은 모델의 중복 CharacterAdded 는 두 번째부터 무시
PASS  CharacterAdded 게이트: 중복 · 교체 · 퇴장 > 더 새로운 스폰이 시작되면 이전 처리(yield 중)는 stale 이라 현재 캐릭터를 덮지 못한다
PASS  CharacterAdded 게이트: 중복 · 교체 · 퇴장 > 오래된 모델의 늦은 Died 는 무시, 현재 모델의 Died 만 인정
PASS  CharacterAdded 게이트: 중복 · 교체 · 퇴장 > 퇴장 중 완료: remove 후에는 진행 중이던 처리가 모두 stale, 사망도 불인정
PASS  CharacterAdded 게이트: 중복 · 교체 · 퇴장 > 플레이어별로 독립
PASS  ForceField 제거 범위 축소 (의도한 보호 효과는 보존) > 스폰 직후 창 안 + 기본 이름 + 속성·태그 없음 + 비관리: 엔진 스폰 ForceField 로 식별 → 제거
PASS  ForceField 제거 범위 축소 (의도한 보호 효과는 보존) > 서버 관리 표시(RoBattlesManaged) 는 보존
PASS  ForceField 제거 범위 축소 (의도한 보호 효과는 보존) > 창이 끝난 뒤의 ForceField 는 보존
PASS  ForceField 제거 범위 축소 (의도한 보호 효과는 보존) > 식별 불가(다른 이름·속성·태그): 제거하지 않고 보고만
PASS  ForceField 제거 범위 축소 (의도한 보호 효과는 보존) > ForceField 가 아니거나 시간 정보가 없으면 대상 아님
PASS  ForceField 제거 범위 축소 (의도한 보호 효과는 보존) > shouldStripForceField 는 strip 일 때만 true
PASS  SWORD LMB 3타 콤보 (14/14/18) > 1·2·3타 피해 14/14/18, 3타 뒤 다시 1타
PASS  SWORD LMB 3타 콤보 (14/14/18) > 이어짐 창(1.2초)을 넘기면 1타부터 다시
PASS  SWORD LMB 3타 콤보 (14/14/18) > 타격별 다중 대상 적중: 부채꼴 안의 모든 적
PASS  SWORD LMB 3타 콤보 (14/14/18) > 쿨타임 안의 재입력은 거부(콤보 단계 유지), 부활 보호는 승인 시에만 해제
PASS  SWORD LMB 3타 콤보 (14/14/18) > 패링에 막힌 타격은 피해 없음 + 자동 반격 18, 사망 후 입력 거부
PASS  SWORD Skill 1 — Triple Slash (10/14/22) > 키 세 번: 10 → 14 → 22, 3번째 후 쿨타임(8초) 시작
PASS  SWORD Skill 1 — Triple Slash (10/14/22) > 연계 사이 최소 간격(0.3초) 미만 거부, 창(1.5초) 만료 시 쿨타임 시작 후 처음부터
PASS  SWORD Skill 1 — Triple Slash (10/14/22) > 타격별 전진: 이동 허가(TripleSlash)를 단계마다 발급, 이벤트에 dash 정보
PASS  SWORD Skill 1 — Triple Slash (10/14/22) > 이동 허가 거부(제한 초과) 시 쿨타임·연계·보호를 소모하지 않는다
PASS  SWORD Skill 1 — Triple Slash (10/14/22) > 패링에 막힌 타격은 피해 없음 + 반격
PASS  SWORD Skill 2 — Lunge (충전 18~32, 경로 다중 적중) > 충전량에 비례한 피해: 즉시 18, 0.5초 25, 1초 이상 32
PASS  SWORD Skill 2 — Lunge (충전 18~32, 경로 다중 적중) > 이동 경로상의 여러 적을 한 번씩 적중, 경로 밖/뒤쪽 적은 제외
PASS  SWORD Skill 2 — Lunge (충전 18~32, 경로 다중 적중) > 같은 돌진에서 한 대상은 한 번만 맞는다(여러 틱 중복 없음)
PASS  SWORD Skill 2 — Lunge (충전 18~32, 경로 다중 적중) > Release 는 충전 중일 때만 유효(위조 Release·중복 Release 거부), 충전 중 재Press 거부
PASS  SWORD Skill 2 — Lunge (충전 18~32, 경로 다중 적중) > 쿨타임: 돌진 시작부터 9초, 그 사이 Press 거부
PASS  SWORD Skill 2 — Lunge (충전 18~32, 경로 다중 적중) > 키를 떼는 요청이 없어도 최대 충전 + 유예 후 서버가 자동 발사
PASS  SWORD Skill 2 — Lunge (충전 18~32, 경로 다중 적중) > 충전 중 다른 공격·스킬·궁극기는 busy, 회피는 충전 취소(쿨타임 소모 없음)
PASS  SWORD Skill 2 — Lunge (충전 18~32, 경로 다중 적중) > 이동 허가(Lunge) 발급
PASS  SWORD Skill 2 — Lunge (충전 18~32, 경로 다중 적중) > 이동 허가 거부 시 충전은 취소되고 쿨타임을 쓰지 않으며 돌진도 없다
PASS  SWORD Skill 2 — Lunge (충전 18~32, 경로 다중 적중) > 사망 시 충전/돌진 상태 정리
PASS  SWORD Skill 3 — Blade Wave (20, 부채꼴 광역) > 전방 부채꼴 안의 모든 적에게 20 피해, 뒤/밖은 제외
PASS  SWORD Skill 3 — Blade Wave (20, 부채꼴 광역) > 쿨타임 6초, 거부 시 상태 유지
PASS  SWORD Skill 3 — Blade Wave (20, 부채꼴 광역) > 패링한 상대에게는 차단되고 반격을 받는다
PASS  SWORD Ultimate — Blade Storm (5×8 + 25) > 게이지 부족은 거부(소모 없음), 가득이면 발동하고 100% 소모
PASS  SWORD Ultimate — Blade Storm (5×8 + 25) > 틱 8회 × 5 + 마무리 25 = 총 65, 반경 안의 모든 적, 밖은 제외
PASS  SWORD Ultimate — Blade Storm (5×8 + 25) > 시전 중 다른 공격/스킬/재발동은 busy, 끝나면 다시 가능
PASS  SWORD Ultimate — Blade Storm (5×8 + 25) > 시전 중 사망하면 남은 틱·마무리는 발생하지 않는다
PASS  SWORD Ultimate — Blade Storm (5×8 + 25) > 부활 보호 중인 적은 맞지 않는다(체력·점수 변화 없음)
PASS  SWORD Ultimate — Blade Storm (5×8 + 25) > 승인 시 부활 보호 해제, 거부(not_ready)는 보호 유지
PASS  SWORD Passive — Duelist (3연속 +8, 전역 4초) > 순수 로직: 같은 대상 3번째 적중에 +8, 발동 후 4초 전역 제한
PASS  SWORD Passive — Duelist (3연속 +8, 전역 4초) > 대상별 카운터는 독립, 다른 대상 적중이 카운터를 끊지 않음, 창(3초) 초과 시 초기화
PASS  SWORD Passive — Duelist (3연속 +8, 전역 4초) > 공격자별 독립, 대상 사망/퇴장 시 해당 카운터 제거
PASS  SWORD Passive — Duelist (3연속 +8, 전역 4초) > 통합: 같은 대상 LMB 3번째 적중 = 18 + 8 = 26, 이후 4초간 재발동 없음
PASS  SWORD Passive — Duelist (3연속 +8, 전역 4초) > 차단(패링)·부활 보호·회피 무적으로 피해가 적용되지 않은 공격은 카운트되지 않는다
PASS  SWORD Passive — Duelist (3연속 +8, 전역 4초) > Triple Slash 3타(22)도 Duelist 대상: 세 번째 22+8 = 30
PASS  SWORD Passive — Duelist (3연속 +8, 전역 4초) > Blade Storm 틱은 Duelist 카운트/발동에 영향을 주지 않는다(임시 규칙 A66)
PASS  SWORD 보안: 위조 입력·원격 검증·서버 권위 > RemoteSpec: Skill phase 는 Press/Release 만, 피해/대상 필드는 허용되지 않는다
PASS  SWORD 보안: 위조 입력·원격 검증·서버 권위 > 라우터 경유: 스킬 3 정상 처리, 같은 요청 반복은 쿨타임 거부
PASS  SWORD 보안: 위조 입력·원격 검증·서버 권위 > 시간 왜곡/원점 위조 요청은 게이트에서 거부되어 스킬이 실행되지 않는다
PASS  SWORD 보안: 위조 입력·원격 검증·서버 권위 > 기절/행동 불가 중에는 스킬·콤보·궁극기 거부, 쿨타임 소모 없음
PASS  SWORD 보안: 위조 입력·원격 검증·서버 권위 > 스킬은 클라이언트가 보낸 대상·피해 없이 서버 판정만 사용(조준 방향만 의사)
PASS  SWORD 보안: 위조 입력·원격 검증·서버 권위 > HUD 스냅샷: SWORD 스킬 3칸 구현됨(이름·쿨타임), 콤보 단계, Duelist 제한 시각, 궁극기 구현됨
PASS  SWORD 클라이언트 순수 로직 (입력·이동·연출·HUD) — 실제 렌더/입력은 Studio 미검증 > 숫자 2 누르면 Press, 떼면 Release 전송(서버 스키마 통과), 누르지 않은 Release 는 없음
PASS  SWORD 클라이언트 순수 로직 (입력·이동·연출·HUD) — 실제 렌더/입력은 Studio 미검증 > 포커스를 잃으면 누르고 있던 Lunge 를 Release 로 정리
PASS  SWORD 클라이언트 순수 로직 (입력·이동·연출·HUD) — 실제 렌더/입력은 Studio 미검증 > UI 가 열려 있으면 스킬 Press 는 막히고, 이미 누른 키의 Release 는 정리된다
PASS  SWORD 클라이언트 순수 로직 (입력·이동·연출·HUD) — 실제 렌더/입력은 Studio 미검증 > dashVelocity: 서버 확정 속도·시간 동안만, 허가 상한 이하로 제한, 비정상 값은 nil
PASS  SWORD 클라이언트 순수 로직 (입력·이동·연출·HUD) — 실제 렌더/입력은 Studio 미검증 > acceptDashEvent: 내 이벤트·dash 포함·최근·중복 아님만
PASS  SWORD 클라이언트 순수 로직 (입력·이동·연출·HUD) — 실제 렌더/입력은 Studio 미검증 > EffectsModel: 콤보 3타/스킬/궁극기/Duelist 연출 큐
PASS  SWORD 클라이언트 순수 로직 (입력·이동·연출·HUD) — 실제 렌더/입력은 Studio 미검증 > 모든 SWORD 연출 큐가 EffectCatalog 에 정의되어 있다
PASS  SWORD 클라이언트 순수 로직 (입력·이동·연출·HUD) — 실제 렌더/입력은 Studio 미검증 > FeedbackModel: 내 스킬 적중은 타격 표시, 내 Duelist 만 토스트, busy 거부 안내
PASS  SWORD 클라이언트 순수 로직 (입력·이동·연출·HUD) — 실제 렌더/입력은 Studio 미검증 > HudModel: SWORD 스킬 이름·쿨타임·연계/충전 상태, 콤보, Duelist, 궁극기
PASS  SWORD 클라이언트 순수 로직 (입력·이동·연출·HUD) — 실제 렌더/입력은 Studio 미검증 > 구현 모듈이 없는 캐릭터(GUNNER)는 스킬/궁극기 미구현 표시
PASS  캐릭터별 최대 체력 > 확정 수치: SWORD 110 / PAINTBALL 95, 데이터에 있고 DamageService 에 반영
PASS  캐릭터별 최대 체력 > HUD 스냅샷의 최대 체력은 캐릭터별 값
PASS  캐릭터별 최대 체력 > PAINTBALL 은 95 피해에 사망, 94에는 생존(체력 1)
PASS  캐릭터별 최대 체력 > 캐릭터 변경은 다음 리스폰에서 새 최대 체력으로 가득 채워진다(SWORD → PAINTBALL → SWORD)
PASS  캐릭터별 최대 체력 > setMaxHealth 는 비정상 값을 거부하고, 체력은 최대치를 넘지 않는다
PASS  PAINTBALL LMB — Paint Shot (7, 초당 3발, 탄창 16, 재장전 1.2초) > 확정 수치
PASS  PAINTBALL LMB — Paint Shot (7, 초당 3발, 탄창 16, 재장전 1.2초) > 서버 투사체가 날아가 명중하면 피해 7
PASS  PAINTBALL LMB — Paint Shot (7, 초당 3발, 탄창 16, 재장전 1.2초) > 초당 3발: 간격 미만은 on_cooldown, 탄약 소모는 성공한 발사만
PASS  PAINTBALL LMB — Paint Shot (7, 초당 3발, 탄창 16, 재장전 1.2초) > 같은 순간 100번 요청해도 1발만 나간다(연타·중복 요청)
PASS  PAINTBALL LMB — Paint Shot (7, 초당 3발, 탄창 16, 재장전 1.2초) > 탄창 16발: 마지막 발 후 자동 재장전 1.2초, 장전 중 발사 불가, 완료 후 가득
PASS  PAINTBALL LMB — Paint Shot (7, 초당 3발, 탄창 16, 재장전 1.2초) > 탄약 0에서 발사 시도는 no_ammo(투사체·쿨타임 소모 없음) + 재장전 시작
PASS  PAINTBALL LMB — Paint Shot (7, 초당 3발, 탄창 16, 재장전 1.2초) > 원거리 자동 조준 보정 없음: 15도 빗나가면 명중하지 않는다
PASS  PAINTBALL LMB — Paint Shot (7, 초당 3발, 탄창 16, 재장전 1.2초) > 재장전 R: 가득이면 거부, 사용 후 허용, 이미 장전 중 거부
PASS  PAINTBALL LMB — Paint Shot (7, 초당 3발, 탄창 16, 재장전 1.2초) > 사망 후 발사 불가, 이미 발사한 투사체는 유지되어 명중
PASS  PAINTBALL LMB — Paint Shot (7, 초당 3발, 탄창 16, 재장전 1.2초) > 부활 보호: 거부된 발사(재장전·쿨타임)는 해제하지 않고, 성공한 발사만 해제
PASS  PAINTBALL RMB — Paint Burst (5발×5, 최대 25, 탄 3, 후딜 1초) > 독립 투사체 5개가 같은 대상에 모두 적중하면 25(다중 적중 허용, 최대 25)
PASS  PAINTBALL RMB — Paint Burst (5발×5, 최대 25, 탄 3, 후딜 1초) > 탄약 3 소모, 탄약 2 이하면 거부(탄약·쿨타임·보호 불변)
PASS  PAINTBALL RMB — Paint Burst (5발×5, 최대 25, 탄 3, 후딜 1초) > 후딜(쿨타임) 1초: 0.9초에 거부, 1.0초에 허용
PASS  PAINTBALL RMB — Paint Burst (5발×5, 최대 25, 탄 3, 후딜 1초) > 산탄: 중거리에서는 일부만 맞는다(결정적 패턴, 25 초과 불가)
PASS  PAINTBALL RMB — Paint Burst (5발×5, 최대 25, 탄 3, 후딜 1초) > 탄이 3 남았을 때 발사하면 0이 되어 자동 재장전, 장전 중 거부
PASS  PAINTBALL RMB — Paint Burst (5발×5, 최대 25, 탄 3, 후딜 1초) > 재장전 중에는 Burst 불가
PASS  PAINTBALL RMB — Paint Burst (5발×5, 최대 25, 탄 3, 후딜 1초) > 투사체 상한이면 일부만 나가지 않고 통째로 거부(탄약·쿨타임 불변)
PASS  PAINTBALL Skill 1 — Color Bomb (광역 24, 쿨 9) > 대상에게 맞아 폭발: 반경 안 모든 적 24, 밖은 0, 시전자는 피해 없음
PASS  PAINTBALL Skill 1 — Color Bomb (광역 24, 쿨 9) > 직접 피해 없음: 같은 대상에 중복 피해가 없다(폭발 1회만)
PASS  PAINTBALL Skill 1 — Color Bomb (광역 24, 쿨 9) > 바닥/벽에 맞아도 그 지점에서 폭발한다(지면 평면 사용)
PASS  PAINTBALL Skill 1 — Color Bomb (광역 24, 쿨 9) > 벽이 폭발을 가린다: 벽 너머 대상은 반경 안이어도 피해 없음
PASS  PAINTBALL Skill 1 — Color Bomb (광역 24, 쿨 9) > 쿨타임 9초: 8.9초 거부, 9초 허용, 거부 시 상태 불변
PASS  PAINTBALL Skill 1 — Color Bomb (광역 24, 쿨 9) > 탄약·재장전과 무관: 탄이 0이거나 재장전 중에도 사용 가능(탄약 불변)
PASS  PAINTBALL Skill 1 — Color Bomb (광역 24, 쿨 9) > 시전자 사망 후에도 날아간 폭탄은 폭발한다(이미 발사한 투사체 규칙)
PASS  PAINTBALL Skill 2 — Piercing Shot (대상당 30, 최대 3명, 쿨 12) > 한 줄로 선 적 3명을 관통해 각각 30, 4번째는 맞지 않는다
PASS  PAINTBALL Skill 2 — Piercing Shot (대상당 30, 최대 3명, 쿨 12) > 같은 대상은 한 번만 맞는다(이중 적중 없음)
PASS  PAINTBALL Skill 2 — Piercing Shot (대상당 30, 최대 3명, 쿨 12) > 벽에서 멈춘다: 벽 너머는 맞지 않는다
PASS  PAINTBALL Skill 2 — Piercing Shot (대상당 30, 최대 3명, 쿨 12) > 쿨타임 12초
PASS  PAINTBALL Skill 2 — Piercing Shot (대상당 30, 최대 3명, 쿨 12) > 피해는 서버 데이터만: 클라이언트가 보낸 damage/대상 필드는 효과 없음
PASS  PAINTBALL Skill 3 — Paint Slide (12 스터드, 쿨 7, 이동 허가) > 이동 허가(PaintSlide) 발급 + 이벤트에 거리 12·dash 정보, 쿨타임 7초
PASS  PAINTBALL Skill 3 — Paint Slide (12 스터드, 쿨 7, 이동 허가) > 허가 상한 안의 속도: 12스터드/0.4초 = 30 ≤ PaintSlide 상한 45
PASS  PAINTBALL Skill 3 — Paint Slide (12 스터드, 쿨 7, 이동 허가) > 서버가 허가를 거부하면 슬라이드·쿨타임 소모 없음
PASS  PAINTBALL Skill 3 — Paint Slide (12 스터드, 쿨 7, 이동 허가) > 벽이 가까우면 거리가 줄고, 거의 막혀 있으면(1 미만) 거부 + 쿨타임 불변
PASS  PAINTBALL Skill 3 — Paint Slide (12 스터드, 쿨 7, 이동 허가) > 슬라이드 중에도 LMB·RMB 사용 가능, 무적 없음(피해를 받는다)
PASS  PAINTBALL Skill 3 — Paint Slide (12 스터드, 쿨 7, 이동 허가) > 판정 없는 이동기: 부활 보호를 해제하지 않는다(공격 행동이 아님)
PASS  PAINTBALL Skill 3 — Paint Slide (12 스터드, 쿨 7, 이동 허가) > HUD: 슬라이드 중 상태 sliding, 이후 해제
PASS  PAINTBALL Ultimate — Color Break (전조 0.8초, 빔 2.5초, 0.25초마다 6, 최대 60) > 확정 수치
PASS  PAINTBALL Ultimate — Color Break (전조 0.8초, 빔 2.5초, 0.25초마다 6, 최대 60) > 게이지 부족은 거부(게이지·보호 불변), 가득이면 발동하고 100% 소모
PASS  PAINTBALL Ultimate — Color Break (전조 0.8초, 빔 2.5초, 0.25초마다 6, 최대 60) > 전조 0.8초 동안은 피해 없음, 이후 0.25초마다 6, 정지 대상은 총 60(최대)
PASS  PAINTBALL Ultimate — Color Break (전조 0.8초, 빔 2.5초, 0.25초마다 6, 최대 60) > 대상당 최대 60: 틱 간격이 어긋나도(큰 dt) 틱 수는 10회로 고정
PASS  PAINTBALL Ultimate — Color Break (전조 0.8초, 빔 2.5초, 0.25초마다 6, 최대 60) > 일직선의 여러 적을 동시에 맞힌다
PASS  PAINTBALL Ultimate — Color Break (전조 0.8초, 빔 2.5초, 0.25초마다 6, 최대 60) > 조준 가능: 빔 시전 중 Aim 갱신을 따라가며 판정 대상이 바뀐다
PASS  PAINTBALL Ultimate — Color Break (전조 0.8초, 빔 2.5초, 0.25초마다 6, 최대 60) > Aim 은 시전 중에만 유효: 시전 전/후 Aim 은 거부되고 상태 불변
PASS  PAINTBALL Ultimate — Color Break (전조 0.8초, 빔 2.5초, 0.25초마다 6, 최대 60) > 벽이 빔을 막는다
PASS  PAINTBALL Ultimate — Color Break (전조 0.8초, 빔 2.5초, 0.25초마다 6, 최대 60) > 시전 중(전조 포함) 사망하면 이후 틱 없음, 궁극기 종료
PASS  PAINTBALL Ultimate — Color Break (전조 0.8초, 빔 2.5초, 0.25초마다 6, 최대 60) > 전조 중 사망하면 피해가 한 번도 발생하지 않는다
PASS  PAINTBALL Ultimate — Color Break (전조 0.8초, 빔 2.5초, 0.25초마다 6, 최대 60) > 자발적 취소 불가 / 재발동 거부는 게이지를 소모하지 않는다
PASS  PAINTBALL Ultimate — Color Break (전조 0.8초, 빔 2.5초, 0.25초마다 6, 최대 60) > 빔 틱의 attackId 는 틱마다 고유: 한 틱에 같은 대상 중복 적용 없음
PASS  PAINTBALL Ultimate — Color Break (전조 0.8초, 빔 2.5초, 0.25초마다 6, 최대 60) > 궁극기는 Color Reload 패시브를 발동시키지 않는다
PASS  PAINTBALL Passive — Color Reload (탄 3 회복, 재발동 5초) > 확정 수치
PASS  PAINTBALL Passive — Color Reload (탄 3 회복, 재발동 5초) > Paint Burst 유효 적중: 탄 3 회복(비용 3 → 순증 0), 한 번의 Burst 에서 5발이 맞아도 1회만
PASS  PAINTBALL Passive — Color Reload (탄 3 회복, 재발동 5초) > 재발동 5초: 5초 안의 두 번째 유효 적중은 회복 없음, 5초 후 다시 회복
PASS  PAINTBALL Passive — Color Reload (탄 3 회복, 재발동 5초) > Color Bomb·Piercing Shot 유효 적중도 3 회복
PASS  PAINTBALL Passive — Color Reload (탄 3 회복, 재발동 5초) > LMB 적중·Paint Slide·궁극기는 발동하지 않는다
PASS  PAINTBALL Passive — Color Reload (탄 3 회복, 재발동 5초) > 재장전 중 유효 적중: 재장전 즉시 취소 + 탄 회복, 옛 완료 시각에 탄이 덮어써지지 않는다
PASS  PAINTBALL Passive — Color Reload (탄 3 회복, 재발동 5초) > 탄창이 가득이고 재장전 중도 아니면 발동·잠금 모두 일어나지 않는다(A69)
PASS  PAINTBALL Passive — Color Reload (탄 3 회복, 재발동 5초) > 피해가 적용되지 않은 적중(부활 보호·회피 무적)은 유효 적중이 아니다
PASS  PAINTBALL Passive — Color Reload (탄 3 회복, 재발동 5초) > 발사 후 사망→부활(같은 캐릭터)하면 이전 생애 투사체의 적중은 패시브를 발동시키지 않는다
PASS  PAINTBALL Passive — Color Reload (탄 3 회복, 재발동 5초) > 캐릭터 변경 후 이전 PAINTBALL 투사체 적중은 새 캐릭터에 영향 없음
PASS  PAINTBALL 보안·상태 정리 > RemoteSpec: Aim 리모트는 단위 방향·원점·시각만, 피해/대상 필드는 허용되지 않는다
PASS  PAINTBALL 보안·상태 정리 > SelectCharacter 로 PAINTBALL 선택 가능(스키마 통과)
PASS  PAINTBALL 보안·상태 정리 > 라우터 경유: 스킬 1 정상 처리, 같은 요청 반복은 쿨타임 거부, 위조 시각은 게이트 거부
PASS  PAINTBALL 보안·상태 정리 > 라우터 경유: Aim 은 시전 중이 아니면 no_aim_use/거부, 죽은 뒤에는 게이트가 거부
PASS  PAINTBALL 보안·상태 정리 > PAINTBALL 스킬에는 충전/해제가 없다: 위조 Release 는 거부되고 아무 상태도 바꾸지 않는다
PASS  PAINTBALL 보안·상태 정리 > 사망 상태·기절 상태에서는 모든 행동 거부, 쿨타임·탄약 불변
PASS  PAINTBALL 보안·상태 정리 > 캐릭터 변경·부활 시 슬라이드/궁극기/패시브 잠금/탄약이 초기화된다
PASS  PAINTBALL 보안·상태 정리 > 퇴장 시 모듈 상태 정리(빔 중 퇴장해도 남는 틱 없음)
PASS  PAINTBALL 보안·상태 정리 > 12명이 동시에 Burst·Bomb·Slide: 오류 없이 처리, 투사체 총량은 상한 이내, 결과는 결정적(두 번 실행해 동일)
PASS  PAINTBALL 보안·상태 정리 > HUD 스냅샷: 스킬 3칸·궁극기·패시브·탄약·보조 쿨타임이 구현됨으로 표시
PASS  PAINTBALL 클라이언트 순수 로직 > 자동 연사: LMB 를 누르고 있는 동안 간격마다 Attack 요청, 떼면 중단, 비자동 캐릭터는 없음
PASS  PAINTBALL 클라이언트 순수 로직 > 자동 연사는 설정창이 열려 있으면 멈춘다
PASS  PAINTBALL 클라이언트 순수 로직 > Aim 전송 시점: 시전 중에만 주기마다, 끝나면 타이머 초기화
PASS  PAINTBALL 클라이언트 순수 로직 > Aim 페이로드는 서버 스키마를 통과한다
PASS  PAINTBALL 클라이언트 순수 로직 > Paint Slide 이벤트(CharSkill + dash)는 이동으로 수용, 남의 이벤트·오래된 이벤트·중복은 거부
PASS  PAINTBALL 클라이언트 순수 로직 > 서버 CharSkill 이벤트 → 카탈로그에 있는 큐만 재생, 모르는 큐는 무시
PASS  PAINTBALL 클라이언트 순수 로직 > Color Bomb(Arc)·Piercing(Pierce) 투사체와 폭발 이벤트 → 전용 큐, 포물선 위치는 서버와 같은 중력식
PASS  PAINTBALL 클라이언트 순수 로직 > 서버가 보내는 모든 PAINTBALL 큐 이름이 카탈로그에 있다(실제 이벤트 수집)
PASS  PAINTBALL 클라이언트 순수 로직 > Color Reload 발동 알림(내 것만 토스트), 탄약 부족 거부 안내
PASS  PAINTBALL 클라이언트 순수 로직 > HUD: 스킬 3칸·슬라이드·궁극기 전조/발동·Color Reload 잠금 표시
PASS  EffectsModel: 이벤트 → 연출 큐 > Swing → sword.slash (내 것 mine=true)
PASS  EffectsModel: 이벤트 → 연출 큐 > 패링 시작/성공/반격 표시
PASS  EffectsModel: 이벤트 → 연출 큐 > Damaged → 피격 번쩍임 + 충격 연출, 공격자 관점 mine 구분
PASS  EffectsModel: 이벤트 → 연출 큐 > Dodge → 잔상(방향·서버 확정 거리·시작 위치 전달)
PASS  EffectsModel: 이벤트 → 연출 큐 > PAINTBALL 발사(Spawned Linear) → 발사 연출 + 시각용 탄, 다른 타입은 무시
PASS  EffectsModel: 이벤트 → 연출 큐 > 투사체 종료 → projectile.end, 명중/벽이면 얼룩(splat)
PASS  EffectsModel: 이벤트 → 연출 큐 > 재장전 완료/사망/리스폰 큐
PASS  EffectsModel: 이벤트 → 연출 큐 > 잘못된 입력은 빈 목록(예외 없음)
PASS  EffectsModel: 재장전 에지·시각 탄·잔상 > 재장전 시작 상승 에지에서만 true
PASS  EffectsModel: 재장전 에지·시각 탄·잔상 > 시각 탄 위치: 속도×경과, 수명 이후·시작 전은 nil
PASS  EffectsModel: 재장전 에지·시각 탄·잔상 > 잔상 위치: 시작점부터 거리까지 균등, 거리 0이면 모두 시작점, 잘못된 입력은 빈 목록
PASS  EffectCatalog: 교체 가능한 구조 검증 > 모든 큐 정의가 유효한 style·color·lifetime 을 가진다
PASS  EffectCatalog: 교체 가능한 구조 검증 > EffectsModel 이 내보내는 모든 cue 이름이 카탈로그에 있다(projectile.end 제외)
PASS  EffectCatalog: 교체 가능한 구조 검증 > Phase 1 캐릭터(SWORD/PAINTBALL) 모두 임시 무기 규격이 있고 다른 캐릭터 규격은 없다
PASS  EffectCatalog: 교체 가능한 구조 검증 > 사운드 정의: id 문자열과 0~1 음량(빈 id 는 재생 생략 허용)
PASS  SpawnDirector > 적이 없으면 어떤 활성 스폰이든 반환하고 HRP 높이를 더한다
PASS  SpawnDirector > 비활성(Enabled=false) 스폰은 선택하지 않는다
PASS  SpawnDirector > 활성 스폰이 하나도 없으면 nil, no_spawns
PASS  SpawnDirector > 생존 적이 가까운 스폰(MinEnemyDistance 이내)은 제외
PASS  SpawnDirector > 죽은 적은 위험으로 보지 않는다
PASS  SpawnDirector > 모든 스폰이 위험하면 fallback 으로라도 가장 덜 위험한 곳을 반환(스폰 실패 없음)
PASS  SpawnDirector > 같은 플레이어는 직전 스폰을 연속해서 쓰지 않는다(최근 사용 감점)
PASS  SpawnDirector > 다른 플레이어가 방금 고른 스폰은 예약 시간 동안 피한다
PASS  SpawnDirector > 예약은 ReserveSeconds 이후 풀린다
PASS  SpawnDirector > 스폰 12개 순차 요청: 4개뿐일 때도 항상 결과를 반환
PASS  SpawnDirector > removePlayer: 기록·예약 정리
PASS  SpawnDirector > 시야가 막힌 적은 시야가 열린 적보다 덜 위험(SpawnRisk 연동)
PASS  SpawnDirector > TopN 무작위: rng 가 있으면 하위 위험 N개 중에서 고른다
PASS  통합: 원본 S01~S20 좌표 (북쪽 -Z, 남쪽 +Z) > 스폰 레지스트리 계약 오류 없음, 20개
PASS  통합: 원본 S01~S20 좌표 (북쪽 -Z, 남쪽 +Z) > 좌표가 설계안과 정확히 일치(수정 좌표 없음 — Adjusted 비어 있음)
PASS  통합: 원본 S01~S20 좌표 (북쪽 -Z, 남쪽 +Z) > 지상 16 + 옥상 4, 중앙 광장(|x|,|z|<38) 안 스폰 없음
PASS  통합: 원본 S01~S20 좌표 (북쪽 -Z, 남쪽 +Z) > 옥상 스폰 높이 14, 어느 건물인지 좌표 부호로 결정(S17=NN, S18=PN, S19=NP, S20=PP)
PASS  통합: 원본 S01~S20 좌표 (북쪽 -Z, 남쪽 +Z) > 북쪽=-Z: 북쪽 외곽 스폰(S04~S06)은 z<0, 남쪽(S10~S12)은 z>0, 지면 파트 이름도 같은 방향
PASS  통합: 원본 S01~S20 좌표 (북쪽 -Z, 남쪽 +Z) > 모든 스폰이 고체 안이 아니고 발 아래에 바닥이 있다(전투 쪽 월드 기준)
PASS  통합: 원본 S01~S20 좌표 (북쪽 -Z, 남쪽 +Z) > 옥상 스폰 비활성 설정: 활성 16개, 옥상은 선택 대상에서 제외
PASS  통합: 스폰 위험도·리스폰 > 12명이 순차 스폰: 서로 MinEnemyDistance 이상 떨어진 자리(가능한 한)와 중복 없는 스폰
PASS  통합: 스폰 위험도·리스폰 > 사망 후 리스폰: 적이 밀집한 쪽을 피하고 방금 죽은 자리를 다시 쓰지 않는다
PASS  통합: 스폰 위험도·리스폰 > 모든 스폰 후보가 안전 필터를 통과하지 못해도 항상 리스폰 위치가 나온다
PASS  통합: 스폰 위험도·리스폰 > 맵 재생성(같은 설정): 레지스트리 결과가 동일 — 선택 로직이 재생성 전후 같은 규칙
PASS  통합: 스폰 위험도·리스폰 > 선택된 스폰 위치(HRP 높이)는 모두 고체 밖이며 바라보는 방향이 수평 단위 벡터
PASS  통합: 실제 맵 위 회피 벽 관통 방지 > 모든 스폰×8방향: 회피 종점이 고체 안에 들어가지 않는다
PASS  통합: 실제 맵 위 회피 벽 관통 방지 > 건물 바깥벽 앞에서 벽 방향 회피: 막혀서 거리 감소, 경로가 벽을 통과하지 않는다
PASS  통합: 실제 맵 위 회피 벽 관통 방지 > 문(폭 8)을 통과하는 회피는 막히지 않는다
PASS  통합: 실제 맵 위 회피 벽 관통 방지 > 클라이언트가 회피를 이용해 건물 벽을 통과하는 위치를 보고하면 보정
PASS  통합: 실제 맵 위 회피 벽 관통 방지 > 서버 계획 + 클라이언트 모델 합성: 클라이언트가 적용하는 총 이동 ≤ 서버가 확정한 거리
PASS  통합: 이동 검증 오탐 방지(실제 맵) > 점프대 비행(서버가 알려준 속도): 벽/속도 보정 없음, 옥상 착지 후 걷기도 정상
PASS  통합: 이동 검증 오탐 방지(실제 맵) > 계단 걷기(문→옥상): 걷기 속도(17)에서 보정 없음
PASS  통합: 이동 검증 오탐 방지(실제 맵) > 광장 가로지르기 달리기: 엄폐물을 돌아가는 경로는 보정 없음(직선으로 벽을 뚫으면 보정)
PASS  통합: 서버/클라이언트 동기화 > Correct 이벤트 수용: 최근·미수용 시각·유효 좌표만 snap
PASS  통합: 서버/클라이언트 동기화 > dodgeVelocity: 서버가 줄인 거리 반영, 0이면 이동 없음, 기본 거리 초과 값은 제한
PASS  통합: 서버/클라이언트 동기화 > 서버 보정 → 같은 위치 재관찰은 ok: 보정이 반복 루프를 만들지 않는다

합계: 586 통과 / 0 실패 / 586 전체
```
