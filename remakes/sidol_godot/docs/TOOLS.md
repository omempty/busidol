# 도구 사용법 (TOOLS)

> **이 문서는 "어떻게 돌리는가"의 정본이다.** `docs/` 아래 나머지는 전부 설계·분석
> 문서라 "무엇을 만들 것인가"를 적는다. 그 사이에 빈 자리가 있었다 — 저장소에는
> 진입점 `.bat` 11개와 파이썬 도구 수십 개가 있는데, **각각을 언제 어떻게 돌리고
> 무엇을 보고 통과/실패를 판단하는지**가 한 곳에 없었다.
>
> 규칙 하나: **여기 적힌 명령은 전부 실제로 돌려 본 것이다.** 출력 예시도 실측이다
> (§9에 그 기록을 모아 뒀다). 돌려 보지 못한 것은 그렇다고 적었다.
> 문서와 실제가 어긋나면 **문서가 아니라 도구가 정본이다** — 도구를 돌려라.

관련 문서 — 이쪽은 설계이고 여기는 사용법이다:

| 무엇 | 어디 |
|---|---|
| 에디터를 **왜 그렇게 만들 것인가** | [02_design/05_toolchain_editors.md](02_design/05_toolchain_editors.md) |
| 에셋 파이프라인 **설계** | [02_design/07_ai_asset_pipeline.md](02_design/07_ai_asset_pipeline.md) |
| 에셋 경로·규격·검증의 **계약** | [`assets/gen/prompts/LLM_WORKFLOW.md`](../assets/gen/prompts/LLM_WORKFLOW.md) |
| 의뢰 운영 절차 요약 | [`assets/gen/prompts/PROMPTING_QUICKGUIDE.md`](../assets/gen/prompts/PROMPTING_QUICKGUIDE.md) |
| 세션 인수인계(이력) | `docs/HANDOFF*.md` — **사용법이 아니다**. 그때 무엇을 했고 다음이 무엇을 이어받는지 |

---

## 목차

