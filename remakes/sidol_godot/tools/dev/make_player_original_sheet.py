#!/usr/bin/env python3
"""원작 I.SPR 주인공 프레임(0~7) → 게임용 시트 생성.

원작 인덱스 매핑(GOODITEM.C move_you 기준):
  DOWN={0,1} LEFT={2,3} RIGHT={4,5} UP={6,7}
산출: assets/sprites/player_original.png (+ .json)
레이아웃(64px 셀 × 2열):
  row0 walk_down / row1 walk_up / row2 walk_left / row3 walk_right
  row4 idle_down (정지 프레임)
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHARED_SRC = ROOT.parent.parent / "_shared" / "src"
sys.path.insert(0, str(SHARED_SRC))

from spr_extract import parse_spr  # noqa: E402
from dosport.formats.png_write import fill_rect, write_png  # noqa: E402

ORIGINALS = ROOT.parent.parent / "originals" / "1995_sidol_bsd_dos"
CELL = 64
W, H = CELL * 2, CELL * 5


def main() -> int:
    _, frames = parse_spr((ORIGINALS / "I.SPR").read_bytes())
    if len(frames) < 8:
        raise ValueError(f"I.SPR 프레임 부족: {len(frames)}")

    buf = bytearray(W * H * 4)

    def blit(row: int, col: int, src_idx: int) -> None:
        w, h, rgba = frames[src_idx]
        ox = max(0, (CELL - w) // 2)
        oy = max(0, CELL - h)
        gx, gy = col * CELL, row * CELL
        for y in range(h):
            dy = gy + oy + y
            if not (0 <= dy < H):
                continue
            for x in range(w):
                dx = gx + ox + x
                if not (0 <= dx < W):
                    continue
                si = (y * w + x) * 4
                if rgba[si + 3] == 0:
                    continue
                di = (dy * W + dx) * 4
                buf[di:di + 4] = rgba[si:si + 4]

    rows = [
        ("walk_down", 0, [0, 1]),
        ("walk_up", 1, [6, 7]),
        ("walk_left", 2, [2, 3]),
        ("walk_right", 3, [4, 5]),
    ]
    for _, row, srcs in rows:
        for c, s in enumerate(srcs):
            blit(row, c, s)
    blit(4, 0, 0)   # idle_down: 정지 프레임
    blit(4, 1, 0)

    out_png = ROOT / "assets" / "sprites" / "player_original.png"
    write_png(out_png, W, H, bytes(buf))
    meta = {
        "schema_version": 1,
        "source": "I.SPR frames 0-7 (원작 도트)",
        "cell": CELL,
        "cols": 2,
        "animations": {
            "walk_down":  {"row": 0, "frames": 2, "fps": 7, "loop": True},
            "walk_up":    {"row": 1, "frames": 2, "fps": 7, "loop": True},
            "walk_left":  {"row": 2, "frames": 2, "fps": 7, "loop": True},
            "walk_right": {"row": 3, "frames": 2, "fps": 7, "loop": True},
            "idle_down":  {"row": 4, "frames": 2, "fps": 1, "loop": True},
        },
    }
    (ROOT / "assets" / "sprites" / "player_original.json").write_text(
        json.dumps(meta, indent=1), encoding="utf-8")
    print(f"player original sheet -> {out_png.name} ({W}x{H})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
