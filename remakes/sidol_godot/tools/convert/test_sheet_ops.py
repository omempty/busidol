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

print(f"\n[test_sheet_ops] 통과 {_pass} · 실패 {_fail}")
sys.exit(1 if _fail else 0)
