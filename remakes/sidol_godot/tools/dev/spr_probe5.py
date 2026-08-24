#!/usr/bin/env python3
"""SPR 프로버 v5 — [매직 28B][팔레트 768B][레코드...] 가설 + 진단 출력.

레코드 가설 A: [u16 size][u16 w][u16 h][data size-4]  stride = 2+size
레코드 가설 B: [u16 size][블록 size바이트 = w,h,data] stride = size
"""
from __future__ import annotations

from pathlib import Path

BASE = Path(r"D:\Project\Etc\Old\부싯돌시절\originals\1995_sidol_bsd_dos")
PAL_START = 28
REC_START = PAL_START + 768   # 796


def walk_diag(data: bytes, start: int, mode: str):
    pos = start
    n = len(data)
    recs = []
    steps = []
    while pos < n:
        if pos + 6 > n:
            steps.append(f"END-short@{pos}(남 {n-pos})")
            break
        size = int.from_bytes(data[pos:pos + 2], "little")
        w = int.from_bytes(data[pos + 2:pos + 4], "little")
        h = int.from_bytes(data[pos + 4:pos + 6], "little")
        ok_dims = 2 <= w <= 400 and 2 <= h <= 400
        steps.append(f"@{pos}: size={size} w={w} h={h}{'✓' if ok_dims else '✗'}")
        if not ok_dims or size < 4:
            return None, steps
        blk = size - 4
        recs.append((w, h))
        pos += (2 + size) if mode == "A" else size
        if len(recs) > 300:
            return None, steps
    return recs, steps


def probe(fname: str) -> None:
    path = BASE / fname
    if not path.exists():
        return
    data = path.read_bytes()
    print(f"\n=== {fname} ({len(data)}B) 레코드영역={REC_START}..{len(data)} ({len(data)-REC_START}B) ===")
    for mode in ("A", "B"):
        recs, steps = walk_diag(data, REC_START, mode)
        head = "; ".join(steps[:3])
        tail = steps[-1] if steps else ""
        status = f"records={len(recs)}" if recs is not None else "실패"
        print(f"  [{mode}] {status} | {head} ... {tail}")
        if recs:
            uniq = sorted(set(recs))[:8]
            print(f"      uniq_dims={uniq}")


for f in ["TILE.SPR", "ITEM.SPR", "num.spr"]:
    probe(f)
