# 07. AI 생성 에셋 파이프라인 (비주얼·오디오 인터페이스)

> **전제**: 스프라이트·타일·컷신 아트·일러스트·BGM·효과음은 **외부 AI로 생성**한다.
> 본 문서는 게임 프로젝트와 생성 AI(이미지/오디오 모델, LLM 에이전트) 사이의
> **계약서 인터페이스**를 정의한다.
>
> 원칙 3줄:
> 1. **JSON 스펙 = 유일한 진실** — 게임이 요구하는 형식을 기계가 검증 가능하게 고정
> 2. **프롬프트/MD 브리프 = 파생물** — 스펙에서 자동 렌더. LLM은 MD 한 장을 읽고 작업
> 3. **검증 통과분만 채택** — 규격 위반 산출물은 게임에 절대 유입 불가

## 1. 전체 흐름

```
[게임이 필요로 하는 것]                [AI 생성 영역]                 [채택 게이트]
spec/*.json ──render_specs.py──► gen/prompts/*.md ──외부 AI──► assets/raw/** ──validator──┐
     ▲                              (LLM이 읽고 실행)            (버전 n 누적)             │ 통과
     │                                                                                      ▼
res://assets/** ◄──────────── converters (atlas 패킹/SpriteFrames/.tres/ogg) ──────── 정규화·리네임
```

- 사람/AI 어느 쪽이 생성하든 동일 게이트. "누가 만들었나"가 아니라 "계약 통과 여부"만 중요.
- `assets/raw/`는 버전 누적(`sheet_v1.png`, `v2.png`…) — 재생성 이력 보존, 롤백 가능.

## 2. 디렉터리 구조

```
assets/
├── style_bible.md              ★스타일 바이블 — LLM/사람 공용 창작 규칙서
├── palette_master.json         팔레트 잠금 파일(hex 배열, DEFAULT.PAL 현대화판)
├── spec/                       ★계약서 (유일한 진실, JSON Schema 강제)
│   ├── sprites/*.json          캐릭터 시트·타일·오브젝트·UI 부품
│   ├── illustrations/*.json    초상화(FACE 계승), 컷신 배경, 엔딩 카드, 키 비주얼
│   └── audio/
│       ├── bgm.json            BGM 6곡 표 (마스터 시나리오 톤 곡선 매핑)
│       └── sfx.json            효과음 트리거 테이블
├── gen/
│   ├── prompts/                spec→자동 생성된 프롬프트 팩 (*.txt + *_index.md)
│   └── _index.md               render_specs.py 산출 — LLM용 요약본(전체 대시보드)
├── raw/{sprites,illustrations,audio}/<asset_id>/   AI 산출물 원본(v{n} 버전 누적)
└── (변환 완료분은 res://assets/{sprites,illustrations,audio}로 이동)
```

## 3. 듀얼 표현 원칙 — JSON(기계) ↔ MD(LLM)

- `tools/render_specs.py`: `spec/**/*.json` → `gen/_index.md`(전체 요약표) + 카테고리별 MD.
- LLM 코딩/생성 에이전트는 **MD만 읽고도** 어떤 에셋이 필요한지, 프롬프트 규칙, 제약을 파악한다.
- JSON 직접 편집은 도구/정밀 작업용, MD는 인간 리뷰와 에이전트 컨텍스트 주입용.
- 두 표현은 항상 동기(렌더는 단방향, MD 편집 금지 — CI에서 일치 검사).

## 4. 비주얼 스펙

### 4.1 스타일 바이블 (`style_bible.md`) — 최상위 창작 규칙

| 항목 | 내용 예시 |
|---|---|
| 픽셀 아트 규칙 | 안티에일리어싱 금지, 그라데이션 금지, 외곽선 1px 다크아웃라인, 명암 3~4단계 |
| 팔레트 | `palette_master.json` hex만 사용(전역 잠금). 신규 색 추가는 바이블 개정으로만 |
| 시대 톤 | 1995 DOS VGA 감성(마스터 시나리오: "레트로" 축) + 현대 가독성 |
| 캐릭터 일관성 | 캐릭터별 **고정 서술 토큰**(§4.2 prompt_vars.subject) — 모든 배치에서 재사용 |

### 4.2 캐릭터 시트 스펙 (예시)