1. [먼저 알아야 할 것 — 환경과 함정](#1-먼저-알아야-할-것--환경과-함정)
2. [진입점 — 루트의 한글 `.bat` 11개](#2-진입점--루트의-한글-bat-11개)
3. [에셋 파이프라인](#3-에셋-파이프라인)
4. [심사·편집](#4-심사편집)
5. [셀 편집기 사용법](#5-셀-편집기-사용법)
6. [관문·검증](#6-관문검증)
7. [맵·소품 덧층](#7-맵소품-덧층)
8. [상황별 — 무엇부터 돌릴까](#8-상황별--무엇부터-돌릴까)
9. [실측 기록 (2026-09-09)](#9-실측-기록-2026-09-09)

---

## 1. 먼저 알아야 할 것 — 환경과 함정

| 항목 | 값 | 왜 |
|---|---|---|
| Godot 실행 파일 | `D:/Game/busidol/_shared/tools/godot/Godot_v4.7.2-stable_win64_console.exe` | 관문·에디터용(콘솔 출력이 나온다). 게임을 그냥 띄울 때는 `_console` 없는 쪽 |
| 심사 서버 포트 | `127.0.0.1:8643` | 심사 보드·셀 편집기가 같은 서버를 쓴다 |
| 뷰어 서버 포트 | `127.0.0.1:8642` | `python -m http.server` 정적 서빙일 뿐 |
| 콘솔 인코딩 | cp949 | **파이썬을 돌릴 때 한글이 깨지면 `PYTHONIOENCODING=utf-8`을 붙여라.** 도구 대부분은 스스로 `sys.stdout.reconfigure(encoding="utf-8")`를 하지만 전부는 아니다 |

### `.bat`에 한글을 쓰지 않는 이유

루트의 `.bat`은 **파일 이름만 한글이고 내용은 ASCII**다. cmd가 배치 파일을 OEM
코드페이지로 파싱하기 때문에, 파일이 UTF-8인데 한글이 들어가면 바이트 위치가 어긋나
`if`/`goto` 해석이 깨진다(실측된 사고다). 그래서 로직은 전부 `.ps1`이나 `.py`로 빼고
`.bat`은 그것을 부르는 껍데기만 남긴다:

```
셀편집기.bat  → tools/review/fixer_launch.ps1
검증실행.bat  → tools/dev/run_gates.ps1
의뢰생성.bat  → tools/dev/make_requests.ps1
통합실행.bat  → tools/dev/launcher.ps1
```

그 `.ps1`들은 한글 문자열을 담으므로 **UTF-8 BOM으로 저장해야 한다**(PowerShell 5.1은
BOM 없는 UTF-8을 cp949로 읽는다).

---

## 2. 진입점 — 루트의 한글 `.bat` 11개

**여기가 실제 사용자 진입점이다.** `바로가기/` 폴더에 같은 것들의 `.lnk`가 10개 있다
(`tools/dev/make_shortcuts.ps1`이 만든다).

| 진입점 | 무엇이 뜨나 | 실제로 부르는 것 |
|---|---|---|
| `통합실행.bat` | **번호 메뉴 하나로 아래 전부** (1 심사 보드 · 2 셀 편집기 · 3 검증 관문 · 4 현황판 · 5 납품 처리 · 6 의뢰 생성 · 7 묶음 포장 · 8 총괄 뷰어 · 9 에셋 공백 현황 · 10 게임 실행 · 11 Godot 에디터) | `tools/dev/launcher.ps1` |
| `현황판.bat` | 정적 대시보드를 **다시 굽고** 브라우저로 연다(서버 불필요) | `tools/dev/make_dashboard.py` → `현황판.html` |
| `의뢰생성.bat` | 그림 LLM에 줄 **의뢰 패키지** 생성. 인자 없으면 카테고리 메뉴 | `tools/dev/make_requests.ps1` → `export_*_packages.py` |
| `묶음포장.bat` | 몇 건만 골라 **자기완결 폴더**로 포장(웹 챗용 축약본 포함) | `tools/dev/pack_request.py` |
| `심사실행.bat` | 서버를 최소화 창으로 띄우고 **심사 보드**를 연다 | `tools/review/review_server.py 8643` → `review_board.html` |
| `셀편집기.bat` | **셀 편집기**를 단독으로 연다. 서버가 없으면 띄우고, 있으면 재사용 | `tools/review/fixer_launch.ps1` → `sprite_fixer.html` |
| `납품처리.bat` | GUI 없이 **검증 → 채택 → 설치**를 한 번에 | `tools/convert/intake.py` |
| `검증실행.bat` | **24단계 관문** 전체(약 6분) | `tools/dev/run_gates.ps1 -Godot <_shared 경로>` |
| `뷰어실행.bat` | 맵·마스터 데이터 **총괄 뷰어** | `python -m http.server 8642` → `tools/viewer.html` |
| `게임실행.bat` | 게임을 `res://scenes/field.tscn`부터 띄운다 | `Godot_v4.7.2-stable_win64.exe` |
| `에디터실행.bat` | Godot 에디터 | `Godot_v4.7.2-stable_win64_console.exe --editor` |

### 인자를 받는 것

```
셀편집기.bat                         편집기 안의 파일 선택기가 뜬다
셀편집기.bat monsters                그 카테고리로 선택기를 연다
셀편집기.bat monsters c_bug_v3.png   그 파일을 바로 연다

의뢰생성.bat                         카테고리 메뉴
의뢰생성.bat portraits               그 카테고리 전량
의뢰생성.bat portraits prof_mo       한 건만 (시범·부분 재생성)

묶음포장.bat --pick 3 --name 시범    비어 있는 것부터 3건
묶음포장.bat monsters:sys_builder effects:hit_spark

납품처리.bat                         10_submitted 전부
납품처리.bat --from assets/raw/llm/_batch/시범/_제출
```

### 쓰는 순서

```
현황판.bat  ─(무엇이 비었나)→  의뢰생성.bat  ─→  묶음포장.bat
                                                    │  (그림 LLM에 폴더 통째로)
                                                    ▼
                   납품처리.bat  ◀───  받은 PNG를 _제출/ 또는 10_submitted/에 저장
                        │
                        ├─ 눈으로 비교하고 싶다 → 심사실행.bat (심사 보드)
                        └─ 규격이 어긋난다     → 셀편집기.bat (셀 단위 수리 후 재납품)
                                                    │
                                                    ▼
                                              검증실행.bat (관문)
```

---

## 3. 에셋 파이프라인

### 3.1 `tools/convert/web_prompt.py` — 웹 챗용 프롬프트를 굽는다

**무엇을 하나.** 첨부 없이 **문장만으로** 규격에 맞는 시트를 받아 내기 위한 프롬프트를
스펙에서 굽는다. 두 조각으로 나눈다 — 브라우저 챗은 대화가 이어지므로 공통 규칙을
매번 붙일 필요가 없다.

**언제 쓰나.** ChatGPT·Gemini 같은 웹 창에 의뢰할 때. `export_*_packages.py`가 만드는
`prompt.md`는 **첨부 5~8장(격자 템플릿·스타일 참조·크기 기준·서브팔레트·원작 그림)을
전제로** 쓰여 있어서, 첨부를 못 주는 자리에 붙이면 프롬프트의 절반이 "없는 파일을
가리키는 문장"이 된다.

**왜 이 도구가 생겼나.** 원래는 손으로 쓴 허브 문서
(`assets/gen/prompts/MONSTER_WEB_PROMPT_HUB.md`)가 그 자리를 맡고 있었는데
**규격이 정본과 어긋나 있었다** — `mad_eye`를 `320×512(셀 64)`로 적었지만 정본 계약은
`640×1024(셀 128)`다(게임 안 프레임 크기 64를 시트 셀 크기로 착각). 거기서 복사해 만든
납품은 크기 위반으로 자동 반려된다. **그래서 손으로 쓰지 않고 스펙에서 굽는다.**

```powershell
python tools/convert/web_prompt.py --common               # 공통 규약(대화 맨 앞에 한 번)
python tools/convert/web_prompt.py monsters mad_eye       # 그 시트의 상세
python tools/convert/web_prompt.py portraits npc_quizman  # 초상·아이템·키아트도 같은 자리
python tools/convert/web_prompt.py --write                # 둘 다 파일로 굽는다
```

산출:

```
assets/gen/prompts/WEB_PROMPT_COMMON.md
assets/gen/prompts/web/<cat>__<id>.md        (2026-09-09 실측 130개)
```

카테고리 8종과 그 개수(실측):

| 카테고리 | 개수 | 시트 종류(kind) | 굽는 방식 |
|---|---|---|---|
| `monsters` | 19 | character | 격자 계약 + 행별 프레임 |
| `npcs` | 4 | character | 〃 |
| `battle_actors` | 1 | character | 〃 |
| `effects` | 5 | **effect** | 〃 |
| `battle_cuts` | 5 | **cut** | 〃 (셀 512) |
| `portraits` | 25 | FLAT | 768×256(256 셀 3개) |
| `items` | 65 | FLAT | 96×96 1장 |
| `keyart` | 6 | FLAT | 1920×1080 1장 |

**"시트 종류"로 가른 이유.** 격자 계약이 같아도 **그리는 것이 다르면 지시가 달라야
한다.** 한 문장이 다섯 카테고리를 굽던 시절, 타격 스파크(`effects hit_spark`)가
`"프레임마다 발 위치가 오르내리면 캐릭터가 떠 보인다"` · `"모든 프레임에서 같은
크기를 유지한다"`는 지시를 받고 있었다. 스파크는 **프레임마다 형태·크기·밝기가
달라져야** 정상(터지고 퍼지고 사라진다)이니 정반대 지시였다. 전투 대형 컷(셀 512)도
필드 도트용 수치(칸의 70~85%)를 그대로 받고 있었다.

**무엇을 보고 판단하나.** 이 도구 자체에는 통과/실패가 없다 — 프롬프트를 찍을 뿐이다.
대신 **의뢰문이 정본과 같은 말을 하는지**는 `prompt_audit.py`가 본다(§6.2).

---

### 3.2 `tools/convert/tileset_contract.py` — 타일셋 시트 계약 (신설)

**무엇을 하나.** 타일셋 납품 시트의 **격자와 묶음 배치**를
`assets/spec/sprites/tileset_campus.json`에서 **결정론적으로** 굽는다. 같은 스펙이면
언제 돌려도 같은 좌표가 나온다.

**왜 생겼나.** 스펙 파일은 필요한 타일 17종과 다중 타일 소품 6종을 적어 뒀는데
**그 파일을 읽는 코드가 저장소에 하나도 없었다**(이 저장소의 지배적 결함 — 선언은
있는데 읽는 코드가 없다). 그리고 스펙은 타일 목록만 적을 뿐 **시트 배치를 정하지
않는다.** 배치를 안 정하면 생성 모델은 매번 다른 자리에 그려 오고 편집기는 어디가
무엇인지 모른다.

**왜 별도 모듈인가.** 이 배치를 쓰는 곳이 셋이다 — 의뢰 프롬프트·심사 서버의 계약
API·검증기. 셋이 각자 계산하면 한쪽만 고쳐져 갈라진다(`sheet_ops.py`를 만든 이유와
같은 함정).

```powershell
python tools/convert/tileset_contract.py          # 사람이 읽는 배치표
python tools/convert/tileset_contract.py --json   # 그대로 JSON (편집기·검증기용)
```

**실측 출력(2026-09-09):**

```
# tileset_campus 시트 계약 (배치 규칙 v1)
- 캔버스 256×288px · 타일 32px · 8열 × 9행 · 정렬 none

## 단일 타일 (한 칸씩)
| 행 | 열 | 타일 |
| 0 | 0 | floor_corridor |   … (0행 8칸: floor_corridor·floor_room_lab·floor_room_office·
                              floor_stair_landing·floor_basement_dust·floor_rooftop·
                              wall_outer_brick·wall_inner_panel)
| 1 | 0 | wall_window_rain |  … (1행 8칸: wall_window_rain·wall_blackboard·door_locked·
                              door_open·door_glass·stairs_up·stairs_down·chest_closed)
| 2 | 0 | chest_open |

## 소품 묶음 (여러 칸에 걸친다 — 칸 경계를 가로질러 이어져야 한다)
| 행 | 열 | 크기 | 소품 | 설명 |
| 3 | 0 | 2×3 | bed_dorm         | 침대 — 이불 주름 |
| 3 | 2 | 2×3 | vending_machine  | 음료 자판기, 디스플레이 발광 |
| 3 | 4 | 1×3 | shelf_books      | 높은 책장 |
| 6 | 0 | 3×2 | lockers          | 사물함 열 — 문 손잡이 디테일 |
| 6 | 3 | 2×2 | desk_pc          | CRT 모니터+본체+키보드 |
| 8 | 0 | 2×1 | desk_lab         | 실험실 긴 책상 — 위에 시약병 디테일 |

## 행별로 왼쪽부터 채우는 칸 수
0행 8칸 · 1행 8칸 · 2행 1칸 · 3행 5칸 · 4행 5칸 · 5행 5칸 · 6행 5칸 · 7행 5칸 · 8행 2칸
```

**배치 규칙(바꾸면 이미 받은 납품이 어긋난다 — 바꿀 때는 `LAYOUT_VERSION`을 올려라):**

1. 가로 8칸 고정(32px × 8 = 256px — 웹 챗이 한 장으로 다루기 좋은 폭).
2. **단일 타일 먼저** — `required_tiles` 순서대로 왼쪽→오른쪽, 위→아래.
3. 그다음 **소품 묶음**. 높이가 같은 것끼리 띠(band)로 묶고 큰 것부터. 높이를 섞으면
   띠의 마지막 줄에 구멍이 생겨 "그 줄에서 왼쪽부터 연속"이 깨지고, 그러면 행별
   `frames`("이 줄에 몇 칸을 채워라")를 못 쓴다.
4. 띠의 가로 합이 8을 넘으면 같은 높이로 띠를 하나 더.

정렬은 `none`이다 — 타일은 칸을 **가득 채워야** 하고, 중앙/하단으로 밀면 이음새가
어긋난다. 셀 편집기의 [정렬 스냅]을 눌러도 움직이지 않으며, **왜 안 움직였는지를
문장으로 답한다**(§5).

---

### 3.3 `tools/convert/sheet_ops.py` — 시트 픽셀 연산의 정본 (라이브러리)

**직접 실행하는 도구가 아니다.** 검증기·설치기·셀 편집기가 **같은 함수**를 부른다.

**왜 생겼나.** 같은 규칙이 두 곳에 살아 있었다 — 안내선 판정(밀도 30% · 단색 폭 40 ·
두께 3px), median-cut 양자화, 마젠타 키잉, 알파 이진화, 정렬 스냅이
`delivery_checks.py`+`install_delivery.py`(검사·설치)와 `sprite_fixer.html`의
자바스크립트(사람이 고치는 편집기)에 각각 있었다. 이 저장소가 반복해 물린 결함이
정확히 그 모양이다: **편집기에서 "자동 정리"를 눌러 통과시킨 시트가 설치 단계의 다른
판정에 걸리거나, 반대로 편집기가 그림을 지우는 사고가 구조적으로 가능했다.**

그래서 픽셀을 만지는 규칙은 전부 여기로 모으고,

- 파이썬 쪽은 그대로 `import`하고,
- 편집기는 `review_server`의 `POST /api/fixer/op`를 거쳐 **이 함수들을 호출**한다.

편집기의 자바스크립트에는 규칙이 남지 않는다(그리기·선택 같은 조작 UI만 남는다).

각 연산은 `(Image, 수치)` 또는 `(Image, dict)`를 돌려준다 — **몇 픽셀을 건드렸는지
사람에게 그대로 보고하기 위해서다.** "고쳤다"는 말만으로는 검증이 안 된다.

담고 있는 연산(§5의 편집기 버튼과 1:1로 대응한다): 키잉 · 배경 자동 제거(연결성 추적) ·
격자 잔선 제거 · 알파 이진화 · 색 양자화 · 순수검정→남색 · 픽셀풍(블록 최빈색) ·
정렬 스냅 · **행별 재배치(refit)** · 계약 격자 재배치(regrid) · 크기 자동 조절 ·
계측(`detail_ratio`·`suggest_pixel_level`).

**무엇을 보고 판단하나.** `python tools/convert/test_sheet_ops.py` — 실측 시험
68건(부정 시험 포함). 관문의 마지막 단계이기도 하다(§6.1).

---

### 3.4 `tools/convert/install_delivery.py` — 채택본을 `assets/`로 설치

**무엇을 하나.** `20_processed/`(채택본)를 **게임이 실제로 읽는 자리**로 옮긴다.

```
20_processed/<id>/processed_sheet.png -> assets/sprites/<id>_remake.png + <id>_remake.json
20_processed/portraits/<id>_v<n>.png  -> assets/portraits/<id>.png
20_processed/keyart/<id>_v<n>.png     -> assets/keyart/<id>.png
20_processed/items/<ID>_v<n>.png      -> assets/icons/<ID>.png
20_processed/effects/<id>_v<n>.png    -> assets/effects/<id>.png + <id>.json
```

**왜 필요했나.** 심사 보드가 승인하면 납품물은 `20_processed/`로 옮겨질 뿐이고
**거기서 게임 에셋 디렉터리로 넘어가는 단계가 파이프라인에 없었다.** 실측으로
`assets/sprites/c_bug_remake.png`가 `c_bug_original.png`와 **바이트 동일**했고
(복사본 그대로) `assets/portraits/`는 디렉터리조차 없었다. 몬스터 4종을 채택하고도
`asset_status.py`의 공백이 1도 줄지 않았다.

**색 양자화 — 크기를 후처리로 강제하듯 색도 강제한다.** 실납품의 고유색은
16,772~50,666개였다(계약 24~48, 원작 도트 18~34). 생성 모델이 리샘플·부드러운 음영을
넣기 때문이고 문장 지시로는 계속 안 고쳐졌다. 불투명 픽셀만 median-cut으로 N색
(기본 48)에 몰고 알파는 0/255로 이진화한다. 이미 도트로 그려 온 납품은 `--no-quantize`.

**설치 메타의 `scale`은 어디서 오나 — 이 도구의 핵심 판단.**

> 화면 배율 = **스펙의 게임 `cell` ÷ 시트 셀**. 다만 **사다리(0.25 · 0.5 · 1.0 · 2.0)
> 위의 값만 쓴다.** 도트를 비정수 배율로 그리면 칸마다 픽셀이 한 줄씩 먹히거나 겹쳐
> 보이기 때문이다(예전 기본값 `0.6667`이 정확히 그 값이었다). 동률이면 큰 쪽.

그래서 잡몹은 0.5, 보스는 1.0이 된다 — 실측 출력에 그 계산이 그대로 찍힌다.

```powershell
python tools/convert/install_delivery.py                 # 채택본 전부
python tools/convert/install_delivery.py c_bug npc_girl  # 지정 id만
python tools/convert/install_delivery.py --dry-run --colors 32
```

**실측 출력(2026-09-09, `--dry-run`) 일부:**

```
[install] (모의 실행) 채택본 -> assets 설치
  ok   c_bug: assets/sprites/c_bug_remake.png 512x896 · 색 48->44 · 애니 7행 ·
       게임 cell 48 ÷ 시트 셀 128 = 0.375 → 배율 0.5 (사다리로 당김 · 화면 64px)
  ok   crt_overseer: assets/sprites/crt_overseer_remake.png 1024x640 · 색 48->40 · 애니 5행 ·
       게임 cell 128 ÷ 시트 셀 128 = 1.000 → 배율 1.0 (화면 128px)
  ok   mad_eye: assets/sprites/mad_eye_remake.png 640x1024 · 색 47->45 · 애니 8행 ·
       게임 cell 64 ÷ 시트 셀 128 = 0.500 → 배율 0.5 (화면 64px)
  ok   null_pointer: … 색 48260->48 · 잔선 2404px 제거+오염 1802px 정리 · …
  ok   npc_girl: assets/portraits/npc_girl.png 768x256 · 색 16772->48 · 잔선 425px 제거+오염 11px 정리
  ─ 설치 20건 · 실패 0건 · 양자화 48색
```

**무엇을 보고 판단하나.** 마지막 줄의 `실패 0건`. 종료코드 0 = 설치(또는 설치할 것
없음) / 1 = 오류. **`--dry-run`으로 먼저 보고 배율·색 수가 납득되면 진짜로 돌려라.**

---

### 3.5 나머지 변환 도구 (한 줄씩)

| 도구 | 무엇을 / 언제 | 명령 |
|---|---|---|
| `process_llm_sheet.py` | 마젠타 배경 납품 시트를 **키잉 → 스펙 격자 컷팅 → 빈 셀 제외 프레임 검출 → 규격 검증** 해서 `20_processed/<캐릭터>/`로. 심사 보드의 "승인"이 스프라이트 계열에서 부르는 것 | `python tools/convert/process_llm_sheet.py <납품.png> [--spec 스펙.json]` |
| `regrid_sheet.py` | **자체 격자가 계약과 어긋난** 시트를 행 단위로 다시 앉힌다. 액자·안내선 제거 → 행 스트립에서 실제 프레임 덩어리 검출 → 계약 프레임 수와 맞는 행만 하단 중앙 정렬로 재배치. **수가 안 맞는 행은 건드리지 않고 보고만 한다**(추측으로 옮기면 조용히 틀린다 — 그 행은 사람이 셀 편집기에서 옮긴다) | `python tools/convert/regrid_sheet.py <시트.png> [--id <스펙 id>] [--inplace]` |
| `normalize_icon.py` | 아이콘 크기를 **96×96으로 되돌린다**. 생성 모델은 "정확히 96×96"을 안 지킨다 — 반려 사유에서 "크기 틀림"을 지우면 심사가 그림 자체에만 집중할 수 있다. 마젠타 키잉 → 트림 → 여백 비율 재배치(가장자리 6px) → 정수 배율이면 nearest, 아니면 box → 반투명 정리 | `python tools/convert/normalize_icon.py <png...> [--inplace]` |
| `intake.py` | **GUI 없이** 검증 → 채택 → 설치를 한 명령으로. 카테고리는 파일 이름에서 자동 판별한다(사람이 카테고리를 외울 필요가 없어야 폴더 드롭이 편해진다) | `python tools/convert/intake.py [--from <폴더>] [--dry-run] [--force]` |
| `pack_request.py` | 몇 건만 골라 **자기완결 폴더**로 포장. 저장소는 공용 참조를 카테고리 루트에 1부만 두므로 패키지가 `../style_ref.png`를 가리키는데, "폴더째 LLM에 던지기"에는 그게 불편하다 — **전달용 사본만 평탄화**한다. `웹붙여넣기.md`(2KB 축약본)도 같이 낸다 | `python tools/dev/pack_request.py --pick 3 --name 시범` |

> `regrid_sheet.py` · `normalize_icon.py`는 이번에 **돌려 보지 않았다**(대상 납품 PNG를
> 골라야 하고, 다른 작업자가 같은 트리를 쓰고 있어 파일을 만들지 않았다).
> 사용법은 각 도구의 독스트링에서 옮긴 것이다.

---

## 4. 심사·편집

### 4.1 `tools/review/review_server.py` — 심사 보드 + 셀 편집기 서버

**무엇을 하나.** 프로젝트 루트를 정적 서빙하고, 심사 보드(`review_board.html`)와
셀 편집기(`sprite_fixer.html`)에 API를 준다. **stdlib 전용**(`http.server` +
`subprocess`)이라 추가 설치가 없다.

```powershell
python tools/review/review_server.py        # 기본 127.0.0.1:8643
python tools/review/review_server.py 8644   # 포트 지정
```

| API | 무엇 |
|---|---|
| `GET /api/categories` | 카테고리 목록·건수 |
| `GET /api/list?cat=portraits` | 납품 목록(+검증 결과·피드백 md·참조 경로) |
| `POST /api/review {cat,file,action,feedback}` | 승인(20_processed 이동 + assets 설치) / 반려(피드백 md 생성) |
| `POST /api/batch {cat,action,feedback}` | 전체 승인 / 전체 반려 |
| `GET /api/fixer/contract?cat&file[&asset]` | 셀 편집기용 그리드 계약(셀 크기·행별 프레임) |
| `GET /api/fixer/assets[?cat=]` | 계약이 있는 에셋 목록 — 편집기 **[계약] 드롭다운** |
| `GET /api/fixer/files[?cat=]` | 편집기 파일 선택기 목록(대기·반려·승인본 전부) |
| `GET /api/fixer/webprompt?cat&file` | 웹 챗용 프롬프트(공통 + 시트 상세) |
| `POST /api/fixer/op {op,params,png}` | 시트 픽셀 연산 — **정본은 `sheet_ops.py`** |
| `POST /api/fixer/save {cat,file,png,mode}` | 편집 결과를 다음 버전으로 재납품 |

**카테고리 9종이 `CATEGORIES`에 있고 그것이 권위다**(실측):
`portraits` · `keyart` · `monsters` · `npcs` · `sprites` · `items` · `effects` ·
`battle_cuts` · `battle_actors`. **여기 없는 이름으로 폴더를 만들면 보드가 무시한다.**

검증기는 카테고리별로 갈린다 — 몬스터는 신규 창작이라 리터치 검증기(주인공 시트
대조)를 쓰면 무조건 반려되므로 격자 계약만 보는 전용 검증기를 쓴다.

**반려하면** `10_submitted/_feedback/<cat>/<파일>.md`에 재요청 패키지가 생긴다
(원본 의뢰 `prompt.md` + 유저 반려 사항 + 자동 검증 결과). 그 파일과 원본 첨부를 다시
던지면 `v<n+1>` 납품이 나온다.

**함정.** `셀편집기.bat`은 **이미 떠 있는 서버를 재사용한다.** 서버 코드를 고쳤으면
`review-server` 창을 닫고 다시 실행해야 한다. 옛 서버면 편집기가 "서버가 옛 버전이라
[계약] 목록을 못 받았다"고 띄운다.

---

## 5. 셀 편집기 사용법

`tools/review/sprite_fixer.html` — `셀편집기.bat`으로 연다.
**규약을 못 맞춘 납품을 통째로 다시 그리게 하는 대신, 셀 단위로 고쳐 다음 버전으로
재납품한다.** 잔선·라벨 글자·색 수 같은 결함은 통째 재생성보다 이쪽이 싸다.

> 픽셀 규칙은 **하나도 브라우저 안에 없다.** 전부 `sheet_ops.py`(정본)에 있고 편집기는
> 서버로 왕복만 한다(§3.3). 그래서 편집기가 "고쳤다"고 한 것은 설치기·검증기가
> 보는 것과 같은 판정이다.

### 여는 방법

```
셀편집기.bat                         편집기 안의 선택기(카테고리·검색·썸네일)
셀편집기.bat monsters                그 카테고리로 선택기를 연다
셀편집기.bat monsters c_bug_v3.png   바로 연다
```

디스크의 PNG는 **[파일 열기] · 드래그&드롭 · Ctrl+V**로도 연다. 파일 목록은
`10_submitted` · `_rejected` · `20_processed` 전부를 담는다.

### 헤더 두 줄

| 줄 | 묶음 | 내용 |
|---|---|---|
| 1 (문서) | 파일 / 저장 | 카테고리 · 파일 · **계약** · 열기 · 원본 복구 ∥ 내려받기 · 다른 이름 · **다음 버전으로 저장** |
| 2 (편집) | 도구 / 브러시 / 편집 / 보기 | 선택·연필·채우기·지우개 ∥ 색·굵기·지움 대상 ∥ 되돌리기·다시 ∥ 확대·격자·어니언 |

**[계약] 드롭다운**이 중요하다. 웹 챗에서 받은 그림은 파일 이름이 제각각이라 계약이
하나도 안 잡히고, 그러면 크기·격자·정렬이 한꺼번에 멎는다. 여기서 **"이 그림을 어느
에셋의 계약으로 다룰지"를 손으로 지정**하면 로컬 파일이라도 계약이 붙고, 붙으면
**다음 버전으로 저장**까지 된다.

### 도구와 단축키

| 키 | 도구 |
|---|---|
| `V` | 선택 — 클릭=셀 선택 · Alt+클릭=스포이드 · Shift+드래그=사각 영역 지우기 |
| `B` | 연필 |
| `G` | 채우기(닿은 영역) |
| `E` | 지우개 — 문질러 지우기 · Shift+드래그=사각 지우기 |
| `O` | 어니언(선택 셀에 이전/다음 프레임 겹쳐 보기) |
| `D` | 선택 셀을 같은 행 다음 칸에 복제 |
| `Ctrl+Z` / `Ctrl+Shift+Z`·`Ctrl+Y` | 되돌리기 / 다시 |
| 방향키 / `Shift`+방향키 | 1px / 8px 이동 · `Del` 비우기 |
| 우클릭 | 어디서나 지우개(도구를 안 바꿔도 된다) |

연필·채우기는 헤더의 색+굵기를 쓴다. **스포이드(Alt+클릭) 색이 있으면 그쪽이 우선.**
지우개는 [지움 대상]으로 "무엇이 남는가"를 고른다 — 마젠타 배경 납품은 투명이 아니라
배경색으로 덮어야 맞다.

### 부동(浮動) 이동 — 확정 전까지 아무것도 안 잘린다

행 이동(`←→↑↓`) · 셀 이동(방향키) · 묶음 이동은 전부 **띄운 채로** 한다.

- **확정 전에는 아무것도 잘리지 않는다.** `↓` 뒤 `↑`는 원본 픽셀 그대로 돌아온다.
- `Enter` 확정 · `Esc` 취소. `Shift`를 누르면 8px씩.
- 집는 범위는 격자가 아니라 **내용이 이어진 만큼**이라, 칸 밖으로 삐져나온 머리·무기도
  같이 따라온다. 떨어져 있는 이웃 행 그림은 따라오지 않는다.
- 확정할 때 캔버스 밖으로 나가 **잘린 픽셀이 있으면 그 수를 세어 알린다.**
- 1px씩 여러 번 눌러도 **되돌리기는 제스처 하나로 쌓인다.**

**자동이 잘못 집을 때 — 집는 범위 직접 지정.** [선택한 행] 안의 접힌 패널에서
상/하/좌/우 여백을 준다. 전부 0이면 자동(연결성 추적), 하나라도 0이 아니면 격자 밴드를
그만큼 넓힌 **사각형 전체**를 집는다. 이웃 행 그림과 붙어 있어 자동이 너무 많이 끌고 올
때 쓴다.

### 행별 재배치(refit) — 이 편집기에서 제일 많이 쓰는 버튼

**문제.** 생성 모델은 **행마다 그 행의 프레임 수로** 가로를 나눠 그린다(walk 4칸,
attack 3칸이면 간격이 서로 다르다). 그런 시트는 통째로 줄여도 칸에 안 떨어져
**셀 경계에서 잘린다.**

**하는 일.** 프레임을 하나씩 떼어 **공통 축척**으로 줄인 뒤 제 칸에 앉힌다 —
캐릭터끼리의 크기 관계는 그대로 간다.

- **배경 키잉을 먼저 하라** (경계상자를 알파로 잡는다).
- **[칸 채움 %]** — 100%면 가장 큰 프레임이 칸에 꽉 차는 배율(예전 고정값).
  낮추면 칸에 여백이 생기고, 높이면 칸을 넘본다(**넘친 픽셀 수는 서버가 세어 알려 준다**).
- **[선택한 행만]** — 그 행만 다시 앉히고 나머지는 손대지 않는다. 한 행만 어긋났을 때
  전체를 흔들 이유가 없다.

### 묶음(다중 타일 소품) 편집

책상·사물함처럼 **여러 칸에 걸친 소품**은 칸 경계를 가로질러 이어져 있는 것이 정상이다.
그래서 칸이 아니라 **상자 하나**로 움직이고 계측도 상자로 판정한다 —
**조각마다 중앙 정렬하면 소품이 부서진다.** 계약(§3.2)이 `groups`를 줄 때만 이 패널이
살아난다.

### 자동 정리 사슬

```
크기 → 키잉 → 배경 자동 제거 → 잔선 제거 → 이진화 → 양자화 → 정렬 스냅
```

- **[열 때 크기·배경 자동 보정]**(기본 켬) — 납품이 요청과 다른 크기·배경으로 오는 것이
  태반이라 여는 순간 맞춘다. **그림을 지우는 연산은 넣지 않는다.** 되돌리기로 취소된다.
- **배경 자동 제거**는 색이 아니라 **가장자리에서 이어진 영역**만 지운다 — 그림 안쪽의
  같은 색(흰자·하이라이트)은 안 뚫린다.
- **픽셀풍**은 블록 **최빈색**을 쓴다(평균색이 아니다 — 평균은 원본에 없던 중간색을
  만든다). 형태가 바뀌므로 자동 정리에는 기본으로 안 들어간다.

### 저장

| 버튼 | 무엇 |
|---|---|
| 내려받기 | 서버 저장 없이 내 PC로 |
| 다른 이름 | 카테고리·파일명을 직접 정해 납품 폴더에 |
| **다음 버전으로 저장** | 같은 이름의 `v<n+1>`로 납품 폴더에 — 그대로 심사를 다시 탄다 |

`v<n+1>`은 **디스크의 최대 버전 + 1**이다(열어 둔 파일명이 아니라). 저장 뒤 검증
FAIL이 뜨면 **알림에 앞 4줄이 붙는다 — 그 내용부터 읽어라.**

### 이 편집기가 맞게 배선돼 있는지 재기

`fixer_check.py`(정적) · `fixer_probe.py`(실조작) — §6.2.

---

## 6. 관문·검증

### 6.1 `tools/dev/run_gates.ps1` — 24단계 관문의 정본

```powershell
pwsh tools/dev/run_gates.ps1 -Godot "D:/Game/busidol/_shared/tools/godot/Godot_v4.7.2-stable_win64_console.exe"
# 또는 그냥
검증실행.bat
```

**목록이 여기 한 곳에만 있다.** 로컬(`검증실행.bat`)과 CI(`.github/workflows/verify.yml`)가
같은 파일을 쓴다 — 두 군데로 갈라지면 "로컬은 녹색, CI는 빨강"(또는 그 반대)이 생긴다.

**전체는 약 6분 걸린다.** 실행 중에 같은 트리를 다른 작업자가 쓰고 있으면 돌리지 마라.

| # | 이름 | 무엇 | 실패 취급 |
|---|---|---|---|
| 1 | Import | `--import` | 아니오(비치명) |
| 2 | Validate | `tools/validate.gd` | 예 |
| 3 | Smoke base | `tests/smoke.tscn` | 예 |
| 4 | Smoke field | `tests/smoke_field.tscn` (`--quit-after 900`) | 예 |
| 5 | Smoke battle | `tests/smoke_battle.tscn` | 예 |
| 6 | Smoke cutscene | `tests/smoke_cutscene.tscn` | 예 |
| 7 | Smoke dialogue | `tests/smoke_dialogue.tscn` | 예 |
| 8 | Smoke transitions | `tests/smoke_transitions.tscn` | 예 |
| 9 | Smoke All-Floors events | `tests/smoke_all_floors_events.tscn` | 예 |
| 10 | Smoke fx/portrait | `tests/smoke_fx.tscn` | 예 |
| 11 | Smoke battle input | `tests/smoke_battle_input.tscn` | 예 |
| 12 | Smoke AI perception | `tests/smoke_ai_perception.tscn` | 예 |
| 13 | SelfCheck | `tests/smoke_selfcheck.tscn` | 예 |
| 14 | Smoke choice | `tests/smoke_choice.tscn` | 예 |
| 15 | Smoke inventory | `tests/smoke_inventory.tscn` | 예 |
| 16 | Smoke credit room | `tests/smoke_credit_room.tscn` | 예 |
| 17 | Script parse check | `tools/check_scripts.gd` | 예 |
| 18 | World audit | `tools/audit/world_audit.tscn` — **조립 결과**를 본다 | 예 |
| 19 | Autoplay | `tools/dev/autoplay.tscn` — 새 게임 하나로 **걸어서** 240초·목표 150·요구 층수 5 | 예 |
| 20 | Export pack rules | `tools/dev/export_check.py` | 예 |
| 21 | Originals match | `tools/dev/originals_check.py` (원본 없으면 SKIP) | 예 |
| 22 | Props overlay | `tools/dev/props_check.py` | 예 |
| 23 | SPR sprite alpha | `tools/dev/spr_alpha_check.py` (원본 없으면 SKIP) | 예 |
| 24 | Sheet ops | `tools/convert/test_sheet_ops.py` | 예 |

1~19가 Godot, 20~24가 파이썬이다. **파이썬 다섯은 Godot 없이 따로 돌릴 수 있다** —
급할 때는 그쪽만 돌려라(§6.2).

**무엇을 보고 판단하나.** 마지막 줄 `ALL GATES PASSED`(종료코드 0).
실패하면 `*** FAIL *** <이름> (exit N)`을 찍고 그 자리에서 멈춘다.

**19번(Autoplay)이 왜 따로 있나.** 앞의 관문들은 검사할 상태를 **손으로 세운다**
(플래그 주입·층 순간이동). 그래서 "앞이 열어야 뒤가 열리는" **순서**를 못 본다.
Autoplay는 새 게임 하나로 되돌리지 않고 걸어 본다 — 판정은 주행 자체의 퇴행만 본다
(한 걸음도 못 걷거나 층을 못 넘으면 실패). 사문화 데이터 목록은
`docs/05_status/01_autoplay.md`로 나오고 **관문을 빨갛게 하지는 않는다.**

**21·23번의 SKIP은 정상이다.** 원본(`originals/1995_sidol_bsd_dos/`)은 저장소에 없다
(gitignored). CI·협업자 PC에서는 스스로 SKIP하고 0을 돌려준다 — CI를 빨간불로 만들지 않는다.

### 6.2 파이썬 단독 검증기 — Godot 없이 돌아간다

| 도구 | 무엇을 보나 | 명령 | 통과 판정 | playwright |
|---|---|---|---|---|
| `tools/convert/test_sheet_ops.py` | 시트 픽셀 규칙의 실측 시험 **68건**. 부정 시험(일부러 어긋난 시트로 계측이 빨개지는지) 포함 | `python tools/convert/test_sheet_ops.py` | `[test_sheet_ops] 통과 68 · 실패 0` | 불필요 |
| `tools/review/fixer_check.py` | 셀 편집기의 **정적** 배선 — 태그 균형 · `$("#id")`↔마크업 · `data-op`↔`OPS` 처리기 · `<use>`↔`<symbol>` · `node --check` | `python tools/review/fixer_check.py` | `통과 — 정적으로 잴 수 있는 항목은 모두 맞다` | 불필요(`node`는 있으면 씀) |
| `tools/review/fixer_probe.py` | 셀 편집기의 **실조작** — 진짜 마우스 드래그로 그리고 지우고 되돌린다 | `python tools/review/fixer_probe.py` / `--server` / `--shots` | `통과 — 그리기·지우기·되돌리기·단축키가 실제 드래그에서 동작한다` | **필요(chromium)** |
| `tools/review/prompt_audit.py` | **의뢰문에 적힌 숫자**가 정본 스펙과 같은가 | `python tools/review/prompt_audit.py [--cat monsters] [--sample 3]` | `FAIL 0` (종료코드 0) | 불필요 |
| `tools/dev/props_check.py` | 소품 덧층의 스키마·참조 무결성 | `python tools/dev/props_check.py [<경로>…]` | `[props_check] ok — …` (종료코드 0) | 불필요 |
| `tools/dev/originals_check.py` | 변환된 맵이 원본 `F*.MAP`과 **바이트 단위로** 같은가 + `MANIFEST.sha256` | `python tools/dev/originals_check.py` | `[originals_check] ok — …` (원본 없으면 SKIP) | 불필요 |
| `tools/dev/asset_status.py` | **정의 대비 실제 파일** — 무엇이 몇 개 비었나 | `python tools/dev/asset_status.py` | 통과/실패가 없다. **숫자를 읽는 도구다** | 불필요 |

**`fixer_probe.py`만 브라우저가 필요하다.** 이 PC에는 playwright(chromium)가 이미 깔려
있다. 서버 없이 `file://`로 열어 로컬 파일 열기 경로로 시험 시트를 밀어 넣고,
계약은 편집기의 폴백을 쓴다. `--server`를 주면 빈 포트에 `review_server`를 띄워
**서버 왕복(= `sheet_ops.py` 호출)까지** 본다.

> **왜 실조작 시험이 따로 있나.** 지우개·연필은 **마우스 이벤트 사이가 비면 자국이
> 점선처럼 끊긴다.** 그 결함은 코드를 읽어서는 안 보이고 `fixer_check.py`로도 안 잡힌다
> — 빠르게 문지를 때만 난다. 예전 세션은 "브라우저가 없어 눌러 보지 못했다"로 끝냈고
> 지우개가 시험 없이 커밋됐다.

> **`prompt_audit.py`가 없으면 안 보이는 층.** `package_check.py`는 첨부가 **있는지**만
> 보고, `validate_*.py`·`delivery_checks.py`는 **납품물**만 본다. 그 사이에 **의뢰문에
> 적힌 숫자**가 있다. 스펙이 바뀌어도 의뢰문은 그대로 남고, 틀린 숫자로 그려 온 납품은
> 검증기가 반려한다 — 그러면 사람은 "생성 모델이 규약을 못 지킨다"고 읽는다.
> **실제로는 우리가 틀린 규격을 준 것이다.**

**2026-09-09 실측:** `prompt_audit`가 `sys_builder` 한 건을 FAIL로 잡았다.

```
[FAIL] sys_builder
      ✗ 선언 크기 1024×768 ≠ 정본 1536×1152 (monster_anim_specs.json)
      ✗ 격자 선언(셀 128·8열×6행) ≠ 정본(셀 192·8열×6행)
[prompt_audit] 패키지 107건 · FAIL 2 · WARN 0 · 지적 있는 패키지 1건
```

같은 패키지의 `grid_template.png`도 1024×768이라 첨부까지 어긋나 있다(다른 18종은
전부 정본 크기였다). **그 패키지는 다시 구워야 한다.**

---

## 7. 맵·소품 덧층

세 파일이 한 덩어리다:

```
data/maps/props_f<N>.json   데이터(무엇이 어디에)
tools/dev/props_check.py    관문(그것이 성한가)
src/map/props_layer.gd      로더(게임이 그것을 어떻게 읽는가)
```

**왜 덧층인가.** 원본 맵 3평면(ground/object/attr, 200×65)은 **원본과 바이트 일치로
잠겨 있다**(`originals_check.py`가 상시 고정한다 — 실측 234,000셀 일치). 맵은 "변환"이
아니라 **그대로 옮긴 것**이고, 그 전제가 깨지면 감사 도구가 보고하는 고립 구역·차단 셀의
의미가 통째로 바뀐다(원작 고증이 아니라 변환 버그가 된다). 그래서 소품은 원본에
**쓰지 않고** 덧씌움으로만 얹는다 — `GameState.chest_overrides`의 **정적 판**이다.
다른 점은 하나뿐: 상자는 플레이 중에 생겨 세이브에 실리고, 소품은 층을 열 때 데이터에서
곧바로 선다(저장할 것이 없다).

**두 층을 섞지 않는다.**

| 층 | 필드 | 무엇 |
|---|---|---|
| 칸 속성 층 | `footprint.attr_grid` → `attr_overrides()` | 칸 → ATT(0 통행 / 1 차단 / 2 머리 위). MapRuntime이 먹는 유일한 모양 |
| 소품 속성 층 | `sprite`·`name_ko`·`state`·`inspect` → `prop_at()` | 무엇이 놓였고 조사하면 무슨 일이 나는가 |

「책장은 막으면서 조사도 된다」는 **한 필드가 아니라 두 층이 각각 한 줄씩 갖는 것**이다.

### 지금 어디까지 배선됐나 — **통행 + 조사가 살아 있다(그림만 남음)**

- ✅ **통행 판정** — 사물함 밑칸을 막고 윗칸으로는 지나간다(`apply_to()`).
- ✅ **조사(SPACE)** — `field._prop_in_front()` → `PropsLayer.inspect_steps()` →
  `_start_inspect()`가 원작 마커 대화와 **같은 대사창**을 연다(2026-09-09).
  우선순위는 트리거 → 계단 → NPC → 워커 → 원작 마커 → 상자 → **소품**(원작에 있던 것이 먼저).
  `requires_flag`가 안 선 소품은 조사 대상에서 빠진다 — 대사가 그 상태를 전제로 쓰여 있어
  상태 밖에서 띄우면 화면과 어긋나기 때문이다(`props_layer.gd`의 규약 주석).
- ❌ **그림** — `sprite` 필드는 아직 읽히지 않는다. 타일셋 납품(§3.2) 대기.
  그때까지 소품의 시각 단서는 **조사 알약 + 몸 셀 하이라이트**뿐이다.

관문 두 개가 이 배선을 지킨다(`world_audit`, 층마다):

| 관문 | 무엇을 잡나 |
|---|---|
| `PropsProbe.check_inspect_reach` | 앞에 설 자리가 없어 대사가 죽는 소품 · 조사 대사가 없는 소품(WARN) |
| `PropsProbe.check_event_alignment` | 소품 `state.open_flag`와 트리거 `done_flag`가 같은데 **자리가 어긋난 짝** — 빈 방 좌표를 밟아 이벤트가 나는 것 |
| `PropsProbe.check_choke` | 소품이 **길을 끊는가**. 판정은 `Placement.blocks_cells()`(NPC 배치가 쓰는 규칙의 임의 모양판)이고, 소품이 **실제로 막는 칸**만 놓고 묻는다(사물함 윗칸은 머리 위로 지나가므로 뺀다) |

실조작 시험은 `tests/smoke_field_test.gd` §6~§7 — 정상(대사창이 열리는가), 부정
(`requires_flag`가 없을 때 조사 대상에서 빠지는가), 그리고 **길목 판정 민감도**
(소품은 안 걸리고, 같은 자리에 가로벽을 세우면 걸리는가 — 판정이 잠들어 있는 것을 가린다).

`props_check.py`는 여기에 더해 **플래그 사슬**을 본다: 소품이 기대는 `state.open_flag`·
`inspect.requires_flag`를 **아무도 세우지 않으면** 그 소품은 영영 열리지 않거나 조사되지
않는다(오타 한 글자로 그렇게 된다). 플래그를 세우는 곳은 트리거 `done_flag`, 컷신
`set_flags`/`flag`/`on_win_flag`, 마커 `sets_flag`, 몬스터 `first_win_flag`, 그리고
GDScript의 `set_flag("…")`까지 훑어 모은다.

### `props_check.py`가 보는 것 / 안 보는 것

```powershell
python tools/dev/props_check.py                    # data/maps/props_f*.json 전부
python tools/dev/props_check.py <경로> [<경로>…]   # 지정 파일만(부정 시험용)
```

| 본다 | 안 본다 |
|---|---|
| 스키마 · 정본 id(타일셋 `multi_tile_objects`) · 크기 일치 | **통행 차단(도달 가능성)** |
| 맵 범위 · 벽 위 · 소품끼리 겹침 · 원본 ATT · 문 간섭 | 그림이 실제로 보기 좋은가 |

**도달 가능성을 여기서 안 재는 이유.** "이 소품이 길을 끊는가"는
`src/map/placement.gd`의 `CHOKE_RADIUS`·`blocks_passage()`가 GDScript로 이미 갖고 있는
규칙이다. 파이썬으로 옮기면 **같은 규칙이 두 벌**이 되고, 이 저장소가 반복해 물린 결함이
정확히 그것이다(한쪽만 고쳐진다). 그 판정은 GDScript 쪽 관문(`world_audit`/`validate.gd`)이
본다 — 도구 스스로도 그렇게 말한다:

```
[props_check] note — 통로 차단(도달 가능성)은 여기서 재지 않는다:
              src/map/placement.gd blocks_passage()/CHOKE_RADIUS가 정본이라
              GDScript 쪽 관문이 봐야 한다.
```

**2026-09-09 실측:** `[props_check] ok — 소품 5개/파일 1개 · 스키마·정본 id·크기·맵 범위·
겹침·원본 ATT·문 간섭 통과 (경고 0건)`. F1에 5개(창고 사물함·서류 선반, 자료 서가,
우편함 열, 교무과 단말기)뿐이고 다른 층은 파일이 없다 — **파일 없는 층은 빈 층이고
오류가 아니다.**

---

## 8. 상황별 — 무엇부터 돌릴까

| 하고 싶은 것 | 순서 |
|---|---|
| 지금 뭐가 비었나 | `현황판.bat` → 부족하면 `python tools/dev/asset_status.py` |
| 그림을 새로 받고 싶다(첨부 가능) | `의뢰생성.bat <cat> [id]` → 패키지 폴더째 LLM에 |
| 그림을 새로 받고 싶다(브라우저 챗) | `python tools/convert/web_prompt.py --common` 한 번 → `… <cat> <id>` 시트마다 |
| 몇 개만 시범 발주 | `묶음포장.bat --pick 3 --name 시범` → 받은 뒤 `납품처리.bat --from …/_제출` |
| 받은 그림 처리 | 눈으로 비교 → `심사실행.bat` / 그냥 통과 → `납품처리.bat` |
| 규격이 어긋난 납품 | `셀편집기.bat <cat> <file>` → [계약] → [행별 재배치] → [다음 버전으로 저장] |
| 아이콘 크기만 틀림 | `python tools/convert/normalize_icon.py <납품.png> --inplace` |
| 채택본이 게임에 안 들어왔다 | `python tools/convert/install_delivery.py --dry-run` → 확인 후 `--dry-run` 빼고 |
| 코드를 고쳤다 | `검증실행.bat` (6분) |
| 급하다 / Godot이 없다 | 파이썬 쪽만: `test_sheet_ops` · `props_check` · `originals_check` · `spr_alpha_check` (관문 20번 `export_check.py`는 인자로 Godot 경로를 받으므로 제외) |
| 편집기를 고쳤다 | `fixer_check.py` → `fixer_probe.py --server` → `test_sheet_ops.py` |
| 의뢰문 숫자를 의심한다 | `python tools/review/prompt_audit.py` |
| 타일셋 시트를 의뢰한다 | `python tools/convert/tileset_contract.py` (배치표를 의뢰문에 그대로 싣는다) |

---

## 9. 실측 기록 (2026-09-09)

이 문서에 적힌 명령은 아래대로 실제 실행했다. 콘솔이 cp949라 `PYTHONIOENCODING=utf-8`을
붙였다. `run_gates.ps1` 전체(약 6분)는 **돌리지 않았다** — 같은 트리를 다른 작업자가
쓰고 있어서다. 관문 목록은 파일에서 그대로 옮겼다.

| 명령 | 결과 |
|---|---|
| `python tools/convert/tileset_contract.py` | 계약 출력 — 256×288px · 타일 32px · 8열 × 9행 · 정렬 none · 단일 타일 17 · 묶음 6 |
| `python tools/convert/install_delivery.py --dry-run` | `설치 20건 · 실패 0건 · 양자화 48색` (배율 계산이 줄마다 찍힘) |
| `python tools/convert/web_prompt.py --common` | 공통 규약 출력(스타일 바이블·픽셀 규칙·팔레트 잠금) |
| `python tools/convert/web_prompt.py monsters mad_eye` | `캔버스 — 640×1024px` · 셀 128 · 5열 × 8행 |
| `python tools/convert/web_prompt.py npcs dev1` | `캔버스 — 256×640px` · 셀 128 · 2열 × 5행 |
| `python tools/convert/web_prompt.py battle_actors player_battle` | `캔버스 — 512×896px` · 셀 128 · 4열 × 7행 |
| `python tools/convert/test_sheet_ops.py` | `통과 68 · 실패 0` |
| `python tools/dev/props_check.py` | `ok — 소품 5개/파일 1개 … (경고 0건)` |
| `python tools/dev/originals_check.py` | `ok — 원본 181파일 해시 일치 · 맵 234000셀 원본과 바이트 일치` |
| `python tools/review/fixer_check.py` | `통과` — 마크업 id 80 · JS가 찾는 id 62 · symbol 12 · `data-op` 29 ↔ `OPS` 29 · 서버 연산 16 · `node --check` OK(1475행) |
| `python tools/review/fixer_probe.py` | `통과` — 실조작 22항목 전부 OK(문지르기·굵은 지우개·우클릭 지우개·Shift 사각·연필·되돌리기·단축키·부동 이동 왕복·잘림 보고·페이지 예외 없음) |
| `python tools/review/prompt_audit.py` | `패키지 107건 · FAIL 2 · WARN 0` — `sys_builder` 한 건(선언 1024×768 ≠ 정본 1536×1152) |
| `python tools/dev/asset_status.py` | `합계 공백 41종` · 의뢰 패키지 현황(monsters 19 · portraits 25 · items 43 · keyart 6 · effects 6 · battle_cuts 7 · npcs 4 · battle_actors 1) |
| `ls assets/gen/prompts/web \| wc -l` | `130` |
| `_batch/0830_1133/monsters__*/grid_template.png` 크기 실측(PIL) | 19종 중 18종이 정본 크기, `sys_builder`만 1024×768로 어긋남 |

### 돌려 보지 못한 것 (그대로 적는다)

| 무엇 | 왜 |
|---|---|
| `run_gates.ps1` 전체(24단계) | 약 6분이고 같은 트리를 다른 작업자가 쓰고 있다 |
| Godot 관문 1~19 개별 | 위와 같은 이유 |
| `tools/dev/export_check.py` · `spr_alpha_check.py` | 관문에 들어 있으나 이번에 따로 돌리지 않았다 |
| `make_dashboard.py` (`현황판.bat`) | 추적 파일 `현황판.html`을 덮어쓴다 — 다른 작업자의 트리를 건드리지 않으려고 걸렀다 |
| `regrid_sheet.py` · `normalize_icon.py` · `process_llm_sheet.py` · `intake.py` · `pack_request.py` | 대상 PNG를 고르고 파일을 만들어야 해서 걸렀다. 설명은 각 도구 독스트링 기준 |
| `.bat` 11개의 실제 실행 | GUI·서버·게임 창을 띄운다. **내용은 전부 열어 읽고** 무엇을 부르는지 확인해 적었다 |
| `install_delivery.py` 실제 설치(`--dry-run` 없이) | 에셋을 바꾸는 일이라 모의 실행까지만 |
