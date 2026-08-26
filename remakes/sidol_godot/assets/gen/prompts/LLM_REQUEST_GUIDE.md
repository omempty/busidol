# 그래픽 LLM 의뢰 간략 가이드 (다른 PC 세션용)

> 목적: 이미지 생성 LLM에 에셋을 의뢰하고, 납품을 심사(승인/반려/재요청)하는 전체 사이클.
> 소요: 패키지 생성 5분 + LLM 의뢰(유저) + 심사 루프. 자세한 계약은 LLM_WORKFLOW.md.

## 0. 사전 준비 (새 PC)

```powershell
git clone https://github.com/omempty/busidol.git && cd busidol/remakes/sidol_godot
pip install pillow numpy          # 패키지 생성기·검증기 의존성 (이것만 있으면 됨)
```

- `assets/raw/llm/`은 gitignored — **클론 직후엔 비어 있음. 아래 1번으로 재생성.**
- 원본 도트(originals_ref)·스펙·팔레트는 git에 있으므로 재생성이 항상 가능.

## 1. 의뢰 패키지 생성 (원하는 카테고리만)

```powershell
python tools/convert/export_portrait_packages.py   # 포트레이트 16종 → assets/raw/llm/portraits/
python tools/convert/export_keyart_packages.py     # 키아트 6종    → assets/raw/llm/keyart/
python tools/convert/export_monster_packages.py    # 몬스터 11종   → assets/raw/llm/monsters/
```

각 패키지 폴더(`assets/raw/llm/<카테고리>/<id>/`)에 `prompt.md` + 첨부 이미지가 생성된다.

## 2. 이미지 LLM에 의뢰

| 카테고리 | 프롬프트 | 같이 첨부할 이미지 |
|---|---|---|
| 포트레이트 | `portraits/<id>/prompt.md` | `<id>_source.png` + `palette_swatch.png`(카테고리 루트) |
| 키아트 | `keyart/<scene_id>/prompt.md` | `tone_anchor.png` + `palette_swatch.png` |
| 몬스터 | `monsters/<id>/prompt.md` | `style_ref.png` + `palette_swatch.png` |

- **prompt.md 내용 전체를 복사해 붙이고, 표의 이미지를 모두 첨부**한다. 이미지 생략 시
  스타일·신원 계약이 깨진다(1차 반려 사유).
- 한 번에 한 개씩. 결과가 마음에 들 때까지 같은 세션에서 "반려 사항"을 던져 재생성해도 된다.

## 3. 납품 저장

받은 PNG를 그대로 저장 (이름 규약 `<id>_v1.png`, 재낡품은 v2, v3…):

```
assets/raw/llm/10_submitted/portraits/<id>_v1.png
assets/raw/llm/10_submitted/keyart/<scene_id>_v1.png
assets/raw/llm/10_submitted/monsters/<id>_v1.png
```

## 4. 심사 (승인 / 반려 / 재요청)

```powershell
심사실행.bat        # 브라우저에 심사 보드가 열린다
```

- 카드 = 원본 참조 | 납품물 | 스타일 앵커 3열 비교 + 자동 검증 배지.
- **승인** → 20_processed 이동(스프라이트는 그리드 컷팅까지 자동).
- **반려** → 사유 입력하면 `_feedback/<카테고리>/<파일>.md`에 **재요청 프롬프트**가
  자동 생성된다(원본 의뢰문 + 반려 사항 + 검증 결과 + v<n+1> 지시).
  이 md를 LLM에 다시 붙이고(원본 첨부물 동일) 나온 결과를 v<n+1>로 저장 → 보드에서 재심사.
- 전체 승인/전체 반려 버튼 지원.

## 5. 채택 이후

`20_processed/`까지가 유저 영역. 게임 반입(패킹, `res://assets/`)은 메인 개발 세션에서
수행한다 — "심사 통과분 채택 패킹"으로 세션에 지시하면 된다.

## 주의

- **원본 의뢰문(prompt.md)의 규격·금지규칙은 임의로 줄이지 말 것** — 그리드/배경 규칙
  위반이 1차 반려의 주원인이었다.
- 스프라이트(주인공 리터치 등)는 그리드 계약이 까다로우니 포트레이트→키아트→몬스터 순으로
  익히는 것을 권장.
- 검증 FAIL인데 시각적으로 괜찮아 보이면 검증 출력을 읽어라 — 대부분 배경 키잉/AA/규격 문제.
