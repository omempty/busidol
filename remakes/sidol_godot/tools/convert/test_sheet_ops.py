#!/usr/bin/env python3
"""sheet_ops 실측 시험 — 합성 시트를 만들어 각 연산이 **몇 픽셀을 어떻게** 바꾸는지 센다.

## 왜 (2026-09-08)

셀 편집기의 픽셀 규칙을 이 모듈로 모으면서, 그 규칙을 눈으로만 확인하고 넘어가면
예전과 똑같아진다(브라우저 안에 있어 아무도 못 재던 상태). 여기서 재는 것은
"연산이 돌았다"가 아니라 **그림을 안 먹고 대상만 건드렸는가**다 — 안내선 제거가
그림을 지우거나, 양자화가 외곽선을 분홍으로 만드는 것이 실제로 났던 사고다.

마지막 시험은 **부정 시험**이다: 일부러 어긋난 시트를 넣어 계측이 빨개지는지 본다.
정상 케이스만 보는 관문은 고장 나도 초록이라 아무 말도 안 해 준다.

실행: python tools/convert/test_sheet_ops.py
종료코드: 0=전부 통과 / 1=실패 있음
"""
from __future__ import annotations

import os
import re
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sheet_ops as so  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

CELL, COLS, ROWS = 32, 4, 2
W, H = CELL * COLS, CELL * ROWS
LAYOUT = [{"row": 0, "name": "walk_down", "frames": 4}, {"row": 1, "name": "attack", "frames": 2}]

_pass = _fail = 0


def check(name: str, cond: bool, detail: str = "") -> None:
    global _pass, _fail
    if cond:
        _pass += 1
        print(f"  ok   {name}" + (f" — {detail}" if detail else ""))
    else:
        _fail += 1
        print(f" FAIL  {name}" + (f" — {detail}" if detail else ""))


def sheet() -> np.ndarray:
    return np.zeros((H, W, 4), dtype=np.uint8)


def blob(a, x0, y0, w, h, rgb, alpha=255) -> None:
    a[y0:y0 + h, x0:x0 + w, :3] = rgb
    a[y0:y0 + h, x0:x0 + w, 3] = alpha


def img(a) -> Image.Image:
    return Image.fromarray(a, "RGBA")


def opaque(im) -> int:
    return int((np.asarray(im.convert("RGBA"))[:, :, 3] > 8).sum())


# ---------------------------------------------------------------- 안내선
a = sheet()
blob(a, 8, 8, 10, 16, (80, 120, 200))          # 그림 160px
a[:, CELL, :3] = (255, 0, 255); a[:, CELL, 3] = 255      # 세로 안내선
a[CELL, :, :3] = (255, 0, 255); a[CELL, :, 3] = 255      # 가로 안내선
out, removed, filled = so.clean_guides(img(a), CELL)
check("안내선 제거 — 잔선만 지운다", opaque(out) == 160,
      f"지운 {removed}px · 오염 {filled}px · 남은 그림 {opaque(out)}px(기대 160)")
check("안내선 제거 — 십자 교차점을 이중으로 세지 않는다", removed == W + H - 1,
      f"{removed}px (기대 {W + H - 1})")

# ---------------------------------------------------------------- 키잉·이진화·검정
a = sheet()
a[:, :, :3] = (255, 0, 255); a[:, :, 3] = 255
blob(a, 4, 4, 8, 8, (200, 100, 50))
out, n = so.key_magenta(img(a))
check("마젠타 키잉", opaque(out) == 64, f"{n}px 키잉 · 남은 {opaque(out)}px(기대 64)")

a = sheet()
blob(a, 1, 1, 1, 1, (10, 10, 10), 200)
blob(a, 2, 1, 1, 1, (10, 10, 10), 60)
out, n = so.binarize_alpha(img(a))
arr = np.asarray(out)
check("알파 이진화", arr[1, 1, 3] == 255 and arr[1, 2, 3] == 0,
      f"a200 -> {arr[1,1,3]}, a60 -> {arr[1,2,3]} ({n}px)")

a = sheet()
blob(a, 0, 0, 4, 4, (0, 0, 0))
out, n = so.deblack(img(a))
check("순수검정 → 남색", n == 16 and tuple(np.asarray(out)[0, 0, :3]) == so.DARK_NAVY,
      f"{n}px · {tuple(np.asarray(out)[0,0,:3])}")

