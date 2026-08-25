# 시나리오 데이터 완충안 (검토용 초안 v1)

> 작성: 2026-08-25 · 상태: **승인됨 (리뷰 완료) — WP 실행 착수 가능**
> 권위: docs/04_scenario/03_remake_scenario_master.md (§3 씬별 대본, §4 플래그 명세)
> 제약: 콘텐츠 하드코딩 금지(전부 data/** JSON), @t229 원문 불변, 신규 대역은 @c,
>       검증 게이트 = validate.gd + smoke_selfcheck + 디버그 패널

## A. 현황 인벤토리 (2026-08-25实测)

| 자산 | 현황 | 비고 |
|---|---|---|
| 원문 @t | 229개 (@t0~@t228) | 원작 이식분 — 불변 |
| 신규 대역 @c | 39개 작성 / **컷신+시퀀스 실사용 26개** | F3 @c317~328 등 13개 미사용 |
| NPC 시퀀스 | 7개 | **4개는 NPC 미배치로 도달 불가(죽은 콘텐츠)** |
| NPC 배치 | **F1에만 2명**(tutor_dumb, prof_chem) | F0/F2~F5 = 0명 |
| 트리거 | 6개, **전부 auto** | zone/interact 0개 — 필드 탐색 보상 없음 |
| 컷신 | 6개(opening/hp_room/quiz/battery/boss/epilogue) | 주요 연출 골격은 확보 |
| 퀘스트 플래그 | 마스터 명세 18종 vs 실사용 ~13종 | Q_F1_SOPO/GAS·Q_F2_FIGHTER·Q_F3_DRAG/ALLIN 미구현 |
| 후일담 카드 조건 | Q_QUIZ_ALL만 존재 | Q_HP_ALL·Q_QUAN_DONE 미신설 |
| 단참조 버그 | cafeteria_girl_shop → `@c001` (dialogue.json에 없음) | 빈 문자열 반환 |

## B. 갭 매트릭스 (마스터 §3 씬 기준)

| 씬 | 마스터 요구 | 현황 | 격차 |
|---|---|---|---|
| S1-1 프롤로그 | 오프닝 컷신 | ✅ opening.json | — |
| S1-2 첫전투·의뢰 | prof_chem 대화 | ⚠️ 시퀀스 2개 있음 | cure_request가 Q_F3_CURE_REQ와 연결 안 됨 |
| S1-3 교무실 침입 | Q_F1_SOPO/GAS + 괴배 | ❌ | 트리거·플래그·컷신 전무 |
| S2-1 HP실 | hp_room_visit | ✅ | — |
| S2-2 친구 구출 | Q_F2_FIGHTER + 스킬 [연속 공격] | ❌ | npc_girl_rescue 시퀀스는 있는데 **미배치** |
| S2-3 만화 브로마이드 | Q_F2_POSTER 게이트 | ❌ | F2→F3 계단 requires_flag 비어있음 |
| S3-1 교수 의뢰 | Q_F3_CURE_REQ | ⚠️ 플래그만 | 트리거 연결 필요 |
| S3-2 재료 3종 피크드 | 드랍/발굴 | ❌ | 인카운터 드랍·zone 트리거 설계 필요 |
| S3-3 합성 | quiz_paline(craft op) | ✅ | — |
| B-1/B-2 지하 서고 | Q_F0_DISK + 레거시 코드 발굴 | ❌ | F0 진입은 east계단으로 가능(8/25 수정), 내용 0 |
| S4-1 배터리 | battery_puzzle | ✅ | — |
| S4-2 희생 | Q_F4_SACRIFICE 연출 | ⚠️ 플래그 존재, 연출 컷신 없음 |
| S5-2 SYS_BUILDER | boss_sys_builder | ✅ | — |
| S5-3 대화 선택지 | "미완성" 선택 분기 | ❌ | 선택지 UI 자체 미검토 — 단일 엔딩 유지 범위 내 처리 필요 |
| E-1/E-2 에필로그 | 카드 3종 삽입 | ⚠️ 골격 | Q_HP_ALL/Q_QUAN_DONE 신설 선행 |

## C. 작업 패키지 제안

### WP-1 퀘스트 플래그 체인 정합화 (기반 — 최우선)
- 마스터 18종을 `data/quests_v2.json`으로 확장: id·zone·name·**목표 설명·보상·선행 flag**
- 누락 6종 신설: Q_F1_START/SOPO/GAS, Q_F2_FIGHTER, Q_F3_DRAG/ALLIN
- 후일담 조건 2종 신설: Q_HP_ALL(S2-1 연관), Q_QUAN_DONE(판교? 마스터 §4.2 확인 필요)
- 검증: SelfCheck에 "플래그 체인 순환/고아" 프루브 추가
- 분량: JSON ~40행 + 프루브 1종

### WP-2 NPC 배치·대사 (F0/F2~F5)
- 미배치 시퀀스 4개를 좌표 배치: npc_girl_rescue→F2, guard_idle/nothing_man/cafeteria_girl_shop→F0~F2 적절 위치
- 구역별 상주 NPC 신규 추가(@c 신설): F2 개발자 2명, F3 랩실생도, F4 방과후 잔류생, 지하 사서 — 마스터 §2.1 프로필 준수
- **@c001 단참조 수정** 포함
- 검증: smoke_selfcheck NPC 시퀀스 프루브가 이미 전수 확인
- 분량: npcs_f*.json + @c ~30개

### WP-3 이벤트 트리거 채우기 (씬 → 데이터)
- zone 트리거: S1-3 교무실 입장, S3-2 재료 3곳, B-1 서고 입장, B-2 발굴 지점
- interact 트리거: S2-3 포스터, S4-2 희생 오브젝트
- 각 트리거 = done_flag 부여(체인은 WP-1 스키마 따름)
- 검증: 트리거 참조 프루브(기존) + 플래그 체인 프루브(WP-1)
- 분량: triggers_f*.json 확장, 컷신 소형 다수(step 2~4)

### WP-4 후일담 카드 3종 · 에필로그 완성
- Q_HP_ALL/Q_QUAN_DONE 달성 판정 위치 확정 → epilogue.json에 카드 삽입 op
- 크레딧룸과 연결(credit_room은 골격 존재)
- 분량: epilogue 확장 + credits.json

### WP-5 S5-3 최종 선택 연출 (스코프 주의)
- 단일 엔딩 유지(마스터 확정) 하의 **연출용 선택**: DialogueBox 선택지 지원 여부 먼저 소규모 스파이크
- 스파이크 실패 시 모노로그 연출로 대체하는 B안 병기

### WP-6 (부수) 데이터 위생
- dialogue_sequences ↔ dialogue 참조 무결성 프루브(SelfCheck 추가)
- 미사용 @c 13개(F3): S3-2 재료 피크드 대사로 재활용 or 폐기 판정

## D. 결정 사항 (리뷰 완료)

- **D1** WP-2 신규 NPC @c 대사의 톤: 기존 톤에 맞춰서 알아서 작성 (예문 불필요)
- **D2** 미구현 퀘스트 6종 구현 범위: 6종 전부 구현 (SOPO/GAS 포함)
- **D3** 후일담 조건 플래그 명칭: 마스터 표기 그대로 유지 (`Q_HP_ALL`, `Q_QUAN_DONE`)
- **D4** S5-3 선택지: 선택지 UI 신규 기능 스파이크 진행 허용
- **D5** F3 재료 피크드 방식: 고정 zone 발굴 방식 채택
- **D6** 미사용 @c 13개 처분: S3-2 재료 피크드 대사 등으로 재활용

## E. 검증 계획 (공통)

1. 매 WP 종료 시: import/validate 0오류 + 스모크 8종 PASS
2. WP-1 완료 시점에 SelfCheck 플래그 체인 프루브 상시화
3. 최종: 디버그 패널로 구역 순회 수동 체크 리스트 제공(체크포인트당 1분 내)

## F. 실행 순서

WP-1 → WP-6 → WP-2 → WP-3 → WP-4 → WP-5 (D4 결과에 따라 WP-5만 후행 가능)
예상 총 분량: JSON/대사 위주 — 코드 변경은 WP-5 스파이크와 SelfCheck 프루브뿐.
