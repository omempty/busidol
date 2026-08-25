# 세션 핸드오프 — 다음 세션 시작 가이드

> 작성일: 2026-08-25 · Phase 8 진행 중(LLM 스프라이트 워크플로우 + 화면 기반 정비 완료) · 세션 종료 시점

## 1. 현재 상태 한 줄 요약

Phase 0~7 완료 + Phase 8 인프라 완료(AudioManager·Validator·DOSBox·리터칭 파이프라인·
LLM 스프라이트 워크플로우) + **아트 모드 시스템·뷰포트 960×540·투명화 정비**.
다음은 **첫 LLM 납품 수령 → 재가공 → 채택 판정**부터.

## 2. 다음 세션 첫 명령

```bash
# LLM 작업 참조자료 확인 (gitignored 임시区 — 스크립트로 재생성 가능)
remakes\sidol_godot\assets\raw\llm\00_reference\   # 62그룹 929프레임 + 컨택트시트

# 워크플로우 문서
remakes\sidol_godot\assets\gen\prompts\LLM_WORKFLOW.md

# 검증 관문 6단계
remakes\sidol_godot\검증실행.bat
```

## 3. 진행 중: 스프라이트 LLM 리터치/생성 (유저 주도)

**확정 워크플로우**: 추출(extract_sprites.py, 완료) → LLM 의뢰(프롬프트 패키지
gen/prompts/ 참조) → 납품을 assets/raw/llm/10_submitted/ 저장 → **재가공 스크립트**
(마젠타 키잉·스펙 그리드 컷팅·검증 → 20_processed/) → 유저 리뷰 채택 → 패킹.

**다음 세션 할 일 (순서대로)**:
1. **process_llm_sheet.py 구현** — 마젠타 키잉(key_magenta 이미 sprite_retouch에
   있음) + 스펙 그리드(셀 128×128) 컷팅 + 빈 셀 제외 프레임 검출 + 검증.
   첫 실제 납품 형식을 보고 맞추는 것이 정확하다.
2. 1차 납품(주인공) 검증 결과 유저 보고 — 1차 납품은 이미 반려됨(마젠타 배경,
   그리드 5행→7행, 재창작). **교훈: 원작은 24×24 도트였다**(셀 64는 패딩 컨테이너)
   — 프롬프트에 명시 후 재요청 필요.
3. 스타일 방향 확정: **표준 규격은 assets/spec/sprites/_standard.md** (셀 128×128,
   세로형 0.6:1, SD 머리:몸 1:1.2, 프레임 가변 최소2/walk 4 권장, idle 4방향 2프레임).
   유저가 생성 시트(128×128 셀, 캐릭터 ~110px) 비율 채택 의사 표시함.

### 스프라이트/화면 관련 확정 사항 (8/25 2차 세션 추가)

- **아트 모드 시스템**: SettingsManager.art_mode(LEGACY/REMAKE) + SpriteSets 리졸버.
  컨벤션 `assets/sprites/<id>_original.*`(레거시) / `<id>_remake.*`(신규), 부재 세트 자동
  폴백 — 신규 시트 미착용 상태에서도 게임 동작. 부팅 화면에서 ←/→ 선택(Enter/Z 시작).
- **레거시 시트 표준**: 원작 24×24 도트를 4배 nearest 베이크(96px) → 표준 셀 128 배치,
  scale ⅔ 메타로 실효 64px = 타일 2.0배(원작 비율). 캐릭터가 바닥 타일보다
  작던 역전 해소. 재생성: `tools/dev/make_player_original_sheet.py`.
- **발 앵커 공식**: `offset.y = TILE_PX/scale − cell_h/2` (SpriteSets.foot_offset).
  scale≠1 시트에서 발 침하 방지 — 리메이크 시트(scale≠1) 투입 시에도 면역.
- **원작 SPR 색0 = 투명**: parse_spr(spr_extract.py)가 팔레트 전색을 불투명으로
  방출해 도트에 검은 배경이 붙던 것 수정(원작 blit 색0 스킵 재현). 불투명 56.2%→33.4%.
- **뷰포트 960×540**: 타일 30×16.9 가시(원작 26.7×16.7과 체감 동일 — 캐릭터
  화면높이 11.9% ≈ 원작 12%). 전투 좌표 보정: 메뉴(800,380)·적열(600+i*100,180)·
  회피 아레나 Rect2(48,48,384,264)·미니게임 패널 중앙.
- **전투 렌더 픽스**: BattleUI 배경 ColorRect가 layer 20에서 월드 스프라이트를
  덮던 문제(하위 CanvasLayer -1로 분리) · 적 텍스처 폴백(스테일 .import 대응) ·
  적 이름에 species 딕셔너리 원문 노출(id만 추출).

### 스프라이트 관련 확정 사항 (이번 세션)

- **셀 128×128 / 캐릭터 세로형(~0.6:1, 실높이 ~110px) 채택** — 스펙 갱신 완료
  (player_sidol.json: cell 128×128, scale 0.75, idle 4방향, 프레임 가변 최소 2)
