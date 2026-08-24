#!/usr/bin/env python3
"""OBJ.SPR(173프레임) → 32px 셀 오브젝트 아틀라스 + 메타 생성 (게임 에셋).

각 오브젝트를 종횡비 유지 스케일로 32x32 셀 중앙 배치.
산출: assets/sprites/obj_original_32.png + .json
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
CELL = 32


def main() -> int:
    _, frames = parse_spr((ORIGINALS / "OBJ.SPR").read_bytes())
    n = len(frames)
    cols = 16
    rows = (n + cols - 1) // cols
    W, H = cols * CELL, rows * CELL
    buf = bytearray(W * H * 4)
    meta: dict[str, dict] = {}
    for i, (w, h, rgba) in enumerate(frames):
        scale = min(CELL / w, CELL / h)
        sw, sh = max(1, int(w * scale)), max(1, int(h * scale))
        ox = (CELL - sw) // 2
        oy = (CELL - sh) // 2
        gx, gy = (i % cols) * CELL, (i // cols) * CELL
        # 중앙 배치 + nearest 재샘플
        for y in range(sh):
            sy = min(h - 1, int(y / scale))
            for x in range(sw):
                sx = min(w - 1, int(x / scale))
                si = (sy * w + sx) * 4
                if rgba[si + 3] == 0:
                    continue
                di = ((gy + oy + y) * W + gx + ox + x) * 4
                buf[di:di + 4] = rgba[si:si + 4]
        meta[str(i)] = {"col": i % cols, "row": i // cols}

    out_png = ROOT / "assets" / "sprites" / "obj_original_32.png"
    write_png(out_png, W, H, bytes(buf))
    meta_payload = {"schema_version": 1, "cell": CELL, "cols": cols, "objects": meta}
    (ROOT / "assets" / "sprites" / "obj_original_32.json").write_text(
        json.dumps(meta_payload, indent=1), encoding="utf-8")
    print(f"obj atlas: {n} objects -> {out_png.name} ({W}x{H})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
