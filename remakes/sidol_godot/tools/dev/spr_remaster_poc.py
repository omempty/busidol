#!/usr/bin/env python3
"""PoC: 원작 TILE.SPR/I.SPR → B안 해상도(32px) 네어리스트 리마스터.

원작 느낌 100% 유지 + 토큰 0. 산출은 originals_ref/remastered/ 아래 참조용.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHARED_SRC = ROOT.parent.parent / "_shared" / "src"
sys.path.insert(0, str(SHARED_SRC))

from dosport.formats.png_write import fill_rect, write_png  # noqa: E402
from spr_extract import parse_spr  # noqa: E402

TILE_PX = 32


def remaster_nearest(w: int, h: int, rgba: bytes, target: int) -> bytes:
    """정사각형 가정: w==h==source → target 크기 글로벌 nearest 재샘플."""
    out = bytearray(target * target * 4)
    for y in range(target):
        sy = min(h - 1, y * h // target)
        for x in range(target):
            sx = min(w - 1, x * w // target)
            si = (sy * w + sx) * 4
            di = (y * target + x) * 4
            out[di:di + 4] = rgba[si:si + 4]
    return bytes(out)


def sheet(frames: list[tuple[int, int, bytes]], target: int, cols: int, out_png: Path) -> None:
    rows = (len(frames) + cols - 1) // cols
    buf = bytearray(cols * target * rows * target * 4)
    for i, (w, h, rgba) in enumerate(frames):
        gx, gy = (i % cols) * target, (i // cols) * target
        rem = remaster_nearest(w, h, rgba, target)
        for yy in range(target):
            di = ((gy + yy) * (cols * target) + gx) * 4
            si = yy * target * 4
            buf[di:di + target * 4] = rem[si:si + target * 4]
    write_png(out_png, cols * target, rows * target, bytes(buf))
    print(f"wrote {out_png.relative_to(ROOT)} ({cols*target}x{rows*target}, {len(frames)} frames)")


def main() -> int:
    out_dir = ROOT / "assets" / "originals_ref" / "remastered"
    out_dir.mkdir(parents=True, exist_ok=True)

    originals = ROOT.parent.parent / "originals" / "1995_sidol_bsd_dos"
    _, tiles = parse_spr((originals / "TILE.SPR").read_bytes())
    sheet(tiles, TILE_PX, 16, out_dir / "tile_32.png")

    _, ichars = parse_spr((originals / "I.SPR").read_bytes())
    sheet(ichars, 64, 8, out_dir / "i_field_64.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
