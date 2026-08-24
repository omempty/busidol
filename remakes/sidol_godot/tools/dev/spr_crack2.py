#!/usr/bin/env python3
"""실패 10파일용 RLE 변형 크래커 — 파일별 승자 자동 판정."""
from __future__ import annotations

from pathlib import Path

BASE = Path(r"D:\Project\Etc\Old\부싯돌시절\originals\1995_sidol_bsd_dos")
BASE_ARJ = BASE / "보존" / "BSD"
REC_START = 28 + 768


def split_records(data: bytes):
    pos = REC_START
    recs = []
    n = len(data)
    while pos + 6 <= n:
        size = int.from_bytes(data[pos:pos + 2], "little")
        w = int.from_bytes(data[pos + 2:pos + 4], "little")
        h = int.from_bytes(data[pos + 4:pos + 6], "little")
        if size == 4 and w == 0 and h == 0:
            break
        if size < 4 or pos + 2 + size > n:
            return None
        recs.append((w, h, data[pos + 6:pos + 2 + size]))
        pos += 2 + size
    return recs


def make_pcx(threshold: int, run_of_marker: bool):
    def fn(d, p, need):
        out = bytearray()
        n = len(d)
        while len(out) < need:
            if p >= n: return None
            b = d[p]; p += 1
            is_mark = (b >= threshold) if not run_of_marker else (b == 0 and False)
            if is_mark:
                if p >= n: return None
                out += bytes([d[p]]) * (b & 0x3F); p += 1
            else:
                out.append(b)
        return (p, bytes(out))
    return fn


def mk_zero2(d, p, need):          # 00 cnt -> 검정런
    out = bytearray(); n = len(d)
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


def mk_zero3(d, p, need):          # 00 cnt val -> 색 런
    out = bytearray(); n = len(d)
    while len(out) < need:
        if p >= n: return None
        b = d[p]; p += 1
        if b == 0:
            if p + 1 >= n: return None
            c = d[p]; v = d[p + 1]; p += 2
            out += bytes([v]) * c
        else:
            out.append(b)
    return (p, bytes(out))


def mk_ctrl80(d, p, need):         # hi-bit: 런 / low: 리터럴 복사
    out = bytearray(); n = len(d)
    while len(out) < need:
        if p >= n: return None
        c = d[p]; p += 1
        if c & 0x80:
            cnt = c & 0x7F
            if p >= n: return None
            out += bytes([d[p]]) * cnt; p += 1
        elif c > 0:
            if p + c > n: return None
            out += d[p:p + c]; p += c
        else:
            return None
    return (p, bytes(out))


def mk_pairs(d, p, need):
    out = bytearray(); n = len(d)
    while len(out) < need:
        if p + 1 >= n: return None
        c = d[p]; v = d[p + 1]; p += 2
        out += bytes([v]) * c
    return (p, bytes(out))


def mk_192_193(d, p, need):        # 192=리터럴 예외, 193+ 런
    out = bytearray(); n = len(d)
    while len(out) < need:
        if p >= n: return None
        b = d[p]; p += 1
        if b >= 193:
            if p >= n: return None
            out += bytes([d[p]]) * (b & 0x3F); p += 1
        else:
            out.append(b)
    return (p, bytes(out))


CANDIDATES = {
    "pcx192": make_pcx(192, False),
    "zero2_black": mk_zero2,
    "zero3_color": mk_zero3,
    "ctrl80": mk_ctrl80,
    "pairs": mk_pairs,
    "pcx193": mk_192_193,
}

FAILING = ["FRAME.SPR", "HANTST.SPR", "HONG.SPR", "HWANG.SPR", "MBOOM.SPR",
           "NA.SPR", "NAM.SPR", "PING1.SPR", "SIDOL.SPR", "WKIM.SPR"]


def main() -> int:
    for fname in FAILING:
        for base in (BASE, BASE_ARJ):
            path = base / fname
            if path.exists():
                break
        data = path.read_bytes()
        recs = split_records(data)
        print(f"\n=== {fname} records={len(recs) if recs else '?'} ===")
        winners = []
        for cname, fn in CANDIDATES.items():
            good = 0
            tested = 0
            for w, h, payload in recs:
                need = w * h
                if len(payload) == need:
                    continue                     # 무압축 레코드는 스킵(항상 성공)
                tested += 1
                r = fn(payload, 0, need)
                if r and r[0] == len(payload):
                    good += 1
            mark = "★WINNER" if tested and good == tested else ""
            print(f"  {cname}: {good}/{tested}{(' ' + mark) if mark else ''}")
            if tested and good == tested:
                winners.append(cname)
        if not winners:
            print("  -> 어떤 후보도 완전 일치 없음")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
