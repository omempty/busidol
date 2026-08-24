# 05. 콘텐츠 제작 툴체인 설계 (외부 에디팅 툴)

> 목표: **맵 / 대화 / 이벤트 / 컷신 / 전투 연출 / 밸런스 데이터**를
> 프로그래머 없이(non-coder) 제작·수정 가능하게 하는 툴 설계.
> 원칙: *"데이터가 계약이다"* — 툴과 게임 런타임은 스키마(JSON/Resource)로만 소통하며
> 어떤 툴도 게임 코드를 직접 건드리지 않는다.

## 1. 툴 구성 매트릭스

| 콘텐츠 | 툴 | 형태 | 근거 |
|---|---|---|---|
| 맵·타일 | **Tiled 1.9+** | 외부 기성품 | 오쏘고널 그리드 RPG 표준. 무한 레이어·커스텀 프로퍼티·폴리라인(순찰 경로) 지원. 자체 제작 불필요 |
| 스프라이트·타일 아트 | **Aseprite** + 변환 스크립트 | 외부 기성품 + CLI | PNG 아틀라스/JSON 내보내기 → Godot SpriteFrames 변환기 |
| 대화·분기 | **Dialogue Editor** | 자체 (Godot 도크) | 원작 대사 ID(@t숫자) 추적, 플래그 조건 분기 시각화 필요 |
| 필드 이벤트 | **Event Editor** | 자체 (Godot 인스펙터+목록) | 트리거 영역→명령 시퀀스 모델 |
| 컷신 | **Cutscene Timeline Editor** | 자체 (Godot 툴 씬) | 액터 이동·카메라·대화·화면효과 타임라인, WYSIWYG 재생 |
| 전투 연출(컷신) | **Battle Choreography Editor** | 자체 (Godot 툴 씬) | 원작의 하드코딩 공격/회피 애니(MyAttackAni 등)를 데이터화 |
| 몬스터·아이템·성장표 | **CSV/Sheets 파이프라인** | 하이브리드 | 표 형태 데이터는 스프레드시트가 최강. 임포터로 ItemDef/EnemyDef/GrowthCurve 생성 |

**왜 자체 툴을 "Godot 에디터 플러그인"으로 만드는가**

1. WYSIWYG 미리보기가 공짜 — 게임 런타임 컴포넌트(CutscenePlayer, BattlePresenter,
   MapRenderer)를 그대로 에디터 안에서 굴릴 수 있음.
2. 배포 단일화 — 게임과 툴이 같은 프로젝트(`addons/`)에 존재. 별도 빌드·동기화 없음.
3. Resource(.tres) 직접 저장 — 중간 포맷 변환 계층 축소.
   (단, 외부 교환용으로 항상 JSON 입출력 병행 — §6)

## 2. 공통 아키텍처

```
┌─────────────── 외부 툴 ───────────────┐      ┌────────── Godot 게임 ──────────┐
│ Tiled(.tmj)  Aseprite(png/json)       │      │                                │
│ Sheets/CSV                            │      │  Runtime Components            │
└──────────────┬────────────────────────┘      │   MapRenderer                  │
               │ import (CLI/headless)         │   CutscenePlayer               │
               ▼                               │   BattlePresenter              │
     ┌──────────────────┐    동일 스키마        │   DialogueRunner               │
     │  res://data/**   │◄──────────────────►│   TriggerSystem                │
     │  JSON ↔ .tres    │    export           └────────────▲───────────────────┘
     └──────────────────┘                                  │ 읽기만
               ▲                                           │
               │            ┌──────────────────────────────┴─────────────┐
      저장(검증 후)          │  addons/rpg_tools/  (자체 에디터 플러그인)     │
               └───────────│   DialogueDock / EventInspector /           │
                           │   CutsceneTimeline / BattleChoreo /         │
                           │   ValidatorPanel / ImportExportMenu         │
                           └─────────────────────────────────────────────┘
```

