"""원본 스프라이트 시범 리터칭 - Phase 8 샘플 파이프라인.

스타일 바이블 준수 방식(2026-08-24 개정):
  - 팔레트: 각 스프라이트의 **원본 색상 세트**에 스냅한다.
    (palette_master.json은 DEFAULT.PAL 기본 VGA DAC이라 처음 16색이 EGA색 +
     나머지가 어두운 램프 -> 여기로 스냅하면 EGA풍으로 붕괴. 검증된 교훈.)
    따라서 팔레트 잠금의 의미는 "외래 색 유입 금지"로 해석하고 원본 팔레트를 쓴다.
  - 명암: 5단 밴딩, 그림자는 색조 그림자(남보라 계열, 블랙 금지)
  - 외곽선: 1px 다크아웃라인(짙은 남색)
  - 구도/실루엣은 원작 그대로(지오메트리 변경 없음)

원본 보호 규칙(손실 대비 복원 대안):
  - 소스(originals_ref/bmp_spr)는 절대 쓰지 않는다. 읽기만 한다.
  - 최초 실행 시 소스 전체 SHA256 베이스라인을 OUT/SOURCES.sha256 에 기록.
  - 이후 실행마다 재해시하여 불일치가 하나라도 있으면 즉시 중단(복원 안내 출력).
    복원: git checkout -- assets/originals_ref
  - 산출물은 전부 assets/gen/viewers/samples/ 아래에만 기록한다.

처리 체계(절차적):
  1) 배경 제거: 모서리 색 flood-fill 투명화
  2) 원본 팔레트 추출 후 스냅
  3) JRPG 톤 셰이딩: 5단 명암 + 남보라 색조 그림자 + 웜 하이라이트, 재스냅
  4) 남색 1px 외곽선
  5) 4x nearest 업스케일

사용: python tools/convert/sprite_retouch.py [--baseline]
"""
from __future__ import annotations
import hashlib
import os
import sys
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
REF = os.path.join(ROOT, "assets", "originals_ref", "bmp_spr")
OUT = os.path.join(ROOT, "assets", "gen", "viewers", "samples")
BASELINE = os.path.join(OUT, "SOURCES.sha256")
SCALE = 4

# 스타일 바이블 상수
SHADOW_TINT = (58, 40, 92)        # 남보라 색조 그림자
HIGHLIGHT_TINT = (255, 244, 214)  # 따뜻한 하이라이트
OUTLINE_RGB = (10, 8, 46)         # 짙은 남색(블랙 금지)
BANDS = 5                         # 명암 단계

SAMPLES = [
    ("e1/frame_000.bmp", "enemy_e1"),
    ("e2/frame_000.bmp", "enemy_e2"),
    ("e5/frame_000.bmp", "enemy_e5"),
    ("a1/frame_000.bmp", "attack_a1"),
    ("d1/frame_000.bmp", "damage_d1"),
]


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def all_sources() -> list[str]:
    out: list[str] = []
    for root, _dirs, files in os.walk(REF):
        for f in sorted(files):
            if f.lower().endswith((".bmp", ".png")):
                out.append(os.path.join(root, f))
    return out


def write_baseline() -> None:
    os.makedirs(OUT, exist_ok=True)
    with open(BASELINE, "w", encoding="utf-8", newline="\n") as fh:
        for p in all_sources():
            rel = os.path.relpath(p, ROOT).replace(os.sep, "/")
            fh.write(f"{sha256(p)}  {rel}\n")
    print(f"baseline written: {len(all_sources())} files")


