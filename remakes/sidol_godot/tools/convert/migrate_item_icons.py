"""원작 아이템 아이콘 일괄 이관 — ITEM.SPR → res://assets/icons/<item_id>.png.

data/items.json의 legacy_ref(원작 ATT 150+ ↔ 신규 id, "영구 유지" 매핑)를 읽어
originals_ref/bmp_spr/item/frame_(att-150).bmp 를 배경 제거 후 4배 nearest 베이크
(24→96px)해 아이콘으로 출력한다. 현행 items.json에 없는 id는 스킵(죽은 에셋 방지).

조회는 ItemIcons.texture() 단일 창구 — 부재 시 기존 색상+글리프 폴백이 그대로
동작한다(UI 전파 없이 아이콘 착지 반영).

실행: python tools/convert/migrate_item_icons.py [item_id ...]
"""
from __future__ import annotations
import io
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import extract_sprites as es  # noqa: E402  (remove_bg_np 재사용)

ROOT = es.ROOT
ITEM_REF = os.path.join(es.REF, "item")
ITEMS_JSON = os.path.join(ROOT, "data", "items.json")
OUT_DIR = os.path.join(ROOT, "assets", "icons")
BAKE = 4  # 원작 24px 도트 → 96px (스프라이트 시트와 동일 레시피)
ATT_BASE = 150  # 원작 상자/인벤 ATT 오프셋 — legacy_ref 키와 동일


def main() -> None:
    data = json.load(io.open(ITEMS_JSON, encoding="utf-8"))
    known_ids = {it["id"] for it in data["items"]}
    legacy: dict[str, str] = {k: v for k, v in data["legacy_ref"].items() if k.isdigit()}
    targets = sys.argv[1:]
    os.makedirs(OUT_DIR, exist_ok=True)

    done, skipped = 0, 0
    for att_str, item_id in sorted(legacy.items(), key=lambda kv: int(kv[0])):
        if item_id not in known_ids:
            skipped += 1
            continue
        if targets and item_id not in targets:
            continue
        frame_idx = int(att_str) - ATT_BASE
        src = os.path.join(ITEM_REF, f"frame_{frame_idx:03d}.bmp")
        if not os.path.exists(src):
            print(f"!! {item_id}: 원본 프레임 부재({src}) — 스킵")
            continue
        img = es.remove_bg_np(Image.open(src))
        w, h = img.width * BAKE, img.height * BAKE
        img.resize((w, h), Image.NEAREST).save(os.path.join(OUT_DIR, f"{item_id}.png"))
        done += 1
    print(f"done -> {OUT_DIR} ({done} icons, legacy 미착용 {skipped} 스킵)")


if __name__ == "__main__":
    main()
