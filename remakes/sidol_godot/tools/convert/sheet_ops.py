#!/usr/bin/env python3
"""시트 픽셀 연산의 **정본** — 검증기·설치기·셀 편집기가 같은 함수를 쓴다.

## 왜 생겼나 (2026-09-08)

같은 규칙이 두 곳에 살아 있었다:

  안내선 판정(밀도 30% · 단색 폭 40 · 두께 3px), median-cut 양자화, 마젠타 키잉,
  알파 이진화, 정렬 스냅 —
    · `tools/convert/delivery_checks.py` + `install_delivery.py` (검사·설치)
    · `tools/review/sprite_fixer.html`의 자바스크립트 (사람이 고치는 편집기)

이 저장소가 반복해 물린 결함이 정확히 이 모양이다(사문화·중복 로직: 한쪽만 고쳐지고
다른 쪽이 조용히 어긋난다). 편집기에서 "자동 정리"를 눌러 통과시킨 시트가 설치 단계의
다른 판정에 걸리거나, 반대로 편집기가 그림을 지우는 사고가 구조적으로 가능했다.

그래서 픽셀을 만지는 규칙은 전부 여기로 모으고,
  · 파이썬 쪽은 그대로 import 해서 쓰고,
  · 편집기는 `review_server`의 `/api/fixer/op`를 거쳐 **이 함수들을 호출**한다.
편집기의 자바스크립트에는 규칙이 남지 않는다(그리기·선택 같은 조작 UI만 남는다).

각 연산은 `(Image, 수치)` 또는 `(Image, dict)`를 돌려준다 — 몇 픽셀을 건드렸는지
사람에게 그대로 보고하기 위해서다("고쳤다"는 말만으로는 검증이 안 된다).
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import delivery_checks as dc  # noqa: E402  (같은 폴더 모듈)

## 순수 검정 대체색 — 스타일 바이블의 "블랙 금지, 짙은 남색" 규약.
DARK_NAVY = (0x0A, 0x08, 0x2E)
## 하단 정렬 시 남기는 여백(셀 높이 비율). 편집기·설치기가 같은 수를 써야 접지가 흔들리지 않는다.
BOTTOM_MARGIN = 0.04


def _rgba_array(im: Image.Image) -> np.ndarray:
    return np.asarray(im.convert("RGBA")).astype(np.uint8).copy()


def _hue_mask(a: np.ndarray) -> np.ndarray:
    """안내선 색(마젠타·청록) 판정 — delivery_checks.guide_hue_mask와 같은 식."""
    rgb = a[:, :, :3].astype(int)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    vis = a[:, :, 3] > 8
    mag = (np.abs(r - b) < 40) & (g + 40 < np.minimum(r, b)) & (np.maximum(r, b) > 40)
    cyan = (np.abs(g - b) < 40) & (r + 40 < np.minimum(g, b)) & (np.maximum(g, b) > 40)
    return (mag | cyan) & vis


# ---------------------------------------------------------------- 시트 전체 연산
def key_magenta(im: Image.Image, tol: int = 40) -> tuple:
    """마젠타 배경 키잉 — #FF00FF 근처를 투명으로."""
    a = _rgba_array(im)
    rgb = a[:, :, :3].astype(int)
    d = np.abs(rgb[:, :, 0] - 255) + rgb[:, :, 1] + np.abs(rgb[:, :, 2] - 255)
    hit = (d <= tol * 3) & (a[:, :, 3] > 0)
    a[hit] = 0
    return Image.fromarray(a, "RGBA"), int(hit.sum())


def binarize_alpha(im: Image.Image) -> tuple:
    """반투명 픽셀 제거 — 계약은 반투명 0%다. 128 이상은 불투명, 미만은 삭제."""
    a = _rgba_array(im)
    alpha = a[:, :, 3]
    semi = (alpha > 0) & (alpha < 255)
    n = int(semi.sum())
    keep = semi & (alpha >= 128)
    drop = semi & (alpha < 128)
    a[keep, 3] = 255
    a[drop] = 0
    return Image.fromarray(a, "RGBA"), n


def deblack(im: Image.Image) -> tuple:
    """순수 검정 → 짙은 남색. 원작 도트의 외곽선 규약."""
    a = _rgba_array(im)
    rgb = a[:, :, :3]
    hit = (a[:, :, 3] > 8) & (rgb[:, :, 0] == 0) & (rgb[:, :, 1] == 0) & (rgb[:, :, 2] == 0)
    a[hit, 0], a[hit, 1], a[hit, 2] = DARK_NAVY
    return Image.fromarray(a, "RGBA"), int(hit.sum())


