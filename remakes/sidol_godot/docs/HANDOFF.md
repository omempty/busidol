# 세션 핸드오프 — 다음 세션 시작 가이드

> 작성일: 2026-08-24 · **Phase 7 완료** 시점

## 1. 현재 상태 한 줄 요약

**Phase 0~7 완료.** 컷신/트리거/미니게임(퀴즈·회로)/craft/엔딩 흐름까지 전부 연결.
다음은 **Phase 8 (도트/오디오 AI 생성 배치)** — G-ART 게이트 확인 후 시작.

## 2. 다음 세션 첫 명령

```bash
# 게임 실행 확인 (F1 진입 시 프롤로그 컷신 자동 재생)
remakes\sidol_godot\게임실행.bat

# 검증 관문 6단계
remakes\sidol_godot\검증실행.bat

# Event Editor v0 — Godot 에디터 하단 패널 "Event Editor"
remakes\sidol_godot\에디터실행.bat
```

## 3. 다음 작업 (Phase 8)

| 순서 | 작업 | 참조 |
|---|---|---|
| 1 | DOSBox 캡처 지원트 + style_refs 확보 | 07_ai_asset_pipeline |
| 2 | 스프라이트/타일 일러스트 AI 배치(spec→Validator 게이트) | assets/spec/** |
| 3 | BGM 6종 + SFX 세트 생성, AudioManager 실구현 | Phase 8 스텁 해소 |
| 4 | 이벤트 데이터 채우기 — 각 층 게이트 플래그 세팅 흐름(q_f2_hp_gate 등) | 마스터 시나리오 §4.2 |

### P7에서 완결된 플레이 흐름 (검증용 체인)

```
F1 진입 → opening(@c101~106) → [시나리오] → F2 HP실(q_f2_hp_gate)→크레딧룸
F3 퀴즈맨(q_f3_quiz_gate)→quiz_paline→퀴즈→팰린→craft→해독제(Q_F3_CURE_DONE)
F4 회로(q_f4_battery_gate)→battery_puzzle→10,000V(Q_F4_BATTERY)
F5 보스(q_f5_boss_gate)→SYS_BUILDER 결전→승리(q_f5_ai_battle_won)
→ epilogue(@c601~605)→크레딧룸 엔딩(Q_ENDING)
```
※ 중간 게이트 플래그(q_*_gate)는 아직 수동/이벤트 미연결 — Phase 9 시나리오 반영 시 채움.

### 재활용 아키텍처 노트 (bombman94/95 포팅 대비)

3계층 분리가 포팅 재활용 단위다 — 신규 리메이크는 2계층만 새로 쓴다:

| 계층 | 위치 | bombman94/95 에서 |
|---|---|---|
| **공용 프레임워크** | `src/battle`(BattleController/DamageCalculator/ChoreographyRunner/BattlePresenter/BattleUI), `src/cutscene`, `src/map/trigger_system.gd`, `src/ui`(DialogueBox/QuizMinigame/BatteryCircuit), `_shared` 도구+schemas | **그대로 이식** |
| **게임 데이터** | `data/**` | 전면 교체(원작 변환기만 작성) |
| **게임 전용 로직** | field/battle/credit_room 조립, 성장, 보스 하이브리드 | 부분 재작성 |

### 구현 노트 (이번 세션 추가)

- **배터리 회로 퍼즐**: BatteryCircuitMinigame + data/minigames/battery_circuit.json
  (6슬롯 × 10/100V, 레버 ×1~25, 목표 10,000V — 정답 예: 400V×25).
- **전투 승리 플래그**: start_battle op의 `on_win_flag` → pending_encounter 경유 →
  승리 시 GameState.set_flag. 에필로그 트리거가 이 플래그로 발동한다.
- **Event Editor v0**: addons/event_editor — 하단 패널에서 cutscenes/*.json 스텝
  열람/op·args 편집/추가·삭제/저장. project.godot에 플러그인 등록됨.
- **Validator 확장**: minigames 검사(퀴즈 문항/answer 범위, 회로 설정값),
  change_scene 경로, 신규 op 화이트리스트(minigame_battery/change_scene).
- QuizMinigame은 "@키"와 원문 텍스트 양쪽 허용(_fmt).

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
