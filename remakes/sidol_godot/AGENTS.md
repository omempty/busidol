# BSD 시돌이의 모험 — Godot 리메이크

- Godot 4.x / GDScript. **정적 타입(`: int` 등) 필수.**
- 문서 지도: `docs/01_analysis`(원작 명세) · `docs/02_design`(설계) ·
  `docs/03_plan`(진행) · `docs/04_scenario`(**★마스터 시나리오 = 권위**)
- 작업 시작 전: 해당 시스템 README + 관련 스키마를 먼저 읽는다.
- 절대 금지: 타입 무시(`as` 남용), 기존 테스트 삭제, docs와 다른 매직넘버 하드코딩.
- **콘텐츠 하드코딩 금지**: 대사·아이템·스탯·퀘스트 조건 등은 반드시 `data/**`(JSON/CSV,
  메모장 편집 가능)에서 읽는다. GDScript 소스에 게임 콘텐츠 값을 직접 쓰지 않는다.
- **UI 문자열도 마찬가지**: 화면에 보이는 문자열은 `data/l10n/ui.csv`(keys·ko·en)에 두고
  `tr("UI_...")`로 읽는다. 정적 함수에서는 `TranslationServer.translate()`.
  `validate.gd`가 코드↔표를 양방향 대조하므로 한쪽만 고치면 관문에서 걸린다.
- 완료 정의: 헤드리스 import 통과 + 스모크 실행 + Validator 0오류.
- **어디까지 원작을 따르는가**: 큰 문맥(줄거리·구조·맵·수치 근거)은 원작을 따른다.
  **세세한 연출(상자 개봉 애니메이션·효과음·화면 흔들림·전환 등)은 원작에 없어도 넣는다** —
  현대 게임 트렌드를 적극 도입하는 쪽이 기본값이다. 근거: `docs/02_design/04_uiux_modernization.md` §0.
  원작에 없다는 사실은 **넣지 않을 이유가 아니라** 설계 자유도가 크다는 뜻으로 읽는다.

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
검증실행.bat                                             # 관문 전 단계 (아래는 그 일부)
godot --headless --path . --script tools/import_all.gd   # 데이터 임포트+스키마
godot --headless --path . --script tools/validate.gd     # 참조/플래그 검사
godot --headless --path . res://tests/smoke.tscn         # 부팅 스모크 (exit 0)
python tools/convert/talk_convert.py --check             # 데이터 변환기 자체검증
```

관문 목록의 단일 소스는 `tools/dev/run_gates.ps1` — `검증실행.bat`과 CI(`.github/workflows/verify.yml`)가
같은 파일을 돌린다. 단계를 늘릴 곳은 그 하나다.

UI를 고쳤으면 **눈으로 확인한다** — 관문은 "화면 밖으로 나갔는가"만 본다:

```powershell
godot --path . --resolution 960x540 res://tools/dev/ui_shots.tscn -- <출력 폴더>
```

필드/전투의 각 패널을 실제로 세워 PNG로 남긴다(창 모드 필요 — 헤드리스는 렌더 결과가 없다).

**"이어 붙는가"는 관문이 따로 본다** — smoke와 world_audit은 검사할 상태를 손으로 세우므로
(플래그 주입·층 순간이동) 앞이 열어야 뒤가 열리는 순서를 못 본다. 그 층은 두 도구가 맡는다:

```powershell
godot --headless --path . res://tools/dev/autoplay.tscn       -- --seconds 600   # 걸어서 어디까지
godot --headless --path . res://tools/dev/autoplay_sweep.tscn -- --seconds 900   # 데려다 놓으면
```

결과는 `docs/05_status/`에 실측으로 남는다. 앞의 것은 관문에 들어 있다.

**좌표를 정해야 할 때는 맵을 굽는다** — 숫자로만 더듬으면 임의 배치가 된다:

```powershell
godot --headless --path . res://tools/dev/map_shots.tscn   # tools/dev/mapshots/ 에 층별 PNG
```

`tools/dev/map_viewer.html` 을 더블클릭하면 층을 넘겨 보며 칸 좌표를 읽고(마우스 올림)
클릭으로 복사할 수 있다. 지형색은 게임 미니맵과 같은 표(`MinimapLayer.color_for`)다.

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
  (`.gdignore`만은 git이 추적한다. 없으면 Godot이 의뢰 첨부 이미지를 전부 임포트한다 —
  2026-08-28 실측 `.import` 1,274개. 패키지 생성기가 없으면 자동으로 깐다.)
- 그래픽 의뢰 요약: `assets/gen/prompts/PROMPTING_QUICKGUIDE.md`(1장) ·
  현황: `python tools/dev/asset_status.py`
- 채택(게이트 통과 → 패킹 → `res://assets/sprites/`)은 메인 개발 측에서만 수행.
