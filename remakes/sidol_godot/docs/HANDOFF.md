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
1. ~~**process_llm_sheet.py 구현**~~ ✅ **완료(8/25 3차 세션)** — 마젠타 키잉
   (sprite_retouch.key_magenta 재사용) + 스펙 그리드 컷팅 + 빈 셀 제외 프레임
   검출 + 표준 규격 검증(_standard.md 임계값) → `20_processed/<캐릭터>/`에
   프레임 PNG + processed_sheet.png + report.json 기록.
   사용: `python tools/convert/process_llm_sheet.py <납품.png> [--spec 스펙.json]`
   (스펙 미지정 시 assets/spec/sprites/<캐릭터>.json 자동 탐색).
   합성 시트 3종(정상/프레임누락/그리드불일치)으로 통과·반려 경로 검증 완료.
   첫 실제 납품을 보고 임계값 미세조정 필요할 수 있음.
2. **LLM 재요청** — 1차 납품은 반려됨(마젠타 배경, 그리드 5행→7행, 재창작).
   교훈: 원작은 24×24 도트였다(셀 64는 패딩 컨테이너) + 표준 규격은
   `_standard.md`(셀 128×128) — 프롬프트에 명시 후 재요청.
   참조자료: `assets/raw/llm/00_reference/` (8/25 3차 세션에 재생성됨 —
   62그룹, gitignored 임시区).
3. 납품 수령 → `10_submitted/<캐릭터>_v<n>.png` 저장 → process_llm_sheet.py
   실행 → 리포트 유저 보고 → 뷰어 검수 → 채택 시 패킹.
4. 스타일 방향: **표준 규격 확정 = assets/spec/sprites/_standard.md**
   (셀 128×128, 세로형 0.6:1, SD 머리:몸 1:1.2, 프레임 가변 최소2/walk 4 권장,
   idle 4방향 2프레임). 유저가 생성 시트 비율 채택 의사 표시함.

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

### Phase 9 착공 (8/25 3차 세션)

**완료 — Q1 세이브/설정 코어 루프 전체**:

- **SaveManager 실구현**: `user://save_auto.json` + `user://save_slot_1..3.json`
  (사람이 읽는 JSON, version 필드). 스냅샷 = 층/플레이어 좌표/스탯/인벤/플래그/
  상자 오버라이드. 오토세이브는 전투 승리 측에서 `request_autosave()` → 필드 진입 시
  `consume_autosave()`(좌표 확정 보장). 층 전환은 게이트에서 도착 좌표로 즉시 기록.
- **SettingsManager 실구현**: 볼륨 4버스(Master/BGM/SFX/Voice)·연출속도·아트모드 →
  `user://settings.json`. 변경 UI가 즉시 적용+저장, 기동 시 버스에 자동 반영.
- **UI 3종 신규**: `src/ui/save_slot_list.gd`(SAVE/LOAD 모드, 타이틀·일시정지 공용),
  `src/ui/settings_panel.gd`(공용), `src/ui/pause_menu.gd`(필드 Esc — 계속/세이브/
  로드/설정/타이틀). 트리 pause 중 입력 유지 위해 오디오 매니저 ALWAYS 모드.
- **타이틀 개편**(scenes/main.gd): 새 게임/계속하기/설정/종료 + 아트모드 ←→ 퀵선택 유지.
- **상자 오버라이드 완비**: 선언만 있던 GameState.chest_overrides가 실제 기록·적용·
  직렬화된다(field._apply_chest_overrides — 로드/재구축 공용).
- **tests/smoke_save.tscn 신규**: 저장→변형→복원 라운드트립 + 메타 + 오토 요청 흐름.

### Phase 9 잔여 완료 + 디버그 도구 (8/25 3차 세션 후반)

- **버그 수정(trigger_system.gd)**: `_consumed()`가 `done_flag`를 검사하지 않아
  F1 재방문마다 오프닝 컷신이 재발동됨(데이터 파일 주석의 규약과 불일치하는
  구현 누락 — Phase 7 잠복 버그). done_flag 스킵 구현으로 해소.
  이 버그가 smoke_dialogue 상시 실패·smoke_transitions 플레키의 근원이었다.
- **smoke_dialogue 재작성**: 프롤로그 플래그 프리셋(smoke_field 동일 패턴) +
  물리 프레임 동기 입력 홀드(`_press_until`) + 감시자 타이머. 정상 PASS.
- **부팅 인트로**(scenes/boot_intro): DOS 가짜 부팅 타이핑 → 타이틀 전환,
  아무 키 스킵. project.godot main_scene 변경.
- **조작 도움말**(src/ui/help_panel.gd): 타이틀·일시정지 양쪽에서 접근.
- **진행 기록 Q3**(data/quests_v2.json + src/ui/quest_log_panel.gd): 마스터
  시나리오 §3 구역명 준용한 14개 마일스톤 플래그 달성 뷰. 일시정지 메뉴에서.
- **접근성 Q9**(SettingsManager.TextSize): 본문 글자 크기 3단 — DialogueBox
  폰트/패널 높이에 스케일 반영, settings.json 영속.
- **디버그 패널**(src/ui/debug_panel.gd, F10 — 디버그 빌드 한정):
  층 이동(transitions.json 앵커 역산)·수치 변경·아이템 지급·전투 강제
  (species+bosses 데이터 구동)·플래그 토글·SelfCheck 실행.
- **SelfCheck 자가검증**(src/core/self_check.gd + tests/smoke_selfcheck.tscn):
  통합 지점 회귀 프루브 7종 — 전층 맵 로드/NPC 시퀀스 참조/트리거 참조/
  적 정의 커버리지/세이브 라운드트립/**done_flag 스킵 규약(8/25 버그 회귀 방지)**/
  인벤 불변식. 게이트로 승격 — 검증실행.bat에 편성.
- **검증 결과**: import·validate 0오류, 스모크 8종 + 부팅인트로/타이틀 헤드리스
  부팅 전부 exit 0.

**P9 잔여**: 시나리오 데이터 완충(퀘스트 상세 목표·대사 보강 — 시나리오 작업) ·
Steam/Itch 패키징·CI(외부 계정·익스포트 템플릿 필요 — 로컬 검증 불가로 보류).

### 기존 결함 종결 (8/25)

| ID | 내용 | 결론 |
|---|---|---|
| — | smoke_dialogue 실패 | ✅ 근원=done_flag 미검사 버그. 규약 구현+테스트 재작성으로 PASS |
| — | smoke_transitions 최초 1회 실패 | ✅ 동일 근원 추정 — 규약 구현 후 연속 PASS |

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
