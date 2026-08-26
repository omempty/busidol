# 06. 병렬 작업 브리프 (다른 세션/에이전트 위탁용)

> 작성: 2026-08-26 · 대상: [05_polish_roadmap.md](05_polish_roadmap.md)의 항목을
> 메인 개발 세션과 **동시에** 진행할 때. 위탁 전에 [AGENTS.md](../../AGENTS.md)
> "에셋 에이전트 작업 경계"와 커밋 소유권 규칙을 먼저 읽는다.

## 0. 왜 아무거나 병렬로 못 돌리나

마감 항목 대부분이 `src/ui/**`와 `src/battle/**` 두 곳으로 수렴한다.
P0-01(전투 메뉴 잘림)·P0-03(폰트)·P0-04(전투 배경)·P1-08(결과 요약)·P1-10(상태이상
아이콘)은 **같은 파일들을 만진다** — 나눠 주면 병합 충돌로 되레 느려진다.

병렬이 성립하는 조건은 하나다: **파일이 겹치지 않을 것.**
아래 세 레인이 그 조건을 만족한다.

| 레인 | 소유 경로 | 메인 세션과 겹침 |
|---|---|---|
| **A. 데이터·밸런스** | `data/monsters.json` | 없음 |
| **B. 감사 프루브** | `src/core/audit/**`(신규) + `tools/audit/world_audit.gd` 1곳 | 1줄 |
| **C. 에셋 사이클** | `assets/raw/**`(gitignored) | 없음 |

**메인 세션이 잡는 것**: `src/ui/**`, `src/battle/**`, `scenes/**`, `project.godot`.
이 경로는 위탁하지 않는다.

---

## WP-A · 몬스터 표기·구성 정비 [데이터만]

**대상 파일**: `data/monsters.json` — **이 파일 하나만**(A-1 선택 프루브 채택 시 `src/core/self_check.gd` 추가).
**읽기 전용 참조**: `data/monster_anim_specs.json`(이름·패턴 설계 원본 — 수정 금지)

### A-1. 종별 한글 이름 배선 (P0-02)

**창작 작업이 아니다.** `data/monster_anim_specs.json`의 `species[]`에 `name_ko`가
**19종 전부 이미 있다**(마드 아이·드웜·불가·오지·아이언 보크·헬캅·오레이·스파커·
씨버그·플라잉 시시·널 포인터·로그 벤딩 + 보스). 게임 DB로 잇기만 하면 된다.

- `monsters.json`의 `species` 12종에 `display_name`을 추가한다.
  **값은 `monster_anim_specs.json`의 같은 id `name_ko`를 그대로 옮긴다.** 새로 짓지 않는다.
- 스키마 예: `"vulgar": {"weaknesses": ["fire"], "display_name": "불가"}`
- 보스 2종은 이미 `display_name`을 갖고 있다 — 형식이 맞는지만 확인.
- **`weaknesses` 배열을 건드리지 말 것** — 약점→브레이크 시스템이 물고 있다.
- (선택) 두 파일이 어긋나지 않게 `src/core/self_check.gd`에 프루브 한 줄 추가:
  `monsters.json.species[i].display_name == monster_anim_specs.species[i].name_ko`.
  이 경우 `self_check.gd`도 소유 파일에 포함된다.

### A-2. 층별 패턴 소실 (신규 발견 — 2026-08-26)

`monsters.json`의 `floors` 항목은 **문자열과 객체가 섞여 있다.** 문자열로 적힌 종은
`Database.encounter_species()`가 패턴 기본값 `wander`로 떨어뜨린다 —
설계된 행동이 통째로 사라진다.

| 층 | 종 | 현재 | anim_specs 설계 |
|---|---|---|---|
| f0 | `sparker` | (문자열 → wander) | `teleport` |
| f3 | `ozzy` | (문자열 → wander) | `zigzag` |
| f3 | `iron_voc` | (문자열 → wander) | `patrol` |
| f3 | `flying_thesis` | (문자열 → wander) | `wander` |

- 위 4건을 객체 형태로 승격한다: `{"id": "sparker", "pattern": "teleport"}`
- **f0·f3 전체를 훑어라** — 위 표는 실측분이고 다른 문자열 항목이 더 있을 수 있다.

### A-3. F1 몬스터 구성 재배분 (P1-07)

`floors.f1.species` 5종 중 `rogue_vending`(패턴 `ambusher` = 설계상 부동)이
뽑히는 비중이 높아 첫 층 4체 중 3체가 멈춰 있다.

- 부동 패턴(`ambusher`)이 한 층에서 과반이 되지 않게 조정한다.
- **종 추가·삭제보다 순서·구성 조정을 우선**한다. 종을 새로 넣으면 시트가 없어
  플레이스홀더가 하나 더 늘어난다(현재 8종 — 05 로드맵 §5.1).
