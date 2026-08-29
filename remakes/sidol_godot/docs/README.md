# BSD 시돌이의 모험 — Godot 리메이크 문서

> 1995년 대구대 부싯돌 동아리의 DOS RPG **"BSD 시돌이의 모험"**을
> Godot 4.x 기반 현대적 리메이크하기 위한 전체 설계 문서.

## 문서 지도

```
docs/
├── README.md                        ← 이 문서 (인덱스)
├── 01_analysis/                     [원작 분석 — 명세로 사용]
│   ├── 01_project_overview.md       개요·기술스택·파일 목록
│   ├── 02_source_code_analysis.md   소스별 분석·전역변수·결함
│   ├── 03_data_format_spec.md       MAP/SPR/EVT/TALK 포맷 명세
│   └── 04_game_systems.md           필드·전투·대화·아이템 시스템
├── 02_design/                       [재설계]
│   ├── 01_oop_redesign.md           OOP 도메인 모델 + 확장형 타일맵 자료구조
│   ├── 02_godot_architecture.md     씬트리·오토로드·디렉터리·입력
│   ├── 03_data_migration.md         변환 파이프라인 + Tiled 연동
│   ├── 04_uiux_modernization.md     UI/UX 현대화 + 타일/스프라이트 스케일업
│   ├── 05_toolchain_editors.md      이벤트/컷신/전투연출 외부 에디터 설계
│   ├── 06_ai_dev_guidelines.md      AI 바이브 코딩 규칙·검증 루프
│   └── 07_ai_asset_pipeline.md      ★AI 생성 에셋 인터페이스 (스프라이트/타일/
│                                      일러스트/BGM/SFX — spec JSON↔MD 계약서)
├── 03_plan/
│   ├── 01_roadmap.md                Phase 0~9 로드맵 + 마일스톤
│   ├── 02_risk_assessment.md        리스크 레지스터
│   ├── 03_content_backlog.md        ★콘텐츠 확장 백로그(맵/아이템/기술)
│   ├── 04_scenario_data_buffering.md 시나리오 데이터 완충 계획
│   ├── 05_polish_roadmap.md         ★마감 로드맵 — "만든 것이 맞물리는가"(실측 기반 18항목)
│   └── 06_parallel_briefs.md        병렬 작업 브리프(다른 세션/에이전트 위탁 계약)
├── 04_scenario/                     [시나리오]
│   ├── 01_scenario_inventory.md     시나리오 원본 자료 위치·상태
│   ├── 02_story_bible.md            현행(1995 원작) 스토리 바이블
│   ├── 03_remake_scenario_master.md ★권위 — 통합 리메이크 마스터 시나리오
│   │                                  (전 6구역 완결 + 스킬트리 + 플래그 명세)
│   └── bkup/03_redesign_proposal.md 개편안 이력(마스터로 대체됨)
└── 05_status/                       [실측 — 도구가 굽는다. 손으로 고치지 않는다.
    │                                  커밋된 것은 "그때 잰 값"이고, 다시 재려면 도구를 돌린다.
    │                                  관문은 user://로 돌려 이 파일을 건드리지 않는다]
    ├── 01_autoplay.md               자동 주행 — 새 게임에서 **걸어서** 어디까지 가는가
    │                                  (`tools/dev/autoplay.tscn`)
    └── 02_floor_sweep.md            층 훑기 — **데려다 놓으면** 그 층 내용이 도는가
                                       (`tools/dev/autoplay_sweep.tscn`)
```

## 한눈에 보는 결정 사항

| 주제 | 결정 | 문서 |
|---|---|---|
| 엔진 | Godot 4.x + GDScript, 정적 타이핑 | 02_design/06 |
| 아키텍처 | 데이터(Resource/JSON) ↔ 노드 컴포지션, Op 레지스트리, EventBus | 02_design/01 |
| 전투 | 스킬 6종 + 상태이상(DoT/버프/마비) + 배틀 스크립트 훅(멀티페이즈 보스) | 02_design/01 §5 |
| 맵 | Tiled(.tmj)를 권위 포맷으로, TileMapLayer×N + Custom Data, 오버라이드 계층 | 02_design/03 |
| 콘텐츠 툴 | 맵=Tiled, 대화/이벤트/컷신/전투안무=자체 Godot 에디터 플러그인 | 02_design/05 |
| 해상도 | 논리 그리드(Vector2i 셀)와 렌더 px(TILE_PX 상수) 완전 분리 → 타일 크기 교체 무상 | 02_design/04 §2 |
| UI/UX | 세이브 신설·레벨업 완성·대화 로그·게임패드 등 QoL 10종 | 02_design/04 §3 |
| 시나리오 | **통합 마스터 시나리오 확정** — 전 6구역 완결, 단일 메인 엔딩+후일담 카드 3종, 비선형 층 진행(F1→2→3→F0→4→5) | 04_scenario/03_master |
| **에셋 공급** | **AI 생성 확정** — spec JSON 계약서 + MD 브리프(렌더) + Validator 게이트. 원작 SPR은 참조 자료로 격하 | 02_design/07 |
| 개발 방식 | AI 중심 — 문서 우선·검증 루프·태스크 규격 고정 | 02_design/06 |

## 시작하기 (구현 담당 AI/개발자 공통)

0. [03_plan/05_polish_roadmap.md](03_plan/05_polish_roadmap.md) — **지금 뭐가 비어 있는지** 먼저 본다
0-1. [05_status/01_autoplay.md](05_status/01_autoplay.md) — **새 게임에서 걸어서 어디까지 가지는지** 실측
0-2. [05_status/02_floor_sweep.md](05_status/02_floor_sweep.md) — 막힌 층의 내용은 도는지 실측
1. [03_plan/01_roadmap.md](03_plan/01_roadmap.md)에서 현재 Phase 확인
2. 게이트(G-ART/G-FAITH/G-SCOPE) 확정 여부 확인
3. 해당 시스템의 design 문서 + 관련 analysis 문서 읽기
4. 작업: 인터페이스 선승인 → 구현 → `tools/import_all.gd`+`validate.gd`+`smoke.tscn` 통과

## 원본 코드에 대해

원본 C 소스·에셋은 **읽기 전용 원전**이다. 구현은 본 문서를 명세로 삼아 재구현하며,
원본 파일을 직접 수정하지 않는다. 모든 한국어 텍스트는 조합형(Johab) 인코딩임에 유의.
원본 보존 위치: `../../../originals/1995_sidol_bsd_dos/` (무결성 기록 = 동 폴더 `MANIFEST.sha256`).

