#!/usr/bin/env python3
"""에이전트 납품 품질 계량 분석 — 리드로우 vs 단순 업스케일 판별.

지표:
  - colors/cell        프레임·타일별 고유색 수 (진본 도트는 다색)
  - flat_cells         단일색으로 채워진 셀 비율
  - block_uniformity   4x4 블록이 내부 균일한 비율 (업스케일본≈100%)
  - edge_density       인접 픽셀 대비 변화 수 (엣지 적으면 단순 도형)
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from png_probe import decode_png  # noqa: E402


def analyze(path: str, cell: int, label: str) -> None:
    w, h, ch, px = decode_png(path)
    cols, rows = w // cell, h // cell
    color_counts = []
    flat = 0
    blk_uniform_total = 0
    blk_total = 0
    edges = 0

    def pix(x: int, y: int):
        i = (y * w + x) * ch
        return tuple(px[i:i + ch])

    for cy in range(rows):
        for cx in range(cols):
            x0, y0 = cx * cell, cy * cell
            colors = set()
            transparent = True
            for y in range(y0, y0 + cell):
                for x in range(x0, x0 + cell):
                    r, g, b, a = pix(x, y)[:4]
                    if a > 0:
                        transparent = False
                        colors.add((r, g, b))
                    if 0 < x - x0 < cell - 1:
                        pr, pg, pb, _ = pix(x - 1, y)[:4]
                        if a > 0 and max(abs(r - pr), abs(g - pg), abs(b - pb)) > 40:
                            edges += 1
            if transparent:
                continue
            color_counts.append(len(colors))
            if len(colors) <= 1:
                flat += 1
            # 4x4 블록 균일도
            for by in range(y0, y0 + cell, 4):
                for bx in range(x0, x0 + cell, 4):
                    blk_total += 1
                    first = pix(bx, by)
                    uniform = all(pix(bx + dx, by + dy) == first
                                  for dx in range(4) for dy in range(4))
                    blk_uniform_total += uniform

    n_cells = len(color_counts) or 1
    avg_colors = sum(color_counts) / n_cells
    print(f"--- {label} ({w}x{h}, cell={cell}, {n_cells} cells) ---")
    print(f"  colors/cell avg      : {avg_colors:.1f}   (권장 ≥8)")
    print(f"  단일색 flat cells     : {flat}/{n_cells}")
    print(f"  4x4 블록 균일률       : {blk_uniform_total}/{blk_total} = {100*blk_uniform_total/max(1,blk_total):.0f}%  (업스케일 의심 ≥95%)")
    print(f"  edge_density         : {edges/max(1,w*h//cell//cell):.1f}/cell  (권장 ≥20)")


if __name__ == "__main__":
    base = Path(r"D:\Project\Etc\Old\부싯돌시절\remakes\sidol_godot\assets\raw\sprites")
    analyze(str(base / "tileset_campus" / "tileset_v1.png"), 32, "tileset_campus v1")
    analyze(str(base / "player_sidol" / "sheet_v1.png"), 64, "player_sidol v1")
