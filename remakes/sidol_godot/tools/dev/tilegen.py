# -*- coding: utf-8 -*-
"""바닥·벽 타일 절차 생성 — 32x32 네이티브, 이음매 없음(seamless), 변종 다수.

왜 프로그램으로 찍는가(외부 의뢰 대신):
  * 이음매가 **수학적으로** 보장된다. 반복 텍스처는 한 픽셀만 어긋나도 화면 전체에
    격자가 뜨는데, 큰 그림을 받아 32칸으로 자르는 방식으로는 이걸 못 맞춘다.
  * 지금 아틀라스는 원작 12x12 도트를 32px로 키운 것이라 뭉개져 있다. 32px 네이티브로
    다시 찍는 것만으로 실효 해상도가 2.7배 오른다.
  * 한 벌이 아니라 **변종 N벌**이 필요하다(같은 id를 셀 좌표 해시로 갈아 끼워 격자감을
    깬다). 변종은 시드만 바꾸면 되는 일이라 손그림보다 프로그램이 압도적으로 싸다.
  * 마음에 안 들면 숫자만 바꿔 다시 뽑는다. 의뢰 왕복이 없다.

형태가 있는 것(인물·오브젝트·키아트)은 여전히 외부 의뢰가 낫다. 여기는 반복 텍스처 전용.
"""
import math
import random

SIZE = 32


def _lerp(a, b, t):
    return a + (b - a) * t


def _smooth(t):
    return t * t * (3.0 - 2.0 * t)


def seamless_noise(size, period, seed):
    """주기 격자 값노이즈 — 격자를 size로 나누어 떨어지게 잡아 이음매가 없다."""
    rnd = random.Random(seed)
    g = [[rnd.random() for _ in range(period)] for _ in range(period)]
    step = size / float(period)
    out = [[0.0] * size for _ in range(size)]
    for y in range(size):
        fy = y / step
        y0 = int(fy) % period
        y1 = (y0 + 1) % period
        ty = _smooth(fy - int(fy))
        for x in range(size):
            fx = x / step
            x0 = int(fx) % period
            x1 = (x0 + 1) % period
            tx = _smooth(fx - int(fx))
            top = _lerp(g[y0][x0], g[y0][x1], tx)
            bot = _lerp(g[y1][x0], g[y1][x1], tx)
            out[y][x] = _lerp(top, bot, ty)
    return out


def fbm(size, seed, octaves=3, period=4):
    acc = [[0.0] * size for _ in range(size)]
    amp, total = 1.0, 0.0
    for o in range(octaves):
        n = seamless_noise(size, period * (2 ** o), seed + o * 977)
        for y in range(size):
            for x in range(size):
                acc[y][x] += n[y][x] * amp
        total += amp
        amp *= 0.5
    for y in range(size):
        for x in range(size):
            acc[y][x] /= total
    return acc


def shade(rgb, k):
    return tuple(max(0, min(255, int(round(c * k)))) for c in rgb)


def mix(a, b, t):
    return tuple(int(round(_lerp(a[i], b[i], t))) for i in range(3))


# ---------------------------------------------------------------------------
# 타일 종류. 원작의 **재질과 색조는 지키고** 해상도·명암·변종만 올린다 —
# 큰 문맥은 원작, 세세한 연출은 현대화(AGENTS.md 방침).
# ---------------------------------------------------------------------------


def floor_grain(base, seed, grain=0.10, warm=None):
    """단색 바닥 — 미세 결만 있는 것. 격자가 절대 안 보여야 한다."""
    px = [[None] * SIZE for _ in range(SIZE)]
    n = fbm(SIZE, seed, octaves=3, period=4)
    n2 = fbm(SIZE, seed + 4211, octaves=2, period=8)
    for y in range(SIZE):
        for x in range(SIZE):
            k = 1.0 + (n[y][x] - 0.5) * grain * 2.0
            c = shade(base, k)
            if warm is not None:
                c = mix(c, warm, max(0.0, (n2[y][x] - 0.62)) * 0.9)
            px[y][x] = c
    return px