def erase_color(im: Image.Image, rgb: tuple, tol: int = 24) -> tuple:
    """스포이드로 찍은 색을 전역 삭제(맨해튼 거리 <= tol*3)."""
    a = _rgba_array(im)
    src = a[:, :, :3].astype(int)
    d = (np.abs(src[:, :, 0] - int(rgb[0]))
         + np.abs(src[:, :, 1] - int(rgb[1]))
         + np.abs(src[:, :, 2] - int(rgb[2])))
    hit = (d <= tol * 3) & (a[:, :, 3] > 0)
    a[hit] = 0
    return Image.fromarray(a, "RGBA"), int(hit.sum())


def quantize(im: Image.Image, colors: int = 48) -> Image.Image:
    """불투명 픽셀만 N색으로 몰고 알파는 0/255로 이진화한다.

    알파를 함께 median-cut에 넣으면 반투명 경계색이 팔레트 한 칸을 먹고
    투명 배경이 색으로 굳는다 — RGB만 양자화하고 알파는 따로 씌운다.

    **안내선 색(마젠타·청록) 픽셀은 팔레트 계산에서 뺀다.** 남은 잔선이 어두운 외곽선과
    한 상자에 묶이면 평균이 자주색이 되어 스프라이트에 분홍 테두리가 생긴다(실측).
    뺀 픽셀은 양자화 뒤 최근접 색으로 흡수돼 구멍이 나지 않는다.
    """
    src = im.convert("RGBA")
    a = np.asarray(src).astype(np.uint8).copy()
    alpha = (a[:, :, 3] > 127).astype(np.uint8) * 255
    tainted = _hue_mask(np.dstack([a[:, :, :3], alpha]))
    clean = a[:, :, :3].copy()
    if tainted.any() and (~tainted & (alpha > 0)).any():
        # 팔레트 산출용 이미지에서 오염 픽셀을 흔한 그림색으로 임시 치환한다.
        fill = clean[(~tainted) & (alpha > 0)].mean(axis=0).astype(np.uint8)
        clean[tainted] = fill
    q = Image.fromarray(clean, "RGB").quantize(
        colors=colors, method=Image.MEDIANCUT, dither=Image.NONE
    ).convert("RGB")
    out = np.dstack([np.asarray(q), alpha]).astype(np.uint8)
    out[alpha == 0] = 0  # 투명 픽셀의 RGB를 0으로 — 키잉 잔색 방지
    return Image.fromarray(out, "RGBA")


def clean_guides(im: Image.Image, cell: int) -> tuple:
    """안내선 잔선을 지우고 **그 주변 2px의 오염 픽셀만** 이웃 그림색으로 메운다.

    범위를 안 좁히면 그림을 먹는다 — 전 마젠타/청록 픽셀을 오염으로 보면 청록 유령
    `null_pointer`는 불투명 83,786px 중 45,959px이 대상이 됐다(실측). 오염은 안내선이
    지나간 자리에만 생기므로 마스크를 팽창시킨 띠 안으로 한정한다.
    반환: (이미지, 지운 잔선 px, 메운 오염 px).
    """
    a = _rgba_array(im)
    line = dc.guide_line_mask(im, cell, cell)
    removed = int(line.sum())
    if not removed:
        return im, 0, 0
    a[line] = 0
    h, w = line.shape
    band = np.zeros_like(line)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            band |= np.roll(np.roll(line, dy, axis=0), dx, axis=1)
    vis = a[:, :, 3] > 8
    bad = _hue_mask(a) & vis & band
    filled_total = int(bad.sum())
    for _ in range(2):
        ys, xs = np.nonzero(bad)
        if ys.size == 0:
            break
        moved = 0
        for y, x in zip(ys, xs):
            cand = []
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if (dy or dx) and 0 <= ny < h and 0 <= nx < w and vis[ny, nx] and not bad[ny, nx]:
                        cand.append(tuple(a[ny, nx, :3]))
            if not cand:
                continue
            a[y, x, :3] = max(set(cand), key=cand.count)
            bad[y, x] = False
            moved += 1
        if not moved:
            break
    return Image.fromarray(a, "RGBA"), removed, filled_total


# ---------------------------------------------------------------- 격자 연산
def cell_bbox(a: np.ndarray, cell: int, r: int, c: int):
    """셀 안 그림의 경계상자(마젠타 배경 제외). 없으면 None."""
    sub = a[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell]
    if sub.size == 0:
        return None
    rgb = sub[:, :, :3].astype(int)
    exact_magenta = (rgb[:, :, 0] == 255) & (rgb[:, :, 1] == 0) & (rgb[:, :, 2] == 255)
    vis = (sub[:, :, 3] > 8) & ~exact_magenta
    ys, xs = np.nonzero(vis)
    if ys.size == 0:
        return None
    return {"x0": int(xs.min()), "y0": int(ys.min()), "x1": int(xs.max()), "y1": int(ys.max())}


