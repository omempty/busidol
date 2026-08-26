#!/usr/bin/env python3
"""원작 SPR 색0(순검정) → 투명 키잉 — 구판 아틀라스 사후 복구용.

배경: 원작 엔진 blit은 팔레트 인덱스 0을 스킵한다(= 투명). spr_extract.parse_spr는
이미 색0을 alpha 0으로 방출하도록 고쳐졌으나(docs/HANDOFF.md "원작 검정=투명 문제"),
`obj_original_32.png`는 그 수정 이전에 구워진 구판이라 오브젝트마다 검은 사각 배경이
붙어 있었다. 원본 SPR이 없는 환경에서도 되돌릴 수 있도록 사후 키잉만 수행한다.

순검정(0,0,0)만 대상 — 원작 도트의 어두운 외곽선은 (32,32,32) 등 별도 인덱스라
안전하다. 캐릭터 시트는 머리카락 등 정당한 순검정을 쓰므로 대상이 아니다.

사용: python tools/dev/key_color0_transparent.py assets/sprites/obj_original_32.png
      (--check 로 변경 없이 통계만)
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

KEY = (0, 0, 0)


def key_file(path: Path, check: bool) -> int:
    img = Image.open(path).convert("RGBA")
    px = img.load()
    w, h = img.size
    hit = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a != 0 and (r, g, b) == KEY:
                hit += 1
                if not check:
                    px[x, y] = (0, 0, 0, 0)
    pct = 100.0 * hit / (w * h)
    verb = "검출" if check else "키잉"
    print(f"{path.name}: {w}x{h} 순검정 {hit}px ({pct:.1f}%) {verb}")
    if not check and hit:
        img.save(path)
    return hit


def main(argv: list[str]) -> int:
    check = "--check" in argv
    targets = [Path(a) for a in argv if not a.startswith("--")]
    if not targets:
        print(__doc__)
        return 2
    for t in targets:
        if not t.exists():
            print(f"[오류] 파일 없음: {t}")
            return 1
        key_file(t, check)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
