"""원본 스프라이트 시범 리터칭 - Phase 8 샘플 파이프라인.

스타일 바이블(assets/style_bible.md) 준수:
  - 팔레트 잠금: palette_master.json(DEFAULT.PAL 유래 256색)만 사용
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
  2) 마스터 팔레트 스냅
  3) JRPG 톤 셰이딩: 5단 명암 + 남보라 색조 그림자 + 웜 하이라이트, 재스냅
  4) 남색 1px 외곽선
  5) 4x nearest 업스케일

사용: python tools/convert/sprite_retouch.py [--baseline]
"""
from __future__ import annotations
import hashlib
import json
import os
import sys
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
REF = os.path.join(ROOT, "assets", "originals_ref", "bmp_spr")
OUT = os.path.join(ROOT, "assets", "gen", "viewers", "samples")
PALETTE_PATH = os.path.join(ROOT, "assets", "palette_master.json")
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


def master_palette() -> list[tuple[int, int, int]]:
    global _MASTER_PAL
    if not _MASTER_PAL:
        with open(PALETTE_PATH, encoding="utf-8") as fh:
            data = json.load(fh)
        # format=raw768: VGA 6비트(0~63) 값을 8비트(0~255)로 스케일
        _MASTER_PAL = [tuple(int(c[i:i + 2], 16) * 255 // 63 for i in (1, 3, 5))
                       for c in data["colors"]]
    return _MASTER_PAL


def snap_palette(img: Image.Image) -> Image.Image:
    """마스터 팔레트 잠금 - 불투명 픽셀을 최근접 팔레트 색으로 스냅."""
    pal = master_palette()
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


def shade_jrpg(img: Image.Image) -> Image.Image:
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
    lo, hi = lums[0], lums[-1]
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
                k = 0.45 * (0.25 - t) / 0.25
                r = int(r + (SHADOW_TINT[0] - r) * k)
                g = int(g + (SHADOW_TINT[1] - g) * k)
                b = int(b + (SHADOW_TINT[2] - b) * k)
            elif t >= 0.75:    # 하이라이트 - 따뜻하게 리프트
                k = 0.22 * (t - 0.75) / 0.25
                r = int(r + (HIGHLIGHT_TINT[0] - r) * k)
                g = int(g + (HIGHLIGHT_TINT[1] - g) * k)
                b = int(b + (HIGHLIGHT_TINT[2] - b) * k)
            px[x, y] = (max(r, 0), max(g, 0), max(b, 0), a)
    return snap_palette(img)


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
    img = crop_content(img)
    img = snap_palette(img)
    img = shade_jrpg(img)
    img = add_outline(img)
    return img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)


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
