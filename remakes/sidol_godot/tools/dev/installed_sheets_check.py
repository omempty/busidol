#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""설치 산출물 관문 — **게임이 읽는 그림**이 **게임이 읽는 계약**과 맞는가.

## 왜 이 관문이 있는가 (2026-09-09, 실측)

납품 검증기(`validate_monster_sheet.py`)는 `10_submitted`의 납품에만 돈다
(`intake.py`, `review_server.py`가 부르는 자리가 전부다). 설치기가 그 뒤에
`clean_guides` + `quantize`를 돌려 `assets/sprites/<id>_remake.png`를 만드는데,
**그 결과를 다시 재는 곳이 없었다.**

그 사이에서 그림이 바뀐다. `sheet_ops.quantize`는 이름과 달리 알파도 0/255로
이진화하므로, 소프트 알파로 온 납품은 설치하면서 깎인다. flying_thesis 실측:

    전체 내용 픽셀   45707 -> 40241  (-12.0%)
    attack r1c0     본체 92% -> 66% · 중심 x 74.0 -> 82.5   (정렬 계약 이탈)
    attack r1c2     본체 84% -> 66% · 중심 x 57.5 -> 39.5   (정렬 계약 이탈)

즉 **납품 게이트를 통과한 시트가 설치에서 계약을 깨고, 아무도 그걸 몰랐다.**
이 저장소의 지배적 결함(데이터는 있는데 읽는 코드가 없다)이 관문에서 난 모양이다.

## 무엇을 재나

`assets/sprites/<id>_remake.png` 를 그 옆의 `<id>_remake.json` **계약으로** 잰다.
스펙 파일이 아니라 설치된 메타를 쓰는 이유: 게임은 이 메타를 읽는다. 메타와 PNG가
갈라진 것도 여기서 잡혀야 한다.

  [ERR ] 크기가 계약(cols x cell, rows x cell)과 다르다
  [ERR ] 선언한 프레임 칸이 비어 있다        -> 재생하면 빈 화면이 나온다
  [ERR ] 여분 칸에 내용이 있다               -> 다음 프레임에 잔상이 붙는다
  [ERR ] 정렬 이탈(가로 중앙 / 하단 접지)     -> 칸 안에서 떠 보이거나 어긋난다
  [warn] 고유색이 계약을 넘는다              -> --no-quantize로 설치한 경우 등
  [warn] 반투명이 내용의 절반을 넘는다        -> 도트가 아니라 소프트 알파다
  [ERR ] 설치본이 처리본에서 재현되지 않는다  -> **낡았다**(아래)

## 낡음 검사가 따로 있는 이유 (2026-09-09, 실측)

승인이 나면 `20_processed/<id>/processed_sheet.png`가 갱신되는데, **설치가 자동으로
따라가지 않는다.** 그래서 게임에는 옛 산출물이 남는다. 실측에서 11종 중 3종
(flying_thesis · null_pointer · rogue_vending)이 그 상태였고, null_pointer는 설치본이
계약까지 어기고 있었다(11프레임 하단 정렬 이탈, 내용 30~40% 적음).

계약 검사만으로는 "낡았지만 계약은 맞는" 경우를 못 잡는다 — 그건 게임이 **옛 그림**을
쓰고 있다는 뜻이라 조용히 넘어가면 안 된다. 그래서 처리본에 설치 연산
(clean_guides + quantize)을 돌려 픽셀이 같은지 직접 대조한다.

정렬 판정은 `delivery_checks.align_anchor` 하나를 쓴다 — 납품 검증기·편집기 계측·
정렬 스냅과 **같은 잣대**여야 "여기선 통과인데 저기선 반려"가 안 생긴다.

