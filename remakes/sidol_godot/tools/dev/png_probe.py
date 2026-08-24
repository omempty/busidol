#!/usr/bin/env python3
"""최소 PNG 프로버(필터 0~4, colortype 2/6, bit8) — 픽셀 색 분포 진단용."""
from __future__ import annotations

import struct
import sys
import zlib
from collections import Counter
from pathlib import Path


def decode_png(path: str):
    data = Path(path).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "PNG 시그니처 아님"
    pos = 8
    width = height = bits = ctype = None
    idat = b""
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height, bits, ctype = struct.unpack(">IIBB", payload[:10])
        elif tag == b"IDAT":
            idat += payload
        elif tag == b"IEND":
            break
        pos += 12 + length
    assert bits == 8, f"bit depth {bits} 미지원"
    ch = {2: 3, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = width * ch
    out = bytearray(stride * height)
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if f == 1:
            for i in range(ch, stride):
                line[i] = (line[i] + line[i - ch]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                left = line[i - ch] if i >= ch else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                b = prev[i]
                c = prev[i - ch] if i >= ch else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, ch, bytes(out)


def top_colors(path: str, k: int = 8) -> None:
    w, h, ch, px = decode_png(path)
    cnt: Counter = Counter()
    mx = [0] * ch
    for i in range(0, len(px), ch):
        cnt[bytes(px[i:i + ch])] += 1
        for j in range(ch):
            mx[j] = max(mx[j], px[i + j])
    print(f"{Path(path).name}: {w}x{h} ch={ch} max_channel={mx} unique={len(cnt)}")
    for c, n in cnt.most_common(k):
        print(f"   #{c.hex().upper()} x{n}")


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        top_colors(arg)