# ---------------------------------------------------------------- 색 지우개·양자화
a = sheet()
blob(a, 0, 0, 4, 4, (100, 100, 100))
blob(a, 8, 0, 4, 4, (104, 98, 102))            # 허용오차 안
blob(a, 16, 0, 4, 4, (10, 200, 10))            # 밖
out, n = so.erase_color(img(a), (100, 100, 100), 8)
check("색 지우개(허용오차)", opaque(out) == 16 and n == 32, f"지움 {n}px · 남음 {opaque(out)}px(기대 16)")

a = sheet()
for y in range(16):
    for x in range(16):
        blob(a, x, y, 1, 1, (x * 16, y * 16, 128))
out = so.quantize(img(a), 8)
arr = np.asarray(out)
vis = arr[:, :, 3] > 8
check("색 양자화 상한", len({tuple(v) for v in arr[:, :, :3][vis]}) <= 8,
      f"256색 → {len({tuple(v) for v in arr[:, :, :3][vis]})}색(요청 8)")

# ---------------------------------------------------------------- 정렬 스냅
a = sheet()
blob(a, 2, 2, 6, 6, (90, 90, 160))             # r0c0 좌상단 구석
out, moved = so.snap_cells(img(a), CELL, ROWS, COLS, "bottom_center")
bb = so.cell_bbox(np.asarray(out).copy(), CELL, 0, 0)
cx = (bb["x0"] + bb["x1"]) / 2
gap = CELL - 1 - bb["y1"]
check("정렬 스냅 — 가로 중앙", abs(cx - CELL / 2) <= 1, f"중심 x={cx}(기대 {CELL/2})")
check("정렬 스냅 — 하단 여백 4%", gap == int(CELL * so.BOTTOM_MARGIN), f"{gap}px(기대 {int(CELL*so.BOTTOM_MARGIN)})")
check("정렬 스냅 — 그림을 잃지 않는다", opaque(out) == 36, f"{opaque(out)}px(기대 36)")

# ---------------------------------------------------------------- 재배치·리샘플
a = np.zeros((16 * ROWS, 16 * COLS, 4), dtype=np.uint8)
blob(a, 0, 0, 16, 16, (200, 0, 0))
out, msg = so.regrid(img(a), 16, CELL, ROWS, COLS)
bb = so.cell_bbox(np.asarray(out).copy(), CELL, 0, 0)
check("계약 격자로 재배치", out.size == (W, H) and bb["x1"] - bb["x0"] + 1 == CELL,
      f"{out.size} · r0c0 폭 {bb['x1']-bb['x0']+1}px · {msg}")

# ---------------------------------------------------------------- 배경 자동 제거
# 흰 배경 납품 + **그림 안쪽의 흰 점**. 색만 보고 지우면 안쪽 흰자에 구멍이 난다 —
# 연결성으로 지워야 배경만 빠진다. 이게 이 연산의 존재 이유다.
a = sheet()
a[:, :, :3] = (255, 255, 255); a[:, :, 3] = 255
blob(a, 8, 8, 10, 16, (80, 120, 200))          # 그림 160px
blob(a, 12, 12, 2, 2, (255, 255, 255))         # 그림 안쪽 흰 점 4px
out, n, msg = so.key_background(img(a), 0, CELL, ROWS, COLS)
arr = np.asarray(out)
check("배경 자동 제거 — 배경만 빠지고 그림은 남는다", opaque(out) == 160,
      f"지운 {n}px · 남은 {opaque(out)}px(기대 160) · {msg}")
check("배경 자동 제거 — 그림 안쪽의 같은 색을 지키다", arr[13, 13, 3] == 255 and tuple(arr[13, 13, :3]) == (255, 255, 255),
      f"안쪽 흰 점 = {tuple(arr[13,13])}")

# 이미 투명한 시트는 손대지 않는다(두 번 눌러도 안전한가).
a = sheet()
blob(a, 4, 4, 8, 8, (200, 100, 50))
out, n, msg = so.key_background(img(a))
check("배경 자동 제거 — 이미 투명하면 손대지 않는다", n == 0 and opaque(out) == 64, msg)

# 가장자리가 얼룩덜룩하면(배경이 아니라 그림이 가장자리까지 찬 경우) 보류해야 한다.
a = sheet()
rng = np.random.default_rng(7)
a[:, :, :3] = rng.integers(0, 255, (H, W, 3), dtype=np.uint8)
a[:, :, 3] = 255
out, n, msg = so.key_background(img(a))
check("배경 자동 제거 — 단색이 아니면 보류한다", n == 0 and opaque(out) == W * H, msg)

