"""최소 256색 PCX 디코더 — 원작 PCX(HUD/얼굴/배경)를 PNG로 수출하기 위한 공용 모듈."""
from __future__ import annotations

from pathlib import Path


def _rle_decode(data: bytes, need: int) -> bytes:
    out = bytearray()
    i = 0
    n = len(data)
    while len(out) < need and i < n:
        b = data[i]
        i += 1
        if b < 192:
            out.append(b)
        else:
            count = b & 0x3F
            out += bytes([data[i]]) * count
            i += 1
    return bytes(out[:need])


def decode_pcx(data: bytes) -> tuple[int, int, list[int]]:
    """반환: (width, height, 인덱스 픽셀 배열)"""
    if data[0] != 0x0A:
        raise ValueError("PCX 아님")
    encoding = data[2]
    bits = data[3]
    x_min = int.from_bytes(data[4:6], "little")
    y_min = int.from_bytes(data[6:8], "little")
    x_max = int.from_bytes(data[8:10], "little")
    y_max = int.from_bytes(data[10:12], "little")
    planes = data[68]
    bytes_per_line = int.from_bytes(data[66:68], "little")
    if encoding != 1 or bits != 8 or planes > 1:
        # 원작 PCX는 planes=0(비표준)으로 저장됨 → 8bpp 단면 관용 처리
        raise ValueError(f"미지원 PCX: enc={encoding} bits={bits} planes={planes}")
    width = x_max - x_min + 1
    height = y_max - y_min + 1
    raw = _rle_decode(data[128:], bytes_per_line * height)
    pixels = []
    for y in range(height):
        start = y * bytes_per_line
        pixels += list(raw[start:start + width])
    return width, height, pixels


def read_palette(data: bytes) -> list[tuple[int, int, int]]:
    """파일 말미 769B(0x0C 마커+RGB768). 6bit 값 자동 감지해 8bit로 스케일."""
    pal = data[-769:]
    if pal[0] != 0x0C:
        raise ValueError("팔레트 마커 없음")
    body = pal[1:]
    max_v = max(body)
    scale = 4 if max_v <= 63 else 1

    def up(v: int) -> int:
        return min(255, v * scale)

    return [(up(body[i]), up(body[i + 1]), up(body[i + 2])) for i in range(0, 768, 3)]


def pcx_to_rgba(data: bytes) -> tuple[int, int, bytes]:
    """PCX 바이트 → (w,h,RGBA bytes). 자체 팔레트 적용."""
    w, h, pixels = decode_pcx(data)
    pal = read_palette(data)
    rgba = bytearray()
    for p in pixels:
        rgba += bytes(pal[p]) + b"\xff"
    return w, h, bytes(rgba)
