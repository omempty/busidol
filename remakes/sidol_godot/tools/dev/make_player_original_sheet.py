#!/usr/bin/env python3
"""원작 I.SPR 주인공 프레임(0~7) → 게임용 시트 생성.

원작 인덱스 매핑(GOODITEM.C move_you 기준):
  DOWN={0,1} LEFT={2,3} RIGHT={4,5} UP={6,7}
산출: assets/sprites/player_original.png (+ .json)
레이아웃(표준 셀 128px × 2열, 원작 도트 4배 nearest 베이크):
  row0 walk_down / row1 walk_up / row2 walk_left / row3 walk_right
  row4 idle_down (정지 프레임)

셀 128·아트 96px는 assets/spec/sprites/_standard.md §1 이관 경로.
scale 메타(⅔)로 실효 64px = 타일 32px 대비 원작 비율(2.0타일) 복원.
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
SCALE = 4                      # nearest 정수배만 — 도트 순도 유지
CELL = 128                     # 표준 셀 (24×4=96px 아트 + 발바닥 하단중앙 패딩)
W, H = CELL * 2, CELL * 5


def main() -> int:
    _, frames = parse_spr((ORIGINALS / "I.SPR").read_bytes())
    if len(frames) < 8:
        raise ValueError(f"I.SPR 프레임 부족: {len(frames)}")

    buf = bytearray(W * H * 4)

    def blit(row: int, col: int, src_idx: int) -> None:
        w, h, rgba = frames[src_idx]
        ox = max(0, (CELL - w * SCALE) // 2)
        oy = max(0, CELL - h * SCALE)
        gx, gy = col * CELL, row * CELL
        for y in range(h):
            dy0 = gy + oy + y * SCALE
            if not (0 <= dy0 < H):
                continue
            for x in range(w):
                si = (y * w + x) * 4
                if rgba[si + 3] == 0:
                    continue
                px = bytes(rgba[si:si + 4])
                dx0 = gx + ox + x * SCALE
                for by_ in range(SCALE):
                    dy = dy0 + by_
                    if not (0 <= dy < H):
                        continue
                    row_off = (dy * W + dx0) * 4
                    for bx_ in range(SCALE):
                        dx = dx0 + bx_
                        if not (0 <= dx < W):
                            continue
                        di = row_off + bx_ * 4
                        buf[di:di + 4] = px

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
        "schema_version": 2,
        "source": "I.SPR frames 0-7 (원작 도트 24×24, 4배 nearest 베이크)",
        "cell": CELL,
        "cell_w": CELL,
        "cell_h": CELL,
        "cols": 2,
        # 실효 높이 = 96px × ⅔ = 64px = 타일(32px) 2.0배 — 원작 비율 복원
        "scale": round(64 / (24 * SCALE), 4),
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
