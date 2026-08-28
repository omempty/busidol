#!/usr/bin/env python3
"""아이템 아이콘 LLM 의뢰 패키지 생성 — data/items.json 기준, 아이콘 없는 항목만.

2026-08-28 실측: items.json 64종 중 아이콘이 있는 것은 24종뿐이고 나머지 40종은
인벤토리·상점·슬롯바에서 **색 상자 + 글자 한 자**로 나온다(ItemIcons 폴백).
방어구 9종·시약 5종·퀘스트 9종처럼 리메이크에서 새로 만든 물건이 특히 비어 있다.

기존 아이콘 24종을 스타일 앵커로 첨부한다 — 규칙 문장보다 그림 석 장이 강하다.

산출: assets/raw/llm/items/<ITEM_ID>/prompt.md + style_ref_1~3.png
      (공통 첨부는 카테고리 루트의 palette_swatch.png)

실행: python tools/convert/export_item_icon_packages.py [ITEM_ID ...]
      인자 없이 실행하면 아이콘이 없는 항목 전부.
"""
from __future__ import annotations

import io
import json
import os
import shutil
import sys

# 콘솔 코드페이지가 cp949여도 한글·em대시가 깨지지 않게 한다(bash·cmd 양쪽).
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from llm_package_common import (
    NEGATIVE_RULES,
    SELF_CHECK,
    dominant_colors,
    make_grid_template,
    make_palette_swatch,
    make_subpalette,
    measure_tone,
    prepare_workspace,
    style_bible_block,
    tone_block,
)

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ITEMS_JSON = os.path.join(ROOT, "data", "items.json")
ICON_DIR = os.path.join(ROOT, "assets", "icons")
OUT_ROOT = os.path.join(ROOT, "assets", "raw", "llm", "items")
## 아이콘 규격 — 기존 24종이 전부 이 크기다(validate_submission.py icon 모드와 같은 값).
ICON_PX = 96
## 스타일 앵커로 붙일 기존 아이콘 — 종류가 겹치면 그것을 우선한다.
ANCHOR_FALLBACK = ["ITEM_MEDICINE.png", "ITEM_BOOK.png", "ITEM_KEY.png"]

## 내부 kind → 사람이 읽는 분류·그리기 지침. 화면 표기는 게임이 번역표로 하고,
## 여기서는 **그림 LLM에게 줄 설명**이라 한국어로 직접 쓴다.
KIND_GUIDE = {
    "weapon": ("무기", "손에 드는 물건. 날·자루·손잡이가 분명히 보이게. 공격력이 높을수록 크고 험하게"),
    "armor": ("방어구", "몸에 걸치는 물건. 착용 형태(가운·장갑·헬멧 등)를 정면에서 알아보게"),
    "consumable": ("소모품", "약·음료·식품. 용기 형태와 내용물 색으로 효과를 짐작하게"),
    "magic_substitute": ("시약", "실험실 시약병. 라벨·액체 색으로 구분되게(화공과 소품 톤)"),
    "material": ("재료", "가공 전 부품·소재. 쓰임을 짐작할 수 있는 형태"),
    "quest": ("중요 물품", "서사에 쓰이는 물건. 한눈에 '평범한 소모품이 아니다'가 보이게"),
    "money": ("돈", "동전·지폐 뭉치"),
}

PROMPT_TEMPLATE = """# {name_ko}(`{item_id}`) 아이템 아이콘 생성 의뢰

{style_bible}

## 역할
너는 1995년 한국 공대 배경 캠퍼스 호러 JRPG의 아이템 아이콘 도트 디자이너다.
게임 안 인벤토리·상점·단축 슬롯에서 **같은 그림이 그대로 쓰인다**.

## 그릴 것
- 이름: **{name_ko}**
- 분류: {kind_ko} — {kind_hint}
{stat_lines}

## 입력 (첨부)
1. `style_ref_1.png` · `style_ref_2.png` · `style_ref_3.png` — **이미 게임에 들어간 기존 아이콘**.
   선 굵기·음영 단계·여백 비율의 기준이다. 새 아이콘이 이것들과 나란히 놓였을 때
   따로 놀면 반려된다.
2. `canvas_template.png` — **정확한 {icon_px}×{icon_px} 캔버스**(청록 선 = 비워 둘 안전 여백).
   가능하면 이 이미지를 열어 그 위에 그린다. 선은 납품물에 남기지 않는다
3. `subpalette.png` — **기존 아이콘에서 실제로 많이 쓰인 색**. 아래 hex를 중심으로 고른다:
   `{subpalette_hex}`
4. `../palette_swatch.png` — 마스터 팔레트 전체(위 색으로 부족할 때만)

**첨부 그림이 규칙 문장보다 우선한다.** 세 장의 공통점(굵은 외곽선, 2~3단 음영,
채도 높은 원색, 상하좌우 여백)을 그대로 따른다.

## 출력 규격 (위반 시 반려)
- **{icon_px}×{icon_px} PNG 정확히 1장.** 다른 크기·여러 장·시트 금지
- 배경은 **완전 투명** 또는 마젠타 `#FF00FF` 단색. 그림자·후광을 배경에 깔지 않는다
- 물건 하나만. 손·인물·문자·설명 텍스트·테두리 액자 금지
- 캔버스 가장자리 6px는 비운다(작게 축소돼도 형태가 뭉개지지 않게)
- 반투명 픽셀 최소화 — 안티에일리어싱은 외곽 1px까지만
- 팔레트: 첨부 스왑치 안의 색을 우선한다

{tone_block}

{negative_rules}

{self_check}

## 파일명
`{item_id}_v1.png` 로 저장한다(재납품은 v2, v3…). 대소문자·언더바까지 정확히 일치해야
심사 보드가 원본 의뢰문을 찾아 붙인다.
"""