def floor_checker(light, dark, seed, cell=16, bevel=0.16, grain=0.12):
    """체커 바닥(원작 id 8) — 판 경계를 살리되 결을 넣어 인쇄물 느낌을 없앤다."""
    px = [[None] * SIZE for _ in range(SIZE)]
    n = fbm(SIZE, seed, octaves=3, period=4)
    for y in range(SIZE):
        for x in range(SIZE):
            on = ((x // cell) + (y // cell)) % 2 == 0
            base = light if on else dark
            k = 1.0 + (n[y][x] - 0.5) * grain
            # 판 안쪽 베벨 — 위/왼쪽은 밝게, 아래/오른쪽은 어둡게(빛이 좌상에서 온다)
            ix, iy = x % cell, y % cell
            if ix == 0 or iy == 0:
                k += bevel
            elif ix == cell - 1 or iy == cell - 1:
                k -= bevel
            px[y][x] = shade(base, k)
    return px


def brick(base, mortar, seed, bh=8, bw=16, offset=True):
    """벽돌 벽 — 줄눈이 타일 경계에서 이어지도록 주기를 32의 약수로 잡는다."""
    px = [[None] * SIZE for _ in range(SIZE)]
    n = fbm(SIZE, seed, octaves=3, period=4)
    rnd = random.Random(seed)
    tone = {}
    for y in range(SIZE):
        row = y // bh
        shift = (bw // 2) if (offset and row % 2 == 1) else 0
        for x in range(SIZE):
            bx = (x + shift) % SIZE
            col = bx // bw
            key = (row, col)
            if key not in tone:
                tone[key] = 1.0 + (rnd.random() - 0.5) * 0.18
            iy, ix = y % bh, bx % bw
            if iy == 0 or ix == 0:
                px[y][x] = shade(mortar, 1.0 + (n[y][x] - 0.5) * 0.10)
                continue
            k = tone[key] + (n[y][x] - 0.5) * 0.14
            if iy == 1 or ix == 1:
                k += 0.14  # 좌상 하이라이트
            elif iy == bh - 1 or ix == bw - 1:
                k -= 0.16  # 우하 그림자
            px[y][x] = shade(base, k)
    return px


def cobble(base, mortar, seed, cell=8):
    """돌 벽(원작 id 22) — 낱돌마다 색을 흔들어 32px 반복을 눈에 안 띄게 한다."""
    px = [[None] * SIZE for _ in range(SIZE)]
    n = fbm(SIZE, seed, octaves=3, period=8)
    rnd = random.Random(seed)
    tone = {}
    for y in range(SIZE):
        for x in range(SIZE):
            gx, gy = x // cell, y // cell
            if (gx, gy) not in tone:
                tone[(gx, gy)] = 1.0 + (rnd.random() - 0.5) * 0.26
            ix, iy = x % cell, y % cell
            edge = ix == 0 or iy == 0
            wob = (n[y][x] - 0.5) * 2.2
            if not edge and (ix == cell - 1 or iy == cell - 1) and wob < 0.35:
                edge = True
            if edge:
                px[y][x] = shade(mortar, 1.0 + (n[y][x] - 0.5) * 0.12)
                continue
            k = tone[(gx, gy)] + (n[y][x] - 0.5) * 0.18
            if ix <= 1 or iy <= 1:
                k += 0.12
            px[y][x] = shade(base, k)
    return px


def luminance(px):
    tot = 0
    for row in px:
        for c in row:
            tot += 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
    return tot / float(SIZE * SIZE)


def normalize(variants):
    """변종들의 평균 밝기를 맞춘다.

    **이걸 안 하면 변종 경계가 사각 얼룩으로 보인다.** 시드만 바꿔 뽑은 변종은
    전체 밝기가 조금씩 달라서, 32px 격자마다 밝기 계단이 생겨 오히려 원래보다
    격자가 더 눈에 띈다(첫 프로토타입에서 id 10·9·40이 그랬다).
    """
    if not variants:
        return variants
    target = sum(luminance(v) for v in variants) / float(len(variants))
    out = []
    for v in variants:
        k = target / max(1e-6, luminance(v))
        out.append([[shade(c, k) for c in row] for row in v])
    return out


def wall_shade(px, top=0.20, bottom=-0.22):
    """벽 전용 마감 — 위를 밝게, 아래를 어둡게. 바닥과 같은 밝기면 공간감이 없다."""
    out = []
    for y in range(SIZE):
        t = y / float(SIZE - 1)
        k = 1.0 + _lerp(top, bottom, t)
        out.append([shade(c, k) for c in px[y]])
    return out


def planks(base, seam, seed, ph=8):
    """나무 판자 벽(원작 id 1) — 결이 가로로 흐른다."""
    px = [[None] * SIZE for _ in range(SIZE)]
    rnd = random.Random(seed)
    n = fbm(SIZE, seed, octaves=2, period=2)
    grain = fbm(SIZE, seed + 31, octaves=3, period=16)
    tone = {}
    for y in range(SIZE):
        row = y // ph
        if row not in tone:
            tone[row] = 1.0 + (rnd.random() - 0.5) * 0.16
        for x in range(SIZE):
            iy = y % ph
            if iy == 0:
                px[y][x] = shade(seam, 1.0 + (n[y][x] - 0.5) * 0.1)
                continue
            k = tone[row] + (grain[y][x] - 0.5) * 0.22 + (n[y][x] - 0.5) * 0.06
            if iy == 1:
                k += 0.10
            elif iy == ph - 1:
                k -= 0.12
            px[y][x] = shade(base, k)
    return px


def void_floor(base, seed, grain=0.5):
    """거의 검은 바닥(원작 id 29 — 걸어다닐 수 있는 어둠).

    원작은 순수 검정 한 색이었다. 16%가 이 타일이라 화면의 큰 덩어리가 통째로
    비어 보였다. 검기는 그대로 두되 **아주 옅은 결**만 넣어 면이 살아 있게 한다.
    """
    px = [[None] * SIZE for _ in range(SIZE)]
    n = fbm(SIZE, seed, octaves=3, period=4)
    for y in range(SIZE):
        for x in range(SIZE):
            px[y][x] = shade(base, 1.0 + (n[y][x] - 0.5) * grain * 2.0)
    return px


def desaturate(rgb, amount, lift=0.0):
    """채도를 깎고 밝기를 살짝 당긴다 — 90년대 VGA 형광색을 눌러 앉히는 데 쓴다."""
    g = 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]
    out = mix(rgb, (g, g, g), amount)
    return shade(out, 1.0 + lift)


def from_column_profile(columns, seed, grain=0.08):
    """원작 타일의 **세로 구조를 그대로 살리고** 결만 얹는다.

    무늬가 의미를 가진 타일에 쓴다 — id 9(f5 바닥이자 f1의 문)의 세로줄을 지웠더니
    벽에 뚫려 있던 문이 통째로 사라졌다. 구조는 원작 것을 쓰고 톤만 손본다.
    columns: 길이 SIZE의 열별 색 목록.
    """
    px = [[None] * SIZE for _ in range(SIZE)]
    n = fbm(SIZE, seed, octaves=3, period=8)
    for y in range(SIZE):
        for x in range(SIZE):
            px[y][x] = shade(columns[x], 1.0 + (n[y][x] - 0.5) * grain * 2.0)
    return px


def auto_remaster(tile, seed, grain=0.10, sat=0.30, keep=52.0):
    """**무엇을 그린 것인지 모르는 타일**을 안전하게 손보는 길.

    맵에 쓰이는 89종 중 14종이 화면의 94%다. 나머지는 장식·지하 벽 조각인데, 이게
    무엇을 그린 것인지 코드가 알 수 없으므로 다시 그리면 뜻을 잃는다(id 9의 세로줄을
    지웠더니 문이 사라진 것과 같은 사고). 그래서 **구조는 한 픽셀도 옮기지 않고**
    두 가지만 한다.

      * 형광색을 눌러 앉힌다 — 90년대 VGA 팔레트가 지금 화면에서 튄다. 다만 **원래
        채도가 낮은 픽셀은 건드리지 않는다**(keep 아래는 그대로). 회색 돌을 더 회색으로
        만들 이유가 없다.
      * 아주 옅은 결을 얹는다 — 평평한 면이 죽어 보이는 것을 살린다. 세기는 그 타일이
        **원래 얼마나 복잡한가**에 반비례한다: 이미 무늬가 빽빽한 타일에 결을 더하면
        지저분해지기만 한다.

    tile: 32x32 RGB 픽셀 목록의 목록.
    """
    lum = [0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2] for row in tile for c in row]
    mean = sum(lum) / len(lum)
    dev = (sum((v - mean) ** 2 for v in lum) / len(lum)) ** 0.5
    busy = min(1.0, dev / 40.0)
    amp = grain * (1.0 - busy * 0.85)
    n = fbm(SIZE, seed, octaves=3, period=4)
    out = [[None] * SIZE for _ in range(SIZE)]
    for y in range(SIZE):
        for x in range(SIZE):
            c = tile[y][x]
            chroma = max(c) - min(c)
            if chroma > keep:
                t = min(1.0, (chroma - keep) / 120.0) * sat
                c = desaturate(c, t)
            out[y][x] = shade(c, 1.0 + (n[y][x] - 0.5) * amp * 2.0)
    return out
