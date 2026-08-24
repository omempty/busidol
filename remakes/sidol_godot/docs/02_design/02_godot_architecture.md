# 02. Godot 아키텍처

> Godot 4.x (LTS) + GDScript. 프로젝트 전체 씬 트리, 오토로드, 디렉터리, 프로젝트 설정.

## 1. 프로젝트 설정 (원작 재현 + 현대화)

```ini
# project.godot 핵심
[display]
window/size/viewport_width=640      # 논리 해상도 (원작 320x200의 2배 기준)
window/size/viewport_height=360     # 16:9 현대 비율 (원작 320x200은 8:5 — §UIUX 문서 참조)
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
[rendering]
textures/canvas_textures/default_texture_filter=0   # nearest — 픽셀아트 필수
[audio]
buses/default_bus_layout="res://audio/buses.tres"   # Master/BGM/SFX/Voice 4버스
[input]
# keyboard: 화살표/Z(X), SPACE, ENTER, ESC / gamepad: D-pad+A,B,Start
```

- **픽셀 그리드**: `TILE_PX` 상수로만 타일 px 결정(기본 24 = 원작 12의 ×2).
  로직 좌표는 전부 셀(Vector2i) 단위 — 해상도/타일 크기 변경에 코드 무영향.
  (타일 크기 개선 정책은 [04_uiux_modernization.md](04_uiux_modernization.md) §2)

## 2. 디렉터리 구조

```
res://
├── addons/rpg_tools/        # 자체 에디터 플러그인 (05_toolchain 문서)
├── assets/
│   ├── style_bible.md       # ★스타일 바이블 + palette_master.json (07_ai_asset §2/§4.1)
│   ├── spec/                # ★AI 생성 계약서 JSON (sprites/illustrations/audio)
│   ├── gen/                 # spec→렌더 프롬프트 팩 + _index.md (커밋 대상)
│   ├── raw/                 # AI 산출물 원본 v{n} 누적 (게이트 통과 전)
│   ├── sprites/             # 게이트 통과 후 패킹된 PNG 아틀라스
│   ├── illustrations/
│   ├── audio/{bgm,sfx,voice}/
│   └── fonts/
├── data/                    # ★ 권위 포맷(JSON) — 툴과 게임의 계약
│   ├── maps/*.json          # Tiled .tmj에서 생성 or Tiled 직접 출력
│   ├── dialogue.json        # @t숫자 → 텍스트 테이블
│   ├── events/*.json
│   ├── cutscenes/*.json
│   ├── battle_moves/*.json
│   ├── items.csv→items.json # CSV 파이프라인 산출물
│   ├── enemies.json  growth.json  l10n/ko.csv
├── scenes/
│   ├── main.tscn            # 루트: SceneRouter가 자식 교체
│   ├── title/  field/  battle/  credit_room/
│   └── ui/{hud,dialogue_box,menu_layer}.tscn
├── src/
│   ├── core/                # grid_mover, trigger_system, EventBus...
│   ├── entities/{player,enemy,npc}/
│   ├── map/                 # map_definition.gd, map_runtime.gd, map_renderer.gd
│   ├── battle/              # battle_controller, combatant, damage_calculator, presenter
│   ├── dialogue/            # dialogue_runner, conditions.gd
│   ├── cutscene/            # cutscene_player.gd (에디터 프리뷰와 공유)
│   └── autoload/            # 아래 §3
├── tests/smoke.tscn         # 헤드리스 스모크
├── tools/import_all.gd      # CLI 임포터
└── AGENTS.md                # AI 코딩 규칙 (06_ai_dev_guidelines)
```

## 3. 오토로드 싱글턴

