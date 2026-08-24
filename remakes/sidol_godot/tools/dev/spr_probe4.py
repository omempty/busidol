#!/usr/bin/env python3
"""SPR 프로버 v4 — SED.H sprites 구조체 기반 레코드 분할 검증.

레코드 가설: [u16 size][u16 폭][u16 높이][데이터 size-4 바이트]
검증: EOF 정확 소진 + 개수 == 원작 Load_Spr 카운트 + 치수 상식 범위.
"""
from __future__ import annotations

from pathlib import Path

BASE = Path(r"D:\Project\Etc\Old\부싯돌시절\originals\1995_sidol_bsd_dos")
BASE_ARJ = BASE / "보존" / "BSD"

EXPECTED = {
    "TILE.SPR": 106, "I.SPR": 159, "ITEM.SPR": 38, "EVENTER.SPR": 41,
    "OBJ.SPR": 175, "num.spr": 11, "FIELD.SPR": None, "MONSTER.SPR": None,
}


def split_records(data: bytes, start: int):
    pos = start
    recs = []
    n = len(data)
    while pos < n:
        if pos + 6 > n:
            return None
        size = int.from_bytes(data[pos:pos + 2], "little")
        w = int.from_bytes(data[pos + 2:pos + 4], "little")
        h = int.from_bytes(data[pos + 4:pos + 6], "little")
        if not (6 <= size <= n and 2 <= w <= 400 and 2 <= h <= 400):
            return None
        recs.append((w, h))
        pos += 2 + size          # size 워드 포함 진행? → 아래 대안과 스왑 테스트
        # 대안: pos += size  (size가 size워드 제외 길이일 경우)
    return recs


def split_records_alt(data: bytes, start: int):
    """대안: pos += size (size = 헤더 제외 블록 길이)."""
    pos = start
    recs = []
    n = len(data)
    while pos < n:
        if pos + 6 > n:
            return None
        size = int.from_bytes(data[pos:pos + 2], "little")
        w = int.from_bytes(data[pos + 2:pos + 4], "little")
        h = int.from_bytes(data[pos + 4:pos + 6], "little")
        if not (4 <= size <= n and 2 <= w <= 400 and 2 <= h <= 400):
            return None
        recs.append((w, h))
        pos += size              # [size][블록 size바이트(x,y,data)] → 다음 레코드
    return recs


def probe(fname: str, base: Path) -> None:
    path = base / fname
    if not path.exists():
        return
    data = path.read_bytes()
    expect = EXPECTED.get(fname)
    print(f"\n=== {fname} ({len(data)}B) expect={expect} ===")

    def score(recs, variant):
        if recs is None:
            return -1
        s = 0
        if expect is not None and len(recs) == expect:
            s += 10
        if recs and recs[0] == (12, 12):
            s += 3
        uniq = sorted(set(recs))[:5]
        tag = "A(+2)" if variant else "B"
        print(f"  [{tag}] hdr fit: count={len(recs)} uniq_dims={uniq}")
        return s

    best = max(
        (score(split_records(data, st), True), f"A start={st}", split_records(data, st))
        for st in (27,)
    )
    best_b = max(
        (score(split_records_alt(data, st), False), f"B start={st}", split_records_alt(data, st))
        for st in (27,)
    )


for fname in ["num.spr", "ITEM.SPR", "TILE.SPR", "EVENTER.SPR", "FIELD.SPR", "I.SPR"]:
    probe(fname, BASE)
probe("MONSTER.SPR", BASE_ARJ)
