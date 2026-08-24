#!/usr/bin/env python3
"""원작 PCX 그래픽 → assets/originals_ref/*.png 수출기.

목적: AI 생성 에이전트와 사람 리뷰를 위한 '진짜 원작 비주얼' 참조 자료 확보.
SPR은 압축 포맷(역공학 부수 과제)이라 PCX 위주로 먼저 수출한다.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHARED_SRC = ROOT.parent.parent / "_shared" / "src"
ORIGINALS = ROOT.parent.parent / "originals" / "1995_sidol_bsd_dos"
sys.path.insert(0, str(SHARED_SRC))

from dosport.formats.pcx import pcx_to_rgba  # noqa: E402
from dosport.formats.png_write import write_png  # noqa: E402

TARGETS = [
    "TEST_F.PCX",    # 필드 HUD 프레임
    "STORE.PCX",     # 상점 실내
    "HP.PCX",        # HP실(크레딧룸)
    "FACE1_2.PCX", "FACE3.PCX", "FACE4.PCX", "FACE4_W.PCX", "FACE5.PCX",  # 대화 얼굴
    "READY1.PCX", "READY2.PCX",  # 전투 준비 화면
    "V-0.PCX",       # 전투 배경 샘플
    "M-R-0.PCX",     # 입장 그림 샘플
    "EFFECT.PCX",    # 이펙트
]


def main() -> int:
    out_dir = ROOT / "assets" / "originals_ref"
    out_dir.mkdir(parents=True, exist_ok=True)
    index = []
    for name in TARGETS:
        src = ORIGINALS / name
        if not src.exists():
            print(f"skip(없음): {name}")
            continue
        try:
            w, h, rgba = pcx_to_rgba(src.read_bytes())
        except ValueError as e:
            print(f"skip(미지원): {name} -> {e}")
            continue
        dst = out_dir / (name.replace(".PCX", ".png").lower())
        write_png(dst, w, h, rgba)
        index.append({"source": name, "png": dst.name, "width": w, "height": h})
        print(f"{name} -> {dst.name} ({w}x{h})")
    (out_dir / "index.json").write_text(json.dumps(index, indent=1), encoding="utf-8")
    print(f"total={len(index)} -> {out_dir.relative_to(ROOT)}/index.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
