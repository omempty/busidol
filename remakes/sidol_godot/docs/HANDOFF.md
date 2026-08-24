# 세션 핸드오프 — 다음 세션 시작 가이드

> 작성일: 2026-08-24 · Phase 5 완료 시점

## 1. 현재 상태 한 줄 요약

Phase 0~5 완료(필드 걷기·대화·전투 코어·몬스터 AI·인벤토리).
다음은 **Phase 6 전투 연출**부터.

## 2. 다음 세션 첫 명령

```bash
# 게임 실행 확인
remakes\sidol_godot\게임실행.bat

# 검증 관문 확인
remakes\sidol_godot\검증실행.bat
```

## 3. 다음 작업 (Phase 5.5~6)

| 순서 | 작업 | 파일 |
|---|---|---|
| 1 | ChoreographyRunner 연결 — battle_moves JSON 재생으로 공격 안무 가시화 | `src/battle/choreography_runner.gd` (작성됨, BattleSceneController 연결만) |
| 2 | 히트스톱 + 화면 흔들림 구현 | `_shake_power` 변수 존재, 실제 카메라 오프셋 적용만 |
| 3 | 데미지 팝 개선 — 속성 색상·크기 비례 | `_show_damage_number()` 이미 있음, 강화만 |
| 4 | DodgePhase → 보스전 연결 | `src/battle/dodge_phase.gd` (작성됨) |

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
