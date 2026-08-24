#!/usr/bin/env python3
"""SPR 프로버 v3 — [헤더][RLE 픽셀] 체인 워크.

레코드 = 헤더(w u16[,h u16][,...]) + RLE 스트림(w*h 픽셀 생성까지 소비).
성공 판정: EOF 정확 소진 + 스프라이트 수 == 원작 Load_Spr 카운트.
"""
from __future__ import annotations

from pathlib import Path

BASE = Path(r"D:\Project\Etc\Old\부싯돌시절\originals\1995_sidol_bsd_dos")

EXPECTED = {
    "TILE.SPR": 106, "I.SPR": 159, "ITEM.SPR": 38,
    "EVENTER.SPR": 41, "OBJ.SPR": 175, "num.spr": 11,
}


def rle_decode(body: bytes, pos: int, need: int, flavor: int):
    """pos부터 need픽셀 생성. 반환 (new_pos, pixels) / 실패 None."""
    out = bytearray()
    n = len(body)
    if flavor == 0:      # PCX식: <192 리터럴, >=192 카운트+값
        while len(out) < need:
            if pos >= n:
                return None
            b = body[pos]; pos += 1
            if b < 192:
                out.append(b)
            else:
                if pos >= n: return None
                out += bytes([body[pos]]) * (b & 0x3F); pos += 1
    elif flavor == 1:    # 순수 페어: [카운트][값]
        while len(out) < need:
            if pos + 1 >= n: return None
            c = body[pos]; v = body[pos + 1]; pos += 2
            if c == 0: return None
            out += bytes([v]) * c
    else:                # 제로RLE: 0 다음에 카운트(투명 런), 그 외 리터럴
        while len(out) < need:
            if pos >= n: return None
            b = body[pos]; pos += 1
            if b == 0:
                if pos >= n: return None
                c = body[pos]; pos += 1
                out += b"\x00" * c
            else:
                out.append(b)
    return pos, bytes(out)


def walk_chain(data: bytes, start: int, hdr: int, flavor: int, expect: int | None):
    pos = start
    dims = []
    n = len(data)
    while pos < n:
        if pos + hdr > n:
            return None
        w = int.from_bytes(data[pos:pos + 2], "little")
        h = int.from_bytes(data[pos + 2:pos + 4], "little")
        if not (2 <= w <= 96 and 2 <= h <= 96):
            return None
        pos += hdr
        r = rle_decode(data, pos, w * h, flavor)
        if r is None:
            return None
        pos, _px = r
        dims.append((w, h))
    if expect is not None and len(dims) != expect:
        return None
    return dims


def probe(fname: str) -> None:
    path = BASE / fname
    if not path.exists():
        return
    data = path.read_bytes()
    expect = EXPECTED.get(path.name)
    print(f"\n=== {fname} ({len(data)}B) expect={expect} ===")
    found = []
    for hdr in (2, 4, 8):
        for flavor in (0, 1, 2):
            for start in range(27, 34):
                dims = walk_chain(data, start, hdr, flavor, expect)
                if dims:
                    uniq = sorted(set(dims))[:5]
                    found.append((hdr, flavor, start, len(dims), uniq))
                    print(f"  FIT hdr={hdr} flavor={flavor} start={start} "
                          f"count={len(dims)} unique_dims={uniq}")
    if not found:
        print("  no fit")


for f in ["num.spr", "ITEM.SPR", "TILE.SPR", "EVENTER.SPR", "I.SPR", "OBJ.SPR"]:
    probe(f)
