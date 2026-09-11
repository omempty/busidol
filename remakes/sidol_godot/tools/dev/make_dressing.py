#!/usr/bin/env python3
"""맵 때·벽장식 데칼 생성기 — 직접 그리기(절차 픽셀) 버전.

외부 무료 리소스 대신 쓰는 이유: 라이선스 추적(출처·귀속) 없이 저장소에 닫히고,
32px 격자·최근접 렌더에 맞는 픽셀 문법으로 나온다. 외부 의뢰로 교체할 때는
assets/decals/ 파일만 갈아끼우면 된다(런타임은 파일명으로만 참조).
사용: python tools/dev/make_dressing.py [--check]
"""
from __future__ import annotations

import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "decals"


def speckle(draw: ImageDraw.ImageDraw, rng: random.Random, box, n: int, colors) -> None:
    for _ in range(n):
        x = rng.randint(box[0], box[2])
        y = rng.randint(box[1], box[3])
        draw.point((x, y), fill=rng.choice(colors))


def grime_blob() -> Image.Image:
    """바닥 오염 큰 덩어리 96px — 흰색+알파(런타임 tint). 타일 2~4개 덮는 용도."""
    rng = random.Random(137)
    im = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    px = im.load()
    blobs = [(30, 34, 26), (62, 58, 30), (52, 30, 18), (34, 64, 16)]
    for y in range(96):
        for x in range(96):
            a = 0.0
            for cx, cy, r in blobs:
                d = math.hypot(x - cx, y - cy) / r
                wob = 1.0 + 0.25 * math.sin(x * 0.35 + y * 0.21)
                if d < wob:
                    a = max(a, (1.0 - d / wob) ** 1.6)
            edge = hash((x, y)) % 100 / 100.0
            alpha = int(150 * a * (0.75 + 0.25 * edge))
            if alpha > 0:
                v = 235 + hash((x * 7, y * 13)) % 20 - 10
                px[x, y] = (v, v, v, alpha)
    draw = ImageDraw.Draw(im)
    speckle(draw, rng, (10, 10, 86, 86), 120, [(255, 255, 255, 200)])
    return im


def poster() -> Image.Image:
    """붙은 포스터 24x32 — 종이+테두리+줄글+도장."""
    rng = random.Random(11)
    im = Image.new("RGBA", (24, 32), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    draw.rectangle((2, 1, 21, 30), fill=(216, 212, 200, 255))
    draw.rectangle((2, 1, 21, 30), outline=(60, 55, 50, 255))
    draw.rectangle((4, 3, 19, 8), fill=(150, 40, 36, 255))
    for i, y in enumerate((12, 16, 20, 24)):
        w = 15 - (i % 3) * 3
        draw.line((4, y, 4 + w, y), fill=(90, 86, 80, 255))
    speckle(draw, rng, (2, 1, 21, 30), 25, [(200, 196, 184, 255)])
    draw.point((2, 1), fill=(216, 212, 200, 0))
    return im


def rust() -> Image.Image:
    """녹슨 때 24x32 — 아래로 흐른 줄기."""
    rng = random.Random(23)
    im = Image.new("RGBA", (24, 32), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    for x, w, l in ((5, 3, 26), (12, 2, 31), (18, 4, 22)):
        for y in range(2, l):
            fade = 1.0 - (y - 2) / max(1, l - 2)
            a = int(190 * fade)
            for dx in range(w):
                if rng.random() < 0.75:
                    draw.point((x + dx, y), fill=(122, 72, 38, a))
    speckle(draw, rng, (3, 20, 21, 31), 40, [(100, 60, 32, 220)])
    return im


def graffiti() -> Image.Image:
    """그래피티 40x24 — 형광 낙서 2획."""
    rng = random.Random(37)
    im = Image.new("RGBA", (40, 24), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    draw.line((4, 16, 14, 6, 24, 14, 34, 5), fill=(64, 220, 220, 235), width=3)
    draw.line((6, 20, 18, 18, 30, 21), fill=(230, 60, 200, 235), width=2)
    for x in (14, 24, 34):
        for y in range(8, 23, 2):
            if rng.random() < 0.5:
                draw.point((x, y), fill=(64, 220, 220, 160))
    return im


def blood() -> Image.Image:
    """핏물 40x32 — 바닥 고임+튀김. 호러층(F4/F5) 전용."""
    rng = random.Random(51)
    im = Image.new("RGBA", (40, 32), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    draw.ellipse((8, 18, 32, 30), fill=(106, 13, 13, 235))
    draw.ellipse((13, 21, 27, 28), fill=(140, 20, 20, 235))
    for x, l in ((10, 14), (20, 10), (29, 16)):
        for y in range(30 - l, 30):
            draw.point((x, y), fill=(106, 13, 13, 220))
    speckle(draw, rng, (2, 2, 38, 30), 45, [(106, 13, 13, 220)])
    return im


DECALS = {
    "grime_blob.png": grime_blob,
    "poster.png": poster,
    "rust.png": rust,
    "graffiti.png": graffiti,
    "blood.png": blood,
}


def main() -> int:
    if "--check" in sys.argv:
        missing = [k for k in DECALS if not (OUT / k).exists()]
        print("[dressing] check - missing: %s" % (missing if missing else "none"))
        return 0 if not missing else 1
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in DECALS.items():
        fn().save(OUT / name)
        print("[dressing] %s" % name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