- **단방향 의존**: 에디터 → 데이터(읽고 씀), 게임 → 데이터(읽기만). 게임 코드는 절대 에디터를 참조하지 않음.
- **Op 레지스트리**: 이벤트 명령(`op`)과 컷신 트랙 타입은 하나의 레지스트리에 등록.
  게임 해석기와 에디터 UI 양쪽이 같은 레지스트리를 사용 → 새 op 추가가 즉시 양쪽에 반영.
- **검증기(Validator)**: 저장 전 스키마+참조 검사. 깨진 참조(@t 인덱스 초과, 없는 액터 ID,
  도달 불가능한 플래그 조건, 순환 대기) 목록 패널에 표시.
- **대사 ID 범위 규칙**(마스터 시나리오 §4.1): `@t000~230`은 원문 불변 참조 전용(재작성 문장에
  `@t` 사용 시 오류), `@c`는 구역 대역 강제 — 지하 001~099 / 1층 101~199 / 2층 201~299 /
  3층 301~399 / 4층 401~499 / 5층 501~599 / 에필로그 601~699.

## 3. 이벤트 시스템 + Event Editor

### 3.1 데이터 모델 (게임 런타임과 공유)

```jsonc
// data/events/campus_events.json
{
  "schema_version": 2,
  "events": [
    {
      "id": "hp_room_enter",
      "trigger": {
        "kind": "zone",             // zone | interact | item_use | auto | flag_change
        "map_id": "f2",
        "cells": [[110, 40], [110, 41]],
        "when": "!flags.hp_room_seen",
        "once": true
      },
      "actions": [
        { "op": "fade_out", "args": { "duration": 0.5 } },
        { "op": "change_scene", "args": { "scene": "credit_room" } },
        { "op": "set_flags", "args": { "hp_room_seen": true } }
      ]
    },
    {
      "id": "quizman_talk",
      "trigger": { "kind": "interact", "npc_id": "quizman" },
      "actions": [
        { "op": "branch", "args": {
            "cases": [
              { "when": "flags.quiz_done", "goto": "quiz_after" },
              { "default": true, "run": ["dialogue:quiz_intro", "quiz:start", "set_flags:quiz_done=true"] }
            ]}}
      ]
    }
  ]
}
```

### 3.2 Op 어휘 (1차 버전 — 원작 이벤트 전량 커버)

| 분류 | op |
|---|---|
| 대사 | `dialogue`(시퀀스 재생·완료 대기), `choice`(선택지→분기) |
| 흐름 | `branch`, `wait`, `label/goto`, `run_event`(다른 이벤트 호출) |
| 상태 | `set_flags`, `give_item`, `take_item`, **`grant_skill`(스킬 습득)**, `give_exp/money`, `heal` |
| 월드 | `spawn_actor`, `despawn_actor`, `move_actor`(경로), `teleport_player`, `open_door`, `place_chest`, **`unlock_transition`(계단/문 게이트 해제 — requires_flag 해소)** |
| 아이템 조합 | **`craft`(재료 소모→산출물. 폭탄 3재료, 해독제 3약품 합성 등)** |
| 씬 | `start_battle`(전투 스크립트 훅 포함, §5.3 참조), `start_cutscene`, `change_map/floor`, `shop`, **`minigame_quiz`, `minigame_battery_circuit`(직렬 전압 퍼즐)** |
| 연출 | `fade_in/out`, `shake`, `flash`, `sfx`, `bgm`, `portrait`(얼굴 클로즈업 — 원작 Hong_P 등의 후속) |

- 확장 규칙: 새 op는 레지스트리 한 곳에 추가 → 해석기(TriggerSystem)와 에디터 드롭다운에 자동 노출.
- **원작 매핑**: event1()(여자 컷신), Run_Event_HP(), Quiz_Man(), store() 진입, 교수 퀘스트 플래그
  로직 전부 위 op 조합으로 치환 가능 — 하드코딩 switch(Talk())는 데이터로 완전 이관.
