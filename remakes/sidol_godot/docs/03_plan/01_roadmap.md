# 01. 마이그레이션 로드맵

> 각 Phase는 **AI 바이브 코딩 태스크의 묶음**이다. 원칙(02_design/06):
> 인터페이스 선승인 → 구현 → 검증 명령 통과 → 문서 갱신.
> 공수는 1인+AI 기준 상대값 (S=수일, M=1~2주, L=3주+).

## 게이트 결정 (Phase 1 전 반드시 확정)

| 게이트 | 내용 | 관련 문서 |
|---|---|---|
| G-ART | **확정됨: B안 — 타일 32px, 캐릭터 프레임 64×64** | 04_uiux §2 |
| G-FAITH | 밸런스 충실이식 vs 개선(Defence 반영, 레벨업 신설 등) | 01_analysis/04 §8 |
| G-SCOPE | 시나리오 개편 범위 **확정됨** — 마스터 기준: 단일 메인 엔딩+후일담 카드 3종, 스킬 6종, 비선형 층 진행(F1→2→3→F0→4→5) | [04_scenario/03_remake_scenario_master.md](../04_scenario/03_remake_scenario_master.md) |

## 트랙 구성

```
T-A [엔진/코어]     T-B [데이터 파이프라인]   T-C [콘텐츠 제작툴]
T-D [아트·오디오]    T-E [시나리오]           T-F [UI/UX]
```

---

## Phase 0 — 기반 셋업 (전트랙 공통) [S]

- [ ] Godot 4.x 프로젝트 골격, 디렉터리, project.godot 설정 (02_godot_architecture §1)
- [ ] **컬렉션 레이아웃 반영**: 본 프로젝트 = `remakes/sidol_godot`, 원본 = `../../../originals/1995_sidol_bsd_dos`
  (불변 + MANIFEST.sha256). 공용 도구(johab/PCX/VOC/Validator/Schema)는 `_shared` dosport 패키지로 —
  이 폴더에는 프로젝트 전용 변환기(map/talk/tables/evt)만 작성
- [ ] `tools/import_all.gd`, `validate.gd`, 빈 smoke.tscn — 검증 루프 가동
- [ ] `AGENTS.md` + gdformat 설정
- [ ] 스키마 v1 껍데기: events/cutscenes/battle_moves JSON Schema
- [ ] Johab 디코더 유틸 + TALK.TXT→dialogue.json 변환기 (가장 빠른 성공 경험)
- [ ] **에셋 스펙 계약서 v1**(sprites/tiles/illustrations/bgm/sfx) + `style_bible.md` +
  `palette_master.json` + Validator 골격 — [07_ai_asset_pipeline](../02_design/07_ai_asset_pipeline.md)
- **검증**: headless import+smoke 녹색

## Phase 1 — 걷는다: 필드 MVP [M]

- [ ] MapDefinition/MapRuntime/MapRenderer + TileMapLayer 바인딩
- [ ] PlayerEntity(GridMover): 그리드 이동·충돌(ATT 시맨틱)·4방향 애니
- [ ] Camera2D 추적, HUD v0(LV/HP/EXP/AP/Money)
- **기술 품질 기준(사용자 지정 강조)**:
  - 애니메이션: 이동 중 셀 보간(이징), 방향 전환 시 즉시 프레임 반응, idle 브리딩 프레임
  - 스크롤링: Camera2D position_smoothing + 저해상도 지터 방지용 픽셀 스냅
  - HUD v0부터 Control 포커스 내비(키보드/패드 동시) 적용 — 나중에 붙이지 말고 처음부터
- F1.MAP 하나만으로 "걷고 부딪히는" 감각 확정 — **G-ART 여기서 체감 검증**
- **수용**: 스모크 시나리오(부팅→이동→벽 차단) 자동화

## Phase 2 — 맵 시스템 완성 ✅ [M]