- `pattern` 값은 `MovementPattern.NAME_TO_KIND`에 있는 이름만 쓴다:
  `wander · chase · dash · burrow · zigzag · patrol · pulse · teleport · ambusher · phaser · ranged`

### A-4. 판단이 필요한 것 (고치지 말고 보고할 것)

일부 층은 anim_specs와 **의도적으로 다르게** 배정돼 있을 수 있다:

| 층 | 종 | floors | anim_specs |
|---|---|---|---|
| f1 | `vulgar` | `wander` | `chase` |
| f2 | `c_bug` | `teleport` | `zigzag` |

층별 변주인지 실수인지는 데이터만 봐서 알 수 없다. **임의로 통일하지 말고**
발견 사항으로 보고한다.

### 검증 (필수 — 출력을 붙일 것)

```powershell
godot --headless --path . --script tools/validate.gd
godot --headless --path . --quit-after 3600 res://tests/smoke_battle.tscn
godot --headless --path . res://tools/audit/world_audit.tscn
```

`world_audit`의 `몬스터 정지` WARN이 f1에서 사라지는지 확인한다.

### 커밋

`data/monsters.json`만 스테이징. `git add -A` 금지.

---

## WP-B · 감사 도구 UI 프루브 [소코드]

**대상 파일**: `src/core/audit/ui_probe.gd`(신규) + `tools/audit/world_audit.gd`(호출 1줄)

### 배경

로드맵 P0-01·P0-02는 **자동으로 잡혔어야 했다.** 전투 커맨드 메뉴가 뷰포트 밖으로
175px 밀려 "도망"이 잘려 있었고, 적 이름이 영문 id 폴백으로 표시되고 있었는데
관문 14단계가 전부 녹색이었다. 조립 검증 층이 필드만 덮고 UI를 안 덮기 때문이다.

### 만들 것

`class_name UiProbe`, 기존 프루브들과 같은 형태(정적 함수 + `AuditReport` 기록).
참고 구현: `src/core/audit/actor_probe.gd`.

| 프루브 | 판정 |
|---|---|
| `check_onscreen` | CanvasLayer 하위 Control을 순회해 `get_global_rect()`가 뷰포트 사각형을 벗어나면 FAIL. 의도적으로 화면 밖에 둔 것(숨김 패널 등)은 `visible == false`로 걸러진다 |
| `check_text_overflow` | Label의 `get_minimum_size()`가 부모 Control의 `size`를 넘으면 WARN |
| `check_display_names` | `Database.encounter_species()` 전 종 + 보스에 대해 `get_enemy_def().display_name`이 id 폴백(`_` 치환 + capitalize 결과와 동일)이면 WARN |

### 붙일 자리

전투 씬은 필드와 조립 경로가 다르므로 `world_audit.gd`에 **전투 씬 감사 한 블록**을
추가한다(`scenes/battle.tscn` 인스턴스화 → 2프레임 대기 → 프루브 → `queue_free`).
`GameState.pending_encounter`에 종 하나를 넣어야 전투가 구성된다:

```gdscript
GameState.pending_encounter = {"enemies": ["vulgar"], "on_win_flag": ""}
```

### 규칙

- **GDScript 정적 타입 필수**(AGENTS.md). `var x := ...` 또는 `var x: T = ...`
- 파일 1개 = 책임 1개, 권장 200행 / 상한 300행
- 기존 프루브·테스트를 수정하지 말 것. 추가만 한다
- 새 FAIL이 나오면 **코드를 고치지 말고 리포트만 한다** — 수정은 메인 세션 담당
  (P0-01·02가 잡히면 성공이다)

### 검증

```powershell
godot --headless --path . --script res://tools/check_scripts.gd
godot --headless --path . res://tools/audit/world_audit.tscn
```

### 커밋

`src/core/audit/ui_probe.gd`, `src/core/audit/ui_probe.gd.uid`,
`tools/audit/world_audit.gd`만 스테이징.

---

## WP-C · 에셋 LLM 사이클 [유저 주도]

경로 `assets/raw/**`(gitignored) — 코드와 완전히 격리된다.
절차는 [LLM_REQUEST_GUIDE.md](../../assets/gen/prompts/LLM_REQUEST_GUIDE.md),
계약은 [LLM_WORKFLOW.md](../../assets/gen/prompts/LLM_WORKFLOW.md).

우선순위는 REQUEST_GUIDE §2 — 플레이스홀더로 도는 액터 8종이 1순위다.
채택분 패킹(`res://assets/`)만 메인 세션이 수행한다.

---

## 위탁 전 전달 문서

저장소 접근이 있는 세션이면 **읽으라고 지정할 파일 목록**이고, 외부 LLM이면
**붙여 넣을 파일 목록**이다. 순서대로 읽힌다는 전제로 배열했다.

