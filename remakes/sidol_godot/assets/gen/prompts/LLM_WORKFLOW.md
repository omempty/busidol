# LLM 에셋 워크플로우 (계약 단일 출처)

> 이 문서가 **경로·규격·검증의 권위**다. 실행 순서만 필요하면
> [LLM_REQUEST_GUIDE.md](LLM_REQUEST_GUIDE.md)를 본다(그쪽이 이 문서를 참조한다).
> 도구 하나하나를 "어떻게 돌리나"는 [`docs/TOOLS.md`](../../../docs/TOOLS.md)에 있다.
>
> `assets/raw/llm/`은 gitignored 임시 작업区다. 버전 관리 대상은 최종 채택 후
> `res://assets/sprites/`(또는 `res://assets/icons/`)로 패킹된 것만.

## 1. 파이프라인

```
[1] 추출   tools/convert/extract_sprites.py
           originals_ref/bmp_spr (935프레임) -> 00_reference/
           (배경 제거 투명 PNG 프레임 단위 + 그룹별 컨택트 시트)

[2] 의뢰   패키지 생성기가 prompt.md + 첨부물을 만든다 (§2 표)
           -> 유저가 이미지 LLM에 프롬프트 전문 + 첨부물 전량 투입

[2-웹] 첨부를 못 주는 브라우저 챗용 경로 — tools/convert/web_prompt.py
           [2]의 prompt.md는 첨부 5~8장을 전제로 쓰여 있어, 챗에 붙이면 절반이
           "없는 파일을 가리키는 문장"이 된다. 그래서 같은 스펙에서 첨부 없는
           프롬프트를 따로 굽는다(공통 규약 1장 + 시트 상세 1장씩).
           -> assets/gen/prompts/WEB_PROMPT_COMMON.md · web/<cat>__<id>.md (실측 130개)

[3] 납품   받은 파일을 10_submitted/<카테고리>/<id>_v<n>.png 로 저장 (§3)

[4] 심사   심사실행.bat -> 심사 보드(tools/review/)
           카드당 원본|납품|앵커 3열 비교 + 자동 검증 배지
           승인 -> §4 표대로 처리 · 반려 -> 재요청 md 생성 + _rejected 이동

[5] 편집   (선택) 규약 미달 납품을 셀 단위로 고친다 — tools/review/sprite_fixer.html
           심사 보드 [셀 편집] 버튼. 결과는 다음 버전으로 10_submitted에 재납품되어
           [4]를 다시 탄다. 통째 재생성보다 싼 경우가 많다(잔선·라벨·색 수)

[6] 설치   tools/convert/install_delivery.py  (승인 시 심사 서버가 자동 실행)
           20_processed -> assets/sprites|portraits|keyart|icons|effects
           색 48 양자화 · 안내선 잔선 제거 · 메타 JSON 생성(스펙에서 산출)
```

## 2. 카테고리 계약

| 카테고리 | 패키지 생성기 | 패키지 산출 위치 | 납품 규격 | 검증기 |
|---|---|---|---|---|
| `portraits` | `export_portrait_packages.py` | `raw/llm/portraits/<id>/` (25) | 768×256, 3셀(표정 3종) | `validate_submission.py portrait` |
| `keyart` | `export_keyart_packages.py` | `raw/llm/keyart/<id>/` (6) | 1920×1080 (480×270 nearest 축소 전제) | `validate_submission.py keyart` |
| `monsters` | `export_monster_packages.py` · `export_monster_remaster_packages.py` | `raw/llm/monsters/<id>/` (19) | 그리드 계약 자동 산출(행별 프레임) | `validate_monster_sheet.py` |
| `npcs` | `export_npc_packages.py` | `raw/llm/npcs/<id>/` (4) | 몬스터와 같은 128 격자 | `validate_monster_sheet.py` |
| `items` | `export_item_icon_packages.py` | `raw/llm/items/<ID>/` (43) | 96×96 1장 | `validate_submission.py icon` |
| `effects` | `export_effect_packages.py` | `raw/llm/effects/<id>/` (6) | 셀 128 × 프레임, **중앙 정렬** | `validate_monster_sheet.py` |
| `battle_cuts` | `export_battle_cut_packages.py` | `raw/llm/battle_cuts/<id>/` (7) | 셀 **512** × 프레임, 배우만 | `validate_monster_sheet.py` |
| `battle_actors` | `export_battle_actor_packages.py` | `raw/llm/battle_actors/<id>/` (1) | 필드와 같은 셀 128 격자(전투 전용 SD) | `validate_monster_sheet.py` |
| `sprites` | `export_player_remaster_package.py`(리터칭 — 원작 기반) | **`assets/raw/llm/sprites/<id>/`** (1) | 정본 `assets/spec/sprites/player_sidol.json` · 셀 128 · 4열 × 8행 | `validate_retouch_sheet.py` |