def verify_baseline() -> bool:
    if not os.path.exists(BASELINE):
        print("베이스라인 없음 - 새로 기록합니다.")
        write_baseline()
        return True
    expected: dict[str, str] = {}
    with open(BASELINE, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            h, rel = line.split("  ", 1)
            expected[rel] = h
    bad: list[str] = []
    seen: set[str] = set()
    for p in all_sources():
        rel = os.path.relpath(p, ROOT).replace(os.sep, "/")
        seen.add(rel)
        if expected.get(rel) != sha256(p):
            bad.append(rel)
    for rel in expected:
        if rel not in seen:
            bad.append(rel + " (삭제됨)")
    if bad:
        print("!! 원본 무결성 위반 감지 - 처리를 중단합니다:")
        for rel in bad:
            print("   ", rel)
        print("복원: git checkout -- remakes/sidol_godot/assets/originals_ref")
        return False
    print(f"integrity ok ({len(seen)} sources)")
    return True


def remove_background(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]

    def is_bg(c) -> bool:
        r, g, b, a = c
        if a == 0:
            return True
        # 모서리 평균색과 충분히 가까우면 배경으로 간주
        for cc in corners:
            cr, cg, cb, ca = cc
            if abs(r - cr) + abs(g - cg) + abs(b - cb) < 60:
                return True
        return False

    seen = bytearray(w * h)
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + \
            [(x, y) for y in range(h) for x in (0, w - 1)]
    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        if not is_bg(px[x, y]):
            continue
        px[x, y] = (0, 0, 0, 0)
        stack.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    return img


_MASTER_PAL: list[tuple[int, int, int]] = []


def build_palette(img: Image.Image) -> list[tuple[int, int, int]]:
    """이미지에서 불투명 픽셀의 고유 색 세트를 추출(원본 팔레트 잠금용)."""
    seen: dict[tuple[int, int, int], None] = {}
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a > 0:
                seen[(r, g, b)] = None
    return list(seen)


def snap_to(img: Image.Image, pal: list[tuple[int, int, int]]) -> Image.Image:
    """주어진 팔레트에 최근접 스냅(외래 색 유입 차단)."""
    if not pal:
        return img
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            best, bd = None, 1 << 30
            for pr, pg, pb in pal:
                d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
                if d < bd:
                    best, bd = (pr, pg, pb), d
            px[x, y] = (*best, a)
    return img


def shade_jrpg(img: Image.Image,
               pal: list[tuple[int, int, int]]) -> Image.Image:
    """5단 명암 밴딩 + 남보라 색조 그림자 + 웜 하이라이트(바이블 준수)."""
    px = img.load()
    w, h = img.size
    lums = []
    for yy in range(h):
        for xx in range(w):
            p = px[xx, yy]
            if p[3] > 0:
                lums.append((p[0] * 299 + p[1] * 587 + p[2] * 114) // 1000)
    if not lums:
        return img
    lo, hi = min(lums), max(lums)
    span = max(hi - lo, 1)

    def band(l: int) -> float:
        """0.0(최암) ~ 1.0(최명) — 밴딩으로 단계화."""
        return round((l - lo) / span * (BANDS - 1)) / (BANDS - 1)

    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            t = band((r * 299 + g * 587 + b * 114) // 1000)
            if t <= 0.25:      # 그림자 - 검정 대신 남보라 색조
                k = 0.35 * (0.25 - t) / 0.25
                r = int(r + (SHADOW_TINT[0] - r) * k)
                g = int(g + (SHADOW_TINT[1] - g) * k)
                b = int(b + (SHADOW_TINT[2] - b) * k)
            elif t >= 0.75:    # 하이라이트 - 따뜻하게 리프트
                k = 0.18 * (t - 0.75) / 0.25
                r = int(r + (HIGHLIGHT_TINT[0] - r) * k)
                g = int(g + (HIGHLIGHT_TINT[1] - g) * k)
                b = int(b + (HIGHLIGHT_TINT[2] - b) * k)
            px[x, y] = (max(r, 0), max(g, 0), max(b, 0), a)
    return snap_to(img, pal)


def add_outline(img: Image.Image) -> Image.Image:
    w, h = img.size
    src = img.load()
    out = Image.new("RGBA", (w, h))
    dst = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = src[x, y]
            if a > 0:
                dst[x, y] = (r, g, b, a)
                continue
            near = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    na = src[nx, ny][3]
                    if na > 128:
                        near = True
                        break
            dst[x, y] = (*OUTLINE_RGB, 255) if near else (0, 0, 0, 0)
    return out


def heal_pinholes(img: Image.Image, radius: int = 2,
                  min_ratio: float = 0.75) -> Image.Image:
    """배경과 얇게 연결된 스프라이트 내부 검정(눈·입·틈) 복원.

    원작 엔진은 색상 0(순수 검정)을 투명으로 취급했으므로 배경과 검정이 구분
    불가능하다. 두 규칙으로 되살린다:
      1) 이미지 경계에 닿지 않는 투명 컴포넌트(완전 밀폐) -> 전부 검정 복원
      2) 국소 판정: 반경 r 창의 min_ratio 이상이 불투명이면 검정으로 봉합
        (실루엣 가장자리는 창의 절반 정도만 불투명이라 옆쪽 배경은 안 건드림)
    """
    px = img.load()
    w, h = img.size

    def neighbors4(x, y):
        return ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1))

    # 1) 밀폐 투명 컴포넌트 복원
    seen = bytearray(w * h)
    for sy in range(h):
        for sx in range(w):
            i = sy * w + sx
            if seen[i] or px[sx, sy][3] > 0:
                continue
            comp = []
            touches_border = False
            stack = [(sx, sy)]
            seen[i] = 1
            while stack:
                x, y = stack.pop()
                comp.append((x, y))
                if x == 0 or y == 0 or x == w - 1 or y == h - 1:
                    touches_border = True
                for nx, ny in neighbors4(x, y):
                    if 0 <= nx < w and 0 <= ny < h:
                        j = ny * w + nx
                        if not seen[j] and px[nx, ny][3] == 0:
                            seen[j] = 1
                            stack.append((nx, ny))
            if not touches_border:
                for x, y in comp:
                    px[x, y] = (0, 0, 0, 255)

    # 2) 국소 핀홀 봉합
    opaque = [[px[x, y][3] > 0 for x in range(w)] for y in range(h)]
    to_fill = []
    for y in range(h):
        for x in range(w):
            if opaque[y][x]:
                continue
            cnt = tot = 0
            for dy in range(-radius, radius + 1):
                for dx in range(-radius, radius + 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        tot += 1
                        if opaque[ny][nx]:
                            cnt += 1
            if tot and cnt / tot >= min_ratio:
                to_fill.append((x, y))
    for x, y in to_fill:
        px[x, y] = (0, 0, 0, 255)
    return img


def crop_content(img: Image.Image) -> Image.Image:
    """불투명 영역의 bounding box 로 크롭(여백 프레임 제거)."""
    bbox = img.getchannel("A").getbbox()
    if bbox:
        pad = 2
        l = max(bbox[0] - pad, 0)
        t = max(bbox[1] - pad, 0)
        r = min(bbox[2] + pad, img.width)
        b = min(bbox[3] + pad, img.height)
        return img.crop((l, t, r, b))
    return img


def retouch(src_path: str) -> Image.Image:
    img = Image.open(src_path)
    img = remove_background(img)
    img = heal_pinholes(img)
    img = crop_content(img)
    pal = build_palette(img)
    img = snap_to(img, pal)
    img = shade_jrpg(img, pal)
    img = add_outline(img)
    return img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)


## 셀 단위 처리용 — 팔레트를 외부(아틀라스 전체)에서 받는 변형
def apply_pipeline(cell: Image.Image,
                   pal: list[tuple[int, int, int]]) -> Image.Image:
    cell = snap_to(cell, pal)
    cell = shade_jrpg(cell, pal)
    cell = add_outline(cell)
    return cell.resize((cell.width * SCALE, cell.height * SCALE), Image.NEAREST)


def main() -> None:
    if "--baseline" in sys.argv:
        write_baseline()
        return
    if not verify_baseline():
        sys.exit(1)
    os.makedirs(OUT, exist_ok=True)
    for rel, name in SAMPLES:
        src = os.path.join(REF, rel.replace("/", os.sep))
        if not os.path.exists(src):
            print(f"skip (없음): {rel}")
            continue
        original = Image.open(src).convert("RGBA")
        ret = retouch(src)
        original.save(os.path.join(OUT, f"{name}_original.png"))
        ret.save(os.path.join(OUT, f"{name}_retouched.png"))
        print(f"ok: {name}  {original.size} -> {ret.size}")
    print("done ->", OUT)


if __name__ == "__main__":
    main()