- [x] map_convert.py: MAP→JSON 전층 변환(TMJ 내보내기는 Phase 8 콘텐츠 편집 개시 시 이월), 계단/문 데이터화(transitions.json)
- [x] 층 이동(TransitionGate 페이드), 문(mapy±3 슬라이드), ATT==2 덮개 렌더(Phase 1 선행)
- [x] MapRuntime 오버라이드 계층(상자 복원은 Phase 4 아이템과 연결)
-[x] 미니맵(Q4) — M키 토글. **전장의 안개(15차, 2026-09-07)**: 어두운 층(`FloorLighting.is_dark`)에서는 화면에 비친 칸만 기록한다 + 프론티어·탐험률·설정 토글. 밝은 층은 종전대로 전체 공개 — `src/map/fog_of_war.gd`
- **수용**: 6층 왕복 + 상자 개봉 후 재진입 상태 유지

## Phase 3 — 말한다: 대화/NPC [M]

- [ ] DialogueRunner + dialogue.json(@t 참조) + 대화창 v1(초상화 포함)
- [ ] NpcEntity + interact 프롭 + Talk() 매핑표 데이터화
- [ ] GameFlags 조건 평가기 + 교수 퀘스트 체인(v_Howa/v_Hong...) 이식
- [ ] Dialogue Editor v0(JSON 직접 편집+Validator만, UI 없이)
- **수용**: 화공과 퀘스트 3단계 대사 흐름 플레이 가능

## Phase 4 — 주운다: 아이템/경제 [S] (확장 백로그 §2: 스토리 아이템·소모형 편입)

- [ ] Inventory + items.json 임포트(tables_convert.py)
- [ ] 상자 개봉/획득 연출, DON 처리, 장비 슬롯(ItemEat 현대판), Viewer→탭형 인벤토리
- [ ] store() → shop 이벤트 op
- - 장비군(방어구)은 백로그 §2 확정분만 이번 Phase에 포함, 나머지는 Phase 8로 이월
- **수용**: 상점 구매→장착→전투 스탯 반영 E2E

## Phase 5 — 싸운다(로직): 전투 코어 ✅ [M→L] (마스터 시나리오로 스코프 확대)

- [x] BattleController/TurnStateMachine/DamageCalculator(순수함수+G-FAITH 스위치)
- [x] **SkillDef 6종 + StatusEffectSystem(DoT/버프/마비)** — 01_oop_redesign §5.1~5.2
- [x] **배틀 스크립트 훅 프레임**(mid_battle_dialogue / phase_transition / require_item_finisher) — §5.3
- [x] Combatant/HP바/**기술 서브메뉴**/도주/승패 처리
- [x] GrowthCurve 연동 — **레벨업 신규 구현**(Q2) + 난이도 상/중/하
- [x] EncounterTable + 필드 EnemyEntity(PatternAI/ChaseAI) + 접촉 인카운터
- 수용: 데미지·상태이상 단위테스트 + 10연속 전투 + 페이즈 전환 스모크 ✓

## Phase 6 — 보여준다: 전투 연출 [L]

- [ ] BattlePresenter + ChoreographyRunner(battle_moves 리소스 재생)
- [ ] 원작 안무 데이터화: a*/d*/e*/fire.spr 기반 무브 20종 내외
- [ ] 데미지 팝/히트스톱/카메라/스크린 셰이크
- [ ] Battle Choreography Editor v0(타임라인 JSON 손편집+프리뷰)
- **수용**: WVISUAL 옵션 = 연출 속도 ×1/×2/스킵

## Phase 7 — 연출한다: 컷신/이벤트 [M]

- [ ] CutscenePlayer(스텝 해석기) + opening.json(event1 이식, PROLOG 대본 축약분 복원)
- [ ] TriggerSystem(zone/interact/auto) + **이동 게이트(unlock_transition: 계단 requires_flag)**
- [ ] Event Editor v0
- [ ] **craft op**(폭탄 3재료, 해독제 3약품 합성) + **미니게임 프레임워크**(quiz, 배터리 회로 퍼즐)
- [ ] 크레딧룸(HP방), 퀴즈맨 이중 역할(팰린 게이트 3문항 + 원작 10문항 보존판)
- **수용**: 오프닝 컷신이 PROLOG.CAP 도입부를 따라 재생됨 + 3층→지하 비선형 진행 통과