| 이름 | 역할 | 대체한 원작 전역 |
|---|---|---|
| `GameState` | 현재 층, CharacterStats, Inventory, GameFlags, chest_overrides | We, f, view[], v_* 플래그 |
| `EventBus` | 전역 시그널 허브 | - |
| `Database` | ItemDef/EnemyDef/DialogueTable/GrowthCurve 로딩·조회 | ITEM_STRUCT, ME_LEVEL |
| `AudioManager` | BGM/SFX/Voice 버스 제어, 재생 API | sound_box/play_music/Voice_Say |
| `SceneRouter` | Title/Field/Battle/Cutscene 전환+페이드 | WarMode() 호출/복귀 패턴 |
| `SettingsManager` | 볼륨/속도/연출스킵/키매핑, user://settings.cfg | WVISUAL/WSOUND/SPEED/gitar() |
| `SaveManager` | 슬롯 저장/로드/오토세이브 | **io()(미구현이었음) 신규** |

## 4. 런타임 씬 트리

```
Main (main.tscn)
├── SceneRouter가 교체하는 현재 씬
│   ├── FieldScene
│   │   ├── MapRenderer
│   │   │   ├── TileMapLayer:Ground / :Object / :Front   # ATT==2 덮개
│   │   │   ├── YSortActors (Player/Enemy/NPC)
│   │   │   └── TriggerSystem (Area2D-less, 그리드 질의)
│   │   ├── Camera2D (limit=맵 크기, position smoothing)
│   │   ├── HUD (Level/Exp/HP/AP/Money — 원작 우측 패널 재현)
│   │   ├── DialogueBox
│   │   └── MenuLayer (메인메뉴/인벤토리/설정/지도)
│   ├── BattleScene
│   │   ├── Stage (배경+Combatants+Presenter)
│   │   ├── BattleMenu / HPBars / DamageNumbers
│   │   └── ChoreographyRunner (battle_moves 재생)
│   └── CutsceneOverlay (레터박스+CutscenePlayer)
└── OverlayLayer (페이드/화이트아웃 공용)
```

## 5. 핵심 흐름 예시

### 5.1 인카운터 (원작 Check_Quang 대응)

```
ChaseAI 접촉 감지 → EventBus.encounter_started.emit(enemy_def)
→ SceneRouter.push_battle(enemy_def)        # FieldScene은 메모리 유지
→ BattleController.run() → 결과 시그널
→ GameState.stats.apply_battle_result(...)  # exp/money/사망 처리
→ SceneRouter.pop()                          # 필드 복귀, 적 despawn
```

### 5.2 대화 상호작용

```
PlayerEntity.interact → InteractionProbe(전방 셀) → NpcEntity.hit
→ DialogueRunner.play(npc.dialogue_for(GameState.flags))
   · 조건 분기는 DialogueSequence.branches (01_oop_redesign §4)
→ 완료 시그널 → 이후 actions(상점 개방, 플래그 세팅) 실행
```

## 6. 입력 설계

| 행동 | 키보드(원작 호환) | 게임패드 | 비고 |
|---|---|---|---|
| 이동 | 방향키 | D-pad/스틱 | 그리드 스냅 이동 유지 |
| 대화/조사/확인 | SPACE 또는 Z | A | 원작 SPACE |
| 메뉴/취소 | ENTER=메뉴, ESC=취소 | Start/Y | 원작 ENTER/ESC |
| 실행 취소 계열 | X | B | 인벤토리 등 |

- InputMap 액션명으로만 코딩(`move_up`, `interact`...) — 리매핑 무료.
- 원작의 `_key[]` 폴링+Multi_Clear 패턴은 Godot 입력 이벤트 모델로 대체하되,
  **격자 이동 중 입력 버퍼 1프레임**을 두어 연속 이동감 보존.

## 7. 성능/품질 노트

- 맵 200×65×3레이어 = 최대 39k셀 — TileMapLayer 네이티브 렌더로 여유. 프리컴파일 불필요.
- 원작의 수동 페이지 플립/Wait_Snow(vsync) 개념은 엔진에 내장 — 재현 코드 없음.
- 60fps 고정 의도, 물리는 이동 판정에만 사용(충돌 주판정은 그리드 질의).