- **마스터 시나리오 매핑**(04_scenario/03_remake_scenario_master): 3약품 합성=`craft`,
  완종이 브로마이드=`take_item+set_flags`, 4층 전압 퍼즐=`minigame_battery_circuit`,
  동료 희생 컷신=컷신 스텝(`bgm` 전환 포함), SYS_BUILDER전=`start_battle(script:...)`.

### 3.3 Event Editor UI (Godot 도크)

- 좌: 이벤트 목록(맵별 필터) / 우: 트리거 속성 + 액션 리스트(위아래 이동, 복제).
- 액션 행은 op 선택 → args 인스펙터 자동 생성(타입 기반).
- "맵에서 영역 찍기" 버튼: 열린 맵 씬에서 드래그로 cells 채움 (Tiled 좌표와 동일 격자).
- 저장 시 Validator 실행 → 오류 0건만 파일 반영.

## 4. 컷신 시스템 + Cutscene Timeline Editor

### 4.1 데이터 모델

컷신은 **순차 명령열 + 선택적 병렬 트랙**. RPG 이벤트는 타임라인 절대시간보다
"끝날 때까지 대기" 시맨틱이 자연스러움 (원작 event1()의 for루프 이동들과 일치).

```jsonc
// data/cutscenes/opening.json
{
  "id": "opening_event1",
  "actors": { "girl": { "def": "npc_girl", "at": [107,15] }, "$player": {} },
  "steps": [
    { "op": "actor_move",  "actor": "girl", "path": "auto_to:$player", "anim": "walk" },
    { "op": "dialogue",    "seq": "@opening.girl_1" },
    { "op": "parallel", "steps": [
        { "op": "actor_move", "actor": "$player", "path": [[104,16],[103,17]] },
        { "op": "camera_follow", "target": "$player", "smooth": true }
    ]},
    { "op": "battle", "enemy": "dworm", "win": "continue", "lose": "@opening.defeated" },
    { "op": "shake",  "power": 4, "time": 0.6 },
    { "op": "end" }
  ],
  "skippable": true
}
```

- `path`는 셀 좌표 배열 또는 Tiled 폴리라인 이름 참조(맵 데이터 재사용).
- `$player`는 런타임 주입 액터. 액터 def는 NpcEntity 씬 프리팹 ID.
- CutscenePlayer(게임)와 에디터 프리뷰어가 **같은 해석기 클래스**를 사용.

### 4.2 에디터 UI

- 중앙: 스텝 타임라인(드래그 정렬, 병렬 블록 들여쓰기 시각화).
- 하단: **미리보기 뷰포트** — 현재 맵 위에서 ▶ 재생(게임과 동일 렌더). 스텝 클릭 시 해당 지점부터 재생.
- 액터 팔레트: 맵에 배치된 NPC/플레이어를 클릭해 액터 바인딩.
- 원작 대본(PROLOG.CAP) 이식 워크플로: 대본 문단 ↔ 스텝 1:1 대응 표를 문서로 유지하며 작업.

## 5. 전투 연출(배틀 컷신) + Choreography Editor

원작의 문제: 공격/회피 애니가 WARMODE.C에 페이지 복사 루프로 하드코딩(AttackAni1~3, MAvoid1~3...).
재설계: **연출은 무브(move) ID당 하나의 안무(choreography) 리소스**.

### 5.1 데이터 모델

```jsonc
// data/battle_moves/player_atk_03.json
{
  "id": "player_atk_03",
  "side": "player",
  "length": 1.2,
  "channels": {
    "sprite": [
      { "t": 0.0, "actor": "self", "anim": "rush", "pos": [200, 0] },
      { "t": 0.5, "actor": "self", "anim": "attack", "pos": [60, 0] }
    ],
    "fx":       [ { "t": 0.62, "effect": "hit_spark", "at": "target_center" } ],
    "camera":   [ { "t": 0.55, "zoom": 1.15, "pan": "target" } ],
    "screen":   [ { "t": 0.62, "shake": 5 }, { "t": 0.7, "flash": "#fff", "a": 0.35 } ],
    "audio":    [ { "t": 0.0, "sfx": "atk_shout_03" }, { "t": 0.62, "sfx": "impact_heavy" } ],
    "logic":    [ { "t": 0.62, "apply_damage": true } ]   // 데미지 적용 프레임 명시
  }
}
```

