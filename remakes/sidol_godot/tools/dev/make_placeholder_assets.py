#!/usr/bin/env python3
"""플레이스홀더 에셋 생성기 (Phase 1 — AI 아트 확보 전 임시 비주얼).

입력: data/maps/f1.json (사용 타일/오브젝트 ID 수집)
산출:
  assets/sprites/tiles_f1_placeholder.png + .json   지면/오브젝트 스트립 아틀라스
  assets/sprites/player_placeholder.png   + .json    48x48 캐릭터 시트(4방향+idle)

색은 ID 기반 결정적 해시 → 재실행해도 동일. R1 선제 조치(리스크 문서) 참조.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHARED_SRC = ROOT.parent.parent / "_shared" / "src"
sys.path.insert(0, str(SHARED_SRC))

from dosport.formats.png_write import fill_rect, write_png  # noqa: E402

TILE_PX = 32   # G-ART B안 확정


def _load_palette() -> list[tuple[int, int, int, int]]:
    src = ROOT / "assets" / "palette_master.json"
    if not src.exists():
        raise SystemExit("palette_master.json 없음 — pal_extract.py 먼저 실행")
    data = json.loads(src.read_text(encoding="utf-8"))
    out = []
    for hexstr in data["colors"]:
        r = int(hexstr[1:3], 16)
        g = int(hexstr[3:5], 16)
        b = int(hexstr[5:7], 16)
        out.append((r, g, b, 255))
    return out

_PALETTE = None


def id_color(i: int, alpha: int = 255) -> tuple[int, int, int, int]:
    """진짜 VGA 팔레트에서 결정적 선택(원본 느낌) — 임의 RGB 대체."""
    global _PALETTE
    if _PALETTE is None:
        _PALETTE = _load_palette()
    c = _PALETTE[(i * 37 + 13) % len(_PALETTE)]
    return (c[0], c[1], c[2], alpha)


def darken(c: tuple[int, int, int, int], k: float) -> tuple[int, int, int, int]:
    return (int(c[0] * k), int(c[1] * k), int(c[2] * k), c[3])


def draw_tile(buf: bytearray, img_w: int, ox: int, oy: int, size: int, base: tuple, checker: bool) -> None:
    for y in range(size):
        for x in range(size):
            border = x in (0, size - 1) or y in (0, size - 1)
            col = darken(base, 0.55) if border else base
            if not border and checker and ((x // 4 + y // 4) % 2 == 0):
                col = darken(base, 0.85)
            i = ((oy + y) * img_w + (ox + x)) * 4
            buf[i:i + 4] = bytes(col)


def gen_tiles() -> None:
    map_json = json.loads((ROOT / "data" / "maps" / "f1.json").read_text(encoding="utf-8"))
    ground_ids = sorted({v for row in map_json["layers"]["ground"] for v in row})
    object_ids = sorted({v for row in map_json["layers"]["object"] for v in row if v > 0})
    cols_g, cols_o = len(ground_ids), len(object_ids)
    width = max(cols_g, cols_o) * TILE_PX
    height = TILE_PX * 2
    buf = bytearray(width * height * 4)

    meta_g: dict[str, int] = {}
    meta_o: dict[str, int] = {}
    for col, tid in enumerate(ground_ids):
        draw_tile(buf, width, col * TILE_PX, 0, TILE_PX, id_color(tid), checker=True)
        meta_g[str(tid)] = col
    for col, oid in enumerate(object_ids):
        base = id_color(oid + 40)
        draw_tile(buf, width, col * TILE_PX, TILE_PX, TILE_PX, darken(base, 0.8), checker=False)
        # 오브젝트 느낌: 중앙 밝은 사각
        o = TILE_PX // 4
        fill_rect(buf, width, col * TILE_PX + o, TILE_PX + o, TILE_PX - 2 * o, TILE_PX - 2 * o, id_color(oid))
        meta_o[str(oid)] = col

    out_png = ROOT / "assets" / "sprites" / "tiles_f1_placeholder.png"
    write_png(out_png, width, height, bytes(buf))
    meta = {"cell": TILE_PX, "ground": meta_g, "object": meta_o,
            "ground_count": cols_g, "object_count": cols_o}
    out_json = ROOT / "assets" / "sprites" / "tiles_f1_placeholder.json"
    out_json.write_text(json.dumps(meta, indent=1), encoding="utf-8")
    print(f"tiles placeholder: {cols_g} ground + {cols_o} object -> {out_png.name} ({width}x{height})")


def gen_player() -> None:
    cell = 64          # G-ART B안: 캐릭터 프레임 64x64 (2x2 타일 점유)
    cols, rows = 4, 5  # rows: down/up/left/right walk + idle_down
    buf = bytearray(cell * cols * cell * rows * 4)

    def U(v: float) -> int:            # 48px 기준 좌표를 cell에 비례 변환
        return int(round(v * cell / 48))

    shirt = (58, 110, 165, 255)
    pants = (52, 62, 88, 255)
    skin = (222, 184, 148, 255)

    def px(x: int, y: int, w: int, h: int, c: tuple) -> None:
        fill_rect(buf, cell * cols, x, y, w, h, c)

    def frame(col: int, row: int, facing: str, step: int, bob: bool) -> None:
        bx, by = col * cell, row * cell
        px(bx + U(18 + (2 if step == 1 else 0)), by + U(36),
           U(5), U(10 - (2 if step != 0 else 0)), pants)
        px(bx + U(25 - (2 if step == -1 else 0)), by + U(36),
           U(5), U(10 - (2 if step != 0 else 0)), pants)
        px(bx + U(14), by + U(22 + (1 if bob else 0)), U(20), U(15), shirt)
        hy = by + U(6 + (1 if bob else 0))
        px(bx + U(16), hy, U(16), U(15), skin)
        px(bx + U(14), hy - U(2), U(20), U(4), (70, 45, 30, 255))
        if facing == "down":
            px(bx + U(19), hy + U(6), U(3), U(3), (30, 30, 40, 255))
            px(bx + U(26), hy + U(6), U(3), U(3), (30, 30, 40, 255))
        elif facing == "left":
            px(bx + U(17), hy + U(6), U(3), U(3), (30, 30, 40, 255))
        elif facing == "right":
            px(bx + U(28), hy + U(6), U(3), U(3), (30, 30, 40, 255))
        elif facing == "up":
            px(bx + U(14), hy - U(2), U(20), U(10), (70, 45, 30, 255))

    for f in range(4):
        s = (-1 if f == 1 else 1) if f % 2 else 0
        frame(f, 0, "down", s, bob=(f % 2 == 1))
        frame(f, 1, "up", s, bob=(f % 2 == 1))
        frame(f, 2, "left", s, bob=(f % 2 == 1))
        frame(f, 3, "right", s, bob=(f % 2 == 1))
    frame(0, 4, "down", 0, bob=False)
    frame(1, 4, "down", 0, bob=True)

    out_png = ROOT / "assets" / "sprites" / "player_placeholder.png"
    write_png(out_png, cell * cols, cell * rows, bytes(buf))
    meta = {
        "cell": cell,
        "animations": {
            "walk_down": {"row": 0, "frames": 4, "fps": 9, "loop": True},
            "walk_up": {"row": 1, "frames": 4, "fps": 9, "loop": True},
            "walk_left": {"row": 2, "frames": 4, "fps": 9, "loop": True},
            "walk_right": {"row": 3, "frames": 4, "fps": 9, "loop": True},
            "idle_down": {"row": 4, "frames": 2, "fps": 2, "loop": True},
        },
    }
    out_json = ROOT / "assets" / "sprites" / "player_placeholder.json"
    out_json.write_text(json.dumps(meta, indent=1), encoding="utf-8")
    print(f"player placeholder: {cell*cols}x{cell*rows} -> {out_png.name}")


if __name__ == "__main__":
    gen_tiles()
    gen_player()
