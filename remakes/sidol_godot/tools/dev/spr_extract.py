#!/usr/bin/env python3
"""SED 'Sprites Data File Ver 3.05' 완전 추출기.

포맷(역공학 확정):
  [28B 매직][768B 팔레트(6bit RGB×256)]
  레코드 반복: [u16 size][u16 w][u16 h][PCX식 RLE 데이터 size-4B]
  종료자: size=4, w=0, h=0
산출: assets/originals_ref/spr/<파일명>/frame_NNN.bmp + <파일명>_contact.png
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHARED_SRC = ROOT.parent.parent / "_shared" / "src"
ORIGINALS = ROOT.parent.parent / "originals" / "1995_sidol_bsd_dos"
sys.path.insert(0, str(SHARED_SRC))

from dosport.formats.png_write import fill_rect, write_png  # noqa: E402


def rle_pcx(d: bytes, pos: int, need: int):
    out = bytearray()
    n = len(d)
    while len(out) < need:
        if pos >= n:
            return None
        b = d[pos]; pos += 1
        if b < 192:
            out.append(b)
        else:
            if pos >= n:
                return None
            out += bytes([d[pos]]) * (b & 0x3F); pos += 1
    if pos != n:          # 레코드 경계 정확 소진 필수
        return None
    return pos, bytes(out[:need])


def parse_spr(data: bytes):
    """반환: (palette[(r,g,b)], [(w,h,rgba_bytes), ...])"""
    pal6 = data[28:28 + 768]

    def up(v: int) -> int:
        return min(255, v << 2)

    palette = [(up(pal6[i]), up(pal6[i + 1]), up(pal6[i + 2])) for i in range(0, 768, 3)]

    pos = 28 + 768
    frames = []
    skipped = []
    n = len(data)
    idx = 0
    while pos + 6 <= n:
        size = int.from_bytes(data[pos:pos + 2], "little")
        w = int.from_bytes(data[pos + 2:pos + 4], "little")
        h = int.from_bytes(data[pos + 4:pos + 6], "little")
        if size == 4 and w == 0 and h == 0:
            break
        if size < 4 or pos + 2 + size > n:
            raise ValueError(f"레코드 파손 @ {pos}")
        payload = data[pos + 6:pos + 2 + size]
        pos += 2 + size
        need = w * h
        px: bytes | None = None
        if len(payload) == need:
            px = payload                      # 무압축 저장분
        else:
            r = rle_pcx(payload, 0, need)
            if r is not None:
                px = r[1]
        if px is None:
            skipped.append(idx)
            idx += 1
            continue                           # 프레임 스킵하고 다음 레코드 계속
        rgba = bytearray()
        for c in px:
            if c == 0:
                # 색0 = 투명 — 원작 엔진 blit의 색0 스킵 재현
                # (docs/HANDOFF.md "원작 검정=투명 문제" 참조)
                rgba += b"\x00\x00\x00\x00"
            else:
                rgba += bytes(palette[c]) + b"\xff"
        frames.append((w, h, bytes(rgba)))
        idx += 1
    if skipped:
        print(f"    (스킵 프레임: {skipped})")
    return palette, frames


def contact_sheet(name: str, frames: list, out_png: Path, cols: int | None = None) -> None:
    if not frames:
        return
    cw = max(w for w, _, _ in frames) + 2
    ch = max(h for h, _, _ in frames) + 2
    cols = cols or min(len(frames), max(1, 2048 // cw))
    rows = (len(frames) + cols - 1) // cols
    W, H = cw * cols, ch * rows
    buf = bytearray(W * H * 4)
    fill_rect(buf, W, 0, 0, W, H, (24, 24, 32, 255))
    for i, (w, h, rgba) in enumerate(frames):
        gx, gy = (i % cols) * cw + 1, (i // cols) * ch + 1
        for yy in range(h):
            di = ((gy + yy) * W + gx) * 4
            si = yy * w * 4
            buf[di:di + w * 4] = rgba[si:si + w * 4]
    write_png(out_png, W, H, bytes(buf))


def extract(fname: str, src_dir: Path, out_base: Path) -> None:
    path = src_dir / fname
    data = path.read_bytes()
    palette, frames = parse_spr(data)
    stem = fname.lower().replace(".spr", "")
    fdir = out_base / stem
    fdir.mkdir(parents=True, exist_ok=True)
    for i, (w, h, rgba) in enumerate(frames):
        write_bmp(fdir / f"frame_{i:03d}.bmp", w, h, rgba)
    try:
        contact_sheet(stem, frames, out_base / f"{stem}_contact.png")
    except (ValueError, IndexError) as e:
        # 개별 프레임 BMP는 이미 저장됨 — 컨택트시트 실패는 치명적이지 않음
        print(f"    (컨택트시트 생략: {e})")
    print(f"{fname}: {len(frames)} frames -> {fdir.relative_to(ROOT.parent.parent)}")


def write_bmp(path: Path, width: int, height: int, rgba: bytes) -> None:
    import struct
    row_raw = width * 3
    pad = (4 - row_raw % 4) % 4
    image_size = (row_raw + pad) * height
    header = b"BM" + struct.pack("<IHHI", 54 + image_size, 0, 0, 54)
    dib = struct.pack("<IiiHHIIiiII", 40, width, -height, 1, 24, 0, image_size, 2835, 2835, 0, 0)
    body = bytearray()
    for y in range(height):   # top-down(음수 높이)
        base = y * width * 4
        row = bytearray()
        for x in range(width):
            i = base + x * 4
            row += bytes((rgba[i + 2], rgba[i + 1], rgba[i]))
        row += b"\x00" * pad
        body += row
    path.write_bytes(header + dib + bytes(body))


def main() -> int:
    out_base = ROOT / "assets" / "originals_ref" / "bmp_spr"
    out_base.mkdir(parents=True, exist_ok=True)
    ok, fail = [], []
    seen = set()
    for src_dir in (ORIGINALS, ORIGINALS / "보존" / "BSD"):
        for src in sorted(src_dir.glob("*.SPR")):
            if src.name.upper() in seen:
                continue
            seen.add(src.name.upper())
            try:
                extract(src.name, src_dir, out_base)
                ok.append(src.name)
            except (ValueError, IndexError) as e:
                fail.append(f"{src.name}: {e}")
    print(f"\nOK={len(ok)} FAIL={len(fail)}")
    for line in fail:
        print("  FAIL", line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