- **로직-연출 분리 유지**: `apply_damage` 타이밍만 데이터가 지정, 실제 수치는 DamageCalculator.
- BattlePresenter는 이 리소스를 AnimationPlayer/Tween으로 컴파일해 재생.
- 원작 8종 몬스터 × 공격/피격/승리/패배 안무를 이 포맷으로 마이그레이션.
  e1~e8.spr, a*.spr, d*.spr, fire.spr 스프라이트가 그대로 채널 소스가 됨.

### 5.2 에디터 UI

- 좌: 무브 목록(몬스터별 그룹) / 중앙: 스테이지 뷰(실제 전투 씬 배경 sample2/TEST_F 위에서 재생) /
  우: 채널 키프레임 인스펙터.
- 키프레임 드래그, 스켈리톤 없는 스프라이트 애니므로 위치+애니클립 타이밍 중심의 단순 UI.
- "히트 프레임" 가이드라인 표시(apply_damage 위치).

## 6. 데이터 교환 및 버전관리 전략

| 항목 | 방침 |
|---|---|
| 권위 포맷(Authoritative) | `res://data/**/*.json` (텍스트=git diff 친화). `.tres`는 Godot 전용 파생물로 임포터가 생성 |
| 임포터 실행 | 에디터 메뉴 + CI(headless): `godot --headless --script tools/import_all.gd` |
| 스키마 버저닝 | 모든 json에 `schema_version`. 마이그레이션 스크립트를 임포터에 체인 |
| 파일 단위 | 이벤트/컷신/무브 각각 파일 1개씩 → 머지 충돌 최소화 |
| 로컬라이징 준비 | 문자열은 `tr_key` 참조만 하고 실제 문장은 `data/l10n/ko.csv`에 분리 |
| 밸런스 파이프라인 | Google Sheets → CSV 다운로드 스크립트 → items/enemies/growth.json 생성 (원작 ITEM_STRUCT/LEVELsruct/PATTERN 표 이식처) |

## 7. 개발 우선순위 (툴)

| 순서 | 툴 | 이유 |
|---|---|---|
| T1 | JSON↔Resource 임포터 + Validator | 모든 것의 전제 |
| T2 | Dialogue Editor (목록형 먼저, 그래프는 나중) | 대사량이 최대 콘텐츠 |
| T3 | Event Editor | 퀘스트/트리거 구현의 생산성 지배 |
| T4 | CSV 파이프라인 (items/enemies/growth) | 원작 데이터 이식에 즉시 필요 |
| T5 | Cutscene Timeline Editor | 오프닝/층 에피소드 집필 단계부터 |
| T6 | Battle Choreography Editor | 전투 연출 고도화 단계(후반) |

> 초기 개발(T1~T4)에는 에디터 UI 없이 **JSON 직접 편집 + Validator + 프리뷰 키**로도 충분.
> UI는 콘텐츠 양이 임계점을 넘을 때 투자 — 과설계 방지.

## 8. 완성 판정 기준 (Definition of Done)

- [ ] 새 방/퀘스트/괴물 1종을 **코드 수정 0건**으로 추가 가능 (데이터+에셋만)
- [ ] Tiled에서 맵 수정 → 게임 재실행 없이 리로드(F5) 반영
- [ ] 컷신 1편을 에디터에서 만들어 프리뷰 → 게임에서 동일 재생 확인
- [ ] Validator가 참조 오류를 전부 잡아냄 (깨진 상태로 저장 불가)
- [ ] 모든 data/*.json이 git diff로 리뷰 가능한 형태 유지
