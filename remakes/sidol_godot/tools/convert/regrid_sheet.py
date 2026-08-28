#!/usr/bin/env python3
"""격자가 어긋난 납품 시트를 계약 격자로 **자동 재배치**한다.

## 왜

리마스터 첫 납품(mad_eye·sparker)은 그림은 좋은데 **자체 격자가 계약과 어긋나** 있었다 —
프레임이 셀 경계를 넘어가 셀마다 두 포즈의 반쪽이 들어왔고(5칸), 셀마다 같은 자리에
액자 선까지 그려져 있었다. 그림을 다시 그리게 할 이유가 없는 결함이다.

이 도구는 행 단위로 이렇게 고친다:

  ① 액자·안내선 제거 — 셀마다 같은 자리에 반복되는 얇은 직선(delivery_checks 판정과 동일)
  ② 행 전체를 가로로 훑어 **실제 프레임 덩어리**를 찾는다. 셀 경계로 잘렸던 그림도
     행 스트립에서는 온전하다 — 자르기 전이 아니라 자른 뒤가 문제였기 때문이다
  ③ 가까운 덩어리를 한 프레임으로 묶는다(전기 아크·파편처럼 떨어진 부속 포함)
  ④ 계약이 요구하는 프레임 수와 맞으면 각 프레임을 셀에 **하단 중앙 정렬**로 다시 놓는다

프레임 수가 안 맞는 행은 **건드리지 않고 보고만 한다** — 추측으로 옮기면 조용히 틀린다.
그런 행은 셀 편집기(sprite_fixer.html)에서 사람이 옮긴다.

사용:
  python tools/convert/regrid_sheet.py <시트.png> [--id <스펙 id>] [--out <출력.png>]
  python tools/convert/regrid_sheet.py <시트.png> --inplace
종료코드: 0=전 행 정상 배치 / 1=일부 행을 건드리지 못함
"""
from __future__ import annotations

import io
import json
import os
import re
import sys

import numpy as np
from PIL import Image

import delivery_checks as dc

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SPEC_FILES = (
    "monster_anim_specs.json",
    "npc_anim_specs.json",
    "effect_specs.json",
    "battle_cut_specs.json",
    "battle_actor_specs.json",
)
## 이 간격 이내로 떨어진 덩어리는 같은 프레임의 부속으로 본다(전기 아크·파편·잔상).
MERGE_GAP = 10
## 셀 하단 여백 비율 — 발이 바닥에 닿게.
BOTTOM_PAD = 0.05

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def load_spec(asset_id: str) -> dict:
    for name in SPEC_FILES:
        path = os.path.join(ROOT, "data", name)
        if not os.path.exists(path):
            continue
        for sp in json.load(io.open(path, encoding="utf-8")).get("species", []):
            if sp.get("id") == asset_id:
                return sp
    return {}


