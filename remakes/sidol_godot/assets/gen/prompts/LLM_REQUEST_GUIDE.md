# 그래픽 LLM 의뢰 간략 가이드 (다른 PC 세션용)

> 목적: 이미지 생성 LLM에 에셋을 의뢰하고, 납품을 심사(승인/반려/재요청)하는 전체 사이클.
> 소요: 패키지 생성 5분 + LLM 의뢰(유저) + 심사 루프.
> **경로·규격의 단일 출처는 [LLM_WORKFLOW.md](LLM_WORKFLOW.md)다.** 이 문서는 실행 순서만 다룬다.

## 이 문서는 누구 것인가 (중요)

**이 문서를 그림 그리는 LLM에게 주지 마라.** 사이클을 *운영하는* 쪽 문서다.

| 상대 | 줄 것 |
|---|---|
| **이미지 생성 LLM**(그림을 그리는 쪽) | 해당 패키지의 `prompt.md` **전문** + 그 폴더의 첨부 이미지 **전량**. 그게 전부다 |
| **작업을 운영하는 에이전트/사람**(패키지 생성·저장·심사·재요청) | 이 문서 + `AGENTS.md`의 "에셋 에이전트 작업 경계" |

`prompt.md`는 규격·금지규칙·첨부 설명이 이미 자기완결로 들어 있다.
이 가이드를 같이 주면 그림 LLM이 폴더 구조·심사 절차 같은 무관한 지시를 따라간다.

## 0. 사전 준비 (새 PC)

```powershell
git clone https://github.com/omempty/busidol.git
cd busidol/remakes/sidol_godot
pip install pillow numpy          # 패키지 생성기·검증기 의존성 (이것만 있으면 됨)
```

- `assets/raw/llm/`은 gitignored — **클론 직후엔 비어 있음. 아래 1번으로 재생성.**
- 원본 도트(`assets/originals_ref/`)·스펙·팔레트는 git에 있으므로 재생성이 항상 가능.
- 심사 보드는 파이썬 표준 라이브러리만 쓴다(추가 설치 없음).

## 1. 의뢰 패키지 생성 (원하는 카테고리만)

```powershell
python tools/convert/export_portrait_packages.py   # 포트레이트 16종 → assets/raw/llm/portraits/
python tools/convert/export_keyart_packages.py     # 키아트 6종    → assets/raw/llm/keyart/
python tools/convert/export_monster_packages.py    # 몬스터 11종   → assets/raw/llm/monsters/
python tools/convert/export_player_sheet.py        # 주인공 리터치 → assets/gen/prompts/   ※경로 다름
python tools/convert/export_player_gen_package.py  # 주인공 신규   → assets/gen/prompts/   ※경로 다름
```

앞 3종은 `assets/raw/llm/<카테고리>/<id>/`에 `prompt.md` + 첨부 이미지를 만든다.
**주인공 2종만 산출 경로가 `assets/gen/prompts/`로 다르다**(git 추적 대상이라 그렇다).

## 2. 무엇부터 의뢰할 것인가

학습 난이도가 아니라 **게임에 실제로 비는 것** 순서다.
근거: [docs/03_plan/05_polish_roadmap.md](../../../docs/03_plan/05_polish_roadmap.md) §5.1

| 순위 | 대상 | 이유 |
|---|---|---|
| 1 | **몬스터 8종** — `rogue_vending` `c_bug` `flying_thesis` `null_pointer` | 지금 게임에서 **주인공 플레이스홀더 도트로 나온다**. 가장 눈에 띄는 공백 |
| 2 | **NPC 4종** — `dev1` `dev2` `lab_student` `afterschool_student` | 위와 같은 이유(전용 시트 부재) |
| 3 | 포트레이트 16종 | 대화창 초상 — 없어도 진행되지만 연출 밀도가 크게 오른다 |
| 4 | 4방향 idle 프레임 | 지금은 `walk` 첫 프레임으로 대체 중. 시트 보강 사안 |
| 5 | 키아트 6종 | 컷신 연출 강화. 마지막 |

처음이라면 **포트레이트 1건으로 사이클을 한 번 완주**해 보고 위 순서로 들어가는 편이 빠르다
(포트레이트가 규격 계약이 가장 단순하다).

## 2-1. 폴더째 넘기는 경우 (파일 접근이 되는 에이전트)

`assets/raw/llm/` 폴더 하나만 넘기면 된다. 루트에 **`README_먼저읽기.md`**(작업 지시서)가
생성기에 의해 항상 깔려 있고, 그 안에 우선순위·절차·저장 규약이 전부 들어 있다.
전달 문구는 이 한 줄이면 충분하다:

> `assets/raw/llm/` 폴더를 준다. 루트의 `README_먼저읽기.md`를 먼저 읽고 그대로 따르라.

파일 접근이 안 되는 순수 이미지 생성기라면 §3의 개별 첨부 방식을 쓴다.

## 3. 이미지 LLM에 의뢰

