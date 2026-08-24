# 세션 핸드오프 — 다음 세션 시작 가이드

> 작성일: 2026-08-24 · Phase 7 첫 슬라이스(컷신/트리거 런타임) 완료 시점

## 1. 현재 상태 한 줄 요약

Phase 0~6 완료 + **Phase 7 핵심 런타임 완료**(CutscenePlayer 실구현, TriggerSystem,
프롤로그 opening 컷신 데이터, 검증 관문 6단계 확장).
다음은 **Phase 7 잔여**(craft op·미니게임 프레임워크·Event Editor v0)부터.

## 2. 다음 세션 첫 명령

```bash
# 게임 실행 확인 (F1 진입 시 프롤로그 컷신 자동 재생)
remakes\sidol_godot\게임실행.bat

# 검증 관문 확인 — 이제 6단계(import/validate/smoke×4)
remakes\sidol_godot\검증실행.bat
```

## 3. 다음 작업 (Phase 7 잔여)

| 순서 | 작업 | 파일 |
|---|---|---|
| 1 | battle_scene_controller UI 분리(~450행, 상한 초과) | `_build_ui`/메뉴 → `src/ui/battle_ui.gd` |
| 2 | craft op + 미니게임 프레임워크(quiz/배터리 회로) | 마스터 시나리오 §F3 |
| 3 | Event Editor v0 / battle_moves JSON Schema 껍데기 | `_shared/schemas/` |
| 4 | 보스 출현 트리거 — start_battle op 연결 | CutscenePlayer.start_battle 이미 구현됨 |
| 5 | 크레딧룸 골격 완성 + 엔딩 카드 | scenes/credit_room.gd |

### 재활용 아키텍처 노트 (bombman94/95 포팅 대비)

3계층 분리가 포팅 재활용 단위다 — 신규 리메이크는 2계층만 새로 쓴다:

| 계층 | 위치 | bombman94/95 에서 |
|---|---|---|
| **공용 프레임워크** | `src/battle`(BattleController/DamageCalculator/ChoreographyRunner/BattlePresenter), `src/cutscene`, `src/map/trigger_system.gd`, `_shared` 도구(johab/PCX/VOC) | **그대로 이식** — 안무 JSON 채널 계약은 엔진 무관 |
| **게임 데이터** | `data/**`(battle_moves/skills/monsters/cutscenes/triggers) | 전면 교체(원작 데이터 변환기만 작성) |
| **게임 전용 로직** | field/battle 씬 조립, Combatant 성장, 보스 하이브리드 | 부분 재작성 |

원칙: 새 시스템 추가 시 "콘텐츠는 data/**, 메커니즘은 범용 클래스" 경계를 유지할 것.
Combatant.stats 타입 Resource화(CharacterStats)가 남은 결합도 해소 과제(Phase 4 TODO).

### 구현 노트 (이번 세션 결정)

- **판정 단일화**: 데미지 적용은 BattleController.submit_player_command 가 유일.
  안무의 logic apply_damage 프레임은 기록된 결과(`cmd["damages"]`)를 **표현만** 한다.
- **보스전 하이브리드**: `monsters.json` bosses 섹션의 `dodge_phase` 설정이 있으면
  적 턴이 탄막 회피 페이즈로 대체. hits × `dodge_damage_per_hit` = 플레이어 피해.
  (구판 HANDOFF가 인용한 05_toolchain §5.3 문서는 실제 미존재 — 방침만 준용)
- **컷신**: CutscenePlayer 비동기 스텝 해석(dialogue/wait/fade/shake/sfx/bgm/
  set_flags/actor_move/start_battle). DialogueBox에 auto_advance 모드 추가(컷신 전용).
- **트리거**: zone/interact/auto 3종, done_flag 1회성, requires_flag 조건.
  F1 프롤로그는 auto 트리거 → opening.json(@c101~@c106) 재생.
- **교훈**: `else if` 구문에서 파싱 실패(원인 불명, `elif` 로 우회) +
  글로벌 클래스 캐시 재구축 필요(`--import`). 신규 클래스 추가 후 반드시 import.
- Godot 4.7.2 를 `_shared/tools/godot/` 에 설치함.

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
