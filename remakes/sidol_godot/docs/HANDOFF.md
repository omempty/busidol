# 세션 핸드오프 — 다음 세션 시작 가이드

> 작성일: 2026-08-24 · Phase 7 대부분 완료(UI 분리·Schema·크레딧룸·보스 트리거) 시점

## 1. 현재 상태 한 줄 요약

Phase 0~7 완료(전투 UI 분리, Schema 껍데기 3종, 크레딧룸 3모드 — 멤버/후일담 카드/스탭롤,
SYS_BUILDER 보스 트리거+컷신). 다음은 **craft op + 미니게임 프레임워크**와 **Event Editor v0**.

## 2. 다음 세션 첫 명령

```bash
# 게임 실행 확인 (F1 진입 시 프롤로그 컷신 자동 재생)
remakes\sidol_godot\게임실행.bat

# 검증 관문 확인 — 6단계(import/validate/smoke×4)
remakes\sidol_godot\검증실행.bat
```

## 3. 다음 작업 (Phase 7 잔여)

| 순서 | 작업 | 파일 |
|---|---|---|
| 1 | Event Editor v0(Godot 플러그인) | docs/02_design/05 §3.3 |
| 2 | 크레딧룸 입구 연결 — F2 HP실 NPC 대화 → credit_room 씬 전환 | triggers_f2.json |
| 3 | 엔딩 진입 — q_f5_ai_battle 승리 후 에필로그 컷신(@c601~605) | data/cutscenes/ |
| 4 | 배터리 회로 퍼즐(minigame_battery_circuit) — 10V/100V 직렬로 10,000V | 마스터 시나리오 씬 4-1 |
| 5 | 퀴즈맨 원작 메타 10문항(Q_QUIZ_ALL, 레트로 보존판) — quiz_man.json 확장 | 마스터 부록 A3 |

### 재활용 아키텍처 노트 (bombman94/95 포팅 대비)

3계층 분리가 포팅 재활용 단위다 — 신규 리메이크는 2계층만 새로 쓴다:

| 계층 | 위치 | bombman94/95 에서 |
|---|---|---|
| **공용 프레임워크** | `src/battle`(BattleController/DamageCalculator/ChoreographyRunner/BattlePresenter/BattleUI), `src/cutscene`, `src/map/trigger_system.gd`, `_shared` 도구(johab/PCX/VOC)+schemas | **그대로 이식** — 안무 JSON 채널 계약은 엔진 무관 |
| **게임 데이터** | `data/**`(battle_moves/skills/monsters/cutscenes/triggers/credits) | 전면 교체(원작 데이터 변환기만 작성) |
| **게임 전용 로직** | field/battle/credit_room 씬 조립, Combatant 성장, 보스 하이브리드 | 부분 재작성 |

원칙: 새 시스템 추가 시 "콘텐츠는 data/**, 메커니즘은 범용 클래스" 경계를 유지할 것.
Combatant.stats 타입 Resource화(CharacterStats)가 남은 결합도 해소 과제(Phase 4 TODO).

### 구현 노트 (이번 세션 결정)

- **Validator 실구현**: validate.gd가 이제 실제 검사 수행 — battle_moves 채널/키프레임,
  컷신 op 화이트리스트 + 대사 키(@t/@c) 해석, 트리거 action 참조(컷신/시퀀스 파일),
  skills→battle_moves, craft 아이템 ID(items.json), credits text_key. 오류 시 exit 1.
  새 콘텐츠 추가 후 반드시 실행. 스키마 자동 검사(JSON Schema 엔진)는 별도.
- **미니게임 프레임워크**: QuizMinigame(data/minigames/*.json — 문항/선택지/정답 전부 데이터).
  CutscenePlayer 신규 op: `minigame_quiz`(통과까지 재도전), `craft`(requires 소비→grant
  지급+플래그, 부족 시 중단), `grant_item`. F3 퀴즈맨 팰린 게이트 완결
  (triggers_f3 → quiz_paline → Q_F3_CURE_DONE).
- **전투 UI 분리**: `src/ui/battle_ui.gd` 신설 — HP바/메뉴/결과 라벨이 시그널
  (`command_selected`/`skill_selected`)으로만 통신. 컨트롤러 455→305행.
  스프라이트 생성도 presenter.build_sprites() 로 이동.
- **Schema 껍데기**: `_shared/schemas/{event,cutscene,battle_move}.schema.json`.
  validate.gd 가 아직 stub 이므로 자동 검사는 미연결(잔여 작업 3번).
- **크레딧룸**: 콘텐츠 전부 `data/credits.json` 으로 이동(하드코딩 해소).
  ↑↓ 모드 전환(멤버/엔딩카드/스탭롤), 후일담 카드 3종은 @c601~@c605 참조.
- **보스 트리거**: `triggers_f5.json` — `q_f5_boss_gate` 플래그에서만 발동하는 auto
  트리거 → `boss_sys_builder.json` 컷신(@c507~@c515) → `start_battle` op 로 결전 진입.
- **판정 단일화**: 데미지 적용은 BattleController.submit_player_command 가 유일.
- **교훈**: 신규 class_name 추가 후 반드시 `--import`(글로벌 클래스 캐시 재구축).
  Godot 4.7.2 는 `_shared/tools/godot/`.

## 4. 알려진 미해결

| ID | 내용 | 우선순위 |
|---|---|---|
| B1 | 빈 폴더 `BSD 시돌이의 모험\` 껍데기 삭제 (세션 CWD 잠김) | 낮음 |
| B2 | gdformat/pre-commit 설정 파일 미생성 | 낮음 |
| B3 | DialogueBox 스킵 시 visible_characters 음수 방지 | 낮음 |

## 5. 핵심 설계 결정 이력

| 결정 | 근거 문서 |
|---|---|
| G-ART = B안(32px 타일, 64px 캐릭터) | roadmap 게이트 표 + 04_uiux §2 |
| G-SCOPE 확정: 단일 엔딩+후일담 카드 3종 | 마스터 시나리오 §1 |
| 몬스터 AI: BFS 추적+배회+분산 (원작 패턴표 폐기) | 01_oop_redesign §5 |
| 대사 ID: @t(원문 불변)+@c(신규, 구역별 대역) | 마스터 부록 A |
| 에셋 공급: 원작 리마스터 우선, AI 생성은 일러스트만 | 07_ai_asset_pipeline |
| 보스전: 턴제+회피 페이즈 하이브리드 | 05_toolchain §5.3 |

## 6. 주요 파일 빠른 참조

| 찾는 것 | 경로 |
|---|---|
| 프로젝트 설정 | project.godot |
| 맵 데이터 | data/maps/f*.json |
| 아이템 DB | data/items.json (63종) |
| 스킬 DB | data/skills.json (6종) |
| 인카운터 테이블 | data/monsters.json |
| 성장 곡선+난이도 | data/growth.json |
| 대사 테이블 | data/dialogue.json (@t229항목) |
| NPC 배치 | data/maps/npcs_f*.json |
| 계단/게이트 | data/maps/transitions.json |
| AI 코딩 규칙 | AGENTS.md |
