# 세션 핸드오프 — 다음 세션 시작 가이드

> 작성일: 2026-08-24 · Phase 6 완료 시점

## 1. 현재 상태 한 줄 요약

Phase 0~6 완료(전투 연출 + 보스전 회피 페이즈 하이브리드까지).
다음은 **Phase 7 (크레딧룸/시나리오 이벤트)**부터 — roadmap 확인.

## 2. 다음 세션 첫 명령

```bash
# 게임 실행 확인
remakes\sidol_godot\게임실행.bat

# 검증 관문 확인 (Godot 4.7.2 — _shared\tools\godot 설치 완료)
remakes\sidol_godot\검증실행.bat

# 전투 스모크 (보스 회피 페이즈 포함)
godot --headless --path remakes/sidol_godot res://tests/smoke_battle.tscn
```

## 3. 다음 작업

| 순서 | 작업 | 파일 |
|---|---|---|
| 1 | battle_scene_controller UI 분리(~450행, 상한 초과) | `_build_ui`/메뉴 계열 → `src/ui/battle_ui.gd` |
| 2 | 보스 출현 트리거 — 시나리오 이벤트 op `start_battle`과 연결 | 마스터 시나리오 §Q_ENDING |
| 3 | battle_moves JSON Schema 껍데기 | `_shared/schemas/` |
| 4 | 크레딧룸 골격 완성 | scenes/credit_room.gd |

### 구현 노트 (이번 세션 결정)

- **판정 단일화**: 데미지 적용은 BattleController.submit_player_command 가 유일.
  안무의 logic apply_damage 프레임은 기록된 결과(`cmd["damages"]`)를 **표현만** 한다.
- **보스전 하이브리드**: `monsters.json` bosses 섹션의 `dodge_phase` 설정이 있으면
  적 턴이 탄막 회피 페이즈로 대체됨. hits × `dodge_damage_per_hit` = 플레이어 피해.
  (HANDOFF 구판이 인용한 05_toolchain §5.3 문서는 실제로 미존재 — 방침만 준용)
- `battle_controller._resolve_skill` all_enemies/self 타게팅 지원,
  self 버프는 피해 판정 제외. Combatant `.stats.ap` 참조 크래시 수정.
- **dodge_phase.gd 잠복 파싱 에러 수정**: 미정의 `_float_cfg()` + 형식 추론 실패.
  지금까지 인스턴스화된 적 없어 발견되지 않았던 것 — 신규 스크립트는 스모크에서
  반드시 한 번은 로드되게 할 것.
- 신규 파일: `src/battle/battle_presenter.gd`, `data/battle_moves/*.json`(7종),
  `tests/smoke_battle.tscn/gd`. Godot 4.7.2 를 `_shared/tools/godot/` 에 설치함.

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
