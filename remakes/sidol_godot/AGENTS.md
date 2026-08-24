# BSD 시돌이의 모험 — Godot 리메이크

- Godot 4.x / GDScript. **정적 타입(`: int` 등) 필수.**
- 문서 지도: `docs/01_analysis`(원작 명세) · `docs/02_design`(설계) ·
  `docs/03_plan`(진행) · `docs/04_scenario`(**★마스터 시나리오 = 권위**)
- 작업 시작 전: 해당 시스템 README + 관련 스키마를 먼저 읽는다.
- 절대 금지: 타입 무시(`as` 남용), 기존 테스트 삭제, docs와 다른 매직넘버 하드코딩.
- **콘텐츠 하드코딩 금지**: 대사·아이템·스탯·퀘스트 조건 등은 반드시 `data/**`(JSON/CSV,
  메모장 편집 가능)에서 읽는다. GDScript 소스에 게임 콘텐츠 값을 직접 쓰지 않는다.
- 완료 정의: 헤드리스 import 통과 + 스모크 실행 + Validator 0오류.

## 레이아웃 (컬렉션)

```
부싯돌시절\
├── _shared\      dosport 공용 패키지(johab/PCX/VOC/PAL/Validator) + 스키마 + 템플릿
├── originals\    원본 보존(MANIFEST.sha256 = 무결성 증명, 수정 금지)
└── remakes\
    └── sidol_godot\   ← 현재 저장소 (docs/ = 설계문서)
```

원본 데이터 경로: `../../../originals/1995_sidol_bsd_dos/`

## 검증 루프 (완료 조건)

```powershell
godot --headless --path . --script tools/import_all.gd   # 데이터 임포트+스키마
godot --headless --path . --script tools/validate.gd     # 참조/플래그 검사
godot --headless --path . res://tests/smoke.tscn         # 부팅 스모크 (exit 0)
python tools/convert/talk_convert.py --check             # 데이터 변환기 자체검증
```

- AI는 "완료" 주장 전에 위 명령의 실제 출력을 붙인다. 출력 없는 완료 보고 = 미완료.
- 파일 규모: 스크립트 1개 = 책임 1개, 권장 ≤200행 / 상한 300행.
- 네이밍: Resource=`XxxDef/Table`, 노드=snake_case 파일=클래스명, 시그널=과거형,
  오토로드=명사 싱글턴, JSON 키=snake_case, 상수=SCREAMING_SNAKE.

상세 규칙: `docs/02_design/06_ai_dev_guidelines.md`

## 에셋 에이전트 작업 경계 (병렬 작업 규칙)

이미지·스프라이트·타일·오디오 생성 에이전트는 아래 경계 안에서만 작업한다:

| 구분 | 경로 | 권한 |
|---|---|---|
| **쓰기 허용** | `assets/raw/**`(엔진 미스캔 — .gdignore), `gen/prompts/**`, `assets/spec/sprites|illustrations/**`(신규 파일) | 자유 생성 |
| **읽기 전용** | `assets/style_bible.md`, `assets/palette_master.json`, `_shared/schemas/**`, `src/**`, `data/**` | 수정 금지 |
| **수정 희망 시** | 위 읽기 전용 항목 | 제안 남기고 메인 개발과 합의 후 반영 |

- **커밋 소유권**: 각자 자기 경로만 스테이징한다. 메인 개발은 `git add -A` 대신
  명시적 경로 스테이징을 사용한다(에셋 에이전트 작업물 오염 방지).
- `assets/raw/`는 gitignored + `.gdignore` — 초안은 버전 관리·엔진 스캔 양측에서 분리.
- 채택(게이트 통과 → 패킹 → `res://assets/sprites/`)은 메인 개발 측에서만 수행.