## Phase 8 — 아트/오디오 AI 생성 배치 [L] ← G-ART 결정값을 스펙에 주입

> 아트·오디오 공급은 **AI 생성 확정** — 워크플로는 [07_ai_asset_pipeline](../02_design/07_ai_asset_pipeline.md).

- [ ] DOSBox 캡처 컨택트시트 제작 → `style_refs` 참조 자료 확보 (SPR 역공학은 부수 과제로 격하)
- [ ] 스프라이트/타일셋/일러스트 생성 배치: spec→프롬프트 렌더→외부 AI→Validator 게이트→패킹
- [ ] 캐릭터 일관성 관리: prompt_vars.subject 고정 토큰 + 배치 간 diff 리뷰
- [ ] BGM 6곡 + SFX 세트 생성(루프 심리스/LUFS 검증), 원작 VOC 보이스 변환 유지
- [ ] AudioManager 버스 믹스
- **수용**: 전 콘텐츠 신규 에셋 적용, Validator 차단 0건, 저해상도 깨짐 0

## Phase 9 — 폴리싱 & 출하 준비 [M]

- [ ] SaveManager 3슬롯+오토세이브(Q1), Settings UI, 조작법 화면
- [ ] 시나리오 개편분 반영(T-E 트랙 산출물), 퀘스트 로그(Q3)
- [ ] **엔딩 시퀀스**: SYS_BUILDER 최종전(전투 스크립트) → CRT/DOS 콘솔 메타 엔딩 연출 +
  후일담 카드 해금 갤러리 — 04_uiux §1.5
- [ ] 도움말 갤러리(HELP.TXT), 접근성 옵션(Q9)
- [ ] Steam/Itch 패키징, CI(headless 검증) 최종화
- **수용**: 실기기 3플랫폼(Win/Mac/Linux) 빌드 + 외부 플레이테스트

---

## 병렬 트랙 (Phase 진행과 동시)

### T-E 시나리오 트랙 (04_scenario 기반)

| 단계 | 내용 | 타이밍 |
|---|---|---|
| SE1 | 원문 복원·정리(PROLOG 오염행 복구) | Phase 0~2 |
| SE2 | ~~개편 집필~~ → **완료**: 통합 마스터 시나리오 확정(전 6구역 + 스킬트리 + 플래그 명세) | ✅ |
| SE3 | dialogue_v2.json 데이터화 — `@t` 불변/`@c` 구역 대역 규칙 적용(마스터 부록 A 정정 포함: HP실=@c2xx, 재작성분 @c 발급) | Phase 3~6 |
| SE4 | 컷신 스텝화(Cutscene Timeline 입력) — 마스터 씬별 대본을 이벤트/컷신 JSON으로 변환 | Phase 7 |

### T-C 툴 트랙 (05_toolchain §7 우선순위)

T1 임포터/Validator(Phase 0) → T4 CSV 파이프라인(Phase 4) → T2 대화 UI(Phase 5쯤) →
T3 이벤트 UI(Phase 7) → T5 컷신 UI(Phase 7~8) → T6 전투 안무 UI(Phase 8)

## 마일스톤 요약

| M | 달성 | 의미 |
|---|---|---|
| MS1 | Phase 1 종료 | "게임이 굴러간다" 체감 확보 |
| MS2 | Phase 3 종료 | 원작 핵심 루프(걷기+대화) 재현 |
| MS3 | Phase 5 종료 | 전투 포함 플레이블 빌드 |
| MS4 | Phase 7 종료 | 원작 콘텐츠 전량 이식 완료 |
| MS5 | Phase 9 종료 | 리메이크 출하 |

