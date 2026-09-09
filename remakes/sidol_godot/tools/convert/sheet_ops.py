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
## 한 프레임 묶음이 가질 수 있는 최대 폭(칸 대비). 넘으면 거기서 끊는다 —
## 넓은 그림자가 좌우 캐릭터를 걸쳐 묶음이 연쇄로 커지는 것을 막는다.
GROUP_WIDTH_MAX = 1.4
## 정렬이 없는 계약에서 [정렬 스냅]을 눌렀을 때의 답. 조용히 아무것도 안 하면
## 사람은 버튼이 고장 난 줄 안다 — 왜 안 움직이는지 그 자리에서 말한다.
ALIGN_NONE_MSG = ("정렬이 없는 계약(align=none)이라 옮기지 않았다 — 타일·아이콘·초상은 "
                  "칸을 가득 채우는 것이 정상이고, 중앙/하단으로 밀면 이음새가 어긋난다")


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


# ------------------------------------------------------- 배경 자동 판정·제거
def _border_connected(mask: np.ndarray, seed: np.ndarray) -> np.ndarray:
    """mask 중 **seed에 이어져 있는 덩어리만** 남긴다.

    왜 연결성인가: 색만 보고 지우면 그림 **안쪽**의 같은 색까지 구멍이 난다
    (흰 배경을 지우면 눈 흰자·하이라이트가 뚫린다 — 실제로 자주 나는 사고다).
    배경은 정의상 가장자리(또는 셀 경계)에서 이어져 들어온 영역이다.
    """
    if not mask.any():
        return mask
    try:
        from scipy import ndimage
        lab, n = ndimage.label(mask)
        if n == 0:
            return np.zeros_like(mask)
        touched = np.unique(lab[seed & mask])
        touched = touched[touched > 0]
        return np.isin(lab, touched)
    except ImportError:
        # scipy가 없을 때의 대체 — 씨앗에서 4방향으로 번지게 한다(느리지만 결과는 같다).
        reach = seed & mask
        for _ in range(mask.shape[0] + mask.shape[1]):
            g = reach.copy()
            g[1:] |= reach[:-1]
            g[:-1] |= reach[1:]
            g[:, 1:] |= reach[:, :-1]
            g[:, :-1] |= reach[:, 1:]
            g &= mask
            if np.array_equal(g, reach):
                break
            reach = g
        return reach


def detect_bg(im: Image.Image) -> dict:
    """가장자리를 보고 배경을 추정한다 — 색·비율·번짐 폭까지.

    웹 LLM은 "배경 투명"을 거의 못 지킨다. 흰색·검정·회색·하늘색 단색으로 오거나
    마젠타로 오거나, 미세한 그라데이션으로 온다. 무엇으로 왔는지부터 **재고** 시작한다.
    """
    a = _rgba_array(im)
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]]).astype(int)
    n = len(border)
    opaque = border[border[:, 3] >= 8]
    if len(opaque) < n * 0.10:
        return {"kind": "transparent", "rgb": None, "share": 0.0, "tol": 0,
                "note": f"가장자리 {100 - round(100 * len(opaque) / n)}%가 이미 투명"}
    cols, counts = np.unique(opaque[:, :3], axis=0, return_counts=True)
    top = cols[int(counts.argmax())]
    share = float(counts.max()) / n
    d = np.abs(opaque[:, :3] - top).sum(axis=1)
    near = d <= 24 * 3
    # 허용오차는 가장자리가 얼마나 고른지에서 뽑는다. 완전 단색이면 좁게, 그라데이션이면 넓게.
    tol = int(np.clip(np.percentile(d[near], 90) / 3 + 6, 8, 60)) if near.any() else 24
    kind = "magenta" if (top[0] > 200 and top[1] < 60 and top[2] > 200) else "solid"
    if share < 0.5:
        kind = "mixed"
    return {"kind": kind, "rgb": [int(v) for v in top], "share": share, "tol": tol,
            "note": f"#{top[0]:02X}{top[1]:02X}{top[2]:02X} 가장자리 {round(share * 100)}%"}


def key_background(im: Image.Image, tol: int = 0, cell: int = 0,
                   rows: int = 0, cols: int = 0) -> tuple:
    """배경색을 스스로 찾아 투명으로 뚫는다(색 일치 + 가장자리 연결성).

    계약 크기에 맞는 시트라면 **셀 경계선도 씨앗으로 쓴다** — 칸마다 배경이 갇혀 있어도
    (스프라이트가 칸을 꽉 채워 바깥 테두리와 이어지지 않는 배치) 같이 뚫린다.
    """
    info = detect_bg(im)
    if info["kind"] == "transparent":
        return im, 0, f"배경이 이미 투명하다 ({info['note']}) — 손대지 않음"
    if info["kind"] == "mixed":
        return im, 0, (f"가장자리가 단색이 아니다({info['note']}) — 자동 배경 판정을 보류한다. "
                       "스포이드로 색을 찍어 [이 색 전역 삭제]를 쓰라")
    a = _rgba_array(im)
    h, w = a.shape[:2]
    t = int(tol) if tol else int(info["tol"])
    rgb = np.array(info["rgb"], dtype=int)
    dist = np.abs(a[:, :, :3].astype(int) - rgb).sum(axis=2)
    mask = (dist <= t * 3) & (a[:, :, 3] > 8)

    seed = np.zeros((h, w), dtype=bool)
    seed[0, :] = seed[-1, :] = True
    seed[:, 0] = seed[:, -1] = True
    lines = 0
    if cell and rows and cols and (w, h) == (cols * cell, rows * cell):
        # 칸마다 배경이 갇혀 있어도(바깥 테두리와 이어지지 않는 배치) 뚫으려고 셀 경계도 씨앗으로 쓴다.
        # 다만 **그 경계선이 실제로 배경으로 덮여 있을 때만**이다 — 칸을 꽉 채운 그림이
        # 경계에 닿아 있는데 씨앗을 심으면 그림이 통째로 지워진다.
        for c in range(1, cols):
            if mask[:, c * cell].mean() >= 0.8:
                seed[:, c * cell - 1:c * cell + 1] = True
                lines += 1
        for r in range(1, rows):
            if mask[r * cell, :].mean() >= 0.8:
                seed[r * cell - 1:r * cell + 1, :] = True
                lines += 1
    grid = f" · 배경으로 덮인 셀 경계선 {lines}줄도 씨앗" if lines else ""
    hit = _border_connected(mask, seed)
    n = int(hit.sum())
    a[hit] = 0
    inner = int(mask.sum()) - n
    msg = (f"배경 자동 제거 {n}px (배경 {info['note']} · 허용오차 {t}{grid})"
           + (f" · 그림 안쪽의 같은 색 {inner}px는 연결돼 있지 않아 지키고 남겼다" if inner else ""))
    return Image.fromarray(a, "RGBA"), n, msg


