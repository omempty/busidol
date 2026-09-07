"""원작 아이템 아이콘 일괄 이관 — ITEM.SPR → res://assets/icons/<item_id>.png.

data/items.json의 legacy_ref(원작 ATT 150+ ↔ 신규 id, "영구 유지" 매핑)를 읽어
원작 ITEM.SPR의 프레임 (att-150)을 4배 nearest 베이크(24→96px)해 아이콘으로
출력한다. 현행 items.json에 없는 id는 스킵(죽은 에셋 방지).

**알파의 유일한 근거는 팔레트 인덱스 0이다.** 예전에는 알파 없는 중간물
`originals_ref/bmp_spr/item/frame_*.bmp`를 `extract_sprites.remove_bg_np`
(테두리 flood-fill)로 지웠는데, 원작 팔레트에는 RGB(0,0,0)인 인덱스가 9개라
(투명 키 0 + 외곽선 224~231) RGB만으로는 구별이 불가능했다. 2026-09-07 실측:
아이콘 35종에서 **외곽선 36,939px가 사라지고 배경 9,465px가 검게 남아** 있었다.
자세한 근거는 tools/convert/migrate_original_sheets.py 상단 참조.

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
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.normpath(os.path.join(ROOT, "..", "..", "_shared", "src")))
sys.path.insert(0, os.path.join(ROOT, "tools", "dev"))
from spr_extract import parse_spr  # noqa: E402  (알파의 유일한 근거 = 팔레트 인덱스 0)

ORIGINALS = os.path.normpath(os.path.join(ROOT, "..", "..", "originals", "1995_sidol_bsd_dos"))
ITEMS_JSON = os.path.join(ROOT, "data", "items.json")
OUT_DIR = os.path.join(ROOT, "assets", "icons")
BAKE = 4  # 원작 24px 도트 → 96px (스프라이트 시트와 동일 레시피)
ATT_BASE = 150  # 원작 상자/인벤 ATT 오프셋 — legacy_ref 키와 동일

_FRAMES: list | None = None


def item_frames() -> list:
    """ITEM.SPR 전 프레임 — 팔레트 인덱스 0만 alpha 0."""
    global _FRAMES
    if _FRAMES is None:
        path = os.path.join(ORIGINALS, "ITEM.SPR")
        if not os.path.exists(path):
            raise SystemExit(f"원본 없음: {path} — 이 도구는 원작 SPR만 읽는다")
        with open(path, "rb") as fh:
            _FRAMES = parse_spr(fh.read())[1]
    return _FRAMES


def icon_targets() -> dict[str, int]:
    """item_id → ITEM.SPR 프레임 인덱스 (현행 items.json에 살아 있는 것만)."""
    data = json.load(io.open(ITEMS_JSON, encoding="utf-8"))
    known = {it["id"] for it in data["items"]}
    out: dict[str, int] = {}
    for att, iid in sorted(data["legacy_ref"].items(), key=lambda kv: kv[0]):
        if not att.isdigit() or iid not in known:
            continue
        idx = int(att) - ATT_BASE
        if 0 <= idx < len(item_frames()):
            out[iid] = idx
    return out


def build_icon_image(frame_idx: int) -> Image.Image:
    """아이콘 1장을 메모리로만 굽는다 — 관문(tools/dev/spr_alpha_check.py)이 이걸 쓴다."""
    w, h, rgba = item_frames()[frame_idx]
    img = Image.frombytes("RGBA", (w, h), rgba)
    return img.resize((w * BAKE, h * BAKE), Image.NEAREST)


def main() -> None:
    only = set(sys.argv[1:])
    os.makedirs(OUT_DIR, exist_ok=True)
    plan = icon_targets()
    done = 0
    for item_id, frame_idx in plan.items():
        if only and item_id not in only:
            continue
        build_icon_image(frame_idx).save(os.path.join(OUT_DIR, f"{item_id}.png"))
        done += 1
    print(f"done -> {OUT_DIR} ({done} icons / 착용 가능 {len(plan)}종)")


if __name__ == "__main__":
    main()
