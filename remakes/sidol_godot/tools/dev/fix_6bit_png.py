#!/usr/bin/env python3
"""6bit VGA 값을 8bit로 스케일 안 한 에이전트 PNG 일괄 교정 (RGB ×4, 알파 유지)."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, r"D:\Project\Etc\Old\부싯돌시절\_shared\src")

from png_probe import decode_png  # noqa: E402
from dosport.formats.png_write import write_png  # noqa: E402


def fix(path: str) -> None:
    w, h, ch, px = decode_png(path)
    if ch != 4:
        print(f"skip(RGBA 아님): {path}")
        return
    mx = max(px[i] for i in range(0, len(px), 4)) , max(px[i+1] for i in range(0, len(px), 4)), max(px[i+2] for i in range(0, len(px), 4))
    if max(mx) > 63:
        print(f"skip(이미 8bit): {path} max={mx}")
        return
    fixed = bytearray(len(px))
    for i in range(0, len(px), 4):
        fixed[i]     = min(255, px[i] * 4)
        fixed[i + 1] = min(255, px[i + 1] * 4)
        fixed[i + 2] = min(255, px[i + 2] * 4)
        fixed[i + 3] = px[i + 3]
    write_png(path, w, h, bytes(fixed))
    print(f"fixed: {path}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        fix(p)
