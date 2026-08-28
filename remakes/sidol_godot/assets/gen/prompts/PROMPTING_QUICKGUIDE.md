# 프롬프팅 퀵가이드 (1장짜리 참조용)

> 상세는 [LLM_REQUEST_GUIDE.md](LLM_REQUEST_GUIDE.md)(운영 절차) ·
> [LLM_WORKFLOW.md](LLM_WORKFLOW.md)(경로·규격 단일 출처).
> 이 문서는 **작업하면서 곁눈질로 보는 요약**이다.

## 0. 한눈에 보기 — 현황판

```powershell
현황판.bat        # 다시 굽고 브라우저로 연다(서버 불필요)
```

`현황판.html`이 카테고리별 진행률 · 에셋별 상태(설치됨/채택/납품 대기/의뢰 준비) ·
프롬프트 바로가기 · 지금 칠 명령을 한 장에 모아 준다. 수치는 `asset_status.collect()`가
정본이라 CLI와 갈라지지 않는다.

## 1. 지금 뭐가 비었나

```powershell
python tools/dev/asset_status.py
```

## 2. 의뢰 패키지 만들기

가장 쉬운 길 — **`의뢰생성.bat`** (메뉴에서 카테고리 선택, 끝나면 현황을 보여 준다):

```
의뢰생성.bat                     메뉴
의뢰생성.bat portraits           그 카테고리 전량
의뢰생성.bat portraits prof_mo   한 건만 — 시범·부분 재생성
```

직접 부르려면:

```powershell
python tools/convert/export_monster_packages.py    # 몬스터·보스   → assets/raw/llm/monsters/
python tools/convert/export_monster_remaster_packages.py  # 원작 몬스터 8종 리마스터 → 같은 폴더
python tools/convert/export_npc_packages.py        # 필드 NPC      → assets/raw/llm/npcs/
python tools/convert/export_item_icon_packages.py  # 아이템 아이콘 → assets/raw/llm/items/
python tools/convert/export_portrait_packages.py   # 대화 초상     → assets/raw/llm/portraits/
python tools/convert/export_keyart_packages.py     # 컷신 키아트   → assets/raw/llm/keyart/
python tools/convert/export_effect_packages.py     # 전투 이펙트   → assets/raw/llm/effects/
python tools/convert/export_battle_cut_packages.py # 전투 대형 컷  → assets/raw/llm/battle_cuts/
```

- 뒤에 **id를 붙이면 그것만** 만든다: `export_item_icon_packages.py ITEM_ARMOR_GOWN`
- **이미 파일이 있어도** id를 명시하면 다시 만든다(부분 수정용)

## 3. 그림 LLM에 줄 것 — 딱 이것뿐

| 준다 | 안 준다 |
|---|---|
| `<패키지 폴더>/prompt.md` **전문** | 이 문서·가이드 문서 |
| prompt.md의 **"입력 (첨부)" 목록에 적힌 파일 전부** | 폴더 구조·심사 절차 설명 |
| (`../foo.png`는 카테고리 루트의 공용 참조 1부) | 추가 지시("잘 그려줘" 같은 것) |

> 공용 참조(style_ref·scale_ref·subpalette·orig_*)는 **카테고리 루트에 1부**만 둔다.
> 패키지마다 복사하던 것을 정리했다(2026-08-28: 몬스터 55 · 초상 48 · 키아트 24개 중복 제거).

프롬프트에는 이미 아래가 **자동으로** 들어 있다 — 따로 덧붙이지 마라:
스타일 바이블 전문 · 실측 베이스라인(원작 수치 ↔ 리메이크 타깃) · 서브팔레트(hex 목록) ·
격자 템플릿 · 크기/정렬 계약 · 금지 목록 · 자기검증 체크리스트.

## 4. 진행 순서

| 단계 | 무엇 | 왜 |
|---|---|---|
| ① 시범 | 대표 1~2건만 뽑아 합격/반려 판단 | 톤을 여기서 확정한다 |
| ② 전체 | 인자 없이 실행해 남은 전량 | 합격본이 **다음 의뢰의 스타일 앵커로 자동 채택**된다 |
| ③ 부분 재생성 | 마음에 안 드는 id만 다시 | 전체를 다시 돌리지 않는다 |

## 5. 납품 저장

```
assets/raw/llm/10_submitted/<카테고리>/<id>_v1.png     # 재납품은 v2, v3…
```

**`<id>`는 패키지 폴더 이름과 글자 단위로 같아야 한다.** 다르면 심사 보드가 원본 의뢰문을
못 찾아 반려 시 재요청 md에 의뢰문이 빠진다.

## 5-1. 몇 건만 시범 발주 — 폴더 통째로 넘기기 (GUI 없이)

이미지 생성은 토큰이 비싸다. 전량이 아니라 **몇 개만** 뽑아 자기완결 폴더로 포장한다:

