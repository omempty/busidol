#!/usr/bin/env python3
"""바닥 타일 현대화 리터치 — tiles_remaster_32.png의 층 바닥 변종을 덧손질한다.

왜 스크립트인가: 아틀라스는 tools/dev/make_tile_atlas.py가 재생성하므로 손손질은
날아간다. 이 스크립트를 마지막에 다시 돌리면 복원된다. 원본 복구 = git checkout.
사용: python tools/dev/retouch_floor_tiles.py [--check]

기법(이음매 대책): 32px 셀이 바둑판 반복이라 방사형 얼룩은 이음매가 터진다.
그래서 주기가 셀에 들어가는 것만 쓴다 — 탈채도(전체)·해시 그레인(1px)·2px/8px
체커(명도 ±). 전부 주기 32px 이하라 이음매가 없다.
"""
from __future__ import annotations

import colorsys
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PNG = ROOT / "assets" / "sprites" / "tiles_remaster_32.png"
CELL = 32
BANKS = 4
BANK_ROWS = 7

# 타일 id: (hue 목표 or None, 채도 목표 or None, 그레인, 명도 배율)
# hue/sat 목표가 있으면 그쪽으로 당기고(None이면 탈채도만), 명도는 곱한다.
# 4 = F3 전용 → 세이지(화공). 9 = F5 사실상 전용(F1/F2/F3/F4 합 1%) → 슬레이트(전산실).
# 10 = F4+F5 공용이라 중립 유지(질감만). 22 = F3 위주 돌바닥 → 쿨그레이 정리.
TILES = {
    4: (0.33, 0.16, 7, 1.02),
    9: (0.58, 0.14, 6, 0.98),
    10: (None, None, 6, 1.0),
    22: (0.58, 0.08, 6, 1.0),
}
DESAT_ONLY = {4: 0.0, 9: 0.0, 10: 0.12, 22: 0.25}

## 전역 톤 — 아틀라스 전체를 음침하게. 2026-09-11 유저 지적("타일이 전반적으로 밝다").
## 밝기 곱·채도 곱·냉색 가산. 소품(obj 아틀라스)은 별개 파일이라 여기 영향 없음
## (소품 명암·톤다운은 다음 세션 — 다중 타일이라 신중 처리 필요).
GLOBAL_LUM = 0.82
GLOBAL_SAT = 0.85
GLOBAL_COOL = 4.0


def global_tone(im: Image.Image) -> Image.Image:
    work = im.convert("RGBA")
    px = work.load()
    for y in range(work.height):
        for x in range(work.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            rr, gg, bb = r / 255.0, g / 255.0, b / 255.0
            hh, ll, ss = colorsys.rgb_to_hls(rr, gg, bb)
            rr2, gg2, bb2 = colorsys.hls_to_rgb(hh, ll * GLOBAL_LUM, min(1.0, ss * GLOBAL_SAT))
            px[x, y] = (
                min(255, max(0, int(rr2 * 255))),
                min(255, max(0, int(gg2 * 255 - GLOBAL_COOL * 0.5))),
                min(255, max(0, int(bb2 * 255 + GLOBAL_COOL))),
                a,
            )
    return work


def hash01(x: int, y: int, seed: int) -> float:
    h = (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
    h ^= h >> 13
    h = (h * 0x5BD1E995) & 0xFFFFFFFF
    h ^= h >> 15
    return (h & 0xFFFF) / 65535.0


def retouch(
    cell: Image.Image,
    seed: int,
    hue: float | None,
    sat: float | None,
    grain: int,
    lum: float,
    desat_only: float,
) -> Image.Image:
    # convert()는 복사본을 내놓는다 — 픽셀은 그 복사본에서 고치고 그것을 반환해야 한다.
    work: Image.Image = cell.convert("RGB")
    px = work.load()
    w, h = work.size
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            rr, gg, bb = r / 255.0, g / 255.0, b / 255.0
            hh, ll, ss = colorsys.rgb_to_hls(rr, gg, bb)
            if hue is not None:
                d = (hue - hh) % 1.0
                if d > 0.5:
                    d -= 1.0
                hh = (hh + d * 0.85) % 1.0
                ss = sat if sat is not None else ss
            else:
                ss = ss * (1.0 - desat_only)
            rr2, gg2, bb2 = colorsys.hls_to_rgb(hh, min(1.0, ll * lum), min(1.0, ss))
            n = (hash01(x, y, seed) - 0.5) * 2.0 * grain
            chk2 = 5.0 if ((x // 2) + (y // 2)) % 2 == 0 else -5.0
            chk8 = 6.0 if ((x // 8) + (y // 8)) % 2 == 0 else -6.0
            r3 = min(255, max(0, int(rr2 * 255 + n + chk2 + chk8)))
            g3 = min(255, max(0, int(gg2 * 255 + n + chk2 + chk8)))
            b3 = min(255, max(0, int(bb2 * 255 + n + chk2 + chk8)))
            px[x, y] = (r3, g3, b3)
    return work


def main() -> int:
    im = Image.open(PNG).convert("RGBA")
    if "--check" in sys.argv:
        print("[retouch] check — %s %s" % (PNG.name, im.size))
        return 0
    for tid, (hue, sat, grain, lum) in TILES.items():
        for bank in range(BANKS):
            cx, cy = (tid % 16) * CELL, (tid // 16 + bank * BANK_ROWS) * CELL
            cell = im.crop((cx, cy, cx + CELL, cy + CELL))
            cell = retouch(cell, tid * 10 + bank, hue, sat, grain, lum, DESAT_ONLY[tid])
            im.paste(cell, (cx, cy))
    im = global_tone(im)
    im.save(PNG)
    print("[retouch] done - tiles %s x%d banks" % (sorted(TILES), BANKS))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