# ------------------------------------------------------- 픽셀풍(해상도 낮추기)
def detail_ratio(im: Image.Image) -> float:
    """'너무 세밀한가'를 재는 값 — 이웃과 색이 다른 불투명 픽셀의 비율.

    생성 모델은 요청과 무관하게 사진처럼 세밀한 그림을 준다. 그 시트는 도트 규약
    (고유색 48 이하·1px 단위 형태)과 어긋나 양자화만으로는 도트로 보이지 않는다.
    0.5를 넘으면 사실상 픽셀마다 색이 다르다는 뜻이다.
    """
    a = _rgba_array(im)
    vis = a[:, :, 3] > 8
    if not vis.any():
        return 0.0
    rgb = a[:, :, :3].astype(int)
    diff = np.zeros(vis.shape, dtype=bool)
    diff[:, :-1] |= (np.abs(rgb[:, :-1] - rgb[:, 1:]).sum(axis=2) > 12) & vis[:, :-1] & vis[:, 1:]
    diff[:-1, :] |= (np.abs(rgb[:-1, :] - rgb[1:, :]).sum(axis=2) > 12) & vis[:-1, :] & vis[1:, :]
    return float((diff & vis).sum()) / float(vis.sum())


def suggest_pixel_level(im: Image.Image, cell: int = 0) -> int:
    """칸 하나가 대략 64도트가 되도록 블록 크기를 고른다(셀 크기의 약수로 맞춘다)."""
    base = cell or min(im.width, im.height)
    lv = max(2, round(base / 64))
    if cell:
        while lv > 2 and cell % lv:
            lv -= 1
    return int(lv)


def pixelize(im: Image.Image, level: int = 0, cell: int = 0) -> tuple:
    """블록 최빈색으로 뭉개 도트풍으로 만든다. 캔버스 크기는 그대로 둔다.

    평균색이 아니라 **최빈색**을 쓴다: 평균은 원본에 없던 중간색을 만들어 고유색이 오히려
    늘고 경계가 흐려진다. 최빈색은 팔레트를 늘리지 않고 형태만 계단으로 만든다.
    알파는 블록의 절반 이상이 불투명할 때만 남긴다(반투명 술이 생기지 않게).

    level은 도트 한 칸의 크기(px)다. 셀 크기의 약수로 당겨 **셀 경계에 블록이 걸치지**
    않게 한다 — 걸치면 정렬 스냅과 셀 판정이 통째로 어긋난다.
    """
    src = im.convert("RGBA")
    lv = int(level) if level else suggest_pixel_level(src, cell)
    lv = max(2, lv)
    if cell:
        while lv > 2 and cell % lv:
            lv -= 1
    W, H = src.width, src.height
    ph, pw = (-H) % lv, (-W) % lv
    a = np.zeros((H + ph, W + pw, 4), dtype=np.uint8)
    a[:H, :W] = np.asarray(src, dtype=np.uint8)
    bh, bw = a.shape[0] // lv, a.shape[1] // lv

    rgbk = (a[:, :, 0].astype(np.int32) << 16) | (a[:, :, 1].astype(np.int32) << 8) | a[:, :, 2]
    rgbk[a[:, :, 3] <= 8] = -1                     # 투명은 후보에서 뺀다
    blocks = (rgbk.reshape(bh, lv, bw, lv).transpose(0, 2, 1, 3).reshape(bh * bw, lv * lv))
    opa = blocks >= 0

    SENT = np.int32(1 << 30)
    srt = np.sort(np.where(opa, blocks, SENT), axis=1)
    grp = np.zeros_like(srt)
    grp[:, 1:] = np.cumsum(srt[:, 1:] != srt[:, :-1], axis=1)
    nb, m = srt.shape
    flat = (np.arange(nb)[:, None] * m + grp).ravel()
    cnt = np.bincount(flat, minlength=nb * m).reshape(nb, m)
    val = np.zeros((nb, m), dtype=np.int32)
    val[np.repeat(np.arange(nb), m), grp.ravel()] = srt.ravel()
    cnt[val == SENT] = 0                            # 투명 무리는 최빈색 후보가 아니다
    best = cnt.argmax(axis=1)
    win = val[np.arange(nb), best]

    out = np.zeros((bh * bw, 4), dtype=np.uint8)
    keep = opa.mean(axis=1) >= 0.5
    out[keep, 0] = ((win[keep] >> 16) & 255).astype(np.uint8)
    out[keep, 1] = ((win[keep] >> 8) & 255).astype(np.uint8)
    out[keep, 2] = (win[keep] & 255).astype(np.uint8)
    out[keep, 3] = 255
    small = Image.fromarray(out.reshape(bh, bw, 4), "RGBA")
    big = small.resize((bw * lv, bh * lv), Image.NEAREST).crop((0, 0, W, H))

    before = len({tuple(v) for v in np.asarray(src)[np.asarray(src)[:, :, 3] > 8][:, :3]})
    ba = np.asarray(big)
    after = len({tuple(v) for v in ba[ba[:, :, 3] > 8][:, :3]})
    return big, (f"픽셀풍 레벨 {lv}px ({bw}×{bh}블록) · 고유색 {before} → {after}"
                 + (f" · 셀 {cell}의 약수로 맞춤" if cell else ""))


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


def _vis_mask(a: np.ndarray, cell: int, r: int, c: int, w: int = 1, h: int = 1):
    """상자 안의 '그림' 마스크(마젠타 배경 제외). 비었으면 None."""
    sub = a[r * cell:(r + h) * cell, c * cell:(c + w) * cell]
    if sub.size == 0:
        return None
    rgb = sub[:, :, :3].astype(int)
    exact_magenta = (rgb[:, :, 0] == 255) & (rgb[:, :, 1] == 0) & (rgb[:, :, 2] == 255)
    vis = (sub[:, :, 3] > 8) & ~exact_magenta
    return vis if vis.any() else None