**규칙은 하나다: `prompt.md` 전문 + 그 폴더의 이미지 전부 + 카테고리 루트의
`palette_swatch.png`.** prompt.md의 "입력(첨부)" 목록이 곧 첨부해야 할 파일 목록이다.

| 카테고리 | 프롬프트 | 폴더에 들어 있는 첨부물 |
|---|---|---|
| 포트레이트 | `raw/llm/portraits/<id>/prompt.md` | `<id>_source.png` · `orig_portrait_1~3.png` |
| 키아트 | `raw/llm/keyart/<scene_id>/prompt.md` | `tone_anchor.png` · `orig_scene_*.png` · `orig_portrait.png` (씬에 원작 대응이 있으면 `orig_this_scene.png`) |
| 몬스터 | `raw/llm/monsters/<id>/prompt.md` | `style_ref.png` · `orig_enemy_1~2.png` |
| 스프라이트(주인공) | `gen/prompts/player_retouch_prompt.md` | `player_sheet_original.png` · `player_sheet_annotated.png` |

- **이미지를 빼지 마라.** `orig_*.png`가 원작 화풍의 1차 근거다 — 빠지면 신규 생성물이
  원작과 겉돈다(규칙 문장만으로는 화풍이 안 잡힌다).
- 한 번에 한 개씩. 결과가 마음에 들 때까지 같은 세션에서 "반려 사항"을 던져 재생성해도 된다.

## 4. 납품 저장

납품 폴더는 §1의 생성기가 이미 만들어 둔다(`10_submitted/{portraits,keyart,monsters,sprites}`).
받은 PNG를 카테고리 폴더에 그대로 저장한다:

```
assets/raw/llm/10_submitted/<카테고리>/<id>_v1.png     # 재납품은 v2, v3…
```

**`<id>`는 패키지 폴더 이름과 글자 단위로 같아야 한다.** 심사 보드는 파일명에서 `<id>`를
떼어내 원본·프롬프트·앵커를 찾는다 — 이름이 어긋나면 3열 비교가 비고, 반려 시 만들어지는
재요청 md에 **원본 의뢰문이 들어가지 않는다**(반려 사유만 남는다).

## 5. 심사 (승인 / 반려 / 재요청)

```powershell
심사실행.bat        # 브라우저에 심사 보드가 열린다 (http://127.0.0.1:8643/tools/review/review_board.html)
```

- 카드 = 원본 참조 | 납품물 | 스타일 앵커 3열 비교 + 자동 검증 배지.
- **반려** → 사유 입력 시 `10_submitted/_feedback/<카테고리>/<파일>.md`에 **재요청 프롬프트**가
  자동 생성된다(원본 의뢰문 + 반려 사항 + 검증 결과 + v\<n+1\> 지시). 납품물은 `_rejected/`로 이동.
  이 md를 LLM에 다시 붙이고(원본 첨부물 동일) 나온 결과를 v\<n+1\>로 저장 → 보드에서 재심사.
- **승인은 카테고리에 따라 동작이 다르다 — 되돌릴 수 없으니 주의:**

| 카테고리 | 승인 시 동작 |
|---|---|
| 포트레이트 · 키아트 | `20_processed/<cat>/`으로 **이동**(원본 보존) |
| 몬스터 · 스프라이트 | `process_llm_sheet.py`가 그리드 컷팅까지 수행하고 **`10_submitted`의 원본을 삭제한다** |

몬스터·스프라이트는 승인 전에 납품 원본을 따로 복사해 두면 안전하다.

- 전체 승인/전체 반려 버튼 지원.

## 6. 채택 이후

`20_processed/`까지가 유저 영역. 게임 반입(패킹, `res://assets/`)은 메인 개발 세션에서
수행한다 — "심사 통과분 채택 패킹"으로 세션에 지시하면 된다.

## 7. 막힐 때

| 증상 | 확인 |
|---|---|
| 심사 보드가 비어 있다 | `10_submitted/<카테고리>/` 폴더가 있는가(§4). 파일 확장자가 `.png`인가 |
| 3열 비교에 원본이 안 뜬다 | 파일명 `<id>`가 패키지 폴더명과 정확히 같은가(§4) |
| 브라우저가 안 열린다 | 직접 접속: `http://127.0.0.1:8643/tools/review/review_board.html` |
| 포트 충돌 | `python tools\review\review_server.py 9000` 후 URL의 포트만 바꿔 접속 |
| `python`을 찾을 수 없다 | PATH 등록 여부 확인. `py -3 tools\convert\...`로도 실행된다 |
| 검증 FAIL인데 눈으로는 괜찮다 | 배지의 검증 출력을 읽어라 — 대부분 배경 키잉·AA·규격 문제다 |

## 주의

- **원본 의뢰문(prompt.md)의 규격·금지규칙은 임의로 줄이지 말 것** — 그리드/배경 규칙
  위반이 1차 반려의 주원인이었다.
- 이미지 LLM에게 "리터치"를 시키지 않는다. 계약은 **원본 첨부 + 신원 유지 재창작**이다.
- 마젠타 배경(`#FF00FF`)은 허용하되 **혼색·안티에일리어싱 금지** — 키잉이 깨진다.