> 괄호 안은 **생성기가 만들 수 있는 종 수가 아니라 지금 디스크에 있는 패키지 폴더 수**다
> (2026-09-09 실측 — `python tools/dev/asset_status.py`의 「의뢰 패키지 생성 현황」과 같은 수).
> 예전 판은 여기에 생성기의 종 수를 적어 뒀는데 폴더가 늘어도 문서가 안 따라와 갈라졌다.
> **세려면 문서를 읽지 말고 `asset_status.py`를 돌려라.**

- **공용 참조는 카테고리 루트에 1부**만 둔다(`style_ref.png`·`scale_ref.png`·`subpalette.png`·
  `orig_*.png`, 아이템은 `_kind/<분류>/`). 패키지 폴더에는 그 패키지에서만 쓰는 것
  (`prompt.md`·`grid_template.png`·`grid_guide.png`·`<id>_source.png`)만 남는다.
  프롬프트의 "입력 (첨부)" 목록이 경로의 단일 근거다.
- `sprites`만 패키지 산출 위치가 다르다 — git 추적 대상이라 `raw/llm/`(gitignored) 밖에 둔다.
- 카테고리 이름 **9종**은 `tools/review/review_server.py`의 `CATEGORIES`가 권위다
  (`portraits`·`keyart`·`monsters`·`npcs`·`sprites`·`items`·`effects`·`battle_cuts`·`battle_actors`
  — 2026-09-09 실측). **여기 없는 이름으로 폴더를 만들면 심사 보드가 무시한다.**
- 원작 리소스는 LLM 경유 없이 코드로 이관(정책 ①):
  `migrate_original_sheets.py`(몬스터 8 + NPC 7), `migrate_item_icons.py`(아이콘 24).
  **신규 창작 대상만 LLM에 위탁한다.**
- 계약 원칙: 이미지 LLM은 "리터치" 불가 — **원본 첨부 + 신원 유지 재창작**으로 의뢰한다.

## 3. 납품 파일명 규약 (심사 보드 기능과 직결)

```
assets/raw/llm/10_submitted/<카테고리>/<id>_v<n>.png
```

- **`<카테고리>`는 §2의 9종 중 하나.** 스프라이트도 `10_submitted/sprites/` 하위다
  (과거 문서가 하위 폴더 없이 적었으나 오기 — 그렇게 두면 보드에 뜨지 않는다).
- **`<id>`는 패키지 폴더명과 글자 단위로 동일해야 한다.** 보드는 `<id>_v<n>` 패턴에서
  `<id>`를 떼어 `raw/llm/<cat>/<id>/`의 `prompt.md`·`<id>_source.png`·`style_ref.png`·
  `tone_anchor.png`를 찾는다. 어긋나면 3열 비교가 비고, 반려 시 생성되는 재요청 md에
  **원본 의뢰문이 들어가지 않는다.**
