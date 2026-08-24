#!/usr/bin/env python3
"""SPR 프로버 v2 — 8바이트 헤더(w,h,?,?) + 무압축 픽셀 가설.

검증 신호(거짓양성 제거):
  1) 첫 레코드부터 파일 끝까지 정확히 소진
  2) 스프라이트 개수 == 원작 코드의 Load_Spr 카운트
기대 치수 단서: 타일=12x12(SCAP.C), 아이콘≈16x16
"""
from __future__ import annotations

from pathlib import Path

BASE = Path(r"D:\Project\Etc\Old\부싯돌시절\originals\1995_sidol_bsd_dos")

# 파일별 기대 스프라이트 수 (원작 소스 Load_Spr 호출)
EXPECTED = {
    "TILE.SPR": 106,   # MAX_TILE 105 +1
    "I.SPR": 159,      # MAX_SPR 158 +1
    "ITEM.SPR": 38,    # NUM_ITEM 37 +1
    "EVENTER.SPR": 41, # MAX_EVE_SPR 40 +1
    "OBJ.SPR": 175,    # MAX_OBJ 174 +1
    "num.spr": 11,
}


def walk(body: bytes, hdr: int, start: int):
    """hdr 바이트 헤더[w@0 u16][h@2 u16] 가설로 레코드 체인 걷기. 성공 시 목록 반환."""
    pos = start
    out = []
    n = len(body)
    while pos < n:
        if pos + hdr > n:
            return None
        w = int.from_bytes(body[pos:pos + 2], "little")
        h = int.from_bytes(body[pos + 2:pos + 4], "little")
        if not (1 <= w <= 200 and 1 <= h <= 200):
            return None
        pos += hdr
        if pos + w * h > n:
            return None
        out.append((w, h))
        pos += w * h
    return out


def probe(fname: str) -> None:
    path = BASE / fname
    if not path.exists():
        return
    data = path.read_bytes()
    expect = EXPECTED.get(path.name)
    print(f"\n=== {fname} ({len(data)}B) expect={expect} ===")
    hits = []
    for hdr in range(4, 17, 2):          # 4,6,8,10,12,14,16
        for start in range(27, 40):       # 매직 직후 시작 오프셋 스윕
            r = walk(data[start:], hdr, 0)
            if r is None:
                continue
            score = 0
            detail = ""
            if expect and len(r) == expect:
                score += 10
                detail += f" COUNT=={expect}!"
            if r[0] == (12, 12):
                score += 3
                detail += " first=12x12"
            uniq = sorted(set(r))[:4]
            if score > 0 or len(r) > 3:
                hits.append((score, hdr, start, len(r), uniq, detail))
    hits.sort(reverse=True)
    for s, hdr, st, cnt, uniq, d in hits[:4]:
        print(f"  hdr={hdr} start={st} count={cnt} uniq={uniq}{d}")
    if not hits:
        print("  no fit")


for f in ["TILE.SPR", "ITEM.SPR", "EVENTER.SPR", "I.SPR", "OBJ.SPR", "num.spr"]:
    probe(f)