def snap_cells(im: Image.Image, cell: int, rows: int, cols: int,
               align: str = "bottom_center", only=None) -> tuple:
    """셀 내용을 계약 정렬 위치로 옮긴다. only=(r,c)면 그 칸만.

    가로는 항상 중앙, 세로는 align에 따라 중앙 또는 하단 접지(여백 BOTTOM_MARGIN).
    """
    a = _rgba_array(im)
    moved = 0
    targets = [only] if only else [(r, c) for r in range(rows) for c in range(cols)]
    for (r, c) in targets:
        bb = cell_bbox(a, cell, r, c)
        if not bb:
            continue
        cx = (bb["x0"] + bb["x1"]) / 2
        dx = int(round(cell / 2 - cx))
        if align == "center":
            dy = int(round(cell / 2 - (bb["y0"] + bb["y1"]) / 2))
        else:
            dy = (cell - 1 - int(cell * BOTTOM_MARGIN)) - bb["y1"]
        if not dx and not dy:
            continue
        y0, x0 = r * cell, c * cell
        src = a[y0:y0 + cell, x0:x0 + cell].copy()
        dst = np.zeros_like(src)
        sy0, sy1 = max(0, -dy), min(cell, cell - dy)
        sx0, sx1 = max(0, -dx), min(cell, cell - dx)
        if sy1 > sy0 and sx1 > sx0:
            dst[sy0 + dy:sy1 + dy, sx0 + dx:sx1 + dx] = src[sy0:sy1, sx0:sx1]
        a[y0:y0 + cell, x0:x0 + cell] = dst
        moved += 1
    return Image.fromarray(a, "RGBA"), moved


