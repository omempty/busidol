#!/usr/bin/env python3
"""BSD MAP(TILE/OBJ/ATT 3레이어) → data/maps/f<N>.json 변환기.

포맷 명세: docs/01_analysis/03_data_format_spec.md §1
  39,000B = BYTE tile[200x65] + BYTE obj[200x65] + BYTE att[200x65]

산출(JSON, 메모장 편집 가능):
{
  "schema_version": 1,
  "map_id": "f1",
  "source": "F1.MAP",
  "width": 200, "height": 65,
  "layers": {
    "ground": [[row0...],[row1...]...],   # 각 행은 공백 구분 정수 문자열(가독성+용량 절충)
    "object": [...],
    "attr":   [...]
  }
}

--stats: 사용 타일 ID 히스토그램과 ATT 분포 출력(플레이스홀더 아틀라스 생성 입력).
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ORIGINALS = ROOT.parent.parent / "originals" / "1995_sidol_bsd_dos"
OUT_DIR = ROOT / "data" / "maps"

WIDTH, HEIGHT = 200, 65
LAYER_SIZE = WIDTH * HEIGHT
MAP_IDS = ["f0", "f1", "f2", "f3", "f4", "f5"]

ATT_NAMES = {
    0: "PASSABLE", 1: "BLOCKED", 2: "OVERHEAD", 9: "DOOR",
}


def convert(map_id: str) -> tuple[dict, Counter, Counter]:
    src = ORIGINALS / f"{map_id.upper()}.MAP"
    data = src.read_bytes()
    if len(data) != LAYER_SIZE * 3:
        raise ValueError(f"{src.name}: 크이상 len={len(data)}")
    tile = data[:LAYER_SIZE]
    obj = data[LAYER_SIZE:LAYER_SIZE * 2]
    att = data[LAYER_SIZE * 2:]

    def rows(buf: bytes) -> list[list[int]]:
        return [[buf[y * WIDTH + x] for x in range(WIDTH)] for y in range(HEIGHT)]

    payload = {
        "schema_version": 1,
        "map_id": map_id,
        "source": src.name,
        "width": WIDTH,
        "height": HEIGHT,
        "layers": {"ground": rows(tile), "object": rows(obj), "attr": rows(att)},
    }
    return payload, Counter(tile), Counter(att)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--stats", action="store_true", help="타일/ATT 분포 리포트")
    parser.add_argument("--maps", nargs="*", default=MAP_IDS, help="변환 대상(기본 전체)")
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    att_total: Counter = Counter()
    for map_id in args.maps:
        payload, tile_hist, att_hist = convert(map_id)
        out = OUT_DIR / f"{map_id}.json"
        out.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
        rel = out.relative_to(ROOT)
        print(f"{map_id}: wrote {rel} ({out.stat().st_size:,}B)")
        if args.stats and map_id == "f1":
            print(f"  f1 ground ids used={len(tile_hist)} top10={tile_hist.most_common(10)}")
            print(f"  f1 object ids used={len([k for k in tile_hist if False]) or 'see obj'}")
        att_total += att_hist
        if args.stats and map_id == "f1":
            named = {ATT_NAMES.get(k, f"VAL{k}"): v for k, v in sorted(att_hist.items())[:12]}
            print(f"  f1 att top12={named}")
    if args.stats:
        print(f"att(all floors) top10={att_total.most_common(10)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
