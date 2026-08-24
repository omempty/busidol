# 03. 데이터 마이그레이션 + 외부 에디터(Tiled) 연동

> 원본 리소스 → Godot 데이터로의 변환 파이프라인 명세.
> 모든 변환기는 **재실행 가능한 CLI 스크립트**(원본은 읽기 전용, 출력은 res://data).

## 1. 파이프라인 전체 지도

```
원본 (읽기전용 보존)                    변환 도구                 Godot 산출물
─────────────────────                ─────────────────        ──────────────────
F0~F5.MAP ────────┐
EVENT1.EVT ───────┤                  tools/convert/
TALK.TXT(Johab) ──┤  Python 3.11+    map_convert.py   ─────► data/maps/*.json (→Tiled 호환)
ITEM 표(소스) ────┼──────────────►    talk_convert.py  ─────► data/dialogue.json
LEVEL/PATTERN표 ──┤                   evt_convert.py   ─────► data/cutscenes/opening.json
PCX ──────────────┤                   tables_convert.py────► items/enemies/growth.json
SPR(도트 참조) ────┤                   pcx_convert.py   ─────► assets/sprites/**.png
VOC ──────────────┘                   AI 생성 배치*     ─────► assets/sprites/atlas*.png+json
ffmpeg ────────────────────────────► voc→wav           ─────► assets/audio/**
(*스프라이트/타일은 AI 생성이 메인 경로 — §5.2 및 07_ai_asset_pipeline §1)
```

- 원칙: 원본 폴더는 **절대 수정 금지**. 변환기는 언제든 재실행 가능(idempotent).
- Johab 디코딩: Python 내장 `bytes.decode('johab')` — 검증 완료.

## 2. 맵 변환 + Tiled 연동 (핵심)

### 2.1 방향 선택: "Tiled를 권위 포맷으로"

```
[일회성] F#.MAP ─map_convert.py─► data/tiled/f#.tmj (+tileset.tmj)
[이후 편집] Tiled에서 .tmj 직접 편집 (레이어/충돌/이벤트폴리라인/NPC배치)
[임포트] godot --headless tools/import_all.gd ─► TileMapLayer 구축용 JSON/.tres
```

- 이유: 맵 편집 주체가 사람이므로 기성 에디터가 권위. 자체 포맷을 거치면 동기화 부채만 발생.
- `.tmj`(JSON)는 git diff 친화적 → AI 바이브 코딩 리뷰 가능.

### 2.2 MAP→TMJ 변환 규칙

| 원본 | Tiled 표현 |
|---|---|
| TILE 레이어 BYTE[13000] | tilelayer "Ground" (12→24px 스케일 옵션) |
| OBJ 레이어 | tilelayer "Object" |
| ATT 레이어 | 분해: 통행/덮개는 타일 Custom Data(`attr`), 문·계단·방ID는 objectlayer로 승격 |
| ATT 150~184 상자 | objectlayer "chests" (point + property item_id=att-150) |
| NPC ID(16~98) | objectlayer "npc_spawns" (npc_id) |
| 계단 좌표 4종 | objectlayer "stairs" (target_floor, offset, **requires_flag**) —
  리메이크는 비선형 진행(F1→2→3→**F0 지하**→4→5, 마스터 시나리오 §3)이므로
  모든 층 전환은 `requires_flag`로 게이트한다. 게이트 예시:
  **3층 계단 = `Q_F2_POSTER`(완종 제압)** / **지하 진입 = `Q_F3_CURE_DONE`(해독제 완성)** /
  **4층 진입 = `Q_F0_DISK`(디스켓·책 발굴)** |
| EVENT1.EVT 경로 | polyline 오브젝트 "cutscene_paths" |

### 2.3 TileSet 구성

- AtlasTexture 소스: tile.png / object.png 아틀라스.
- Custom Data Layers: `attr:int`, `occludes:bool`, `zone_id:int`.
- 물리 레이어: BLOCKED 타일에 사각 콜리전 폴리곤 자동 부여(변환기가 attr 기반 생성).
- Godot 임포터는 TMJ → `MapDefinition` 리소스 생성(MapRenderer가 소비).

## 3. 대사 변환 (talk_convert.py)

```
입력: TALK.TXT (Johab C 배열)
출력: data/dialogue.json = { "@t0": "...", "@t1": "...", ... }
옵션:
  --keep-comments  주석(#장면 설명)을 메타 "scene" 필드로 보존
  --validate-refs  코드의 Talk_Window(...,num,len) 호출과 인덱스 대조 리포트
```

- 빈 문자열(#87~100 등)은 그대로 유지 — 인덱스 안정성 우선.
- **dialogue_v2.json 작성 규칙**(마스터 시나리오 §4.1 + 부록 A):
  - `@t0~230` = 원문 불변. 재작성 문장에 `@t`를 쓰면 Validator 오류(→ 신규 `@c*` 발급).
  - `@c*` 구역 대역 강제: 지하 001~099 / 1층 101~199 / 2층 201~299 / 3층 301~399 /
    4층 401~499 / 5층 501~599 / 에필로그 601~699.
  - HP실 멤버 대사 등 원작 하드코딩분은 `@t`가 아니라 `@c2xx`로 발급(원본 TALK.TXT 밖 데이터).
- 옵션 추가: `--check-id-ranges` — 위 대역 규칙 + `@t` 원문 일치 검사.

## 4. 테이블 변환 (tables_convert.py)

| 소스(하드코딩) | 산출 |
|---|---|
| ITEM_STRUCT(GOODITEM.H, 37종) | items.json — id/name/kind/bonus/sprite_ref |
| WARMODE.H ITEM_TABLE(24종) | 위에 병합(불일치 목록 리포트) |
| LEVELsruct/ME_LEVEL(20단계) | growth.json |
| PATTERN/EVE_PATTERN | patrol_paths.json (TMJ 폴리라인으로도 병행 출력) |
| move_enemy 층별 난수 범위 | enemies.json stats_by_floor |
| store() 가격/HP 표 | shop.json |
| Quiz_Man quiz 배열 | events/quiz.json |
| **마스터 시나리오 §4.2 플래그표** | **quests_v2.json — Q_F1_START~Q_ENDING 18종 + 서브퀘스트
  해금 카드(Q_QUIZ_ALL/Q_QUAN_DONE/Q_HP_ALL). 원본은 수기 문서이므로 수동 작성 후
  Validator가 코드/컷신 참조와 일치 검사** |
| **마스터 시나리오 §2.2 스킬트리** | skills.json — SkillDef 6종(choreography_id 포함) |
| **퀘스트 아이템 ID 매핑**(마스터 시나리오) | items.json에 신규 ID 체계 병기 —
  **원작 승격**: `ITEM_DISK`(원작 DISK), `ITEM_BOOK`(원작 BOOK), `ITEM_SOPO`(원작 SOPO) /
  **순수 신규**: `ITEM_CURE`(안티 바이오틱-X), `ITEM_LIGHTER`, `ITEM_GASOLINE`,
  `ITEM_POSTER`(만화 브로마이드), `ITEM_DIPLOMA`(졸업 확인서), `ITEM_APPROVAL`(연구비 품의서).
  원작 인덱스(150+) ↔ 신규 id 대응은 items.json의 `legacy_ref` 필드로 영구 유지 |

## 5. 이미지 변환

### 5.1 PCX (확정)

```bash
# Pillow 또는 ImageMagick
python tools/convert/pcx_convert.py --in "*.pcx" --out assets/sprites/ --pal DEFAULT.PAL
```

- 팔레트 적용 필수(PCX는 인덱스 색). DEFAULT.PAL 768바이트 가정 — 헤더 유무 확인 후 처리.
- 대상: TEST_F(HUD 프레임), STORE, HP, FACE*, I-V/M-R/M_E/V-* (전투 배경).

### 5.2 SPR — **AI 재생성이 메인 경로** (2026-08-24 정책 변경)

> 에셋은 AI 생성으로 공급하기로 확정(→ [07_ai_asset_pipeline.md](07_ai_asset_pipeline.md))에 따라
> SPR 포맷 역공학은 **critical path에서 제외**되었다. 원작 스프라이트는 추출 대상이 아니라
> 생성 품질의 **참조 자료**다.

```
메인:   AI 재생성 — spec/sprites/*.json 계약서 → 외부 생성 → Validator 게이트 → 아틀라스 패킹
참조:   DOSBox에서 sidol.exe 실행 → 화면 캡처 컨택트시트 제작 → style_refs로 프롬프트에 첨부
        (SCAP.C가 원래 캡처 도구였음 — 동일 워크플로의 현대판)
선택:   SPR 포맷 해독은 여유 리소스 시 부수 과제(성공해도 원작 도트를 '참고 이미지'로
        더 정밀하게 첨부할 수 있는 수준)
```

- 스프라이트 분할 규격(셀 크기/인덱스 의미)은 역공학과 무관하게 소스 주석으로 이미 확정 가능:
  spt[0~7]=플레이어 4방향×2프레임, 적 8방향 단위 등 — [01_analysis/03_data_format_spec.md](../01_analysis/03_data_format_spec.md).
  이 규격이 곧 `spec/sprites/*.json`의 grid/animations 정의로 이행된다.
- .PCX(HUD/STORE/FACE 등)는 기존대로 변환 후 즉시 사용 병행.

## 6. 오디오 변환

```bash
ffmpeg -i D1.VOC -ar 22050 d1.wav     # VOC→WAV (음성류)
# PC스피커 sound_box/play_music은 주파수 배열 → 파이선으로 WAV 렌더:
python tools/convert/pcspk_render.py --src gooditem.c --out assets/audio/sfx/
```

- Voice(SB)와 PC 스피커 SFX를 버스 구분(Voice/SFX).
- BGM은 원작에 없음 → **AI 생성 확정**: 칩튠 6곡(bgm.json 계약) —
  [07_ai_asset_pipeline](07_ai_asset_pipeline.md) §5.1 및 04_uiux §5 참조.

## 7. 검증

각 변환기 공통:

```
--report : 변환 건수/경고/스킵 목록
--check  : 출력 검증 (맵=크기 일치·참조 타일 존재 / 대사=@t 연속성 /
           오디오=샘플레이트 정규화 확인)
CI(headless): import_all.gd → validate.gd → smoke.tscn 순차 통과가 녹색 기준
```

## 8. 변환기 구현 순서 (AI 태스크 단위)

1. `talk_convert.py` (Johab+JSON) — 가장 쉬움, 즉시 성공 경험
2. `tables_convert.py` (소스 파싱은 정규식 기반)
3. `evt_convert.py` + cutscene JSON 스키마 v1
4. `pcx_convert.py` + 팔레트 검증
5. `map_convert.py` (MAP→TMJ) ← 물량 최대
6. **스프라이트 AI 생성 배치 연동**(spec→프롬프트 렌더→Validator→패킹; SPR 역공학은 부수 과제) — 07_ai_asset §1
7. `pcspk_render.py`