```powershell
묶음포장.bat --pick 3 --name 시범          # 비어 있는 것부터 3건
묶음포장.bat monsters:sys_builder effects:hit_spark
```

산출: `assets/raw/llm/_batch/<이름>/`
- `작업지시.md` — 무엇을 몇 장, 어떤 순서로, 어디에 저장할지
- `<카테고리>__<id>/` — prompt.md(경로 평탄화) + 첨부 **전부**(밖을 참조하지 않는다)
- `<카테고리>__<id>/웹붙여넣기.md` — **웹 채팅용 축약본(2KB 안팎)**. 무료 LLM에 한 메시지로
  붙여넣고 이미지 3~4장만 첨부한다. 톤은 스타일 6줄 + 서브팔레트 hex + 원작 참조가 잡는다
- `_제출/` — 납품을 여기 받는다

받은 뒤:

```powershell
납품처리.bat --from assets/raw/llm/_batch/시범/_제출
```

검증 → 채택(시트는 그리드 컷팅) → **설치**까지 한 번에 간다. 반려는 사유가 담긴
재요청 md가 `10_submitted/_feedback/`에 생긴다. 카테고리는 파일명 id로 자동 판별한다.

## 6. 심사

```powershell
심사실행.bat        # http://127.0.0.1:8643/tools/review/review_board.html
```

- **승인** → `20_processed`로. 스프라이트 계열은 그리드 컷팅까지 자동.
  이어서 **`install_delivery.py`가 게임 에셋 자리로 설치**한다(색 48 양자화 · 잔선 제거 ·
  메타 JSON 생성). 승인만 하고 게임엔 안 들어가던 구멍을 막은 자리다
- **셀 편집** → 규약을 못 맞춘 납품을 통째로 다시 그리게 하는 대신
  `sprite_fixer.html`에서 **셀 단위로 고쳐 다음 버전으로 재납품**한다
- **반려** → 사유만 적으면 `10_submitted/_feedback/<카테고리>/<파일>.md`에
  **재요청 프롬프트**(원본 의뢰문 + 반려 사유 + 검증 결과)가 생긴다. 그대로 다시 던진다

## 7. 자주 나오는 실패와 대응

| 증상 | 대응 |
|---|---|
| **크기가 틀림**(아이콘) | 반려 말고 고쳐 쓴다: `python tools/convert/normalize_icon.py <납품.png> --inplace` |
| 크기·프레임 수가 틀림(시트) | 심사 보드 **[셀 편집] → 계약 격자로 재배치**. 그래도 안 되면 반려 |
| **격자 안내선이 남음** | [셀 편집] → 자동 정리(잔선 제거 + 주변 오염 정리). 설치 단계도 같은 정리를 한다 |
| **고유색 수천~수만** | 계약은 48색. [셀 편집] → 색 양자화, 또는 설치 시 자동 양자화 |
| **애니 이름·대사 글자가 박혀 옴** | 반려(캔버스 내 글자 금지). 짧으면 [셀 편집]에서 Shift+드래그로 지운다 |
| 톤이 원작과 겉돎 | 첨부 이미지를 빠뜨렸는지 먼저 확인(`orig_*.png`가 화풍의 1차 근거다) |
| 너무 원작 복사 같음 | 프롬프트의 "리메이크 타깃" 열을 지목해 재요청 — 명암 4~6단·색 24~48로 올리라고 |
| 배경이 흰색/체커보드 | 반려. 투명 또는 마젠타 `#FF00FF`만 허용 |
| 여러 장·시트로 보냄 | 반려. 아이콘은 1장, 시트는 규격 1장 |

## 8. 규격 요약

| 카테고리 | 크기 | 배경 |
|---|---|---|
| 아이템 아이콘 | **96×96** 1장 | 투명 / 마젠타 |
| 필드 캐릭터(NPC·몬스터) | 셀 128 × (열×행) — 패키지마다 다름, `prompt.md`에 명시 | 투명 / 마젠타 |
| 대화 초상 | 768×256 (256 셀 3개) | 투명 / 마젠타 |
| 컷신 키아트 | 1920×1080 | 불투명 |
| 전투 이펙트 | 셀 128 × 프레임 수 (1행), **셀 중앙 정렬** | 투명 / 마젠타 |
| 전투 대형 컷 | 셀 **512** × 프레임 수 (1행), 하단 중앙 정렬 · 배우만 | 투명 / 마젠타 |

공통: 안티에일리어싱 금지(반투명 픽셀 0%) · 외곽선 1px 다크(순수 블랙 금지) ·
명암 4~6단 + 색조 그림자 · **고유색 48색 이하** · 캔버스 안 글자/워터마크 금지 ·
**격자 안내선 잔존 금지**(흐리게 남겨도 자동 검출·반려).
