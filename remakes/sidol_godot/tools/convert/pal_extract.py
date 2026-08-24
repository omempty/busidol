#!/usr/bin/env python3
"""DEFAULT.PAL(raw VGA 768바이트 RGB) → assets/palette_master.json 추출기.

포맷 자동 판별: RIFF-PAL / JASC-PAL / raw768 (원본 검증 결과 = raw768).
스펙: docs/02_design/07_ai_asset_pipeline.md §4.1 (팔레트 잠금 파일)
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE_PATH = ROOT.parent.parent / "originals" / "1995_sidol_bsd_dos" / "DEFAULT.PAL"
OUTPUT_PATH = ROOT / "assets" / "palette_master.json"


def detect_format(data: bytes) -> str:
    if data.startswith(b"RIFF") and data[8:12] == b"PAL ":
        return "riff_pal"
    if data.startswith(b"JASC-PAL"):
        return "jasc_pal"
    if len(data) == 768:
        return "raw768"
    raise ValueError(f"알 수 없는 팔레트 포맷: size={len(data)} head={data[:12].hex()}")


def to_colors(data: bytes, fmt: str) -> list[str]:
    if fmt == "raw768":
        triples = [tuple(data[i:i + 3]) for i in range(0, 768, 3)]
    elif fmt == "jasc_pal":
        lines = data.decode("ascii").splitlines()[3:]
        triples = [tuple(int(v) for v in ln.split()) for ln in lines if ln.strip()]
    else:  # riff_pal
        count = int.from_bytes(data[18:20], "little")
        base = 24
        triples = [tuple(data[base + i * 4: base + i * 4 + 3]) for i in range(count)]
    return ["#{:02X}{:02X}{:02X}".format(*t) for t in triples]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="리포트만")
    args = parser.parse_args()

    data = SOURCE_PATH.read_bytes()
    fmt = detect_format(data)
    colors = to_colors(data, fmt)
    unique = sorted(set(colors))
    print(f"source={SOURCE_PATH.name} format={fmt} colors={len(colors)} unique={len(unique)}")
    print("first8=" + ",".join(colors[:8]))

    if args.check:
        return 0

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": 1,
        "source": SOURCE_PATH.name,
        "format": fmt,
        "colors": colors,
    }
    OUTPUT_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"wrote {OUTPUT_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
