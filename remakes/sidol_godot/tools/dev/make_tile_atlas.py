# -*- coding: utf-8 -*-
"""리마스터 타일 아틀라스를 만든다 — 원본은 건드리지 않는다.

원본 `tiles_original_32.png`(16x7 = 112칸)를 **뱅크 4벌**로 세로로 쌓고,
다시 찍기로 한 타일만 뱅크마다 다른 변종으로 덮는다. 나머지 타일은 네 뱅크가
모두 원본과 같으므로, 렌더러는 어느 타일이든 좌표 해시로 뱅크를 골라도 된다.

왜 뱅크인가 — 맵 데이터(어느 칸에 어느 타일)는 **원본과 바이트 단위로 같아야**
한다(originals_check 관문). 그래서 자동 타일링으로 다시 깔 수는 없다. 대신 같은
타일 id에 여러 벌의 그림을 두고 렌더에서 골라, 32px 격자 반복을 눈에서 지운다.

원복: 이 스크립트가 만든 두 파일을 지우면 렌더러가 원본 아틀라스로 돌아간다.

실행: python tools/dev/make_tile_atlas.py [--preview]
"""
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tilegen as tg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "assets", "sprites", "tiles_original_32.png")
OUT = os.path.join(ROOT, "assets", "sprites", "tiles_remaster_32.png")
META = os.path.join(ROOT, "assets", "sprites", "tiles_remaster_32.json")

COLS = 16
ROWS = 7
BANKS = 4

# 다시 찍는 타일. 맵 78,000칸 중 이 12종이 92%다 — 여기만 바꿔도 화면 대부분이 바뀐다.
# kind: floor(바닥) / wall(벽 — 위를 밝게 아래를 어둡게 마감한다)
SPECS = {
    29: ("f1~f5 어두운 바닥", "floor", lambda s: tg.void_floor((26, 26, 30), s, 0.22)),
    8: ("f1·f2 체커 바닥", "floor",
        lambda s: tg.floor_checker((196, 196, 190), (150, 150, 146), s, grain=0.05)),
    10: ("f4 바닥", "floor", lambda s: tg.floor_grain((226, 190, 166), s, 0.13, (244, 214, 192))),
    28: ("회색 바닥", "floor", lambda s: tg.floor_grain((178, 178, 176), s, 0.12, (206, 206, 202))),
    0: ("벽돌 벽", "wall", lambda s: tg.brick((176, 96, 44), (96, 70, 52), s)),
    4: ("f3 바닥", "floor", lambda s: tg.floor_grain((132, 92, 168), s, 0.14, (170, 140, 200))),
    39: ("f0 지하 벽", "wall", lambda s: tg.floor_grain((58, 46, 24), s, 0.22, (86, 70, 36))),
    40: ("f0 지하 바닥", "floor", lambda s: tg.floor_grain((86, 66, 44), s, 0.20, (126, 96, 62))),
    2: ("벽 윗면(벽돌·가로)", "wall", lambda s: tg.brick((168, 92, 42), (88, 64, 48), s, 8, 32, False)),
    22: ("돌 바닥", "floor", lambda s: tg.cobble((150, 150, 148), (96, 96, 96), s, 12)),
    1: ("나무 벽", "wall", lambda s: tg.planks((150, 104, 58), (78, 54, 32), s)),
}


## 원작 무늬가 뜻을 가진 타일 — 세로 구조를 그대로 쓰고 톤만 손본다.
## id 9는 f5 바닥(4,131칸)이면서 f1에서는 **문**(ATT 9)이다. 세로줄이 문의 표현이라
## 지우면 벽에 뚫린 문이 사라진다(2026-08-29 첫 시안에서 실제로 사라졌다).
PROFILE_TILES = {9: ("f5 바닥 · 문 겸용", "floor", 0.42, 0.0)}


def _add_profile_tiles(src):
    for tid, (name, kind, sat, lift) in PROFILE_TILES.items():
        tile = src.crop(
            ((tid % COLS) * 32, (tid // COLS) * 32, (tid % COLS) * 32 + 32, (tid // COLS) * 32 + 32)
        ).convert("RGB")
        cols = []
        for x in range(32):
            acc = [0, 0, 0]
            for y in range(32):
                px = tile.getpixel((x, y))
                for i in range(3):
                    acc[i] += px[i]
            cols.append(tg.desaturate(tuple(c // 32 for c in acc), sat, lift))
        SPECS[tid] = (name, kind, lambda s, c=cols: tg.from_column_profile(c, s))


def to_image(px):
    im = Image.new("RGBA", (tg.SIZE, tg.SIZE))
    im.putdata([px[y][x] + (255,) for y in range(tg.SIZE) for x in range(tg.SIZE)])
    return im


def build():
    src = Image.open(SRC).convert("RGBA")
    _add_profile_tiles(src)
    out = Image.new("RGBA", (COLS * 32, ROWS * 32 * BANKS))
    for b in range(BANKS):
        out.paste(src, (0, b * ROWS * 32))
    for tid, (_name, kind, fn) in SPECS.items():
        variants = [fn(9000 + tid * 37 + k * 101) for k in range(BANKS)]
        variants = tg.normalize(variants)
        if kind == "wall":
            variants = [tg.wall_shade(v) for v in variants]
        for b, v in enumerate(variants):
            out.paste(to_image(v), ((tid % COLS) * 32, (tid // COLS + b * ROWS) * 32))
    out.save(OUT)
    meta = {
        "_comment": (
            "리마스터 타일 아틀라스 — 원본 16x7 격자를 뱅크 %d벌로 세로로 쌓은 것. "
            "타일 id t의 뱅크 b는 (t%%16, t/16 + b*%d) 칸에 있다. variant_ids만 뱅크마다 "
            "그림이 다르고 나머지는 네 뱅크가 원본과 동일하다 — 렌더러는 어느 id든 좌표 "
            "해시로 뱅크를 골라도 안전하다. 생성기: tools/dev/make_tile_atlas.py. "
            "이 파일과 png를 지우면 렌더러가 tiles_original_32.png로 돌아간다."
        )
        % (BANKS, ROWS),
        "cols": COLS,
        "rows_per_bank": ROWS,
        "banks": BANKS,
        "variant_ids": sorted(SPECS),
        "names": {str(k): SPECS[k][0] for k in sorted(SPECS)},
    }
    with open(META, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    print("[make_tile_atlas] %s %dx%d / 뱅크 %d / 다시 찍은 타일 %d종"
          % (os.path.basename(OUT), out.width, out.height, BANKS, len(SPECS)))


if __name__ == "__main__":
    build()
