#!/usr/bin/env python3
"""SPR 포맷 프로버 — sed.lib 'Sprites Data File Ver 3.05' 구조 가설 검증.

가설(H): 매직(27B) 후 각 스프라이트가 [헤더][픽셀] 연속.
  H_u16: u16le w, u16le h, w*h 픽셀
  H_u8 : u8 w, u8 h, w*h 픽셀
  H_u16_pad: u16 w,u16 h,u8 pad,w*h
성공 판정: 첫 스프라이트부터 파일 끝까지 딱 떨어지고, 치수가 상식 범위(4..128).
"""
from __future__ import annotations

import sys
from pathlib import Path

MAGIC_LEN = 27


def probe(path: Path) -> None:
    data = path.read_bytes()
    print(f"\n=== {path.name} ({len(data)}B) ===")
    print("magic:", data[:MAGIC_LEN])
    body_start_candidates = range(MAGIC_LEN, MAGIC_LEN + 8)

    def try_hyp(body: bytes, hw: int, hh: int, pad: int = 0) -> list[tuple[int, int, int]] | None:
        pos = 0
        out = []
        while pos < len(body):
            if pos + hw + hh > len(body):
                return None
            w = int.from_bytes(body[pos:pos + hw], "little")
            h = int.from_bytes(body[pos + hw:pos + hw + hh], "little")
            pos += hw + hh + pad
            if not (1 <= w <= 128 and 1 <= h <= 128):
                return None
            if pos + w * h > len(body):
                return None
            out.append((pos, w, h))
            pos += w * h
        return out if out else None

    for start in body_start_candidates:
        body = data[start:]
        for name, hw, hh, pad in [("u16", 2, 2, 0), ("u8", 1, 1, 0), ("u16pad", 2, 2, 1)]:
            r = try_hyp(body, hw, hh, pad)
            if r:
                dims = {(w, h) for _, w, h in r}
                print(f"  FIT start={start} hyp={name} sprites={len(r)} unique_dims={sorted(dims)[:8]}")
                print(f"   first5={[(w, h) for _, w, h in r[:5]]}")


if __name__ == "__main__":
    base = Path(r"D:\Project\Etc\Old\부싯돌시절\originals\1995_sidol_bsd_dos")
    for f in ["TILE.SPR", "SIDOL.SPR", "ITEM.SPR", "OBJ.SPR", "E1.SPR"]:
        p = base / f
        if p.exists():
            probe(p)