- **런타임 수용 코드 완비**: player_entity/battle_presenter 가 cell_w/cell_h(비정형)
  + scale 메타 + 방향별 idle(폴백 idle_down) 지원. 필드 스모크 PASS.
- **마젠타 키잉 허용**: LLM이 투명 처리 못 하면 #FF00FF 단색 배경으로 납품 받고
  파이프라인이 누끼(sprite_retouch.key_magenta). 단 혼색/AA 금지를 프롬프트에 명시.
- **palette_master.json 함정**(재발 방지): DEFAULT.PAL 기본 VGA DAC(raw768, 6비트) —
  첫 16색=EGA색, 8비트 스케일 없이 쓰면 검정화. 리터치는 **원본 자체 팔레트** 스냅이 정답.
- **원작 검정=투명 문제**: 원작 엔진이 색0 스킵이라 스프라이트 내부 검정이 배경과
  연결되면 뚫림. heal_pinholes(밀폐 복원+핀홀 봉합) 넣었으나 불완전 —
  원본 코드 blit 방식 확인이 근본 해법(HANDOFF 구판 §3 기록 참조).

### 기타 미해결 (우선순위 낮음)

| ID | 내용 |
|---|---|
| B1 | ~~빈 폴더 껍데기 삭제~~ ✅ 해소(8/25 확인 — 이미 부재) |
| B2 | gdformat/pre-commit 미설정 |
| B3 | ~~DialogueBox 스킵 visible_characters 음수 방지~~ ✅ 해소(8/25 재검증 — 현행 코드에서 음수 경로 없음) |
| — | battle_scene_controller ~305행(상한 초과 소폭) UI 분리는 완료, 추가 분리 여지 |

## 4. Phase 8 남은 작업

| 순서 | 작업 | 상태 |
|---|---|---|
| 0 | 스프라이트 LLM 워크플로우 첫 사이클 완주 (주인공) | **진행 중** |
| 1 | BGM/SFX 실제 파일 생성 -> assets/audio/ 배치 | 스펙 21종 준비 |
| 2 | 도트/타일/포트레이트 AI 배치 확산 (주인공 패턴 복제) | 대기 |
| 3 | 이벤트 데이터 채우기 — q_*_gate 플래그 흐름 | Phase 9 병행 |

### 재활용 아키텍처 노트 (bombman94/95 포팅 대비)

3계층 분리 — 신규 리메이크는 2계층만 새로 쓴다:

| 계층 | 위치 |
|---|---|
| **공용 프레임워크** | src/battle, src/cutscene, src/map/trigger_system, src/ui(미니게임·DialogueBox·BattleUI), _shared 도구+schemas+**스프라이트 표준/LLM 워크플로우** |
| **게임 데이터** | data/**, assets/spec/**, gen/prompts/** |
| **게임 전용 로직** | 씬 조립, 성장, 보스 하이브리드 |

### 구현 노트 (P8 세션 추가)

- **LLM 워크플로우**: extract_sprites.py(numpy 벡터화 flood-fill, 935프레임 수십 초,
  중복 제거, 컨택트 시트는 표준 128 셀 + 마젠타 배경) — 00_reference는 gitignored
  임시区, 스크립트로 재생성 가능.
- **validate_retouch_sheet.py**: 납품 자동 판정(크기/투명도/마젠타/도트 bbox/편차).
- **export_player_sheet.py(리터칭용) / export_player_gen_package.py(신규 생성용)**:
  원판+주석+프롬프트 md 생성. 프롬프트에 "실제 도트 크기/오프셋/마젠타 규칙/그리드
  무변경" 명시 — 누락이 1차 반려 원인.
- **오디오**: AudioManager 실구현(버스/루프/SFX풀), 필드·전투 BGM 배선,
  spec sfx 21종. 실제 음원 파일은 미생성(부재 시 조용히 스킵).
- **DOSBox**: run_sidol.bat 레포 상대경로 conf 생성, 캡처 assets/raw/dosbox_capture.

## 4. 알려진 미해결

| ID | 내용 | 우선순위 |
|---|---|---|
| B1 | ~~빈 폴더 `BSD 시돌이의 모험\` 껍데기 삭제~~ ✅ 해소(8/25 — 이미 부재) | — |
| B2 | gdformat/pre-commit 설정 파일 미생성 | 낮음 |
| B3 | ~~DialogueBox 스킵 시 visible_characters 음수 방지~~ ✅ 해소(8/25 재검증) | — |
| — | 로컬 Godot 4.7 vs 저장소 features=4.3 — 버전 승격 여부 결정 필요(미결정 시 임포트마다 project.godot 재변경) | 중간 |
| — | `_shared/schemas/{sprite_spec,audio_spec,event_cutscene}.json` 등 5종이 커밋 미포함 상태로 로컬 존재 — 데이터 `$schema` 참조 대상, 업스트림 커밋 누락 의심 | 중간 |

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
