# -*- coding: utf-8 -*-
"""시각 플레이스홀더 생성 — **그림이 비면 늘 무언가는 나와야 한다**(2026-08-29 유저 방침).

`make_keyart_fallback.py`와 같은 갈래의 도구다. 그쪽이 컷신 배경(분위기)을 맡고
여기는 **대화 초상 · 아이템 아이콘 · 전투 이펙트** 셋을 맡는다. 셋을 고른 기준은
「계약이 명확하고, 절차 생성이 어울리는가」다.

  초상      768×256(256 셀 3개 = 표정 3종). 얼굴은 절차로 못 그리지만 **누가 말하고
            있는지**는 실루엣·머리색·표정 변화만으로도 전달된다. 없으면 대화창에
            얼굴 자리가 통째로 접힌다(PortraitLibrary).
  아이템    96×96. 없으면 색 상자 + 글자가 나온다. 무기/방어구/소모품의 **꼴**만
            달라도 가방과 상점에서 훑어보는 속도가 달라진다.
  이펙트    <id>.png(셀 정사각 가로 스트립) + <id>.json. 이건 절차 생성이 **원래
            어울리는** 대상이다 — 불꽃·전격·충격파는 형태가 아니라 운동이다.
            없으면 물리·화염·전격이 전부 같은 흰 점 파티클로 나온다.

일부러 빼놓은 것:
  * 컷신 키아트 — `make_keyart_fallback.py`가 이미 6/6 만들어 뒀다.
  * 몬스터·NPC 스프라이트 시트 — `monster_anim_specs.json`의 행/열 계약이 종마다
    달라 잘못 만들면 "그림이 없다"보다 나쁜 "틀린 그림이 움직인다"가 된다.
  * 전투 대형 컷 — 미납품이면 조용히 건너뛰고 기존 도트 연출이 그대로 돈다.
    즉 지금도 화면이 비지 않는다.

**진짜 납품이 오면 그쪽이 이긴다** — 이 스크립트는 이미 있는 파일을 덮지 않는다
(`--force`로만 덮는다). 미납품 경고도 그대로 남는다(asset_status는 그대로 센다).

색은 id 해시로 정해 **재실행해도 같은 그림**이 나온다(`make_placeholder_assets.py` 규약).

실행: python tools/dev/make_visual_placeholders.py [--force] [--only portraits,icons,effects]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys

from PIL import Image, ImageDraw, PngImagePlugin

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# 스타일 바이블: 외곽선은 순수 블랙 금지 — 짙은 남색 계열.
OUTLINE = (26, 22, 42, 255)
SHADOW = (58, 46, 84, 255)


# 생성물에 박는 표식. **`--force`는 이 표식이 있는 파일만 덮는다.**
# 표식 없이 만들었다가 방금 설치한 진짜 납품 초상 9장을 --force로 날렸다(2026-09-06).
# 플레이스홀더 생성기가 납품물을 덮을 수 있으면 그것은 생성기가 아니라 사고다.
PLACEHOLDER_KEY = "sidol_placeholder"
PLACEHOLDER_VAL = "make_visual_placeholders.py"


def is_placeholder(path: str) -> bool:
    try:
        with Image.open(path) as im:
            return im.info.get(PLACEHOLDER_KEY) == PLACEHOLDER_VAL
    except Exception:
        return False


def save_marked(im: Image.Image, path: str) -> None:
    meta = PngImagePlugin.PngInfo()
    meta.add_text(PLACEHOLDER_KEY, PLACEHOLDER_VAL)
    im.save(path, pnginfo=meta)


## 덮어써도 되는가 — 없으면 만들고, 있으면 **내가 만든 것일 때만** 덮는다.
def may_write(path: str, force: bool) -> bool:
    if not os.path.exists(path):
        return True
    if not force:
        return False
    if is_placeholder(path):
        return True
    out("  [보호] %s — 납품물이라 덮지 않는다" % os.path.basename(path))
    return False


def out(msg: str) -> None:
    sys.stdout.write(msg + "\n")


def seed_of(key: str) -> int:
    return int(hashlib.md5(key.encode("utf-8")).hexdigest()[:8], 16)


def hsv(h: float, s: float, v: float, a: int = 255):
    """0~1 HSV → RGBA. 팔레트를 파일에서 읽지 않는 이유는 이것이 '임시 그림'이기
    때문이다 — palette_master를 따르면 진짜 납품과 구별이 안 돼 교체를 잊는다."""
    i = int(h * 6.0) % 6
    f = h * 6.0 - int(h * 6.0)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    r, g, b = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
    return (int(r * 255), int(g * 255), int(b * 255), a)


def shade(c, k):
    return (int(c[0] * k), int(c[1] * k), int(c[2] * k), c[3])


# ─────────────────────────────────────────────────────────── 초상


# 표정 이름은 스펙마다 다르다(annoyed·shout·stern·scheming·drunk·sleepy·coughing…).
# 목록을 코드에 박으면 스펙이 늘 때마다 조용히 「전부 무표정」이 된다 — 실제로 처음
# 그렇게 만들었다가 3칸이 똑같이 나왔다(2026-09-06). 그래서 **이름 해시로** 눈썹·눈·입을
# 고른다. 무엇이 나올지는 정확하지 않아도 **세 칸이 서로 다르다**는 것은 보장된다.
BROW = [0, 2, -2, 1, -1]      # +면 처진(화남/피곤), -면 올라간(놀람)
MOUTH = ["flat", "frown", "open", "grin", "wobble"]


def expr_shape(expr: str, index: int):
    if index == 0:
        return 0, "flat", False       # 첫 칸은 언제나 무표정 — 기본 얼굴이 흔들리면 안 된다
    h = seed_of(expr or ("e%d" % index))
    return BROW[h % len(BROW)], MOUTH[(h >> 4) % len(MOUTH)], bool((h >> 9) & 1)


def portrait_cell(aid: str, expr: str, index: int = 0, size: int = 256) -> Image.Image:
    """한 표정 칸. 정면 흉상 — 어깨·목·머리·머리카락·눈·입.
    형태(머리 모양·색)는 aid가 정하고, 표정만 칸마다 바뀐다."""
    s = seed_of(aid)
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    hue = ((s >> 3) % 360) / 360.0
    skin = hsv(0.07 + ((s >> 11) % 5) * 0.004, 0.34, 0.90)
    hair = hsv(hue, 0.55, 0.28 + ((s >> 7) % 4) * 0.07)
    cloth = hsv((hue + 0.45) % 1.0, 0.45, 0.58)
    u = size / 64.0  # 64px 도트를 그린다는 감각으로 좌표를 잡는다

    def R(x0, y0, x1, y1, c):
        d.rectangle([x0 * u, y0 * u, x1 * u - 1, y1 * u - 1], fill=c)

    def P(pts, c):
        d.polygon([(x * u, y * u) for x, y in pts], fill=c)

    brow_dy, mouth, blush = expr_shape(expr, index)

    # 어깨 — 사다리꼴로 목과 이어 붙인다. 사각 막대로 그렸더니 머리와 끊겨 보였다.
    P([(2, 64), (12, 46), (52, 46), (62, 64)], OUTLINE)
    P([(4, 64), (13, 48), (51, 48), (60, 64)], cloth)
    P([(4, 64), (13, 48), (24, 48), (18, 64)], shade(cloth, 1.16))
    # 깃 — 옷이라는 것이 읽히도록
    P([(26, 47), (38, 47), (32, 57)], OUTLINE)
    P([(27, 48), (37, 48), (32, 55)], shade(cloth, 0.72))
    # 목
    R(26, 41, 38, 50, OUTLINE)
    R(27, 42, 37, 50, shade(skin, 0.78))
    # 머리 — 화면을 채우도록 키웠다(구판은 흉상이 작아 여백만 넓었다)
    R(15, 6, 49, 45, OUTLINE)
    R(16, 7, 48, 44, skin)
    R(16, 7, 48, 16, shade(skin, 1.07))
    R(16, 38, 48, 44, shade(skin, 0.86))
    # 귀
    R(13, 24, 17, 32, OUTLINE)
    R(14, 25, 16, 31, shade(skin, 0.92))
    R(47, 24, 51, 32, OUTLINE)
    R(48, 25, 50, 31, shade(skin, 0.92))
    # 머리카락 — 해시로 앞머리 모양 셋 중 하나
    style = s % 3
    R(14, 3, 50, 16, OUTLINE)
    R(15, 4, 49, 15, hair)
    if style == 0:
        R(15, 13, 30, 19, hair)
    elif style == 1:
        R(15, 13, 49, 18, hair)
        R(30, 16, 35, 22, shade(hair, 1.25))
    else:
        R(15, 13, 21, 30, hair)
        R(43, 13, 49, 30, hair)
    R(15, 4, 49, 7, shade(hair, 1.3))

    # 눈·눈썹
    eye_y = 24
    for ex in (21, 36):
        R(ex - 2, eye_y + brow_dy - 3, ex + 8, eye_y + brow_dy - 2, shade(hair, 0.8))
        R(ex, eye_y, ex + 6, eye_y + 6, OUTLINE)
        R(ex + 1, eye_y + 1, ex + 5, eye_y + 5, (250, 250, 255, 255))
        pup_y = eye_y + (1 if mouth == "open" else 2)
        R(ex + 2, pup_y, ex + 5, pup_y + 3, OUTLINE)
    if blush:
        R(18, 33, 24, 35, shade(skin, 0.80))
        R(40, 33, 46, 35, shade(skin, 0.80))
    # 입
    if mouth == "open":
        R(28, 35, 36, 41, OUTLINE)
        R(29, 36, 35, 40, (120, 40, 50, 255))
    elif mouth == "frown":
        R(27, 38, 37, 39, OUTLINE)
        R(26, 37, 28, 38, OUTLINE)
        R(36, 37, 38, 38, OUTLINE)
    elif mouth == "grin":
        R(26, 36, 38, 38, OUTLINE)
        R(27, 37, 37, 39, (250, 250, 255, 255))
    elif mouth == "wobble":
        R(27, 37, 31, 38, OUTLINE)
        R(31, 38, 35, 39, OUTLINE)
        R(35, 37, 38, 38, OUTLINE)
    else:
        R(28, 37, 36, 38, shade(skin, 0.60))
    return im


def gen_portraits(force: bool) -> int:
    spec_dir = os.path.join(ROOT, "assets", "spec", "portraits")
    dst_dir = os.path.join(ROOT, "assets", "portraits")
    if not os.path.isdir(spec_dir):
        out("  [초상] 스펙 디렉터리 없음 — 건너뜀")
        return 0
    made = 0
    for name in sorted(os.listdir(spec_dir)):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(spec_dir, name), encoding="utf-8") as fh:
            spec = json.load(fh)
        aid = str(spec.get("asset_id", name[:-5]))
        exprs = list(spec.get("expressions", ["normal"]))[:3] or ["normal"]
        dst = os.path.join(dst_dir, aid + ".png")
        if not may_write(dst, force):
            continue
        sheet = Image.new("RGBA", (256 * 3, 256), (0, 0, 0, 0))
        for i in range(3):
            e = exprs[min(i, len(exprs) - 1)]
            sheet.paste(portrait_cell(aid, e, i), (256 * i, 0))
        save_marked(sheet, dst)
        out("  [초상] %-22s %s" % (aid, "/".join(exprs)))
        made += 1
    return made


# ─────────────────────────────────────────────────────────── 아이템 아이콘


def icon_image(item_id: str, kind: str, size: int = 96) -> Image.Image:
    """96×96 아이콘. 종류로 **꼴**을 나누고 id 해시로 색을 나눈다 —
    가방을 훑을 때 글자를 읽기 전에 무기/방어구/약이 구분되는 것이 목적이다."""
    s = seed_of(item_id)
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    hue = ((s >> 5) % 360) / 360.0
    main = hsv(hue, 0.55, 0.86)
    dark = shade(main, 0.55)
    lite = shade(main, 1.15)
    u = size / 24.0

    def R(x0, y0, x1, y1, c):
        d.rectangle([x0 * u, y0 * u, x1 * u - 1, y1 * u - 1], fill=c)

    def P(pts, c):
        d.polygon([(x * u, y * u) for x, y in pts], fill=c)

    k = (kind or "").upper()
    if "WEAPON" in k:
        # 자루 + 날 — 대각 실루엣
        P([(4, 20), (8, 20), (20, 6), (20, 3), (17, 3), (4, 16)], OUTLINE)
        P([(5, 19), (8, 19), (19, 5), (18, 4), (5, 17)], main)
        P([(5, 19), (7, 19), (17, 6), (16, 5), (5, 18)], lite)
        R(3, 18, 8, 22, OUTLINE)
        R(4, 19, 7, 21, dark)
    elif "ARMOR" in k:
        # 방패꼴 흉갑
        P([(6, 4), (18, 4), (18, 13), (12, 21), (6, 13)], OUTLINE)
        P([(7, 5), (17, 5), (17, 13), (12, 19), (7, 13)], main)
        P([(7, 5), (12, 5), (12, 19), (7, 13)], lite)
        R(9, 8, 15, 10, dark)
    elif "WATER" in k or "DRINK" in k or "TEA" in k or "JU" in k:
        # 병
        R(10, 3, 14, 7, OUTLINE)
        R(7, 7, 17, 21, OUTLINE)
        R(8, 8, 16, 20, main)
        R(8, 12, 16, 20, dark)
        R(9, 9, 11, 19, lite)
    else:
        # 약봉지/일반 — 모서리 접힌 사각
        R(5, 5, 19, 20, OUTLINE)
        R(6, 6, 18, 19, main)
        R(6, 6, 18, 10, lite)
        R(11, 9, 13, 17, dark)
        R(8, 12, 16, 14, dark)
    return im


def gen_icons(force: bool) -> int:
    items_path = os.path.join(ROOT, "data", "items.json")
    dst_dir = os.path.join(ROOT, "assets", "icons")
    if not os.path.exists(items_path):
        out("  [아이콘] items.json 없음 — 건너뜀")
        return 0
    os.makedirs(dst_dir, exist_ok=True)
    with open(items_path, encoding="utf-8") as fh:
        raw = json.load(fh)
    items = raw.get("items", raw)
    seq = items.items() if isinstance(items, dict) else [(x.get("id"), x) for x in items]
    made = 0
    for iid, idef in sorted(seq):
        if not iid or str(iid).startswith("_"):
            continue
        dst = os.path.join(dst_dir, str(iid) + ".png")
        if not may_write(dst, force):
            continue
        kind = str(idef.get("kind", idef.get("category", ""))) + " " + str(iid)
        save_marked(icon_image(str(iid), kind), dst)
        made += 1
    if made:
        out("  [아이콘] %d종" % made)
    return made


# ─────────────────────────────────────────────────────────── 전투 이펙트

# id → (색상 hue, 꼴). 꼴은 data/effect_specs.json의 이름에서 읽히는 성격 그대로.
EFFECTS = {
    "hit_spark": (0.13, "burst"),
    "flame_burst": (0.04, "flame"),
    "volt_arc": (0.62, "arc"),
    "blast": (0.02, "ring"),
    "shield_up": (0.52, "ring"),
}
FX_CELL = 128
FX_FRAMES = 6


def fx_frame(kind: str, hue: float, t: float, cell: int = FX_CELL) -> Image.Image:
    """t=0~1 진행도. 형태가 아니라 **운동**을 그린다 — 그래서 절차 생성이 어울린다."""
    im = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = cell / 2.0
    fade = int(255 * (1.0 - t * t))
    core = hsv(hue, 0.35, 1.0, fade)
    edge = hsv(hue, 0.85, 0.95, fade)
    if kind == "ring":
        r = 8 + t * (c - 12)
        w = max(2, int(10 * (1.0 - t)))
        d.ellipse([c - r, c - r, c + r, c + r], outline=edge, width=w)
        d.ellipse([c - r * 0.6, c - r * 0.6, c + r * 0.6, c + r * 0.6], outline=core, width=max(1, w // 2))
    elif kind == "burst":
        for i in range(8):
            a = i * math.pi / 4.0 + t * 0.6
            r0, r1 = 6 + t * 22, 14 + t * (c - 18)
            d.line(
                [c + math.cos(a) * r0, c + math.sin(a) * r0, c + math.cos(a) * r1, c + math.sin(a) * r1],
                fill=edge,
                width=max(2, int(7 * (1 - t))),
            )
        d.ellipse([c - 10 + t * 6, c - 10 + t * 6, c + 10 - t * 6, c + 10 - t * 6], fill=core)
    elif kind == "flame":
        for i in range(7):
            a = (i / 7.0) * math.tau
            rr = 12 + t * 34 + ((i * 37) % 11)
            x, y = c + math.cos(a) * rr * 0.7, c + math.sin(a) * rr - t * 26
            s2 = max(3, int(20 * (1 - t)))
            d.ellipse([x - s2, y - s2, x + s2, y + s2], fill=edge if i % 2 else core)
    else:  # arc — 지그재그 낙뢰
        x, y = c, 6.0
        pts = [(x, y)]
        for i in range(7):
            x += (-1 if (i + int(t * 5)) % 2 else 1) * (10 + (i * 5) % 13)
            y += (cell - 12) / 7.0
            pts.append((x, y))
        d.line(pts, fill=edge, width=max(2, int(8 * (1 - t))))
        d.line([(px + 3, py) for px, py in pts], fill=core, width=max(1, int(4 * (1 - t))))
    return im


def gen_effects(force: bool) -> int:
    dst_dir = os.path.join(ROOT, "assets", "effects")
    os.makedirs(dst_dir, exist_ok=True)
    made = 0
    for fx_id, (hue, kind) in sorted(EFFECTS.items()):
        png = os.path.join(dst_dir, fx_id + ".png")
        if not may_write(png, force):
            continue
        strip = Image.new("RGBA", (FX_CELL * FX_FRAMES, FX_CELL), (0, 0, 0, 0))
        for i in range(FX_FRAMES):
            strip.paste(fx_frame(kind, hue, i / float(FX_FRAMES - 1)), (FX_CELL * i, 0))
        save_marked(strip, png)
        meta = {
            "_comment": "플레이스홀더 — tools/dev/make_visual_placeholders.py 생성. 납품이 오면 덮어쓴다.",
            "cell": FX_CELL,
            "animations": {"play": {"row": 0, "frames": FX_FRAMES, "fps": 14}},
        }
        with open(os.path.join(dst_dir, fx_id + ".json"), "w", encoding="utf-8", newline="\n") as fh:
            json.dump(meta, fh, ensure_ascii=False, indent=2)
        out("  [이펙트] %-14s %d프레임 %dpx" % (fx_id, FX_FRAMES, FX_CELL))
        made += 1
    return made


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="이미 있는 파일도 덮어쓴다")
    ap.add_argument("--only", default="portraits,icons,effects")
    args = ap.parse_args()
    only = {x.strip() for x in args.only.split(",")}
    out("[placeholders] 시작 (force=%s)" % args.force)
    total = 0
    if "portraits" in only:
        total += gen_portraits(args.force)
    if "icons" in only:
        total += gen_icons(args.force)
    if "effects" in only:
        total += gen_effects(args.force)
    out("[placeholders] %d개 생성" % total)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