실행: python tools/dev/installed_sheets_check.py
종료코드: 0=통과 / 1=계약 위반 있음
"""
from __future__ import annotations

import glob
import io
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "convert"))
import delivery_checks as dc  # noqa: E402
import sheet_ops as so  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SPRITES = os.path.join(ROOT, "assets", "sprites")
PROCESSED = os.path.join(ROOT, "assets", "raw", "llm", "20_processed")
## 납품 검증기와 같은 허용 오차 — 다른 값을 쓰면 두 관문이 서로 다른 말을 한다.
ALIGN_TOL_X = 0.12
ALIGN_TOL_BOTTOM = 0.14
COLOR_BUDGET = 48
SEMI_SOFT_ART = 0.5


def opaque_mask(cell_img: Image.Image) -> np.ndarray:
    """불투명(=그림) 마스크. 마젠타 배경도 배경으로 친다(납품 검증기와 같은 판정)."""
    arr = np.asarray(cell_img)
    rgb = arr[:, :, :3]
    is_magenta = (rgb[:, :, 0] > 240) & (rgb[:, :, 1] < 20) & (rgb[:, :, 2] > 240)
    return (arr[:, :, 3] > 8) & ~is_magenta


def check_sheet(png: str, meta_path: str) -> tuple:
    """(오류 목록, 경고 목록). 계약은 설치된 메타에서 읽는다."""
    errs: list[str] = []
    warns: list[str] = []
    name = os.path.basename(png)

    try:
        with io.open(meta_path, encoding="utf-8") as f:
            meta = json.load(f)
    except (OSError, ValueError) as exc:
        return ([f"{name}: 메타를 읽을 수 없다 ({exc})"], [])

    cell = int(meta.get("cell") or meta.get("cell_w") or 0)
    cols = int(meta.get("cols") or 0)
    anims = meta.get("animations") or {}
    if not (cell and cols and anims):
        return ([f"{name}: 메타에 cell/cols/animations가 없다 — 게임이 못 읽는다"], [])

    layout = [(int(a.get("row", 0)), int(a.get("frames", 1)), n) for n, a in anims.items()]
    rows = max(r for r, _, _ in layout) + 1
    align = str(meta.get("align", "bottom_center"))

    im = Image.open(png).convert("RGBA")
    want = (cols * cell, rows * cell)
    if im.size != want:
        return ([f"{name}: 크기 {im.size[0]}x{im.size[1]} — 계약 {want[0]}x{want[1]}"
                 f" ({rows}행 {cols}열)"], [])

    frames_of = {r: f for r, f, _ in layout}
    name_of = {r: n for r, _, n in layout}
    for row in range(rows):
        frames = frames_of.get(row, 0)
        anim = name_of.get(row, f"행{row}")
        for col in range(cols):
            box = (col * cell, row * cell, (col + 1) * cell, (row + 1) * cell)
            mask = opaque_mask(im.crop(box))
            has = bool(mask.any())
            declared = col < frames
            if declared and not has:
                errs.append(f"{name}: {anim} 행{row} 프레임{col} 비어 있음"
                            f" — {frames}프레임 선언(재생하면 빈 화면)")
                continue
            if not declared and has:
                errs.append(f"{name}: {anim} 행{row} 셀{col}은 여분인데 내용이 있다")
                continue
            if not declared:
                continue
            if align == "none":
                continue
            bb, scattered, ratio = dc.align_anchor(mask)
            if bb is None:
                continue
            cx = (bb["x0"] + bb["x1"]) / 2.0
            if abs(cx - cell / 2.0) > cell * ALIGN_TOL_X:
                errs.append(f"{name}: {anim} 행{row} 프레임{col} 가로 중앙 이탈"
                            f"(중심 x={cx:.0f}, 기대 {cell // 2})")
            if align == "center":
                cy = (bb["y0"] + bb["y1"]) / 2.0
                if abs(cy - cell / 2.0) > cell * ALIGN_TOL_BOTTOM:
                    errs.append(f"{name}: {anim} 행{row} 프레임{col} 세로 중앙 이탈"
                                f"(중심 y={cy:.0f}, 기대 {cell // 2})")
            elif (cell - 1 - bb["y1"]) > cell * ALIGN_TOL_BOTTOM:
                errs.append(f"{name}: {anim} 행{row} 프레임{col} 하단 정렬 이탈"
                            f"(바닥 여백 {cell - 1 - bb['y1']}px)")

    arr = np.asarray(im)
    alpha = arr[:, :, 3]
    content = alpha > 8
    if content.sum():
        n_colors = len({tuple(c) for c in arr[:, :, :3][content]})
        if n_colors > COLOR_BUDGET:
            warns.append(f"{name}: 고유색 {n_colors}개 — 계약 {COLOR_BUDGET}색 이하"
                         f"(--no-quantize로 설치했나?)")
        semi = (alpha > 0) & (alpha < 255) & content
        share = float(semi.sum()) / float(content.sum())
        if share > SEMI_SOFT_ART:
            warns.append(f"{name}: 내용의 {share * 100:.0f}%가 반투명 — 도트가 아니라"
                         f" 소프트 알파 그림이다")
    return (errs, warns)


def check_stale(png: str, cell: int) -> str:
    """설치본이 처리본에서 재현되나 — install_delivery와 **같은 연산**으로 대조한다.

    재현되지 않으면 옛 산출물이거나 옛 코드로 설치된 것이다. 어느 쪽이든 게임이
    지금 채택된 그림을 안 쓰고 있다는 뜻이다.
    """
    asset_id = os.path.basename(png)[: -len("_remake.png")]
    src = os.path.join(PROCESSED, asset_id, "processed_sheet.png")
    if not os.path.exists(src):
        return ""          # 처리본이 없는 설치본은 출처를 모른다 — 여기서 판단하지 않는다
    try:
        a = Image.open(src).convert("RGBA")
        b = Image.open(png).convert("RGBA")
    except OSError as exc:
        return f"{os.path.basename(png)}: 대조 실패 ({exc})"
    if a.size != b.size:
        return (f"{os.path.basename(png)}: 처리본 {a.size[0]}x{a.size[1]} vs "
                f"설치본 {b.size[0]}x{b.size[1]} — 낡았다(재설치하라)")
    g, _lines, _tainted = so.clean_guides(a, cell)
    q = so.quantize(g, COLOR_BUDGET)
    if not np.array_equal(np.asarray(q), np.asarray(b)):
        return (f"{os.path.basename(png)}: 설치본이 처리본에서 재현되지 않는다 — "
                f"낡았다(python tools/convert/install_delivery.py 로 재설치)")
    return ""


def main() -> int:
    sheets = sorted(glob.glob(os.path.join(SPRITES, "*_remake.png")))
    if not sheets:
        print("[설치 시트] 검사할 *_remake.png 가 없다 — 설치된 것이 없다")
        return 0

    all_err: list[str] = []
    all_warn: list[str] = []
    print(f"[설치 시트 관문] {len(sheets)}종 — assets/sprites/*_remake.png")
    for png in sheets:
        meta = png[:-4] + ".json"
        if not os.path.exists(meta):
            all_err.append(f"{os.path.basename(png)}: 메타 JSON이 없다 — 게임이 못 읽는다")
            continue
        errs, warns = check_sheet(png, meta)
        try:
            with io.open(meta, encoding="utf-8") as f:
                cell = int(json.load(f).get("cell") or 128)
        except (OSError, ValueError):
            cell = 128
        stale = check_stale(png, cell)
        if stale:
            errs = errs + [stale]
        all_err += errs
        all_warn += warns
        mark = "X" if errs else ("!" if warns else "ok")
        print(f"  {mark:>2} {os.path.basename(png)}"
              + (f" — 위반 {len(errs)}건" if errs else "")
              + (f" · 경고 {len(warns)}건" if warns else ""))

    for w in all_warn:
        print("  [warn] " + w)
    if all_err:
        print(f"\n실패 — 설치된 시트가 계약을 어긴다 {len(all_err)}건:")
        for e in all_err:
            print("  [ERR ] " + e)
        print("\n납품 게이트를 통과했더라도 설치(clean_guides+quantize)에서 바뀔 수 있다."
              "\n소프트 알파 납품은 양자화가 알파를 0/255로 뭉개 형태가 깎인다 —"
              " 도트로 다시 받거나 --no-quantize로 설치하라.")
        return 1
    print("\n통과 — 게임이 읽는 시트가 게임이 읽는 계약과 맞다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
