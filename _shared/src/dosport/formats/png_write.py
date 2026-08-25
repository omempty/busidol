"""순수 파이썬 PNG(RGBA8) 인코더 — 외부 의존성 없이 플레이스홀더 에셋 생성용."""
from __future__ import annotations

import struct
import zlib
from pathlib import Path


def write_png(path: str | Path, width: int, height: int, rgba: bytes) -> None:
    """rgba: 길이 width*height*4 바이트. 필터 0 스캔라인으로 압축해 저장."""
    if len(rgba) != width * height * 4:
        raise ValueError(f"rgba 크이상: {len(rgba)} != {width*height*4}")

    def chunk(tag: bytes, payload: bytes) -> bytes:
        body = tag + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    stride = width * 4
    raw = b"".join(b"\x00" + rgba[y * stride:(y + 1) * stride] for y in range(height))
    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(raw, 9))
    out += chunk(b"IEND", b"")
    Path(path).write_bytes(out)


def fill_rect(rgba: bytearray, img_w: int, x0: int, y0: int, w: int, h: int, color: tuple[int, int, int, int]) -> None:
    """rgba 버퍼에 사각형 채우기 유틸."""
    for y in range(y0, y0 + h):
        row = y * img_w * 4
        for x in range(x0, x0 + w):
            i = row + x * 4
            rgba[i:i + 4] = bytes(color)
