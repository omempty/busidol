#!/usr/bin/env python3
"""RLE 플레이버 크래커 — ITEM.SPR 레코드들로 검증.

판정: 모든 테스트 레코드에서 (a) 데이터 정확 소진 (b) 출력 == w*h 픽셀.
"""
from __future__ import annotations

from pathlib import Path

BASE = Path(r"D:\Project\Etc\Old\부싯돌시절\originals\1995_sidol_bsd_dos")
REC_START = 796


def split_records(data: bytes, start: int):
    pos = start
    recs = []
    n = len(data)
    while pos < n:
        if pos + 6 > n:
            break
        size = int.from_bytes(data[pos:pos + 2], "little")
        w = int.from_bytes(data[pos + 2:pos + 4], "little")
        h = int.from_bytes(data[pos + 4:pos + 6], "little")
        if size == 4 and w == 0 and h == 0:
            pos += 6
            recs.append(("TERM", w, h, b""))
            continue
        if size < 4 or pos + 2 + size > n:
            return None, recs
        recs.append((w, h, data[pos + 6:pos + 2 + size]))
        pos += 2 + size
    return pos, recs


# ---- 후보 디코더: 각각 (data,pos,need)->(new_pos,pixels)|None ----

def d_pcx(d, p, need):
    out = bytearray()
    n = len(d)
    while len(out) < need:
        if p >= n: return None
        b = d[p]; p += 1
        if b < 192:
            out.append(b)
        else:
            if p >= n: return None
            out += bytes([d[p]]) * (b & 0x3F); p += 1
    return (p, bytes(out))


def d_pairs(d, p, need):
    out = bytearray()
    n = len(d)
    while len(out) < need:
        if p + 1 >= n: return None
        c = d[p]; v = d[p + 1]; p += 2
        out += bytes([v]) * c
    return (p, bytes(out))


def d_zero_run(d, p, need):
    out = bytearray()
    n = len(d)
    while len(out) < need:
        if p >= n: return None
        b = d[p]; p += 1
        if b == 0:
            if p >= n: return None
            c = d[p]; p += 1
            out += b"\x00" * c
        else:
            out.append(b)
    return (p, bytes(out))


def d_ctrl_lit_run(d, p, need):
    """제어바이트: 상위비트1=런(다음 바이트를 하위7bit횟수만큼), 0=리터럴 n바이트 복사."""
    out = bytearray()
    n = len(d)
    while len(out) < need:
        if p >= n: return None
        c = d[p]; p += 1
        if c & 0x80:
            cnt = c & 0x7F
            if p >= n: return None
            out += bytes([d[p]]) * cnt; p += 1
        else:
            if p + c > n: return None
            out += d[p:p + c]; p += c
    return (p, bytes(out))


def d_zero_then_pairs(d, p, need):
    """0 다음 카운트=투명런 / 0아니면 [값][카운트]? 순서 혼합형 A."""
    out = bytearray()
    n = len(d)
    while len(out) < need:
        if p >= n: return None
        b = d[p]; p += 1
        if b == 0:
            if p >= n: return None
            c = d[p]; p += 1
            out += b"\x00" * c
        else:
            if p >= n: return None
            c = d[p]; p += 1
            out += bytes([b]) * c
    return (p, bytes(out))


DECODERS = {
    "pcx": d_pcx, "pairs": d_pairs, "zero_run": d_zero_run,
    "ctrl_litrun": d_ctrl_lit_run, "zero_then_pairs": d_zero_then_pairs,
}


def main() -> int:
    data = (BASE / "ITEM.SPR").read_bytes()
    _, recs = None, None
    pos = REC_START
    recs = []
    while pos < len(data):
        size = int.from_bytes(data[pos:pos + 2], "little")
        w = int.from_bytes(data[pos + 2:pos + 4], "little")
        h = int.from_bytes(data[pos + 4:pos + 6], "little")
        if size == 4 and w == 0 and h == 0:
            break
        recs.append((w, h, data[pos + 6:pos + 2 + size]))
        pos += 2 + size
    print(f"records={len(recs)}")

    # 첫 8개 레코드로 승부
    sample = recs[:8]
    for name, fn in DECODERS.items():
        good = 0
        detail = ""
        for i, (w, h, payload) in enumerate(sample):
            need = w * h
            r = fn(payload, 0, need)
            if r and r[0] == len(payload):
                good += 1
                if i == 0:
                    detail = f" first_px={r[1][:12].hex()}"
        status = "★" if good == len(sample) else ("o" if good > len(sample)//2 else "x")
        print(f"  {status} {name}: {good}/{len(sample)}{detail}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