def erase_frame_lines(arr: np.ndarray, cell: int) -> int:
    """셀마다 같은 자리에 반복되는 얇은 직선을 지운다. 반환: 지운 픽셀 수."""
    op = (arr[:, :, 3] > 8) & ~(
        (arr[:, :, 0] == 255) & (arr[:, :, 1] == 0) & (arr[:, :, 2] == 255)
    )
    cells, tally = dc._repeated_lines(op, cell, cell)
    if cells < 3:
        return 0
    threshold = max(2, int(cells * dc.BORDER_REPEAT_RATIO))
    killed = 0
    for axis in ("col", "row"):
        coords = [pos for (ax, pos), n in tally.items() if ax == axis and n >= threshold]
        for group in dc._thin_groups(coords):
            for pos in group:
                for r in range(arr.shape[0] // cell):
                    for c in range(arr.shape[1] // cell):
                        y0, x0 = r * cell, c * cell
                        if axis == "col":
                            seg = arr[y0:y0 + cell, x0 + pos]
                        else:
                            seg = arr[y0 + pos, x0:x0 + cell]
                        killed += int((seg[:, 3] > 8).sum())
                        seg[:] = 0
    return killed


def frame_groups(strip_mask: np.ndarray, want: int, cell_w: int) -> list:
    """행 스트립에서 프레임 덩어리를 찾아 x 순으로 묶는다. 반환 [(x0, x1), ...]."""
    parts = dc.blobs(strip_mask)
    if not parts:
        return []
    spans = sorted(((b["x0"], b["x1"]) for b in parts if b["n"] >= 20))
    if not spans:
        return []
    merged = [list(spans[0])]
    for x0, x1 in spans[1:]:
        if x0 - merged[-1][1] <= MERGE_GAP:
            merged[-1][1] = max(merged[-1][1], x1)
        else:
            merged.append([x0, x1])
    # 덩어리가 프레임 수보다 많으면 가까운 이웃끼리 더 합친다(부속이 멀리 떨어진 경우).
    # 단 **합쳐서 셀보다 넓어지면 합치지 않는다** — 그건 이웃한 두 프레임을 붙이는 것이다.
    while len(merged) > want >= 1:
        cand = [
            (merged[i + 1][0] - merged[i][1], i)
            for i in range(len(merged) - 1)
            if merged[i + 1][1] - merged[i][0] + 1 <= cell_w
        ]
        if not cand:
            break
        _gap, i = min(cand)
        merged[i][1] = max(merged[i][1], merged[i + 1][1])
        del merged[i + 1]
    return [tuple(m) for m in merged]


def score(arr: np.ndarray, cell: int, anims: list) -> tuple:
    """(반쪽 잘림 칸 수, 정렬 이탈 프레임 수) — 재배치가 실제로 나아졌는지 재는 잣대."""
    im = Image.fromarray(arr, "RGBA")
    split = sum(f.value for f in dc.check_split_cells(im, cell, cell))
    op = dc.opaque_mask(im)
    off = 0
    for name, a in anims:
        row, frames = int(a.get("row", 0)), int(a.get("frames", 1))
        for c in range(frames):
            cellmask = op[row * cell:(row + 1) * cell, c * cell:(c + 1) * cell]
            if not cellmask.any():
                continue
            parts = dc.blobs(cellmask)
            if not parts:
                continue
            main = parts[0]
            cx = (main["x0"] + main["x1"]) / 2.0
            if abs(cx - cell / 2.0) > cell * 0.12:
                off += 1
            elif (cell - 1 - main["y1"]) > cell * 0.14:
                off += 1
    return int(split), off


def regrid(path: str, asset_id: str, out_path: str) -> int:
    sp = load_spec(asset_id)
    if not sp:
        print(f"스펙 없음: {asset_id}")
        return 1
    cell = int(sp.get("sheet_cell", 128))
    anims = sorted(sp["animations"].items(), key=lambda kv: int(kv[1].get("row", 0)))
    cols = max(int(a.get("frames", 1)) for _, a in anims)
    src = Image.open(path).convert("RGBA")
    if src.size != (cols * cell, len(anims) * cell):
        print(f"크기 {src.size} != 계약 {(cols * cell, len(anims) * cell)} — 먼저 크기를 맞춰라")
        return 1

    arr = np.asarray(src).astype(np.uint8).copy()
    killed = erase_frame_lines(arr, cell)
    if killed:
        print(f"  액자·안내선 제거: {killed}px")

    out = np.zeros_like(arr)
    stuck = 0
    for name, a in anims:
        row = int(a.get("row", 0))
        want = int(a.get("frames", 1))
        y0 = row * cell
        strip = arr[y0:y0 + cell]
        mask = (strip[:, :, 3] > 8) & ~(
            (strip[:, :, 0] == 255) & (strip[:, :, 1] == 0) & (strip[:, :, 2] == 255)
        )
        groups = frame_groups(mask, want, cell)
        if len(groups) != want:
            out[y0:y0 + cell] = strip  # 손대지 않는다
            print(f"  [건너뜀] {name} 행{row}: 덩어리 {len(groups)}개 ≠ 계약 {want}프레임")
            stuck += 1
            continue
        for i, (x0, x1) in enumerate(groups):
            sub = strip[:, x0:x1 + 1]
            sub_mask = mask[:, x0:x1 + 1]
            ys = np.nonzero(sub_mask.any(axis=1))[0]
            if ys.size == 0:
                continue
            top, bot = int(ys.min()), int(ys.max())
            piece = sub[top:bot + 1]
            pm = sub_mask[top:bot + 1]
            ph, pw = piece.shape[0], piece.shape[1]
            if pw > cell or ph > cell:
                out[y0:y0 + cell] = strip
                print(f"  [건너뜀] {name} 행{row} 프레임{i}: {pw}x{ph} 가 셀 {cell} 보다 크다")
                stuck += 1
                break
            dx = (cell - pw) // 2
            dy = cell - int(cell * BOTTOM_PAD) - ph
            dy = max(0, min(dy, cell - ph))
            dst = out[y0 + dy:y0 + dy + ph, i * cell + dx:i * cell + dx + pw]
            dst[pm] = piece[pm]
    # **자기 검증** — 재배치가 오히려 나빠지면 쓰지 않는다. 자동 배치는 프레임 경계를
    # 추정하는 일이라, 그림이 불규칙하게 흩어진 납품에서는 조각을 잘못 묶을 수 있다
    # (mad_eye 실측: 지적 14건 → 29건). 그런 시트는 셀 편집기에서 사람이 옮기는 게 맞다.
    before = score(np.asarray(src).astype(np.uint8), cell, anims)
    after = score(out, cell, anims)
    if after > before:
        print(
            "  [중단] 재배치가 더 나빠진다 — 반쪽 잘림 %d→%d칸 · 정렬 이탈 %d→%d프레임"
            % (before[0], after[0], before[1], after[1])
        )
        print("         이 시트는 셀 편집기(sprite_fixer.html)에서 사람이 옮기는 편이 낫다")
        return 1
    print("  검증: 반쪽 잘림 %d→%d칸 · 정렬 이탈 %d→%d프레임" % (before[0], after[0], before[1], after[1]))
    Image.fromarray(out, "RGBA").save(out_path)
    try:  # 임시 폴더가 다른 드라이브면 상대경로를 못 만든다
        shown = os.path.relpath(out_path, ROOT).replace(os.sep, "/")
    except ValueError:
        shown = out_path
    print(f"  저장: {shown}")
    return 1 if stuck else 0


def main() -> None:
    args = list(sys.argv[1:])
    if not args:
        raise SystemExit(__doc__)
    path = args[0]
    inplace = "--inplace" in args
    asset_id = ""
    out = ""
    if "--id" in args:
        asset_id = args[args.index("--id") + 1]
    if "--out" in args:
        out = args[args.index("--out") + 1]
    if not asset_id:
        stem = os.path.splitext(os.path.basename(path))[0]
        asset_id = re.sub(r"_v\d+$", "", stem)
    if not out:
        out = path if inplace else os.path.splitext(path)[0] + "_regrid.png"
    print(f"[regrid] {os.path.basename(path)} (id={asset_id})")
    sys.exit(regrid(path, asset_id, out))


if __name__ == "__main__":
    main()