def align_bbox(a: np.ndarray, cell: int, r: int, c: int, w: int = 1, h: int = 1):
    """정렬을 맞출 기준 상자 — (bbox, 흩어짐?). 판정과 보정이 **같은 것**을 봐야 한다.

    예전에는 계측·정렬 스냅이 `cell_bbox`(내용 전체)로, 검증기가 본체 덩어리로 재서
    잣대가 둘이었다. 그래서 [정렬 스냅]을 눌러도 검증기 [ERR]이 그대로 남는 상태가
    가능했다(실측: flying_thesis death r2c2 — 스냅이 1칸 옮겼는데 판정 그대로 ERR).
    자동보정이 수렴하려면 둘이 같아야 하므로 여기서 dc.align_anchor로 모은다.
    """
    mask = _vis_mask(a, cell, r, c, w, h)
    if mask is None:
        return None, False
    bb, scattered, _ = dc.align_anchor(mask)
    return bb, scattered


def box_bbox(a: np.ndarray, cell: int, r: int, c: int, w: int, h: int):
    """여러 칸에 걸친 상자 안 그림의 경계상자(상자 좌상단 기준). 없으면 None.

    묶음(다중 타일 소품)은 **칸 경계를 가로질러 이어지는 것이 정상**이라 칸 단위
    `cell_bbox`로는 잴 수 없다 — 조각마다 따로 재면 책상 하나가 네 조각으로 보인다.
    """
    sub = a[r * cell:(r + h) * cell, c * cell:(c + w) * cell]
    if sub.size == 0:
        return None
    rgb = sub[:, :, :3].astype(int)
    exact_magenta = (rgb[:, :, 0] == 255) & (rgb[:, :, 1] == 0) & (rgb[:, :, 2] == 255)
    vis = (sub[:, :, 3] > 8) & ~exact_magenta
    ys, xs = np.nonzero(vis)
    if ys.size == 0:
        return None
    return {"x0": int(xs.min()), "y0": int(ys.min()), "x1": int(xs.max()), "y1": int(ys.max())}


def group_cells(groups) -> dict:
    """(r, c) -> 그 칸이 속한 묶음. 묶음이 없으면 빈 사전."""
    out = {}
    for g in (groups or []):
        try:
            gr, gc = int(g["r"]), int(g["c"])
            gw, gh = int(g.get("w", 1)), int(g.get("h", 1))
        except (KeyError, TypeError, ValueError):
            continue
        for dr in range(gh):
            for dc in range(gw):
                out[(gr + dr, gc + dc)] = g
    return out


def _shift_box(a: np.ndarray, cell: int, r: int, c: int, w: int, h: int, dx: int, dy: int) -> None:
    """상자 안 내용을 (dx, dy)만큼 옮긴다(상자 밖으로 나간 것은 버린다). 제자리 수정."""
    y0, x0 = r * cell, c * cell
    bh, bw = h * cell, w * cell
    src = a[y0:y0 + bh, x0:x0 + bw].copy()
    dst = np.zeros_like(src)
    sy0, sy1 = max(0, -dy), min(bh, bh - dy)
    sx0, sx1 = max(0, -dx), min(bw, bw - dx)
    if sy1 > sy0 and sx1 > sx0:
        dst[sy0 + dy:sy1 + dy, sx0 + dx:sx1 + dx] = src[sy0:sy1, sx0:sx1]
    a[y0:y0 + bh, x0:x0 + bw] = dst


def snap_cells(im: Image.Image, cell: int, rows: int, cols: int,
               align: str = "bottom_center", only=None, groups=None) -> tuple:
    """셀 내용을 계약 정렬 위치로 옮긴다. only=(r,c)면 그 칸만.

    가로는 항상 중앙, 세로는 align에 따라 중앙 또는 하단 접지(여백 BOTTOM_MARGIN).

    ## align="none"이면 **아무것도 옮기지 않는다** (2026-09-09)

    예전에는 `center`가 아니면 전부 하단 정렬로 떨어졌다. 그래서 정렬이 없는 계약
    (초상 768×256 · 아이콘 96 · 타일셋)에서 [정렬 스냅]을 누르면 얼굴과 타일이 칸
    아래로 밀렸다. 타일은 칸을 가득 채워야 이음새가 맞으므로 미는 순간 격자가 깨진다.

    ## 묶음(groups)은 **상자 하나로** 옮긴다

    다중 타일 소품(책상 2×2 등)은 칸 경계를 가로질러 이어져 있다. 칸마다 따로 중앙
    정렬하면 조각들이 각자 칸 중앙으로 흩어져 **소품이 부서진다**. 묶음에 속한 칸은
    개별 정렬에서 빼고, 묶음 상자 전체를 한 단위로 정렬한다.
    """
    if str(align) == "none":
        return im, 0
    a = _rgba_array(im)
    moved = 0
    in_group = group_cells(groups)

    def _align_delta(bb, bw, bh):
        dx = int(round(bw / 2 - (bb["x0"] + bb["x1"]) / 2))
        if align == "center":
            dy = int(round(bh / 2 - (bb["y0"] + bb["y1"]) / 2))
        else:
            dy = (bh - 1 - int(bh * BOTTOM_MARGIN)) - bb["y1"]
        return dx, dy

    # 묶음 먼저 — 상자 단위. only가 묶음 안의 칸을 가리키면 그 묶음을 옮긴다.
    done = set()
    for (r, c), g in in_group.items():
        if only and (int(only[0]), int(only[1])) != (r, c):
            continue
        key = (int(g["r"]), int(g["c"]))
        if key in done:
            continue
        done.add(key)
        gw, gh = int(g.get("w", 1)), int(g.get("h", 1))
        bb, _ = align_bbox(a, cell, key[0], key[1], gw, gh)
        if not bb:
            continue
        dx, dy = _align_delta(bb, gw * cell, gh * cell)
        if not dx and not dy:
            continue
        _shift_box(a, cell, key[0], key[1], gw, gh, dx, dy)
        moved += 1

    targets = [only] if only else [(r, c) for r in range(rows) for c in range(cols)]
    for (r, c) in targets:
        if (int(r), int(c)) in in_group:      # 묶음 칸은 위에서 상자로 처리했다
            continue
        bb, _ = align_bbox(a, cell, r, c)
        if not bb:
            continue
        dx, dy = _align_delta(bb, cell, cell)
        if not dx and not dy:
            continue
        _shift_box(a, cell, r, c, 1, 1, dx, dy)
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


