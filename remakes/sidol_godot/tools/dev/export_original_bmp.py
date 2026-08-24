#!/usr/bin/env python3
"""원작 폴더의 모든 .PCX → BMP 일괄 수출 (그래픽 AI 에이전트 참조 세트).

산출: assets/originals_ref/bmp/<name>.bmp  (+ 실패 목록 리포트)
각 파일은 자체 임베디드 팔레트를 사용한다(dosport.formats.pcx).
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHARED_SRC = ROOT.parent.parent / "_shared" / "src"
ORIGINALS = ROOT.parent.parent / "originals" / "1995_sidol_bsd_dos"
sys.path.insert(0, str(SHARED_SRC))

from dosport.formats.bmp_write import write_bmp24  # noqa: E402
from dosport.formats.pcx import pcx_to_rgba  # noqa: E402

OUT_DIR = ROOT / "assets" / "originals_ref" / "bmp"


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sources = sorted(ORIGINALS.glob("*.PCX"))
    ok, failed = [], []
    for src in sources:
        dst = OUT_DIR / (src.stem.lower() + ".bmp")
        try:
            w, h, rgba = pcx_to_rgba(src.read_bytes())
            write_bmp24(dst, w, h, rgba)
            ok.append(f"{src.name} -> {dst.name} ({w}x{h})")
        except (ValueError, Exception) as e:   # noqa: BLE001 — 배치 계속 진행이 목적
            failed.append(f"{src.name}: {e}")

    print(f"converted={len(ok)} failed={len(failed)}")
    for line in ok:
        print("  OK ", line)
    for line in failed:
        print("  FAIL", line)
    print(f"out={OUT_DIR.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
