#!/usr/bin/env python3
"""아이템 아이콘 납품물 규격 정규화 — 크기가 어긋난 납품을 96×96으로 되돌린다.

이미지 생성 모델은 "정확히 96×96"을 지켜 주지 않는다(실납품에서 반복 확인).
프롬프트를 조여도 한계가 있어, **크기만큼은 후처리로 강제**한다.
반려 사유에서 "크기 틀림"을 지우면 심사는 그림 자체(톤·형태)에만 집중할 수 있다.

하는 일:
  1. 마젠타(#FF00FF) 배경 → 투명 키잉
  2. 내용 경계 트림 후 **여백 비율을 규격에 맞춰** 재배치(가장자리 6px 확보)
  3. 정수 배율이면 nearest, 아니면 box 축소 — 도트가 흐려지지 않게
  4. 반투명 픽셀 정리(임계값 이분화) — 원작·기존 아이콘의 AA 비율은 0%다

원본은 건드리지 않는다. `_normalized.png` 접미로 옆에 쓰고, --inplace면 덮어쓴다.

실행: python tools/convert/normalize_icon.py <png...> [--inplace]
"""
from __future__ import annotations

import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import numpy as np
from PIL import Image

ICON_PX = 96
SAFE_PAD = 6  # 가장자리 여백 — 작게 축소돼도 형태가 뭉개지지 않게
ALPHA_CUT = 128  # 이 값 미만은 완전 투명, 이상은 완전 불투명
MAGENTA_TOL = 90


def key_magenta(im: Image.Image) -> Image.Image:
    a = np.asarray(im.convert("RGBA")).astype(int)
    rgb, alpha = a[:, :, :3], a[:, :, 3]
    dist = np.abs(rgb - np.array([255, 0, 255])).sum(axis=2)
    alpha[dist < MAGENTA_TOL] = 0
    a[:, :, 3] = alpha
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def harden_alpha(im: Image.Image) -> Image.Image:
    a = np.asarray(im).copy()
    a[:, :, 3] = np.where(a[:, :, 3] >= ALPHA_CUT, 255, 0)
    return Image.fromarray(a, "RGBA")


def normalize(path: str, out_path: str) -> str:
    im = key_magenta(Image.open(path).convert("RGBA"))
    bbox = im.getbbox()
    if bbox is None:
        return "빈 이미지 — 건너뜀"
    content = im.crop(bbox)
    target = ICON_PX - SAFE_PAD * 2
    w, h = content.size
    scale = min(target / w, target / h)
    new_w, new_h = max(1, round(w * scale)), max(1, round(h * scale))
    # 정수 배율이면 nearest(도트 보존), 축소는 box가 덜 뭉갠다
    resample = Image.NEAREST if abs(scale - round(scale)) < 0.01 else Image.BOX
    content = content.resize((new_w, new_h), resample)

    canvas = Image.new("RGBA", (ICON_PX, ICON_PX), (0, 0, 0, 0))
    canvas.paste(content, ((ICON_PX - new_w) // 2, (ICON_PX - new_h) // 2))
    canvas = harden_alpha(canvas)
    canvas.save(out_path)
    return "%dx%d → %dx%d (내용 %dx%d, 배율 %.2f)" % (
        im.width, im.height, ICON_PX, ICON_PX, w, h, scale
    )


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    inplace = "--inplace" in sys.argv
    if not args:
        raise SystemExit(__doc__)
    for path in args:
        if not os.path.exists(path):
            print("없음: %s" % path)
            continue
        out = path if inplace else path[:-4] + "_normalized.png"
        print("%s: %s" % (os.path.basename(path), normalize(path, out)))


if __name__ == "__main__":
    main()