## 칸 채움 비율의 허용 범위. 아래로는 프레임이 점이 되고, 위로는 칸을 두 배 넘겨
## 잘려 나가는 양이 그림보다 많아진다 — 사람이 실수로 0이나 10을 넣는 자리를 막는다.
FILL_MIN, FILL_MAX = 0.2, 2.0


def refit(im: Image.Image, cell: int, rows: int, cols: int,
          layout=None, align: str = "bottom_center",
          fill: float = 1.0, only_row=None) -> tuple:
    """행마다 프레임 수가 다른 시트를 **계약 격자에 다시 앉힌다.**

    왜 필요한가(2026-09-08 실측, flying_thesis): 생성 모델은 계약의 4열 격자를 쓰지 않고
    **행마다 그 행의 프레임 수로 가로를 나눠** 그린다. walk 4칸 · attack 3칸 · death 3칸이면
    1행 간격은 W/4, 2·3행 간격은 W/3이다. 그 시트를 통째로 리샘플하면 2·3행 프레임이
    칸 간격과 어긋나 **칸 경계에서 잘린다** — 행을 옆으로 밀어도 해결되지 않는다.

    그래서 통짜 리샘플 대신:
      1) 행을 rows등분하고, 각 행을 **그 행의 프레임 수로** 등분해 조각을 뽑는다.
      2) 조각마다 내용 경계상자를 잡는다(배경이 투명해야 한다 — 키잉을 먼저 돌린다).
      3) **모든 프레임에 같은 축척**을 쓴다. 프레임마다 칸에 꽉 채우면 죽는 모습이 걷는
         모습만큼 커져 크기 관계가 무너진다. 가장 큰 프레임이 칸에 겨우 들어가는 배율
         하나를 골라 전부에 적용한다.
      4) 계약 정렬대로 칸에 앉힌다(하단 정렬이면 BOTTOM_MARGIN을 남긴다).

    ## fill — 칸 채움 비율 (2026-09-09)

    3)의 "가장 큰 프레임이 칸에 겨우 들어가는 배율"은 **기계가 고른 하나**라 사람이
    손댈 수 없었다. 실제 납품은 행마다 삐져나오는 양이 다르다(그 행에서 유난히 큰
    프레임 하나가 축척을 끌어내려 나머지가 칸에서 헐렁해지거나, 반대로 다 같이 작다).
    편집기의 1px 밀기로는 축척이 안 바뀌므로 해결이 안 된다 — **비율 자체**를 줘야 한다.

    최종 축척은 `k = min(cell/maxw, (cell-pad)/maxh) * fill`. `fill=1.0`이 예전 동작이고
    (픽셀 단위로 같은 결과가 나와야 한다 — 회귀 금지), 값은 [0.2, 2.0]으로 자른다.

    `fill > 1.0`이면 프레임이 칸을 넘친다. 넘친 픽셀을 그대로 붙이면 **이웃 칸을
    침범해 옆 프레임 위에 덮인다**(붙이는 순서에 따라 결과가 달라지는, 재현이 안 되는
    사고다). 그래서 프레임마다 자기 칸 사각형으로 클립해 붙이고, **잘려 나간 불투명
    픽셀 수를 문장에 적는다.** 이 저장소의 규약이 "조용히 자르지 않는다"이다.

    ## only_row — 그 행만 재배치 (2026-09-09)

    fill을 행마다 다르게 주려면 한 행씩 손볼 수 있어야 한다. `only_row=r`이면 그 행만
    다시 앉히고 나머지 행은 입력 이미지에서 그대로 가져온다(그래서 입력이 이미 계약
    캔버스 크기여야 한다 — 아니면 손대지 않고 [크기 자동 조절]을 먼저 하라고 돌려준다).

    이때 축척은 **그 행의 프레임들만** 보고 잡는다. 전 시트 축척을 쓰면 이미 재배치돼
    작아진 다른 행의 프레임까지 최댓값 계산에 들어가 축척이 매번 틀어진다(누르는 순서가
    결과를 바꾼다). 대신 행마다 축척이 달라지므로 **계산된 축척 값을 문장에 노출한다** —
    사람이 다른 행과 비율을 맞출 유일한 근거다.

    돌려주는 값: (이미지, 문장, 앉힌 프레임 수)
    """
    if not (cell and rows and cols):
        return im, "계약 격자가 없어 재배치할 수 없다", 0

    f = float(fill) if fill else 1.0
    fk = min(FILL_MAX, max(FILL_MIN, f))
    clamped = f" · 채움 비율 {f:.2f}는 허용 범위 밖이라 {fk:.2f}로 제한했다" if abs(fk - f) > 1e-9 else ""

    tgt_w, tgt_h = cols * cell, rows * cell
    only = None
    if only_row is not None:
        only = int(only_row)
        if not (0 <= only < rows):
            return im, f"행 {only}은 계약 범위(0~{rows - 1}) 밖이라 재배치할 것이 없다", 0
        if (im.width, im.height) != (tgt_w, tgt_h):
            return im, (f"행 {only}만 재배치하려 했으나 크기가 계약과 달라 이 행만 재배치할 수 없다. "
                        f"[크기 자동 조절]을 먼저 하라 "
                        f"(현재 {im.width}×{im.height}, 계약 {tgt_w}×{tgt_h})"), 0

    src = im.convert("RGBA")
    a = np.asarray(src)
    H, W = a.shape[:2]
    frames_of = {int(l["row"]): int(l["frames"]) for l in (layout or [])}
    todo = [only] if only is not None else list(range(rows))

    boxes = {}
    anchors = {}      # 프레임마다 '무엇을 칸 중앙에 둘 것인가' — 본체 상자
    missing = []
    dropped = []      # 계약보다 많이 그려 온 묶음 — 조용히 버리지 않고 문장에 싣는다
    for r in todo:
        nfr = max(1, frames_of.get(r, cols))
        yb0, yb1 = round(r * H / rows), round((r + 1) * H / rows)
        band = a[yb0:yb1, :, 3] > 8
        if not band.any():
            missing += [f"r{r}c{c}" for c in range(nfr)]
            continue
        # 프레임은 왼쪽→오른쪽 순서로 놓인다. 가로로 겹치는 덩어리끼리 한 프레임이고
        # (캐릭터 + 발밑 그림자처럼), 넓은 그림자가 좌우를 동시에 걸쳐 묶음이 연쇄로
        # 커지는 것은 폭 상한으로 끊는다 — 한 칸에 앉을 것이므로 그보다 넓으면 프레임이
        # 아니다. 밴드로 자르던 예전 방식은 그림이 시트 폭을 안 채우면 배정이 어긋났다.
        cap = cell * GROUP_WIDTH_MAX
        groups = []
        for b in sorted(dc.blobs(band), key=lambda b: b["x0"]):
            g = groups[-1] if groups else None
            if g and b["x0"] <= g["x1"] and (max(g["x1"], b["x1"]) - g["x0"] + 1) <= cap:
                g["x1"] = max(g["x1"], b["x1"])
                g["blobs"].append(b)
                g["n"] += b["n"]
            else:
                groups.append({"x0": b["x0"], "x1": b["x1"], "blobs": [b], "n": b["n"]})
        if len(groups) > nfr:
            # 계약보다 묶음이 많다 — 픽셀이 많은 것부터 계약 수만큼만 프레임으로 본다.
            # (실측: flask_titan_v3 hurt 행은 3프레임 계약인데 캐릭터 3개 + 주인 없는
            #  그림자 4개가 그려져 있었다. 그림자를 프레임으로 세면 배치가 통째로 밀린다.)
            dropped.append(f"r{r} 계약 {nfr} 밖 묶음 {len(groups) - nfr}개")
            groups = sorted(sorted(groups, key=lambda g: -g["n"])[:nfr], key=lambda g: g["x0"])
        per = {i: g["blobs"] for i, g in enumerate(groups)}
        for c in range(nfr):
            bl = per.get(c)
            if not bl:
                missing.append(f"r{r}c{c}")
                continue
            boxes[(r, c)] = (min(b["x0"] for b in bl), yb0 + min(b["y0"] for b in bl),
                             max(b["x1"] for b in bl), yb0 + max(b["y1"] for b in bl))
            # **앉히는 기준은 본체다** — 검증기·계측·정렬 스냅과 같은 규칙(align_anchor)을
            # 쓴다. 예전에는 잔조각까지 포함한 전체 상자를 칸 중앙에 맞춰, 멀리 떨어진
            # 파편 하나가 본체를 밀어냈다(실측: dworm_v1 burrow r7c1 — 재배치 뒤 본체가
            # 내용의 98%인데 중심 43, 기대 64로 검증기가 이탈로 잡았다).
            big = max(bl, key=lambda b: b["n"])
            tot = sum(b["n"] for b in bl)
            if big["n"] >= tot * dc.MAIN_BLOB_MIN:
                anchors[(r, c)] = (big["x0"], yb0 + big["y0"], big["x1"], yb0 + big["y1"])
            else:
                anchors[(r, c)] = boxes[(r, c)]      # 본체가 없으면 전체가 기준이다
    if not boxes:
        scope = f"행 {only}에" if only is not None else ""
        return im, f"{scope}내용이 없어 재배치할 것이 없다(배경 키잉을 먼저 하라)".lstrip(), 0

    # 축척 산출 대상: 전 시트면 전 프레임, only_row면 **그 행의 프레임만**.
    # 상자는 이미 '본체 중심 한 칸 폭'으로 좁혀져 있으므로 전체 폭으로 잡아도 된다.
    maxw = max(b[2] - b[0] + 1 for b in boxes.values())
    maxh = max(b[3] - b[1] + 1 for b in boxes.values())
    pad = round(cell * BOTTOM_MARGIN) if align == "bottom_center" else 0
    k = min(cell / maxw, (cell - pad) / maxh) * fk
    # **기본값으로는 키우지 않는다.** refit의 일은 어긋난 배치를 바로잡는 것이지 작게
    # 그려 온 그림을 칸에 꽉 채우는 것이 아니다. 키우면 본체와 그림자 사이 간격까지
    # 함께 늘어나 정렬이 깨진다 — 실측(o_ray_v1): 오류 0건짜리 시트를 1.684배로 키우자
    # 본체 바닥여백이 11px → 18px가 되어 하단 정렬 이탈이 30건 났다.
    # 키우는 것은 사람이 fill>1로 명시할 때만 한다.
    if fk <= 1.0:
        k = min(k, 1.0)

    if only is not None:
        # 나머지 행은 입력 그대로 — 다시 앉힐 행의 띠만 비운다.
        out = src.copy()
        band = Image.new("RGBA", (tgt_w, cell), (0, 0, 0, 0))
        out.paste(band, (0, only * cell))
    else:
        out = Image.new("RGBA", (tgt_w, tgt_h), (0, 0, 0, 0))

    clipped_px = clipped_frames = 0
    for (r, c), (x0, y0, x1, y1) in sorted(boxes.items()):
        piece = src.crop((x0, y0, x1 + 1, y1 + 1))
        nw = max(1, round(piece.width * k))
        nh = max(1, round(piece.height * k))
        piece = piece.resize((nw, nh), Image.NEAREST)
        cx0, cy0 = c * cell, r * cell
        # 조각 안에서 본체가 어디에 있는지 — 축척을 먹인 좌표로 환산한다.
        ax0, ay0, ax1, ay1 = anchors.get((r, c), (x0, y0, x1, y1))
        a_cx = (ax0 + ax1 + 1 - 2 * x0) / 2.0 * k          # 조각 왼쪽 끝 기준 본체 중심
        a_bot = (ay1 + 1 - y0) * k                          # 조각 위 끝 기준 본체 바닥
        px = cx0 + int(round(cell / 2.0 - a_cx))
        py = (cy0 + cell - pad - int(round(a_bot))) if align == "bottom_center" \
            else (cy0 + (cell - nh) // 2)
        # 세로는 본체 바닥을 접지선에 맞추되, 조각이 칸 밖으로 나가면 안으로 당긴다 —
        # 접지 정확도보다 픽셀을 잃지 않는 것이 먼저다(잘린 양은 아래에서 세어 알린다).
        if nh <= cell:
            py = max(cy0, min(py, cy0 + cell - nh))
        # 자기 칸 사각형으로 클립한다. fill>1에서 넘친 픽셀을 그냥 붙이면 이웃 칸의
        # 프레임을 덮어써, 붙이는 순서가 결과를 바꾸는 사고가 난다.
        lx0, ly0 = max(px, cx0), max(py, cy0)
        lx1, ly1 = min(px + nw, cx0 + cell), min(py + nh, cy0 + cell)
        if (lx0, ly0, lx1, ly1) != (px, py, px + nw, py + nh):
            pa = np.asarray(piece)
            kept = pa[max(0, ly0 - py):max(0, ly1 - py), max(0, lx0 - px):max(0, lx1 - px)]
            lost = int((pa[:, :, 3] > 8).sum()) - int((kept[:, :, 3] > 8).sum()) if kept.size else int((pa[:, :, 3] > 8).sum())
            if lost > 0:
                clipped_px += lost
                clipped_frames += 1
            if lx1 <= lx0 or ly1 <= ly0:
                continue
            piece = piece.crop((lx0 - px, ly0 - py, lx1 - px, ly1 - py))
            px, py = lx0, ly0
        out.paste(piece, (px, py))

    scope = f"행 {only}만 재배치" if only is not None else "행별 재배치"
    basis = "그 행에서 가장 큰 프레임" if only is not None else "가장 큰 프레임"
    msg = (f"{scope} {len(boxes)}프레임 → {tgt_w}×{tgt_h} "
           f"({basis} {maxw}×{maxh}px 기준 축척 {k:.3f}, 채움 {fk:.2f}, 정렬 {align})")
    if dropped:
        msg += " · 계약 밖 묶음은 빼고 앉혔다(" + ", ".join(dropped) + ")"
    msg += clamped
    if clipped_px:
        msg += f" · 칸 경계에서 잘린 픽셀 {clipped_px:,}px (프레임 {clipped_frames}개)"
    if missing:
        msg += f" · 내용이 없던 칸 {len(missing)}개: " + ", ".join(missing[:6])
    return out, msg, len(boxes)


def scale_cells(im: Image.Image, cell: int, rows: int, cols: int,
                k: float, align: str = "bottom_center", only=None) -> tuple:
    """칸 안의 그림만 축척 k로 줄인다(격자·칸 배치는 그대로).

    ## 왜 refit과 따로 있나

    refit은 프레임을 **다시 찾아 다시 앉힌다** — 배치가 틀어진 납품을 바로잡는 도구다.
    배치는 맞는데 그림만 칸보다 큰 경우에는 그렇게까지 할 필요가 없고, 오히려 프레임
    묶음을 잘못 잡을 위험만 진다. 이건 칸마다 있는 것을 제자리에서 줄이기만 한다.

    줄이는 기준점은 계약 정렬과 같다: 가로 중앙, 세로는 바닥 접지(align에 따라 중앙).
    그래야 줄인 뒤에도 정렬 검사를 그대로 통과한다.
    """
    if not (cell and rows and cols):
        return im, "계약 격자가 없어 칸 단위로 줄일 수 없다", 0
    k = float(k)
    if not (0.05 <= k <= 1.0):
        return im, f"축척 {k}는 0.05~1.00 밖이다(줄이는 연산이다)", 0
    src = im.convert("RGBA")
    out = src.copy()
    pad = round(cell * BOTTOM_MARGIN) if align == "bottom_center" else 0
    targets = [tuple(only)] if only else [(r, c) for r in range(rows) for c in range(cols)]
    done = 0
    for (r, c) in targets:
        r, c = int(r), int(c)
        box = (c * cell, r * cell, (c + 1) * cell, (r + 1) * cell)
        sub = src.crop(box)
        a = np.asarray(sub)
        vis = a[:, :, 3] > 8
        if not vis.any():
            continue
        ys, xs = np.where(vis)
        x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
        piece = sub.crop((x0, y0, x1 + 1, y1 + 1))
        nw = max(1, round(piece.width * k))
        nh = max(1, round(piece.height * k))
        piece = piece.resize((nw, nh), Image.NEAREST)
        blank = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        px = (cell - nw) // 2
        py = (cell - pad - nh) if align == "bottom_center" else (cell - nh) // 2
        blank.paste(piece, (max(0, px), max(0, py)))
        out.paste(blank, (box[0], box[1]))
        done += 1
    what = f"r{targets[0][0]}c{targets[0][1]}" if only else f"{done}칸"
    return out, f"칸 내용 축소 {what} × {k:.2f} (정렬 {align} 유지)", done


def autosize(im: Image.Image, cell: int, rows: int, cols: int, size=None) -> tuple:
    """어떤 크기로 와도 계약 캔버스에 맞춘다 — 무엇을 했는지 문장으로 돌려준다.

    웹 LLM은 캔버스 크기를 거의 못 맞춘다(1024x1024, 1536x1024 같은 자기 기본값으로 온다).
    사람이 재배치/리샘플 중 무엇을 눌러야 하는지 매번 판단하던 자리를 없앤다.

    목표 크기는 **격자(cols x cell)가 있으면 그것, 없으면 계약이 적어 준 `size`**다.
    예전에는 격자로만 계산해서 keyart처럼 **셀이 0인 계약(1920x1080 한 장)은 자동 조절이
    통째로 건너뛰어졌다** — 2048x1152로 온 납품이 그대로 남았다(2026-09-08 실측).

    판단 순서 — 그림을 덜 망가뜨리는 쪽부터:
      1) 이미 계약 크기 → 아무것도 안 한다
      2) 가로세로 **비율이 같다** → 전체를 nearest로 균일 확대·축소(격자가 그대로 산다)
      3) 격자가 있으면 **칸 단위 리샘플**: 원본을 cols x rows로 등분해 각 조각을 셀 크기로
         옮긴다. 비율이 달라도 칸마다 내용이 보존된다(전체 리샘플은 격자가 어긋난다).
      4) 격자가 없는 한 장짜리인데 비율이 다르면 **비율을 지켜 채우고 가운데를 자른다**.
         한 장 그림(keyart)에 투명 띠를 두르는 것이 더 큰 결함이라 그렇게 한다.
         잘라 낸 양은 문장으로 돌려주니 아니다 싶으면 [되돌리기].
    """
    grid = bool(cell and rows and cols)
    if grid:
        W, H = cols * cell, rows * cell
    elif size and int(size[0]) > 0 and int(size[1]) > 0:
        W, H = int(size[0]), int(size[1])
    else:
        return im, "계약이 없어 크기를 맞출 수 없다"
    src = im.convert("RGBA")
    if (src.width, src.height) == (W, H):
        return src, f"이미 계약 크기 {W}×{H} — 변경 없음"
    if abs(src.width / max(1, src.height) - W / H) < 0.01:
        out = src.resize((W, H), Image.NEAREST)
        return out, f"비율이 같아 균일 리샘플 {src.width}×{src.height} → {W}×{H}"
    if not grid:
        # cover: 짧은 쪽을 기준으로 키운 뒤 가운데를 잘라 낸다.
        k = max(W / src.width, H / src.height)
        rw, rh = max(1, round(src.width * k)), max(1, round(src.height * k))
        big = src.resize((rw, rh), Image.NEAREST)
        x0, y0 = (rw - W) // 2, (rh - H) // 2
        out = big.crop((x0, y0, x0 + W, y0 + H))
        cut = f"가로 {rw - W}px" if rw > W else (f"세로 {rh - H}px" if rh > H else "없음")
        return out, (f"비율이 달라 비율 유지 채우기 {src.width}×{src.height} → {W}×{H} "
                     f"(가운데 기준, 잘라 낸 양 {cut}). 자르지 않고 늘리려면 [계약 크기로 리샘플]")
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for r in range(rows):
        for c in range(cols):
            box = (round(c * src.width / cols), round(r * src.height / rows),
                   round((c + 1) * src.width / cols), round((r + 1) * src.height / rows))
            out.paste(src.crop(box).resize((cell, cell), Image.NEAREST), (c * cell, r * cell))
    return out, (f"칸 단위 리샘플 {src.width}×{src.height} → {W}×{H} "
                 f"(원본 칸 {round(src.width/cols)}×{round(src.height/rows)} → {cell}×{cell})")


def _target_size(cell: int, rows: int, cols: int, size=None):
    """계약이 요구하는 캔버스 크기 — 격자가 있으면 격자, 없으면 계약의 size. 없으면 None."""
    if cell and rows and cols:
        return (cols * cell, rows * cell)
    if size and int(size[0]) > 0 and int(size[1]) > 0:
        return (int(size[0]), int(size[1]))
    return None


def scale_to(im: Image.Image, w: int, h: int) -> tuple:
    """계약 크기로 nearest 리샘플."""
    return im.convert("RGBA").resize((int(w), int(h)), Image.NEAREST), f"{im.width}×{im.height} → {w}×{h}"


# ---------------------------------------------------------------- 계측
def measure(im: Image.Image, cell: int = 0, rows: int = 0, cols: int = 0,
            layout=None, align: str = "bottom_center", budget: int = 48,
            groups=None) -> dict:
    """편집기 계측 패널이 쓰는 수치 — 검증기와 **같은 근거**로 잰다.

    ## 묶음(groups)이 있으면 판정 단위가 칸이 아니다 (2026-09-09)

    다중 타일 소품은 **칸 경계를 가로질러 이어져 있는 것이 정상**이다. 칸 단위로 재면
    2×2 책상의 왼쪽 조각이 전부 "가로 중앙 이탈"로 잡혀 계측이 통째로 빨개진다.
    묶음에 속한 칸은 개별 판정에서 빼고, **상자 하나**로 본다.
    """
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
    in_group = group_cells(groups)
    if cell and rows and cols:
        # 묶음은 상자 하나로 본다 — 비었는지, 상자를 너무 안 채우는지만.
        for g in (groups or []):
            try:
                gr, gc = int(g["r"]), int(g["c"])
                gw, gh = int(g.get("w", 1)), int(g.get("h", 1))
            except (KeyError, TypeError, ValueError):
                continue
            gid = str(g.get("id") or f"r{gr}c{gc}")
            bb = box_bbox(a, cell, gr, gc, gw, gh)
            if not bb:
                bad.append(f"묶음 {gid}({gw}×{gh}) 비어 있음")
                continue
            fw = (bb["x1"] - bb["x0"] + 1) / float(gw * cell)
            fh = (bb["y1"] - bb["y0"] + 1) / float(gh * cell)
            # 소품은 제 상자를 채우라고 그린 것이다. 절반도 못 채우면 칸 배정이 틀렸거나
            # 생성 모델이 상자를 무시하고 한 칸에만 그린 것이다 — 둘 다 사람이 봐야 한다.
            if fw < 0.5 or fh < 0.5:
                bad.append(f"묶음 {gid}가 상자를 거의 안 채움"
                           f"(가로 {round(fw * 100)}% · 세로 {round(fh * 100)}%)")
        frames_of = {int(l["row"]): int(l["frames"]) for l in (layout or [])}
        for r in range(rows):
            frames = frames_of.get(r, cols)
            for c in range(cols):
                if (r, c) in in_group:      # 묶음 칸은 위에서 상자로 판정했다
                    continue
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
                if align == "none":
                    # 정렬이 없는 계약(타일셋·아이콘·초상)은 칸을 가득 채우는 것이 정상이라
                    # 중앙 이탈이라는 개념이 없다. 예전에는 여기서 전부 빨개졌다.
                    continue
                # 정렬은 검증기와 **같은 기준 상자**로 잰다 — 아니면 편집기는 깨끗한데
                # 검증기는 반려하는(또는 그 반대) 갈라짐이 생긴다.
                ab, _scattered = align_bbox(a, cell, r, c)
                if not ab:
                    continue
                cx = (ab["x0"] + ab["x1"]) / 2
                if abs(cx - cell / 2) > cell * 0.12:
                    bad.append(f"r{r}c{c} 가로 중앙 이탈 {round(cx - cell / 2)}px")
                if align == "center":
                    cy = (ab["y0"] + ab["y1"]) / 2
                    if abs(cy - cell / 2) > cell * 0.14:
                        bad.append(f"r{r}c{c} 세로 중앙 이탈 {round(cy - cell / 2)}px")
                elif align == "bottom_center" and (cell - 1 - ab["y1"]) > cell * 0.14:
                    bad.append(f"r{r}c{c} 하단 정렬 이탈 {cell - 1 - ab['y1']}px")
    bg = detect_bg(im)
    return {
        "size": [im.width, im.height],
        "semi": semi, "opaque": opaque, "colors": colors, "black": black,
        "guides": guides, "budget": budget, "cell_issues": bad,
        # 배경이 무엇으로 왔는지 · 얼마나 세밀한지 — 자동 보정이 무엇을 할지의 근거다.
        "bg": {"kind": bg["kind"], "note": bg["note"], "rgb": bg["rgb"]},
        "detail": round(detail_ratio(im), 3),
        "pixel_level": suggest_pixel_level(im, cell),
    }


# ---------------------------------------------------------------- 연산 디스패치
def apply_op(im: Image.Image, op: str, params: dict) -> tuple:
    """(이미지, 로그 문자열) — 서버가 편집기에 그대로 돌려준다."""
    p = params or {}
    cell = int(p.get("cell") or 0)
    rows = int(p.get("rows") or 0)
    cols = int(p.get("cols") or 0)
    align = str(p.get("align") or "bottom_center")
    # 묶음(다중 타일 소품) — 있으면 정렬·계측의 판정 단위가 칸이 아니라 상자다.
    groups = p.get("groups") or []
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
    if op == "autosize":
        im, msg = autosize(im, cell, rows, cols, p.get("size"))
        return im, "크기 자동 조절: " + msg
    if op == "refit":
        # 편집기(JS)가 보내는 JSON이라 숫자가 문자열로 온다("0.8", "1"). 잘못 오면
        # 기본값으로 되돌린다 — 여기서 터지면 사람은 이유 없이 안 되는 버튼만 본다.
        try:
            raw_fill = p.get("fill")
            fill = 1.0 if raw_fill is None or str(raw_fill).strip() == "" else float(raw_fill)
        except (TypeError, ValueError):
            fill = 1.0
        raw_row = p.get("only_row")
        only_row = None
        if raw_row is not None and str(raw_row).strip() != "":
            try:
                only_row = int(float(str(raw_row).strip()))
            except (TypeError, ValueError):
                only_row = None
        im, msg, n = refit(im, cell, rows, cols, p.get("layout"), align, fill, only_row)
        return im, msg
    if op == "autokey":
        im, n, msg = key_background(im, int(p.get("tol", 0)), cell, rows, cols)
        return im, msg
    if op == "pixelize":
        im, msg = pixelize(im, int(p.get("level", 0)), cell)
        return im, msg
    if op == "autoprep":
        # 파일을 열자마자 도는 자리. **그림을 지우는 연산은 넣지 않는다** —
        # 크기와 배경만 계약에 맞춘다(양자화·정렬은 사람이 [자동 정리]로 고른다).
        logs = []
        # 목표 크기는 격자가 있으면 격자, 없으면 계약이 적어 준 size다.
        # 예전에는 격자만 봐서 셀 0인 계약(keyart)이 조용히 건너뛰어졌다.
        tgt = _target_size(cell, rows, cols, p.get("size"))
        if tgt and (im.width, im.height) != tgt:
            im, msg = autosize(im, cell, rows, cols, p.get("size"))
            logs.append("크기 자동 조절: " + msg)
        im, n, msg = key_background(im, int(p.get("tol", 0)), cell, rows, cols)
        logs.append(msg)
        return im, "\n".join(logs)
    if op == "scale":
        size = p.get("size") or [im.width, im.height]
        im, msg = scale_to(im, size[0], size[1])
        return im, "리샘플: " + msg
    if op == "snap":
        if not cell:
            return im, "셀 크기를 모르는 계약이라 정렬할 수 없다"
        if align == "none":
            return im, ALIGN_NONE_MSG
        only = p.get("cell_rc")
        im, n = snap_cells(im, cell, rows or 1, cols or 1, align, groups=groups,
                           only=(int(only[0]), int(only[1])) if only else None)
        return im, (f"정렬 스냅 {n}칸" if n else "이동 불필요")
    if op == "scalecells":
        only = p.get("cell_rc")
        im, msg, _n = scale_cells(im, cell, rows, cols, p.get("k", 0.9), align,
                                  only=(int(only[0]), int(only[1])) if only else None)
        return im, msg
    if op == "snapall":
        if not (cell and rows and cols):
            return im, "계약이 없어 전 셀 정렬을 못 한다"
        if align == "none":
            return im, ALIGN_NONE_MSG
        im, n = snap_cells(im, cell, rows, cols, align, groups=groups)
        return im, f"전 셀 정렬 스냅 {n}칸" + (f" (묶음 {len(groups)}개는 상자로)" if groups else "")
    if op == "autofix":
        logs = []
        tgt = _target_size(cell, rows, cols, p.get("size"))
        if tgt and (im.width, im.height) != tgt:
            # 예전에는 regrid(원본 셀 크기를 사람이 입력)였다. 웹에서 받은 시트는 셀 크기를
            # 모르는 게 보통이라 autosize가 스스로 고른다.
            im, msg = autosize(im, cell, rows, cols, p.get("size"))
            logs.append("크기 자동 조절: " + msg)
        im, n = key_magenta(im, 40)
        logs.append(f"마젠타 키잉 {n}px")
        # 마젠타가 아닌 배경(흰색·회색·하늘색…)으로 오는 납품이 더 많다. 색을 스스로 찾는다.
        im, n, msg = key_background(im, int(p.get("tol", 0)), cell, rows, cols)
        logs.append(msg)
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
        # 픽셀풍은 형태를 바꾸는 연산이라 **기본으로는 안 돈다**. 켠 경우에만.
        lv = int(p.get("pixel_level", 0) or 0)
        if lv:
            im, msg = pixelize(im, lv, cell)
            logs.append(msg)
        if cell and rows and cols:
            if align == "none":
                logs.append(ALIGN_NONE_MSG)
            else:
                im, n = snap_cells(im, cell, rows, cols, align, groups=groups)
                logs.append(f"전 셀 정렬 스냅 {n}칸")
        return im, "\n".join(logs)
    raise ValueError(f"알 수 없는 연산: {op}")
