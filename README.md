# 부싯돌 컬렉션 (busidol)

> 1995년 대구대 전산과 게임동아리 **부싯돌**의 DOS 게임 원본 보존소 + Godot 리메이크 워크스페이스.
> 레이아웃 확정: 2026-08-24 (MANIFEST.sha256 해시 검증 완료)

## 구조

```
부싯돌시절\
├── _shared\      dosport 공용 패키지(johab/PCX/VOC/SPR) + 스키마 + 템플릿
├── originals\    ★원본 보존区 — 수정 금지 (MANIFEST.sha256 무결성)
│   ├── 1994_bombman_dos\      BOMB (BombMan '94)
│   ├── 1995_bombman_dos\      BOMB95 (BombMan '95)
│   └── 1995_sidol_bsd_dos\    BSD 시돌이의 모험
├── remakes\
│   └── sidol_godot\           ★진행 중 — Godot 4.x 리메이크
├── 게임실행.bat / 검증실행.bat / 에디터실행.bat
└── README.md
```

## 규칙

1. **originals/**: 읽기전용 — MANIFEST.sha256과 불일치 시 훼손
2. **경로**: 기계 경로 ASCII, 한국어 원명은 매니페스트 헤더가 공식 기록
3. **공용 vs 전용**: 포맷 도구(johab/PCX/VOC/PAL) → `_shared`, 프로젝트 변환기 → `remakes/*/tools/`
4. **새 포팅**: `_shared/templates/` 스캐폴드 → `remakes/<id>_godot` 생성

## 현재 진행

| 프로젝트 | 상태 | 상세 |
|---|---|---|
| **sidol_godot** | Phase 0~7 완료 · Phase 8 진행 중(오디오 인프라·리터칭 시범) | [문서](remakes/sidol_godot/docs/README.md) |
| bombman94_godot | 대기 | sidol 파이프라인 재사용 |
| bombman95_godot | 대기 | 〃 |

## sidol_godot 구현 상태

| 시스템 | 파일 | 상태 |
|---|---|---|
| 맵 로딩·렌더(원작 도트) | MapRenderer + tiles_original_32.png | ✅ |
| 그리드 이동·충돌(2×2 발판) | GridMover + PlayerEntity(원작 I.SPR 도트) | ✅ |
| 층 전환(F1↔…↔F0↔F5) | TransitionGate + transitions.json | ✅ |
| 문 통과(ATT==9 mapy±3) | TransitionGate._try_door | ✅ |
| 미니맵(M키 토글) | MinimapLayer | ✅ |
| NPC 배치·대화창(@t/@c 조회) | NpcEntity + DialogueBox + Database | ✅ |
| 몬스터 AI(BFS 추적+배회+분산) | AIBrain/WanderAI/ChaseAI/EnemyManager | ✅ |
| 인카운터→전투 씬 전환 | field.gd → BattleSceneController | ✅ |
| 전투 커맨드(공격/기술/방어/도망) | BattleSceneController | ✅ |
| 데미지 계산(속성 약점 ×1.5) | DamageCalculator | ✅ |
| 스킬 6종(SkillDef) | data/skills.json | ✅ |
| 상태이상(DoT/버프/마비) | StatusEffectDef + Combatant.tick_effects | ✅ |
| 인벤토리(add/remove/count) | Inventory + items.json 63종 | ✅ |
| 상점 UI | ShopUI(구매→소지금 차감→Inventory.add) | ✅ |
| 회피 페이즈(탄막 10패턴) | DodgePhase | ✅ |
| 보스전 하이브리드(턴제+탄막 회피) | BattleSceneController._run_dodge_phase + monsters.json bosses | ✅ |
| 컷신 재생기(비동기 스텝 해석) | CutscenePlayer + data/cutscenes | ✅ |
| 이벤트 트리거(zone/interact/auto) | TriggerSystem + triggers_f*.json | ✅ |
| 프롤로그 컷신(씬 1-1 무대화) | opening.json + @c101~@c106 | ✅ |
| 전투 UI 계층 분리 | BattleUI(시그널 통신) | ✅ |
| 데이터 스키마 껍데기 3종 | _shared/schemas/{event,cutscene,battle_move} | ✅ |
| 크레딧룸(멤버/후일담카드/스탭롤) | credit_room.gd + credits.json | ✅ |
| 최종보스 각성 컷신+트리거 | boss_sys_builder.json + triggers_f5.json | ✅ |
| 데이터 Validator(교차참조 검사) | tools/validate.gd (대사키·안무·아이템·컷신) | ✅ |
| 퀴즈 미니게임 프레임워크 | QuizMinigame + data/minigames/quiz_man.json | ✅ |
| craft/grant_item op(해독제 합성) | CutscenePlayer + quiz_paline.json | ✅ |
| 배터리 회로 퍼즐(10,000V) | BatteryCircuitMinigame + battery_puzzle.json | ✅ |
| 전투 승리→에필로그→엔딩 흐름 | on_win_flag + epilogue.json | ✅ |
| Event Editor v0 | addons/event_editor (컷신 스텝 편집) | ✅ |
| 세이브/로드 3슬롯+오토세이브(Q1) | SaveManager + 타이틀 계속하기·일시정지 메뉴 | ✅ |
| 설정 저장(볼륨·연출속도·아트모드·글자크기 Q9) | SettingsManager + SettingsPanel | ✅ |
| 진행 기록(Q3) | QuestLogPanel + data/quests_v2.json | ✅ 골격 |
| 부팅 인트로(DOS 스타일) | scenes/boot_intro.tscn | ✅ |
| 디버그 패널+자가검증(F10, 개발빌드) | DebugPanel + SelfCheck(smoke_selfcheck 게이트) | ✅ |

## Phase 진행

| Phase | 내용 | 상태 |
|---|---|---|
| 0~5 | 기반·맵·필드·대화·전투 코어·인벤토리 | ✅ |
| 6 | 전투 연출(안무/히트스톱/보스 회피 하이브리드) | ✅ |
| 7 | 컷신·이벤트·미니게임·크래프트·엔딩·에디터 v0 | ✅ |
| 8 | 도트/오디오 AI 생성 배치 | 진행 중(LLM 워크플로우 완비) |
| 9 | 세이브·설정·시나리오 데이터 완충 | **진행 중(세이브·설정·부팅·도움말·접근성·진행기록 완료)** |
| 전투 안무(battle_moves JSON 재생) | ChoreographyRunner + BattlePresenter | ✅ |
| 히트스톱·화면 흔들림 | BattlePresenter | ✅ |
| 데미지 팝(속성 색상·크기 비례) | BattlePresenter.ELEMENT_COLORS | ✅ |
| 크레딧룸 | credit_room.tscn/gd | ✅ 골격 |
| 난이도 상/중/하 | growth.json difficulty_presets | ✅ |

## 빠른 시작

```
게임실행.bat       더블클릭 → 필드에서 걷기·전투·대화 플레이
검증실행.bat       더블클릭 → import+validate+smoke 자동 검증
에디터실행.bat     Godot 에디터 열기
```