def regrid(im: Image.Image, src_cell: int, cell: int, rows: int, cols: int) -> tuple:
    """임의 셀 크기로 그려 온 시트를 계약 격자에 재배치한다(nearest)."""
    src = im.convert("RGBA")
    sc = int(src_cell) or max(1, round(src.width / max(1, cols)))
    out = Image.new("RGBA", (cols * cell, rows * cell), (0, 0, 0, 0))
    src_rows = max(1, src.height // sc)
    src_cols = max(1, src.width // sc)
    for r in range(min(src_rows, rows)):
        for c in range(min(src_cols, cols)):
            box = (c * sc, r * sc, (c + 1) * sc, (r + 1) * sc)
            tile = src.crop(box).resize((cell, cell), Image.NEAREST)
            out.paste(tile, (c * cell, r * cell))
    return out, f"{src_cols}×{src_rows}(셀 {sc}) → {cols}×{rows}(셀 {cell})"


def scale_to(im: Image.Image, w: int, h: int) -> tuple:
    """계약 크기로 nearest 리샘플."""
    return im.convert("RGBA").resize((int(w), int(h)), Image.NEAREST), f"{im.width}×{im.height} → {w}×{h}"


# ---------------------------------------------------------------- 계측
def measure(im: Image.Image, cell: int = 0, rows: int = 0, cols: int = 0,
            layout=None, align: str = "bottom_center", budget: int = 48) -> dict:
    """편집기 계측 패널이 쓰는 수치 — 검증기와 **같은 근거**로 잰다."""
    a = _rgba_array(im)
    alpha = a[:, :, 3]
    semi = int(((alpha > 0) & (alpha < 255)).sum())
    vis = alpha > 8
    opaque = int(vis.sum())
    rgb = a[:, :, :3]
    colors = len({tuple(v) for v in rgb[vis]}) if opaque else 0
    black = int((vis & (rgb[:, :, 0] == 0) & (rgb[:, :, 1] == 0) & (rgb[:, :, 2] == 0)).sum())
    guides = int(dc.guide_line_mask(im, cell, cell).sum()) if cell else 0

    bad = []
    if cell and rows and cols:
        frames_of = {int(l["row"]): int(l["frames"]) for l in (layout or [])}
        for r in range(rows):
            frames = frames_of.get(r, cols)
            for c in range(cols):
                bb = cell_bbox(a, cell, r, c)
                declared = c < frames
                if declared and not bb:
                    bad.append(f"r{r}c{c} 비어 있음(계약 {frames}프레임)")
                    continue
                if not declared and bb:
                    bad.append(f"r{r}c{c} 여분 셀에 내용")
                    continue
                if not bb:
                    continue
                cx = (bb["x0"] + bb["x1"]) / 2
                if abs(cx - cell / 2) > cell * 0.12:
                    bad.append(f"r{r}c{c} 가로 중앙 이탈 {round(cx - cell / 2)}px")
                if align == "center":
                    cy = (bb["y0"] + bb["y1"]) / 2
                    if abs(cy - cell / 2) > cell * 0.14:
                        bad.append(f"r{r}c{c} 세로 중앙 이탈 {round(cy - cell / 2)}px")
                elif align == "bottom_center" and (cell - 1 - bb["y1"]) > cell * 0.14:
                    bad.append(f"r{r}c{c} 하단 정렬 이탈 {cell - 1 - bb['y1']}px")
    return {
        "size": [im.width, im.height],
        "semi": semi, "opaque": opaque, "colors": colors, "black": black,
        "guides": guides, "budget": budget, "cell_issues": bad,
    }


# ---------------------------------------------------------------- 연산 디스패치
def apply_op(im: Image.Image, op: str, params: dict) -> tuple:
    """(이미지, 로그 문자열) — 서버가 편집기에 그대로 돌려준다."""
    p = params or {}
    cell = int(p.get("cell") or 0)
    rows = int(p.get("rows") or 0)
    cols = int(p.get("cols") or 0)
    align = str(p.get("align") or "bottom_center")
    if op == "key":
        im, n = key_magenta(im, int(p.get("tol", 40)))
        return im, f"마젠타 키잉 {n}px"
    if op == "guides":
        if not cell:
            return im, "셀 크기를 모르는 계약이라 안내선 판정을 못 한다"
        im, removed, filled = clean_guides(im, cell)
        return im, f"격자 잔선 제거 {removed}px · 가장자리 오염 정리 {filled}px"
    if op == "binarize":
        im, n = binarize_alpha(im)
        return im, f"알파 이진화 {n}px"
    if op == "quantize":
        n = int(p.get("colors", 48))
        im = quantize(im, n)
        return im, f"색 양자화 → 최대 {n}색"
    if op == "deblack":
        im, n = deblack(im)
        return im, f"순수검정 치환 {n}px"
    if op == "erasecolor":
        rgb = p.get("rgb") or [0, 0, 0]
        im, n = erase_color(im, rgb, int(p.get("tol", 24)))
        return im, f"색 삭제 {n}px"
    if op == "regrid":
        if not (cell and rows and cols):
            return im, "계약이 없어 재배치할 격자를 모른다"
        im, msg = regrid(im, int(p.get("src_cell", 0)), cell, rows, cols)
        return im, "재배치: " + msg
    if op == "scale":
        size = p.get("size") or [im.width, im.height]
        im, msg = scale_to(im, size[0], size[1])
        return im, "리샘플: " + msg
    if op == "snap":
        if not cell:
            return im, "셀 크기를 모르는 계약이라 정렬할 수 없다"
        only = p.get("cell_rc")
        im, n = snap_cells(im, cell, rows or 1, cols or 1, align,
                           only=(int(only[0]), int(only[1])) if only else None)
        return im, (f"정렬 스냅 {n}칸" if n else "이동 불필요")
    if op == "snapall":
        if not (cell and rows and cols):
            return im, "계약이 없어 전 셀 정렬을 못 한다"
        im, n = snap_cells(im, cell, rows, cols, align)
        return im, f"전 셀 정렬 스냅 {n}칸"
    if op == "autofix":
        logs = []
        if cell and rows and cols and (im.width, im.height) != (cols * cell, rows * cell):
            im, msg = regrid(im, int(p.get("src_cell", 0)), cell, rows, cols)
            logs.append("크기 불일치 — 재배치: " + msg)
        im, n = key_magenta(im, 40)
        logs.append(f"마젠타 키잉 {n}px")
        if cell:
            im, removed, filled = clean_guides(im, cell)
            logs.append(f"격자 잔선 제거 {removed}px · 오염 정리 {filled}px")
        im, n = binarize_alpha(im)
        logs.append(f"알파 이진화 {n}px")
        colors = int(p.get("colors", 48))
        im = quantize(im, colors)
        logs.append(f"색 양자화 → 최대 {colors}색")
        # 양자화가 어두운 외곽선을 순수 검정으로 몰아넣는다(실측: c_bug 자동 정리 뒤 147px).
        # 스타일 규약이 순수 블랙을 금지하므로 마지막에 남색으로 되돌린다.
        im, n = deblack(im)
        if n:
            logs.append(f"순수검정 치환 {n}px")
        if cell and rows and cols:
            im, n = snap_cells(im, cell, rows, cols, align)
            logs.append(f"전 셀 정렬 스냅 {n}칸")
        return im, "\n".join(logs)
    raise ValueError(f"알 수 없는 연산: {op}")