### 공통 (레인 불문 — 이것부터)

| 파일 | 왜 |
|---|---|
| [AGENTS.md](../../AGENTS.md) | 정적 타입 필수·콘텐츠 하드코딩 금지·커밋 소유권·검증 루프. **이거 없이 보내면 규약 위반 결과물이 온다** |
| [docs/03_plan/06_parallel_briefs.md](06_parallel_briefs.md) | 이 문서 — 해당 WP 절과 합류 규칙 |
| [docs/03_plan/05_polish_roadmap.md](05_polish_roadmap.md) | 그 항목이 왜 존재하는지(§0 조립 검증 층 설명 포함) |

외부 LLM에는 `AGENTS.md` + 해당 WP 절만 붙여도 된다. 05는 배경이라 선택.

### WP-A · 데이터·밸런스

| 파일 | 용도 |
|---|---|
| `data/monsters.json` | **작업 대상** |
| `data/monster_anim_specs.json` | 이름·패턴 설계 원본. **읽기 전용** |
| `src/core/ai/movement_pattern.gd` | 유효한 `pattern` 이름 목록(`NAME_TO_KIND`) |
| `src/autoload/database.gd` | `encounter_species()` — 문자열/객체 정규화 지점(A-2의 근거) |
| [docs/04_scenario/02_story_bible.md](../04_scenario/02_story_bible.md) §필드 몬스터 8종 | 원작 종명 대조 |

`monsters.json`이 크면 `species` + `floors` 두 블록만 잘라 붙여도 된다.
`monster_anim_specs.json`은 `species[].id / name_ko / pattern` 세 필드만 있으면 충분하다.

### WP-B · 감사 프루브

| 파일 | 용도 |
|---|---|
| `src/core/audit/actor_probe.gd` | **참고 구현** — 이 형태를 그대로 따른다 |
| `src/core/audit/audit_report.gd` | 기록 API(`ok`/`warn`/`fail`/보류 목록) |
| `tools/audit/world_audit.gd` | 붙일 자리 |
| `src/ui/battle_ui.gd` | 판정 대상 구조(메뉴 위치·적 라벨). **수정 금지** |
| [docs/02_design/06_ai_dev_guidelines.md](../02_design/06_ai_dev_guidelines.md) | GDScript 코딩 규칙 상세 |

### WP-C · 에셋

| 파일 | 용도 |
|---|---|
| [assets/gen/prompts/LLM_REQUEST_GUIDE.md](../../assets/gen/prompts/LLM_REQUEST_GUIDE.md) | 실행 순서 |
| [assets/gen/prompts/LLM_WORKFLOW.md](../../assets/gen/prompts/LLM_WORKFLOW.md) | 경로·규격 계약(단일 출처) |
| `assets/style_bible.md` | 아트 톤 |
| `assets/spec/sprites/_standard.md` | 셀 128 표준 규격 |
| `assets/palette_master.json` | 팔레트. **`_comment`의 6비트 DAC 경고를 반드시 함께 읽힐 것** — 스케일 없이 쓰면 전 색이 검게 나온다 |

이미지 LLM에는 위 문서가 아니라 **생성기가 만든 `prompt.md` + 첨부 이미지**를 준다.
위 표는 사이클을 돌리는 사람/에이전트용이다.

### 안 보내는 것

- `originals/**` — 읽기 전용 원전. 접근 금지(AGENTS.md)
- `src/ui/**`, `src/battle/**`, `scenes/**`, `project.godot` — 메인 세션 소유
- `docs/HANDOFF.md` — 524행이고 세션 이력이라 위탁 작업에 불필요. 필요한 결정은
  05·06에 옮겨 적었다

### 전달 문구 예시

> `AGENTS.md`와 `docs/03_plan/06_parallel_briefs.md`의 **WP-A** 절을 먼저 읽어라.
> 작업 대상은 `data/monsters.json` 한 파일이고, `data/monster_anim_specs.json`은
> 읽기 전용 참조다. 완료 조건은 WP-A "검증" 절의 세 명령을 실제로 돌려
> **출력을 붙이는 것**이다. 출력 없는 완료 보고는 미완료로 간주한다.
> 커밋은 `data/monsters.json`만 스테이징한다.

## 합류 규칙

1. 각 레인은 **자기 경로만 스테이징**한다(`git add -A` 금지).
2. 합류 전 각자 `검증실행.bat` 14단계를 통과시킨다.
3. WP-B가 새로 FAIL을 잡으면 그 목록을 05 로드맵에 항목으로 추가한다 — 즉시 고치지 않는다.
4. 위탁 세션은 **작업 전에** `AGENTS.md` + 해당 시스템 design 문서를 읽는다(AGENTS.md 규약).
