"""순수 파이썬 24비트 BMP 라이터 — 무압축, 최대 호환(모든 툴/에이전트 즉시 열람)."""
from __future__ import annotations

import struct
from pathlib import Path


def write_bmp24(path: str | Path, width: int, height: int, rgba: bytes) -> None:
    """rgba(top-down RGBA bytes)를 24bit BGR BMP(bottom-up)로 저장."""
    if len(rgba) != width * height * 4:
        raise ValueError(f"rgba 크이상: {len(rgba)} != {width*height*4}")
    row_raw = width * 3
    row_pad = (4 - row_raw % 4) % 4
    row_size = row_raw + row_pad
    image_size = row_size * height
    file_size = 54 + image_size

    header = b"BM" + struct.pack("<IHHI", file_size, 0, 0, 54)
    dib = struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0,
                      image_size, 2835, 2835, 0, 0)

    body = bytearray()
    for y in range(height - 1, -1, -1):          # bottom-up
        row = bytearray()
        base = y * width * 4
        for x in range(width):
            i = base + x * 4
            row += bytes((rgba[i + 2], rgba[i + 1], rgba[i]))  # BGR
        row += b"\x00" * row_pad
        body += row

    Path(path).write_bytes(header + dib + bytes(body))