# 칸 안에 갇힌 배경 — 바깥 테두리와 이어지지 않아도 셀 경계 씨앗으로 뚫린다.
a = sheet()
a[:, :, :3] = (255, 255, 255); a[:, :, 3] = 255
a[1, 1:-1, :3] = (30, 40, 90); a[-2, 1:-1, :3] = (30, 40, 90)      # 1px 안쪽에 파란 액자
a[1:-1, 1, :3] = (30, 40, 90); a[1:-1, -2, :3] = (30, 40, 90)
out, n, msg = so.key_background(img(a), 0, CELL, ROWS, COLS)
arr = np.asarray(out)
check("배경 자동 제거 — 칸 안에 갇힌 배경도 뚫는다", arr[H // 2, W // 2, 3] == 0,
      f"한가운데 alpha={arr[H//2, W//2, 3]} · {msg}")

# 반대 방향 안전장치: 셀 경계가 그림으로 덮여 있으면 씨앗을 심지 않는다.
a = sheet()
a[:, :, :3] = (255, 255, 255); a[:, :, 3] = 255
a[:, CELL - 2:CELL + 2, :3] = (30, 40, 90)      # 경계선을 그림이 덮고 있다
out, n, msg = so.key_background(img(a), 0, CELL, ROWS, COLS)
arr = np.asarray(out)
check("배경 자동 제거 — 그림이 덮은 셀 경계는 씨앗에서 뺀다", "3줄" in msg,
      f"경계 4줄 중 그림이 덮은 1줄을 빼고 3줄이어야 · {msg}")
check("배경 자동 제거 — 경계를 덮은 그림은 살아남는다", arr[H // 2, CELL, 3] == 255,
      f"x={CELL} 열의 alpha={arr[H//2, CELL, 3]}")

# ---------------------------------------------------------------- 픽셀풍
# 픽셀마다 색이 다른 '너무 세밀한' 그림 — 생성 모델이 흔히 주는 모양.
a = sheet()
for y in range(H):
    for x in range(W):
        blob(a, x, y, 1, 1, ((x * 7) % 256, (y * 11) % 256, (x * y) % 256))
fine = img(a)
d0 = so.detail_ratio(fine)
out, msg = so.pixelize(fine, 4, CELL)
arr = np.asarray(out)
d1 = so.detail_ratio(out)
check("픽셀풍 — 세밀도가 떨어진다", d1 < d0 * 0.5, f"{d0:.2f} → {d1:.2f} · {msg}")
check("픽셀풍 — 캔버스 크기를 그대로 둔다", out.size == (W, H), f"{out.size}")
blocks_uniform = all(len({tuple(v) for v in arr[by:by + 4, bx:bx + 4, :3].reshape(-1, 3)}) == 1
                     for by in range(0, H, 4) for bx in range(0, W, 4))
check("픽셀풍 — 블록마다 단색이다", blocks_uniform, "4×4 블록 안에 색이 둘 이상 있으면 실패")
check("픽셀풍 — 원본에 없던 중간색을 만들지 않는다(최빈색)",
      set(map(tuple, arr[:, :, :3].reshape(-1, 3))) <= set(map(tuple, np.asarray(fine)[:, :, :3].reshape(-1, 3))),
      "평균색을 쓰면 여기서 실패한다")

# 레벨은 셀 크기의 약수로 당긴다 — 블록이 셀 경계에 걸치면 정렬 판정이 어긋난다.
out, msg = so.pixelize(fine, 5, CELL)          # 32는 5로 안 나눠떨어진다
check("픽셀풍 — 레벨을 셀 크기의 약수로 당긴다", "레벨 4px" in msg, msg)

# 반투명한 술이 남지 않는다(블록 절반 미만이 불투명하면 통째로 투명).
a = sheet()
blob(a, 0, 0, 1, 4, (200, 50, 50))             # 4x4 블록의 1/4만 채움
out, msg = so.pixelize(img(a), 4, CELL)
check("픽셀풍 — 반쯤 빈 블록은 투명으로", opaque(out) == 0, f"{opaque(out)}px 남음 · {msg}")

check("세밀도 — 단색 그림은 낮다", so.detail_ratio(img(sheet_solid := (lambda: (lambda b: (blob(b, 4, 4, 20, 20, (10, 20, 30)), b)[1])(sheet()))())) < 0.2,
      "단색 덩어리")

# ---------------------------------------------------------------- 행별 재배치(refit)
# 행마다 그 행의 프레임 수로 가로를 나눈 시트(생성 모델이 실제로 주는 모양).
# 통짜 축소로는 2행 프레임이 칸 경계에서 잘리고 여분 칸까지 넘친다.
RAG_W, RAG_H = 96 * 4, 96 * 3
rag = np.zeros((RAG_H, RAG_W, 4), dtype=np.uint8)
for r, (n, sz) in enumerate([(4, 40), (3, 80), (3, 70)]):
    for c in range(n):
        cx = int(RAG_W * (c + 0.5) / n)
        cy = int(RAG_H * (r + 0.5) / 3)
        blob(rag, cx - sz // 2, cy - sz // 2, sz, sz, (90 + 20 * r, 120, 200))
RAG_LAYOUT = [{"row": 0, "frames": 4}, {"row": 1, "frames": 3}, {"row": 2, "frames": 3}]

flat, _ = so.autosize(img(rag), CELL, 3, 4)
flat, _ = so.snap_cells(flat, CELL, 3, 4, "bottom_center")
mflat = so.measure(flat, CELL, 3, 4, RAG_LAYOUT, "bottom_center")
check("부정 시험 — 통짜 축소는 여분 칸을 침범한다",
      any("여분 셀에 내용" in i for i in mflat["cell_issues"]),
      "이 시험이 통과해야 refit이 필요한 이유가 성립한다: "
      + "; ".join(mflat["cell_issues"][:3]))

fit, msg, n = so.refit(img(rag), CELL, 3, 4, RAG_LAYOUT, "bottom_center")
check("행별 재배치 — 선언한 프레임을 전부 앉힌다", n == 10, f"{n}개 · {msg}")
check("행별 재배치 — 캔버스가 계약 크기다", fit.size == (CELL * 4, CELL * 3), f"{fit.size}")
mfit = so.measure(fit, CELL, 3, 4, RAG_LAYOUT, "bottom_center")
check("행별 재배치 — 계측 이상이 사라진다", not mfit["cell_issues"],
      "; ".join(mfit["cell_issues"][:4]))

fa = np.asarray(fit)
sizes = {}
for r in range(3):
    for c in range(RAG_LAYOUT[r]["frames"]):
        bb = so.cell_bbox(fa.copy(), CELL, r, c)
        sizes[(r, c)] = (bb["x1"] - bb["x0"] + 1) if bb else 0
check("행별 재배치 — 칸 경계에 닿지 않는다", all(v < CELL for v in sizes.values()),
      f"{ {k: v for k, v in sizes.items() if v >= CELL} }")
check("행별 재배치 — 크기 관계를 뭉개지 않는다(공통 축척)",
      sizes[(0, 0)] < sizes[(2, 0)] < sizes[(1, 0)],
      f"walk {sizes[(0,0)]} · death {sizes[(2,0)]} · attack {sizes[(1,0)]} (원본 40<70<80)")
check("행별 재배치 — 같은 행 프레임은 같은 크기다",
      len({sizes[(1, c)] for c in range(3)}) == 1, f"{[sizes[(1,c)] for c in range(3)]}")

# 격자가 없으면 손대지 않는다.
_, msg, n = so.refit(img(rag), 0, 0, 0, RAG_LAYOUT, "bottom_center")
check("행별 재배치 — 계약 격자가 없으면 손대지 않는다", n == 0 and "격자가 없어" in msg, msg)

# ------------------------------------------------- 채움 비율(fill)·행 선택(only_row)
# 기계가 고른 축척 하나로는 행마다 삐져나오는 양이 달라 맞출 수 없다. 그래서 사람이
# 비율을 주고(fill), 행 하나씩 손본다(only_row). 여기서 재는 것은 그 두 손잡이가
# **다른 행을 안 건드리고** · **넘친 픽셀을 조용히 안 자르는가**다.


def frame_h(im, r, c):
    bb = so.cell_bbox(np.asarray(im.convert("RGBA")).copy(), CELL, r, c)
    return (bb["y1"] - bb["y0"] + 1) if bb else 0


def frame_w(im, r, c):
    bb = so.cell_bbox(np.asarray(im.convert("RGBA")).copy(), CELL, r, c)
    return (bb["x1"] - bb["x0"] + 1) if bb else 0


def clipped_of(msg):
    """문장에서 잘린 픽셀 수를 뽑는다 — '조용히 자르지 않는다'가 말로 지켜지는지 본다."""
    m = re.search(r"잘린 픽셀 ([\d,]+)px", msg)
    return int(m.group(1).replace(",", "")) if m else 0


# 1) fill=1.0은 예전 동작과 픽셀 단위로 같아야 한다(회귀 금지).
base, base_msg, _ = so.refit(img(rag), CELL, 3, 4, RAG_LAYOUT, "bottom_center")
one, one_msg, _ = so.refit(img(rag), CELL, 3, 4, RAG_LAYOUT, "bottom_center", fill=1.0)
check("fill — 1.0은 인자 없던 예전 결과와 바이트 일치",
      np.array_equal(np.asarray(base), np.asarray(one)),
      f"두 결과의 불일치 픽셀 {int((np.asarray(base) != np.asarray(one)).any(axis=2).sum())}px(기대 0) · {one_msg}")

# 2) fill=0.6이면 프레임이 실제로 작아진다 — 눈이 아니라 경계상자로 잰다.
small, small_msg, _ = so.refit(img(rag), CELL, 3, 4, RAG_LAYOUT, "bottom_center", fill=0.6)
h10, h10s = frame_h(base, 1, 0), frame_h(small, 1, 0)
h20, h20s = frame_h(base, 2, 0), frame_h(small, 2, 0)
ratio = h10s / max(1, h10)
check("fill — 0.6이면 프레임 높이가 0.6배가 된다", abs(ratio - 0.6) <= 0.1,
      f"r1c0 {h10}px → {h10s}px (비 {ratio:.3f}) · r2c0 {h20}px → {h20s}px · {small_msg}")
check("fill — 범위 밖 값은 잘라 내고 그 사실을 문장에 적는다",
      "제한" in so.refit(img(rag), CELL, 3, 4, RAG_LAYOUT, "bottom_center", fill=9.0)[1],
      so.refit(img(rag), CELL, 3, 4, RAG_LAYOUT, "bottom_center", fill=9.0)[1][-60:])
check("fill — 축척 값을 문장에 노출한다(행끼리 비율을 맞출 근거)",
      "축척" in small_msg and "채움 0.60" in small_msg, small_msg)

# 3) only_row=r — 그 행만 바뀌고 나머지 행은 **입력 그대로**여야 한다.
# 입력은 이미 계약 캔버스인 시트(행마다 자기 프레임 수로 가로를 나눠 그린 모양).
rag2 = np.zeros((CELL * 3, CELL * 4, 4), dtype=np.uint8)
for r, (n, sz) in enumerate([(4, 20), (3, 26), (3, 22)]):
    for c in range(n):
        cx = int(CELL * 4 * (c + 0.5) / n)
        cy = CELL * r + CELL // 2
        blob(rag2, cx - sz // 2, cy - sz // 2, sz, sz, (90 + 20 * r, 120, 200))
src2 = np.asarray(img(rag2).convert("RGBA"))
row1, row1_msg, n1 = so.refit(img(rag2), CELL, 3, 4, RAG_LAYOUT, "bottom_center",
                              fill=0.6, only_row=1)
r1a = np.asarray(row1)
check("only_row — 고르지 않은 행은 입력 픽셀 그대로다",
      np.array_equal(r1a[0:CELL], src2[0:CELL]) and np.array_equal(r1a[2 * CELL:], src2[2 * CELL:]),
      f"행0 불일치 {int((r1a[0:CELL] != src2[0:CELL]).any(axis=2).sum())}px · "
      f"행2 불일치 {int((r1a[2*CELL:] != src2[2*CELL:]).any(axis=2).sum())}px (둘 다 0이어야)")
check("only_row — 고른 행은 실제로 바뀐다",
      not np.array_equal(r1a[CELL:2 * CELL], src2[CELL:2 * CELL]) and n1 == 3,
      f"행1 바뀐 픽셀 {int((r1a[CELL:2*CELL] != src2[CELL:2*CELL]).any(axis=2).sum())}px · "
      f"앉힌 프레임 {n1}개(기대 3) · {row1_msg}")

# 축척은 **그 행만** 보고 잡아야 한다 — 전 시트 축척을 쓰면 이미 작아진 다른 행이
# 최댓값 계산에 끼어들어 누르는 순서가 결과를 바꾼다.
k_row = float(re.search(r"축척 ([\d.]+)", row1_msg).group(1))
k_all = float(re.search(r"축척 ([\d.]+)", small_msg).group(1))
check("only_row — 축척을 그 행만 보고 잡는다",
      abs(k_row - min(CELL / 26, (CELL - round(CELL * so.BOTTOM_MARGIN)) / 26) * 0.6) < 0.002,
      f"행1 최대 프레임 26px 기준 축척 {k_row:.3f} (전 시트 축척 {k_all:.3f}과 다른 값이어야)")

# 4) 계약과 크기가 다르면 이 행만은 재배치할 수 없다 — 손대지 말고 안내한다.
odd_row, odd_msg, odd_n = so.refit(img(rag), CELL, 3, 4, RAG_LAYOUT, "bottom_center", only_row=1)
check("only_row — 계약과 크기가 다르면 손대지 않고 안내한다",
      odd_n == 0 and np.array_equal(np.asarray(odd_row.convert("RGBA")), np.asarray(img(rag)))
      and "크기 자동 조절" in odd_msg,
      f"프레임 {odd_n}개(기대 0) · {odd_msg}")
check("only_row — 범위 밖 행은 아무것도 안 한다",
      so.refit(img(rag2), CELL, 3, 4, RAG_LAYOUT, "bottom_center", only_row=7)[2] == 0,
      so.refit(img(rag2), CELL, 3, 4, RAG_LAYOUT, "bottom_center", only_row=7)[1])

# 5) fill>1.0 — 칸을 넘친다. 넘친 픽셀이 이웃 칸을 침범하면 옆 프레임을 덮어써
#    붙이는 순서가 결과를 바꾼다. 클립하고, 자른 양을 문장에 적어야 한다.
big_fit, big_msg, _ = so.refit(img(rag), CELL, 3, 4, RAG_LAYOUT, "bottom_center", fill=1.5)
cut = clipped_of(big_msg)
check("fill>1 — 잘린 픽셀 수를 문장에 적는다(조용히 자르지 않는다)", cut > 0,
      f"잘린 {cut:,}px · {big_msg}")
bf = np.asarray(big_fit)
check("fill>1 — 칸을 실제로 넘쳐 가로를 꽉 채운다(클립이 도는 상황이 맞다)",
      frame_w(big_fit, 1, 0) == CELL, f"r1c0 폭 {frame_w(big_fit,1,0)}px(칸 {CELL}px)")
# 1·2행은 3프레임 계약이라 c3은 비어 있어야 한다. 클립을 안 하면 c2가 넘쳐 여기로 샌다.
invade = [f"r{r}c3 {int((bf[r*CELL:(r+1)*CELL, 3*CELL:4*CELL, 3] > 8).sum())}px"
          for r in (1, 2) if (bf[r * CELL:(r + 1) * CELL, 3 * CELL:4 * CELL, 3] > 8).any()]
check("fill>1 — 넘친 픽셀이 이웃 칸을 침범하지 않는다", not invade,
      "; ".join(invade) or "여분 칸 r1c3·r2c3 모두 0px")
mbig = so.measure(big_fit, CELL, 3, 4, RAG_LAYOUT, "bottom_center")
check("fill>1 — 여분 셀 침범이 계측에도 안 잡힌다",
      not any("여분 셀에 내용" in i for i in mbig["cell_issues"]),
      "; ".join(mbig["cell_issues"][:3]) or "계측 이상 없음")

# 6) 디스패치 — 편집기가 보내는 JSON은 숫자가 문자열로 온다.
out_s, msg_s = so.apply_op(img(rag2), "refit",
                           {"cell": CELL, "rows": 3, "cols": 4, "align": "bottom_center",
                            "layout": RAG_LAYOUT, "fill": "0.6", "only_row": "1"})
check("apply_op — 문자열로 온 fill·only_row를 알아듣는다",
      np.array_equal(np.asarray(out_s)[0:CELL], src2[0:CELL]) and "채움 0.60" in msg_s
      and "행 1만 재배치" in msg_s, msg_s)
out_d, msg_d = so.apply_op(img(rag2), "refit",
                           {"cell": CELL, "rows": 3, "cols": 4, "align": "bottom_center",
                            "layout": RAG_LAYOUT, "only_row": ""})
check("apply_op — fill 없음·only_row 빈 문자열이면 예전 그대로 돈다",
      "채움 1.00" in msg_d and "행별 재배치" in msg_d, msg_d)

# ---------------------------------------------------------------- 격자 없는 계약(keyart)
# 셀이 0이고 size만 있는 계약(keyart 1920x1080)에서 자동 조절이 통째로 건너뛰어지던 결함.
# 2026-09-08 실측: 2048x1152로 온 납품이 편집기에서 그대로 남았다.
KEY = [192, 108]                                # 시험용 축소판(같은 16:9)
big = Image.new("RGBA", (256, 144), (255, 255, 255, 255))
out, msg = so.autosize(big, 0, 1, 1, KEY)
check("격자 없는 계약 — 비율이 같으면 균일 리샘플", out.size == tuple(KEY), f"{out.size} · {msg}")

odd = Image.new("RGBA", (200, 200), (255, 255, 255, 255))
out, msg = so.autosize(odd, 0, 1, 1, KEY)
check("격자 없는 계약 — 비율이 다르면 채우고 가운데를 자른다",
      out.size == tuple(KEY) and "잘라 낸 양" in msg, f"{out.size} · {msg}")

out, msg = so.autosize(Image.new("RGBA", tuple(KEY)), 0, 1, 1, KEY)
check("격자 없는 계약 — 이미 맞으면 손대지 않는다", "변경 없음" in msg, msg)

out, msg = so.autosize(big, 0, 1, 1, [0, 0])
check("계약이 없으면 크기를 건드리지 않는다", out.size == (256, 144) and "계약이 없어" in msg, msg)

# 디스패치까지 이어지는가 — autoprep이 격자 없는 계약에서도 크기를 고쳐야 한다.
out, msg = so.apply_op(Image.new("RGBA", (256, 144), (255, 255, 255, 255)), "autoprep",
                       {"cell": 0, "rows": 1, "cols": 1, "size": KEY, "align": "none"})
check("autoprep — 격자 없는 계약에서도 크기를 맞춘다", out.size == tuple(KEY),
      f"{out.size} · {msg.splitlines()[0] if msg else ''}")

# ---------------------------------------------------------------- 열자마자 자동 보정(autoprep)
# 크기도 틀리고 배경도 흰색인, 웹 LLM 납품의 전형.
a = np.zeros((48 * ROWS, 48 * COLS, 4), dtype=np.uint8)
a[:, :, :3] = (255, 255, 255); a[:, :, 3] = 255
a[10:40, 10:40, :3] = (60, 90, 180)
out, msg = so.apply_op(img(a), "autoprep",
                       {"cell": CELL, "rows": ROWS, "cols": COLS, "align": "bottom_center"})
check("autoprep — 크기와 배경을 한 번에 맞춘다",
      out.size == (W, H) and np.asarray(out)[0, 0, 3] == 0,
      f"{out.size} · 좌상단 alpha={np.asarray(out)[0,0,3]} · {msg.splitlines()[0] if msg else ''}")

# ---------------------------------------------------------------- 계측
a = sheet()
blob(a, 0, 0, 4, 4, (0, 0, 0))
blob(a, 20, 20, 1, 1, (10, 20, 30), 128)
m = so.measure(img(a), CELL, ROWS, COLS, LAYOUT, "bottom_center")
check("계측 — 반투명·검정 집계", m["semi"] == 1 and m["black"] == 16,
      f"semi={m['semi']} black={m['black']} colors={m['colors']}")

# ---------------------------------------------------------------- 부정 시험
# 계약은 r0 4프레임 · r1 2프레임인데 그림을 r0c0 한 칸에만, 그것도 위쪽에 붙여 넣는다.
# 계측이 "빈 셀"과 "하단 정렬 이탈"을 잡아야 한다 — 못 잡으면 관문이 고장 난 것이다.
a = sheet()
blob(a, 2, 2, 6, 6, (90, 90, 160))
m = so.measure(img(a), CELL, ROWS, COLS, LAYOUT, "bottom_center")
issues = m["cell_issues"]
check("부정 시험 — 빈 셀을 잡는다", sum("비어 있음" in i for i in issues) == 5,
      f"{sum('비어 있음' in i for i in issues)}건(계약 6칸 중 채운 1칸 제외)")
check("부정 시험 — 정렬 이탈을 잡는다", any("하단 정렬 이탈" in i for i in issues),
      "; ".join(i for i in issues if "정렬" in i) or "못 잡음")
a = sheet()
blob(a, 8, 8, 10, 16, (80, 120, 200))          # 그림
a[:, CELL, :3] = (255, 0, 255)                 # 세로 마젠타 안내선 1줄 주입
a[:, CELL, 3] = 255
m = so.measure(img(a), CELL, ROWS, COLS, LAYOUT, "bottom_center")
check("부정 시험 — 안내선을 잡는다", m["guides"] > 0, f"guides={m['guides']}px")

# ---------------------------------------------------------------- 묶음(다중 타일 소품)
# 왜: 책상·사물함은 **칸 경계를 가로질러 이어져 있는 것이 정상**이다. 칸 단위로 재고
# 칸 단위로 정렬하면 조각들이 각자 칸 중앙으로 흩어져 소품이 부서지고, 계측은 조각마다
# "가로 중앙 이탈"을 뱉어 통째로 빨개진다. 그 둘을 여기서 픽셀로 잰다.
GROUPS = [{"id": "desk_pc", "r": 0, "c": 0, "w": 2, "h": 1}]
GL = [{"row": 0, "name": "props", "frames": 2}, {"row": 1, "name": "props", "frames": 0}]

a = sheet()
blob(a, 4, 8, 56, 20, (90, 130, 210))         # r0c0~c1을 가로지르는 책상 하나
before = a.copy()
im, n = so.snap_cells(img(a), CELL, ROWS, COLS, "bottom_center", groups=GROUPS)
after = np.asarray(im)
gb = so.box_bbox(after, CELL, 0, 0, 2, 1)
check("묶음 — 상자 하나로 정렬한다(조각으로 안 쪼갠다)",
      gb is not None and (gb["x1"] - gb["x0"] + 1) == 56,
      f"상자 폭 {None if not gb else gb['x1'] - gb['x0'] + 1}px (기대 56 — 쪼개지면 달라진다)")
check("묶음 — 정렬해도 픽셀을 잃지 않는다",
      int((after[:, :, 3] > 8).sum()) == int((before[:, :, 3] > 8).sum()),
      f"{int((before[:, :, 3] > 8).sum())}px → {int((after[:, :, 3] > 8).sum())}px")

# 묶음을 안 넘기면(예전 동작) 같은 그림이 어떻게 되는지 — 이 대조가 있어야 위 시험이 의미를 갖는다.
a2 = sheet()
blob(a2, 4, 8, 56, 20, (90, 130, 210))
im2, _ = so.snap_cells(img(a2), CELL, ROWS, COLS, "bottom_center")
gb2 = so.box_bbox(np.asarray(im2), CELL, 0, 0, 2, 1)
check("부정 시험 — 묶음을 모르면 소품이 부서진다",
      gb2 is not None and (gb2["x1"] - gb2["x0"] + 1) != 56,
      f"묶음 없이 정렬한 상자 폭 {None if not gb2 else gb2['x1'] - gb2['x0'] + 1}px (56이면 부정 시험 실패)")

a = sheet()
blob(a, 12, 8, 48, 20, (90, 130, 210))     # 상자 안에서 오른쪽으로 치우친 소품 — 칸 단위로 재면 왼쪽 조각이 중앙 이탈로 잡힌다
m_no = so.measure(img(a), CELL, ROWS, COLS, GL, "bottom_center")
m_yes = so.measure(img(a), CELL, ROWS, COLS, GL, "bottom_center", groups=GROUPS)
check("묶음 — 계측이 칸 경계 가로지름을 결함으로 안 센다",
      not any("중앙 이탈" in i for i in m_yes["cell_issues"]),
      "; ".join(m_yes["cell_issues"]) or "없음")
check("부정 시험 — 묶음을 모르면 계측이 중앙 이탈로 잡는다",
      any("중앙 이탈" in i for i in m_no["cell_issues"]),
      "; ".join(m_no["cell_issues"]) or "못 잡음")

m_empty = so.measure(img(sheet()), CELL, ROWS, COLS, GL, "bottom_center", groups=GROUPS)
check("묶음 — 빈 묶음을 잡는다",
      any("묶음 desk_pc" in i and "비어" in i for i in m_empty["cell_issues"]),
      "; ".join(m_empty["cell_issues"]) or "못 잡음")

a = sheet()
blob(a, 4, 8, 8, 8, (90, 130, 210))           # 상자를 거의 안 채운 소품
m_thin = so.measure(img(a), CELL, ROWS, COLS, GL, "bottom_center", groups=GROUPS)
check("묶음 — 상자를 거의 안 채우면 알린다",
      any("거의 안 채움" in i for i in m_thin["cell_issues"]),
      "; ".join(m_thin["cell_issues"]) or "못 잡음")

# align=none — 타일·아이콘·초상은 칸을 가득 채우는 것이 정상이라 밀면 안 된다.
a = sheet()
blob(a, 0, 0, CELL, CELL, (60, 160, 120))      # 칸을 꽉 채운 타일
im, n = so.snap_cells(img(a), CELL, ROWS, COLS, "none")
check("align=none — 정렬 스냅이 타일을 밀지 않는다",
      n == 0 and np.array_equal(np.asarray(im), a),
      f"옮긴 칸 {n}개 · 픽셀 일치 {np.array_equal(np.asarray(im), a)}")
_, msg = so.apply_op(img(a), "snapall",
                     {"cell": CELL, "rows": ROWS, "cols": COLS, "align": "none"})
check("align=none — 왜 안 움직였는지 문장으로 답한다", "align=none" in msg, msg[:60])
m_none = so.measure(img(a), CELL, ROWS, COLS, GL, "none")
check("align=none — 계측이 중앙 이탈을 안 만든다",
      not any("이탈" in i for i in m_none["cell_issues"]),
      "; ".join(m_none["cell_issues"]) or "없음")


print(f"\n[test_sheet_ops] 통과 {_pass} · 실패 {_fail}")
sys.exit(1 if _fail else 0)