- `<n>`은 1부터. 재납품마다 증가시킨다 — 재요청 md가 다음 번호를 지정해 준다.
- **폴더는 자동 생성되지 않는다.** 없으면 그 카테고리 목록이 빈 채로 뜬다.

## 4. 승인 동작 (카테고리별로 다르다 — 비가역)

| 카테고리 | 승인 시 |
|---|---|
| `portraits` · `keyart` | `20_processed/<cat>/`으로 **이동**(원본 보존) |
| `monsters` · `sprites` | `process_llm_sheet.py` 실행(마젠타 키잉 → 스펙 그리드 컷팅 → 프레임 검출 → 검증 → `20_processed/<캐릭터>/`) 후 **`10_submitted`의 원본을 삭제** |

몬스터·스프라이트는 승인 전에 납품 원본을 별도 보관해 두는 편이 안전하다.

반려는 공통이다: `10_submitted/_feedback/<cat>/<파일>.md`에 재요청 패키지
(원본 의뢰문 + 유저 반려 사유 + 자동 검증 결과 + v\<n+1\> 지시)를 만들고
납품물을 `_rejected/<cat>/`으로 옮긴다.

## 5. 폴더

| 폴더 | 내용 | 비고 |
|---|---|---|
| `00_reference/` | 원작 추출본(투명 PNG + 컨택트 시트) | LLM 첨부용, 언제든 재생성 |
| `10_submitted/<cat>/` | LLM 납품 원본(마젠타 배경) | 손대지 않고 보관 |
| `10_submitted/_feedback/<cat>/` | 반려 시 자동 생성된 재요청 md | LLM에 다시 붙일 것 |
| `10_submitted/_rejected/<cat>/` | 반려된 납품물 | 이력 |
| `20_processed/` | 키잉·컷팅·검증 완료 프레임 | 뷰어 검수 대상 |
| `30_packed/` | 게임 반입 준비 완료 | 채택분만 |

## 6. 경계 규칙

- 납품 검증(`validate_submission` / `validate_retouch_sheet` / `process_llm_sheet` 내장 검사)
  미통과분은 `20_processed`로 넘어가지 않는다.
- `30_packed` → `res://assets` 복사는 **메인 개발(에이전트)만** 수행한다.
- 에셋 작업자는 자기 경로만 스테이징한다([AGENTS.md](../../../AGENTS.md) 커밋 소유권).
- `assets/raw/`는 임시라 언제든 삭제 가능 — `00_reference`는 스크립트로 재생성된다.

## 7. 검증이 잡는 것 / 못 잡는 것

자동 배지를 신뢰할 수 있는 범위를 알아야 눈으로 볼 곳이 정해진다.

| 자동 검증이 잡는다 | 사람이 봐야 한다 |
|---|---|
| 캔버스 크기·셀 그리드 일치 | 캐릭터 신원 유지(같은 인물로 보이는가) |
| 마젠타 배경 잔존·혼색·AA | 원작 톤·팔레트 감각 |
| 투명도 비율, 도트 bbox 편차 | 프레임 간 동작 연속성(보행 위상) |
| 빈 셀·프레임 수 불일치 | 게임 내 크기감(타일 대비 비율) |
| **격자 안내선 잔존**(반감광 포함) | **캔버스 안 글자**(애니 이름·대사 — 검사가 못 읽는다) |
| **고유색 수**(계약 48) | 표정·동작이 실제로 요구대로인가 |

2026-08-28에 아래 세 줄이 추가됐다. 그전 게이트는 규격만 봤고, 납품 9장이 **전부 통과**한 뒤
수동 검증에서 5건이 반려급으로 드러났다(잔선 8건 · 라벨 글자 2건 · 신원 불일치 1건 ·
고유색 16k~50k 9건). `tools/convert/delivery_checks.py`가 그 판정의 단일 소스다.

`20_processed/` 산출물은 `뷰어실행.bat`(tools/viewer.html)로 검수한다.