```jsonc
// assets/spec/sprites/player_sidol.json
{
  "$schema": "../sprite_spec.schema.json",
  "asset_id": "player_sidol",
  "kind": "character_sheet",                    // character_sheet | tileset | object | ui_part
  "cell": { "w": 32, "h": 48 },                  // G-ART 확정값 주입 (24/32/48)
  "grid": { "cols": 6, "rows": 8 },
  "animations": {                                // 행 = 애니메이션 (런타임 SpriteFrames 매핑)
    "walk_down":  { "row": 0, "frames": 4, "fps": 6, "loop": true },
    "walk_up":    { "row": 1, "frames": 4, "fps": 6, "loop": true },
    "walk_left":  { "row": 2, "frames": 4, "fps": 6, "loop": true },
    "walk_right": { "row": 3, "frames": 4, "fps": 6, "loop": true },
    "idle_down":  { "row": 4, "frames": 2, "fps": 2, "loop": true }
  },
  "anchor": { "x": 0.5, "y": 0.9 },              // 발 기준점 (그리드 y-sort용)
  "palette_ref": "../../palette_master.json",
  "constraints": ["transparent_bg", "no_aa", "1px_outline", "palette_locked"],
  "style_refs": ["style_bible.md#characters",
                 "../../../원본참조/i_spr_contact_sheet.png"],   // 원작 도트 = 참고 자료
  "prompt_vars": {
    "subject": "부싯돌: 1995년 한국 공대 새내기, 허둥댄 표정의 활달한 남학생,
                회색 교복 재킷+청바지, 손에 부싯돌 조각"
  },
  "output_contract": {
    "raw_dir": "raw/sprites/player_sidol/",
    "file_pattern": "sheet_v{n}.png",
    "validator": ["tools/validate_sprite.py --spec {spec} --in {file}"]
  }
}
```

### 4.3 타일셋 스펙 (핵심 필드만)

```jsonc
{
  "asset_id": "tileset_campus",
  "kind": "tileset",
  "tile_px": 32,                                  // G-ART 값
  "terrain_rules": {                               // Tiled terrain/autotile 매핑 가능해야 함
    "floor_corridor": { "border_match": true }, "wall_lab": { "border_match": true }
  },
  "required_tiles": ["floor_*","wall_*","door_locked","door_open",
                     "stairs_up","stairs_down","chest_closed","chest_open"],
  "occlusion_overhead": true                       // ATT==2 덮개 타일 세트 포함 여부
}
```

- 변환기가 `required_tiles` ID → TileSet Atlas 좌표를 결정하므로, AI는 **ID 목록을 지키는 것** 외에
  배치 순서를 몰라도 됨(패킹은 우리가 함).

### 4.4 일러스트 / 컷신 아트

| 용도 | 스펙 포인트 |
|---|---|
| 초상화(대화창) | 256×256, 8방향 표정 변형 옵션, 원작 FACE*.PCX 구도 참조 |
| 컷신 배경/키아트 | 마스터 시나리오 각 씬의 "상황" 문단 → scene_id 기반 스펙. 16:9, 1920×1080 권장(다운스케일 운용) |
| 엔딩 후일담 카드 ×3 | Q_QUIZ_ALL/Q_QUAN_DONE/Q_HP_ALL — 공통 프레임 템플릿 + 개별 일러스트 |
| CRT/DOS 엔딩 | 이미지 불필요(셰이더+폰트 연출) — 스펙 제외 |

## 5. 오디오 스펙

### 5.1 BGM (`spec/audio/bgm.json`) — 6곡 (04_uiux §5 확정분)

| id | 용도 | mood_tags | bpm | 길이(sec) | 톤 커브 매핑(마스터 §1.2) |
|---|---|---|---|---|---|
| bgm_title | 타이틀 | retro, nostalgic | 90~110 | 60~90 | - |
| bgm_field | 필드 공용 | retro, adventure | 100~130 | 60~120 | 레트로 60% |
| bgm_battle | 일반 전투 | chiptune, driving | 130~160 | 30~60 | - |
| bgm_boss | 보스/SYS_BUILDER | tense, industrial | 140~170 | 60~120 | 메타 20% 구간 |
| bgm_basement | 지하 탐색 | dusty, quiet | 70~90 | 60~120 | 탐색 50% |
| bgm_emotional | 4층 희생·엔딩 | sad, majestic | 60~85 | 90~150 | 감동 20%↑ |

공통 제약: `loop: seamless_required`, `instrumentation: FM/PSG 칩튠 음색(square/triangle/noise), 실악기 금지`,
`mix_target: -16 LUFS ±1`, 출력 `ogg 44.1kHz`.

### 5.2 SFX (`spec/audio/sfx.json`) — 트리거 테이블

| id | 트리거(런타임 이벤트) | 길이(ms) | 성격 힌트 |
|---|---|---|---|
| sfx_menu_move | 커서 이동 | ≤80 | 짧은 클릭 |
| sfx_item_get | 아이템 획득 | ≤600 | 상승 아르페지오 (원작 play_music[0] 재해석) |
| sfx_encounter | 인카운터 | ≤800 | 충격음+경보 (원작 "쾅!~~") |
| sfx_hit_player / sfx_hit_enemy | 피격 | ≤300 | 타격감 차등 |
| sfx_door_open / sfx_explosion / sfx_thunder | 문/폭파/4층 아크 | - | 원작 VOC 목록 참조 |
| voice_* | DEAD/WIN/DOMANG 등 원작 보이스 | - | **원작 VOC 변환본 유지**(재생성 아님) |

- 원작 PC 스피커 배열(sound_box/play_music 주파수표)은 **프롬프트 힌트 소스**로 활용:
  "원곡은 220Hz→392Hz 상승 20스텝 시퀀스" 식의 서술을 sfx.json에 자동 주입.

## 6. 프롬프트 팩 규칙 (`gen/prompts/`)