def load_items() -> list:
    return json.load(io.open(ITEMS_JSON, encoding="utf-8"))["items"]


def existing_icons() -> list:
    if not os.path.isdir(ICON_DIR):
        return []
    return sorted(f for f in os.listdir(ICON_DIR) if f.endswith(".png"))


def pick_anchors(items: list, kind: str, icons: list) -> list:
    """같은 kind의 기존 아이콘을 우선 앵커로. 없으면 범용 3종."""
    by_id = {i["id"]: i for i in items}
    same_kind = [f for f in icons if by_id.get(f[:-4], {}).get("kind") == kind]
    picked = same_kind[:3]
    for fallback in ANCHOR_FALLBACK:
        if len(picked) >= 3:
            break
        if fallback in icons and fallback not in picked:
            picked.append(fallback)
    for f in icons:
        if len(picked) >= 3:
            break
        if f not in picked:
            picked.append(f)
    return picked


def stat_lines(item: dict) -> str:
    """수치가 있으면 프롬프트에 적는다 — 강한 무기가 커 보여야 한다."""
    out = []
    if "ap" in item:
        out.append(f"- 공격력 {int(item['ap'])}")
    if "dp" in item:
        out.append(f"- 방어력 {int(item['dp'])}")
    if "hp_restore" in item:
        out.append(f"- HP {int(item['hp_restore'])} 회복")
    if "element" in item and str(item["element"]) != "physical":
        out.append(f"- 속성: {item['element']}")
    if item.get("_hint"):
        out.append(f"- 용도 메모: {item['_hint']}")
    if "price" in item:
        out.append(f"- 상점가 {int(item['price'])}온")
    return "\n".join(out) if out else "- (수치 없음 — 이름과 분류로 판단)"


def export_one(item: dict, items: list, icons: list) -> None:
    item_id = item["id"]
    kind = str(item.get("kind", ""))
    kind_ko, kind_hint = KIND_GUIDE.get(kind, (kind or "기타", "이름에 맞는 형태로"))
    out_dir = os.path.join(OUT_ROOT, item_id)
    os.makedirs(out_dir, exist_ok=True)

    for n, src_name in enumerate(pick_anchors(items, kind, icons), start=1):
        shutil.copyfile(
            os.path.join(ICON_DIR, src_name), os.path.join(out_dir, f"style_ref_{n}.png")
        )

    anchors = [os.path.join(ICON_DIR, f) for f in pick_anchors(items, kind, icons)]
    all_icons = [os.path.join(ICON_DIR, f) for f in icons]
    make_grid_template(os.path.join(out_dir, "canvas_template.png"), 1, 1, ICON_PX, [])
    sub_hex = make_subpalette(
        dominant_colors(anchors or all_icons, 12), os.path.join(out_dir, "subpalette.png")
    )
    prompt = PROMPT_TEMPLATE.format(
        style_bible=style_bible_block(),
        subpalette_hex=sub_hex,
        tone_block=tone_block(measure_tone(all_icons), "게임에 이미 들어간 아이템 아이콘"),
        negative_rules=NEGATIVE_RULES,
        self_check=SELF_CHECK,
        item_id=item_id,
        name_ko=item.get("name_ko", item_id),
        kind_ko=kind_ko,
        kind_hint=kind_hint,
        stat_lines=stat_lines(item),
        icon_px=ICON_PX,
    )
    with io.open(os.path.join(out_dir, "prompt.md"), "w", encoding="utf-8") as f:
        f.write(prompt)
    print(f"{item_id}: {kind_ko} — prompt.md + 앵커 3장")


def main() -> None:
    os.makedirs(OUT_ROOT, exist_ok=True)
    prepare_workspace()
    make_palette_swatch(os.path.join(OUT_ROOT, "palette_swatch.png"))
    items = load_items()
    icons = existing_icons()
    have = {f[:-4] for f in icons}
    # id를 명시하면 **이미 아이콘이 있어도** 패키지를 만든다 — 마음에 안 드는 것만
    # 골라 다시 의뢰하는 흐름(전체 적용 후 부분 수정)을 위해서다.
    targets = {a for a in sys.argv[1:] if not a.startswith("--")}
    if targets:
        todo = [i for i in items if i["id"] in targets]
    else:
        todo = [i for i in items if i["id"] not in have]
    for item in todo:
        export_one(item, items, icons)
    print(f"done -> {OUT_ROOT} ({len(todo)}종 / 전체 {len(items)}종 중 아이콘 보유 {len(have)}종)")


if __name__ == "__main__":
    main()
