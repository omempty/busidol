# 프롬프팅 퀵가이드 (1장짜리 참조용)

> 상세는 [LLM_REQUEST_GUIDE.md](LLM_REQUEST_GUIDE.md)(운영 절차) ·
> [LLM_WORKFLOW.md](LLM_WORKFLOW.md)(경로·규격 단일 출처).
> 이 문서는 **작업하면서 곁눈질로 보는 요약**이다.

## 1. 지금 뭐가 비었나

```powershell
python tools/dev/asset_status.py
```

## 2. 의뢰 패키지 만들기

```powershell
python tools/convert/export_monster_packages.py    # 몬스터·보스   → assets/raw/llm/monsters/
python tools/convert/export_npc_packages.py        # 필드 NPC      → assets/raw/llm/npcs/
python tools/convert/export_item_icon_packages.py  # 아이템 아이콘 → assets/raw/llm/items/
python tools/convert/export_portrait_packages.py   # 대화 초상     → assets/raw/llm/portraits/
python tools/convert/export_keyart_packages.py     # 컷신 키아트   → assets/raw/llm/keyart/
```

- 뒤에 **id를 붙이면 그것만** 만든다: `export_item_icon_packages.py ITEM_ARMOR_GOWN`
- **이미 파일이 있어도** id를 명시하면 다시 만든다(부분 수정용)

## 3. 그림 LLM에 줄 것 — 딱 이것뿐

| 준다 | 안 준다 |
|---|---|
| `<패키지 폴더>/prompt.md` **전문** | 이 문서·가이드 문서 |
| 그 폴더의 **이미지 전부** | 폴더 구조·심사 절차 설명 |
| 카테고리 루트의 `palette_swatch.png` | 추가 지시("잘 그려줘" 같은 것) |

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

## 6. 심사

```powershell
심사실행.bat        # http://127.0.0.1:8643/tools/review/review_board.html
```

- **승인** → `20_processed`로. 스프라이트 계열은 그리드 컷팅까지 자동
- **반려** → 사유만 적으면 `10_submitted/_feedback/<카테고리>/<파일>.md`에
  **재요청 프롬프트**(원본 의뢰문 + 반려 사유 + 검증 결과)가 생긴다. 그대로 다시 던진다

## 7. 자주 나오는 실패와 대응

| 증상 | 대응 |
|---|---|
| **크기가 틀림**(아이콘) | 반려 말고 고쳐 쓴다: `python tools/convert/normalize_icon.py <납품.png> --inplace` |
| 크기·프레임 수가 틀림(시트) | 반려. 재요청 시 `grid_template.png`를 **열어서 그 위에 그리라**고 한 줄 덧붙인다 |
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

공통: 안티에일리어싱 금지(반투명 픽셀 0%) · 외곽선 1px 다크(순수 블랙 금지) ·
명암 4~6단 + 색조 그림자 · 캔버스 안 글자/워터마크 금지.