```
{asset_id}.txt        # 스펙+바이블+prompt_vars를 조립한 최종 프롬프트
{asset_id}_neg.txt    # 네거티브(anti-aliasing, watermark, text, gradient, extra limbs…)
_category_index.md    # 카테고리 요약 — LLM 에이전트의 작업 대기열
```

- 템플릿 변수: `{{STYLE_TOKEN}}`(바이블 해시 — 버전 추적), `{{PALETTE_HEX}}`, `{{CELL}}`, `{{SUBJECT}}`.
- **금지**: 프롬프트 파일 수동 편집 후 재렌더 미실행(CI가 drift 검출).
- 오디오용 프롬프트는 텍스트-투-뮤직 모델용 브리프 + 실패 시 수동 작곡가용 브리프 이중 출력.

## 7. 검증기 (채택 게이트)

| 대상 | 자동 검사 |
|---|---|
| 스프라이트 시트 | 캔버스=cell×grid 정확 일치, 프레임 경계 침범 없음, 팔레트 hex 이탈 0건, 투명배경, 앵커 하단 여백 |
| 타일셋 | required_tiles 전 존재, terrain border 매칭 샘플 통과, 타일 px 일치 |
| 일러스트 | 해상도/비율, 안전 마진, 얼굴 검출(선택), 스타일 토큰 유사도(선택) |
| BGM | 길이 범위, 루프 심리스(엔드-스타트 크로스페이드 무결성), LUFS, 클리핑 0건, ogg/샘플레이트 |
| SFX | 길이 상한, 무음 구간 트림, 피크 레벨 |

- 실패 시 리포트에 **재생성 프롬프트 수정 제안**까지 포함(예: "프레임 3에서 배경 오염 → 네거티브 추가").
- 게이트 통과 → 컨버터(atlas 패킹, SpriteFrames .tres, AudioStreamOggVorbis) → res:// 반영.

## 8. 원작 에셋의 역할 재정의

| 원본 | 새 역할 |
|---|---|
| .SPR (sed.lib 포맷) | **직접 추출 불요**. DOSBox 캡처 컨택트시트를 만들어 `style_refs` 참조 자료로만 사용.
  R1 리스크(포맷 역공학)는 critical path에서 제외됨 |
| .PCX (HUD/STORE/FACE) | 참조 자료 + 즉시 사용 가능한 것은 변환 후 그대로 채택 병행 |
| DEFAULT.PAL | palette_master.json 생성의 시드 |
| .VOC 보이스 | **변환 후 그대로 사용**(재생성 아님 — 원작 정체성) |
| PC스피커 멜로디 배열 | SFX/BGM 프롬프트의 멜로디 힌트 |

### 8.1 알파 규칙 — 투명의 근거는 팔레트 인덱스뿐 (2026-09-07 확정)

원작 SPR 파생 에셋(`<id>_original.png` · `assets/icons/*` · `obj_original_32.png` ·
`player_original.png`)에서 **알파를 정하는 근거는 팔레트 인덱스 0 하나뿐이다.**
`spr_extract.parse_spr`가 그것만 alpha 0으로 방출한다.

> **금지**: 구운 뒤에 RGB로 투명을 다시 정하는 모든 사후 처리 — 순검정 일괄 키잉,
> 테두리 flood-fill, "배경색 추정" 등. 원작 팔레트에는 RGB(0,0,0)인 인덱스가 **9개**
> 있다(투명 키 0 + 외곽선·그림자 224~231). 팔레트를 잃은 RGB 위에서 이 둘을 가르는 것은
> **원리적으로 불가능**하다. 실제로 이 규칙을 어긴 도구 셋이 외곽선 204,932px을 지웠다
> ([R13](../03_plan/02_risk_assessment.md#r13-팔레트-인덱스를-잃은-뒤-rgb로-투명을-정하기-확률-상이미-발생--충격-상)).

- 에셋이 상했으면 사후 보정이 아니라 **원본에서 다시 굽는다**. 빌더가 정본이다.
- 굽는 레시피는 빌더 안에만 둔다. 관문은 빌더의 `build_*_image()`를 호출해
  게임 파일과 바이트 비교한다(`tools/dev/spr_alpha_check.py` — run_gates.ps1 마지막 단계).
  레시피를 관문에 베끼면 소스가 둘로 갈라져 관문 자신이 사문화된다.
- `assets/originals_ref/bmp_spr/*.bmp`는 **알파가 없는 RGB 중간물**이다. 참고용이지
  에셋 소스가 아니다(`tools/dev/bake_battle_sheets.py`도 같은 경고를 달고 있다).

## 9. DoD (Definition of Done)

- [ ] `spec/` 전체가 JSON Schema 통과 + `render_specs.py`로 MD 재렌더 시 diff 0
- [ ] 대표 에셋 1세트(주인공 시트 + 타일셋 + BGM 1곡 + SFX 3종)가 외부 AI 생성→검증→게임 표시 E2E 통과
- [ ] Validator가 고의로 망가뜨린 샘플(크기 오류, 팔레트 이탈, 루프 끊김)을 전부 차단함
- [ ] LLM 에이전트가 `gen/_index.md`만 읽고 다음 생성 작업 지시를 스스로 도출함 (수동 확인)
