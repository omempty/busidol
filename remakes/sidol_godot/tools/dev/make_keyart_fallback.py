# -*- coding: utf-8 -*-
"""그림 폴백 생성 — **그림이 비면 늘 무언가는 나와야 한다**(2026-08-29 유저 방침).

키아트는 타일과 성격이 정반대다. 타일은 형태가 없어서(반복 텍스처, 이음매만 맞으면
된다) 프로그램이 그릴 수 있지만, 키아트는 **형태가 전부**다(인물·구도·표정).
그러니 절차 생성으로 진짜 키아트를 만들 수는 없다.

대신 **분위기 층**은 프로그램의 영역이다. 스펙 6장의 설명을 보면 상당 부분이 분위기다
— 폭우와 번개, 초록 CRT 스캔라인, 먼지 낀 시멘트, 고전압 스파크, 녹색 와이어프레임,
아침 햇살. 인물은 없지만 **화면이 비지는 않는다.**

두 갈래로 만든다.
  * **원작에 그 장면이 있으면 원작 그림을 쓴다.** scene_02_hp_room은 원작 `HP.PCX`가
    정확히 그 장면(HP실 단체 사진)이다. 절차 생성보다 고증이 낫다.
  * 나머지는 절차 생성 — 스펙 설명에서 고른 색과 요소로 분위기만 세운다.

진짜 납품이 오면 `assets/keyart/<id>.png`가 이긴다(CutscenePlayer가 그쪽을 먼저 본다).
폴백이 있다고 해서 미납품 경고가 사라지지는 않는다 — validate는 그대로 센다.

실행: python tools/dev/make_keyart_fallback.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "keyart", "_fallback")
REF = os.path.join(ROOT, "assets", "originals_ref")

# 스펙의 render_native. 픽셀 아트라 여기서 그리고 최종 확대는 게임이 한다.
W, H = 480, 270


def vgrad(top, bottom):
    im = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(im)
    for y in range(H):
        t = y / float(H - 1)
        d.line(
            [(0, y), (W, y)],
            fill=tuple(int(round(top[i] + (bottom[i] - top[i]) * t)) for i in range(3)),
        )
    return im


def vignette(im, power=0.55):
    px = im.load()
    cx, cy = W / 2.0, H / 2.0
    m = math.hypot(cx, cy)
    for y in range(H):
        for x in range(W):
            d = math.hypot(x - cx, y - cy) / m
            k = 1.0 - power * (d ** 2)
            r, g, b = px[x, y]
            px[x, y] = (int(r * k), int(g * k), int(b * k))
    return im


def silhouette(im, rnd, count, color, ymin, ymax):
    """건물·인영 실루엣 — 형태를 흉내 내지 않는다. **덩어리만** 세운다."""
    d = ImageDraw.Draw(im)
    for _ in range(count):
        w = rnd.randint(24, 78)
        x = rnd.randint(-20, W - 4)
        y = rnd.randint(ymin, ymax)
        d.rectangle([x, y, x + w, H], fill=color)
    return im


def rain(im, rnd, n=340, color=(180, 200, 230), slant=3):
    d = ImageDraw.Draw(im)
    for _ in range(n):
        x = rnd.randint(0, W)
        y = rnd.randint(0, H)
        ln = rnd.randint(6, 16)
        d.line([(x, y), (x - slant, y + ln)], fill=color, width=1)
    return im


def scanlines(im, step=3, k=0.82):
    px = im.load()
    for y in range(0, H, step):
        for x in range(W):
            r, g, b = px[x, y]
            px[x, y] = (int(r * k), int(g * k), int(b * k))
    return im


def sparks(im, rnd, n=90, color=(220, 240, 255)):
    d = ImageDraw.Draw(im)
    for _ in range(n):
        x, y = rnd.randint(0, W), rnd.randint(0, H)
        for _ in range(rnd.randint(2, 5)):
            nx, ny = x + rnd.randint(-9, 9), y + rnd.randint(-9, 9)
            d.line([(x, y), (nx, ny)], fill=color)
            x, y = nx, ny
    return im


def wireframe(im, rnd, color=(90, 240, 140)):
    d = ImageDraw.Draw(im)
    cx, cy = W // 2, H // 2 - 10
    for r in range(24, 130, 12):
        d.ellipse([cx - r, cy - int(r * 0.78), cx + r, cy + int(r * 0.78)], outline=color)
    for a in range(0, 180, 18):
        t = math.radians(a)
        d.line(
            [
                (cx - int(126 * math.cos(t)), cy - int(98 * math.sin(t))),
                (cx + int(126 * math.cos(t)), cy + int(98 * math.sin(t))),
            ],
            fill=color,
        )
    return im


def dust(im, rnd, n=520, color=(210, 200, 180)):
    px = im.load()
    for _ in range(n):
        x, y = rnd.randint(0, W - 1), rnd.randint(0, H - 1)
        r, g, b = px[x, y]
        px[x, y] = tuple(min(255, int(c * 0.4 + color[i] * 0.6)) for i, c in enumerate((r, g, b)))
    return im


def scene_01(rnd):
    im = vgrad((18, 22, 40), (44, 48, 66))
    im = silhouette(im, rnd, 7, (12, 14, 24), 120, 190)
    d = ImageDraw.Draw(im)
    d.rectangle([W // 2 - 46, 150, W // 2 + 46, H], fill=(26, 28, 40))  # 닫힌 셔터
    for y in range(154, H, 6):
        d.line([(W // 2 - 46, y), (W // 2 + 46, y)], fill=(38, 40, 54))
    d.line([(120, 0), (150, 46), (128, 44), (162, 104)], fill=(232, 238, 255), width=2)  # 번개
    im = rain(im, rnd)
    return vignette(im, 0.6)


def scene_03(rnd):
    im = vgrad((38, 36, 32), (22, 21, 19))
    d = ImageDraw.Draw(im)
    for x in range(20, W, 74):  # 캐비닛 열
        d.rectangle([x, 70, x + 54, H - 20], fill=(52, 48, 42), outline=(30, 28, 25))
        for y in range(78, H - 28, 18):
            d.rectangle([x + 6, y, x + 48, y + 12], fill=(64, 59, 51))
    im = dust(im, rnd)
    return vignette(im, 0.62)


def scene_04(rnd):
    im = vgrad((28, 26, 34), (16, 15, 20))
    d = ImageDraw.Draw(im)
    d.rectangle([W // 2 - 70, 60, W // 2 + 70, H - 30], fill=(40, 40, 48), outline=(70, 70, 80))
    for i in range(4):  # 레버 줄
        x = W // 2 - 46 + i * 30
        d.rectangle([x, 84, x + 14, 150], fill=(96, 90, 60))
    im = sparks(im, rnd)
    im = im.filter(ImageFilter.SMOOTH)
    return vignette(im, 0.5)


def scene_05(rnd):
    im = vgrad((6, 14, 10), (2, 6, 5))
    im = wireframe(im, rnd)
    im = scanlines(im, 3, 0.7)
    return vignette(im, 0.55)


def scene_06(rnd):
    im = vgrad((60, 72, 110), (232, 206, 152))
    d = ImageDraw.Draw(im)
    d.rectangle([40, 60, W - 40, H - 46], fill=(30, 32, 38), outline=(70, 72, 84))  # 모니터
    for y in range(70, H - 56, 7):  # 크레딧 줄
        w = rnd.randint(60, W - 140)
        d.line([(W // 2 - w // 2, y), (W // 2 + w // 2, y)], fill=(150, 210, 170))
    im = scanlines(im, 3, 0.88)
    return vignette(im, 0.45)


## 원작에 그 장면이 있는 것. 절차 생성보다 고증이 낫다.
FROM_ORIGINAL = {"scene_02_hp_room": "hp.png"}
PROCEDURAL = {
    "scene_01_prologue_rain": scene_01,
    "scene_03_basement_archive": scene_03,
    "scene_04_4f_sacrifice": scene_04,
    "scene_05_5f_sys_builder": scene_05,
    "scene_06_epilogue_2026": scene_06,
}


## 초상 폴백 — 이름표만 뜨고 말하는 사람이 없는 화면을 막는다.
## 얼굴을 흉내 내지 않는다. **누군가 거기 있다**만 말하는 실루엣이다.
def build_portrait_fallback():
    d_out = os.path.join(ROOT, "assets", "portraits")
    os.makedirs(d_out, exist_ok=True)
    S = 256
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    body = (58, 62, 78, 255)
    d.ellipse([S * 0.30, S * 0.14, S * 0.70, S * 0.56], fill=body)  # 머리
    d.pieslice([S * 0.12, S * 0.54, S * 0.88, S * 1.30], 180, 360, fill=body)  # 어깨
    im = im.filter(ImageFilter.SMOOTH)
    im.save(os.path.join(d_out, "_fallback.png"))
    return "_fallback(초상)"


def build():
    os.makedirs(OUT, exist_ok=True)
    made = []
    for art_id, ref in FROM_ORIGINAL.items():
        src = os.path.join(REF, ref)
        if not os.path.exists(src):
            continue
        im = Image.open(src).convert("RGB")
        # 원작 320x200을 480x270 화폭에 넣는다 — 늘리지 않고 중앙에 앉히고 여백은 어둡게.
        canvas = Image.new("RGB", (W, H), (10, 10, 14))
        k = min(W / im.width, H / im.height)
        big = im.resize((int(im.width * k), int(im.height * k)), Image.NEAREST)
        canvas.paste(big, ((W - big.width) // 2, (H - big.height) // 2))
        canvas.save(os.path.join(OUT, art_id + ".png"))
        made.append(art_id + "(원작)")
    for art_id, fn in PROCEDURAL.items():
        rnd = random.Random(hash(art_id) & 0xFFFF)
        fn(rnd).save(os.path.join(OUT, art_id + ".png"))
        made.append(art_id)
    made.append(build_portrait_fallback())
    print("[make_keyart_fallback] %d장: %s" % (len(made), ", ".join(made)))


if __name__ == "__main__":
    build()
