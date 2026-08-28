#!/usr/bin/env python3
"""신규 몬스터 시트 납품 검증기 — 그리드 계약 대조.

## 왜 별도인가 (2026-08-26)

심사 보드가 `monsters` 카테고리에 `validate_retouch_sheet.py`를 물려 놓았는데,
그 검증기는 **주인공 시트(`player_original.png`)를 하드코딩**해 셀별 실루엣을
비교한다. 리터치(같은 캐릭터를 다시 그림) 전용 도구다. 몬스터는 **신규 창작**이고
시트 규격도 종마다 다르므로, 무엇을 내든 크기 불일치 + 드리프트로 100% 반려됐다.

이 검증기는 원본과 비교하지 않는다. `monster_anim_specs.json`의 **계약**만 본다:
캔버스 크기 · 행별 프레임 수 · 빈 셀 투명 · 하단 중앙 정렬 · 배경 키잉 · 팔레트.

2026-08-28 추가: 위 항목을 전부 통과한 납품에서 격자 안내선 잔선·라벨 바·고유색
폭증이 나왔다(수동 검증). 공통 판정은 `delivery_checks.py`가 맡는다.

사용: python tools/convert/validate_monster_sheet.py <납품.png>
      (파일명 `<id>_v<n>.png`에서 종 id를 뽑는다)
exit 0=통과 / 1=반려
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
from llm_package_common import scale6to8

# 콘솔이 cp949면 한글 리포트의 em dash에서 죽는다 — 보드는 -X utf8로 부르지만
# 사람이 직접 CLI로 돌릴 때를 위해 여기서 고정한다.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SPECS = os.path.join(ROOT, "data", "monster_anim_specs.json")
## NPC도 같은 스키마·같은 그리드 계약을 쓴다 — 스펙이 두 파일로 나뉘어 있을 뿐이라
## 여기서 둘 다 훑는다(몬스터 파일에 없으면 NPC 파일에서 찾는다).
NPC_SPECS = os.path.join(ROOT, "data", "npc_anim_specs.json")
## 전투 이펙트도 같은 128 격자 계약을 쓴다 — 정렬만 다르다(spec.align="center").
EFFECT_SPECS = os.path.join(ROOT, "data", "effect_specs.json")
## 전투 대형 컷 — 셀이 512라 크기를 스펙이 정한다(spec.sheet_cell).
CUT_SPECS = os.path.join(ROOT, "data", "battle_cut_specs.json")
## 전투 전용 SD 시트(주인공) — 필드 시트와 같은 128 격자.
ACTOR_SPECS = os.path.join(ROOT, "data", "battle_actor_specs.json")
PALETTE_JSON = os.path.join(ROOT, "assets", "palette_master.json")
## 기본 셀. 스펙에 sheet_cell이 있으면 그 값으로 바뀐다(대형 컷 512).
CELL = 128
MAGENTA = (255, 0, 255)
## 하단 중앙 정렬 허용 오차(셀 대비 비율)
ALIGN_TOL_X = 0.12
ALIGN_TOL_BOTTOM = 0.14
## 마젠타 근처이나 정확히 마젠타가 아닌 픽셀 = 혼색/AA. 이 비율을 넘으면 키잉이 깨진다.
MAGENTA_AA_LIMIT = 0.01
PALETTE_WARN_DIST = 60


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warns: list[str] = []

    def fail(self, msg: str) -> None:
        self.errors.append(msg)
        print(f"  [ERR ] {msg}")

    def warn(self, msg: str) -> None:
        self.warns.append(msg)
        print(f"  [warn] {msg}")

    def ok(self, msg: str) -> None:
        print(f"  ok   {msg}")


def load_spec(asset_id: str) -> dict:
    for path in (SPECS, NPC_SPECS, EFFECT_SPECS, CUT_SPECS, ACTOR_SPECS):
        if not os.path.exists(path):
            continue
        data = json.load(io.open(path, encoding="utf-8"))
        for sp in data.get("species", []):
            if sp.get("id") == asset_id:
                return sp
    return {}


def sheet_contract(spec: dict) -> tuple:
    """스펙 → (cols, rows, [(행, 프레임수), ...]) — 생성기와 같은 산출식."""
    anims = sorted(spec["animations"].items(), key=lambda kv: int(kv[1].get("row", 0)))
    rows = len(anims)
    cols = max(int(a.get("frames", 1)) for _, a in anims)
    layout = [(int(a.get("row", 0)), int(a.get("frames", 1)), name) for name, a in anims]
    return cols, rows, layout


def opaque_mask(cell_img: Image.Image) -> np.ndarray:
    """불투명(=캐릭터) 픽셀 마스크. 마젠타 배경도 배경으로 친다."""
    arr = np.asarray(cell_img)
    alpha = arr[:, :, 3]
    rgb = arr[:, :, :3]
    is_magenta = (rgb[:, :, 0] > 240) & (rgb[:, :, 1] < 20) & (rgb[:, :, 2] > 240)
    return (alpha > 8) & ~is_magenta


def check_background(im: Image.Image, rep: Report) -> None:
    arr = np.asarray(im)
    rgb = arr[:, :, :3].astype(int)
    alpha = arr[:, :, 3]
    near = (np.abs(rgb[:, :, 0] - 255) < 60) & (rgb[:, :, 1] < 60) & (np.abs(rgb[:, :, 2] - 255) < 60)
    exact = (rgb[:, :, 0] == 255) & (rgb[:, :, 1] == 0) & (rgb[:, :, 2] == 255)
    aa = near & ~exact & (alpha > 8)
    ratio = float(aa.sum()) / float(arr.shape[0] * arr.shape[1])
    if ratio > MAGENTA_AA_LIMIT:
        rep.fail(f"마젠타 혼색/AA {ratio * 100:.1f}% — 누끼가 깨진다(단색 #FF00FF만 허용)")
    else:
        rep.ok(f"배경 키잉(마젠타 AA {ratio * 100:.2f}%)")


def check_palette(im: Image.Image, rep: Report) -> None:
    hexes = json.load(io.open(PALETTE_JSON, encoding="utf-8"))["colors"]
    pal = np.array([scale6to8(h) for h in hexes])
    arr = np.asarray(im)
    mask = opaque_mask(im)
    rgb = arr[:, :, :3][mask].astype(int)[::11]
    if rgb.shape[0] == 0:
        return
    d = np.empty(rgb.shape[0])
    for i in range(0, rgb.shape[0], 4096):
        chunk = rgb[i:i + 4096]
        d[i:i + 4096] = np.abs(chunk[:, None, :] - pal[None, :, :]).sum(axis=2).min(axis=1)
    mean_d = float(d.mean())
    if mean_d > PALETTE_WARN_DIST:
        rep.warn(f"팔레트 평균 거리 {mean_d:.0f} — 마스터 팔레트 이탈 의심")
    else:
        rep.ok(f"팔레트 평균 거리 {mean_d:.0f}")


def check_grid(im: Image.Image, layout: list, cols: int, rep: Report, align: str = "bottom_center") -> None:
    for row, frames, name in layout:
        for col in range(cols):
            box = (col * CELL, row * CELL, (col + 1) * CELL, (row + 1) * CELL)
            mask = opaque_mask(im.crop(box))
            has = bool(mask.any())
            declared = col < frames
            if declared and not has:
                rep.fail(f"{name} 행{row} 프레임{col} 비어 있음 — {frames}프레임 선언")
                continue
            if not declared and has:
                rep.fail(f"{name} 행{row} 셀{col}은 여분 — 완전 투명이어야 한다")
                continue
            if not declared:
                continue
            ys, xs = np.nonzero(mask)
            cx = (xs.min() + xs.max()) / 2.0
            if abs(cx - CELL / 2.0) > CELL * ALIGN_TOL_X:
                rep.fail(f"{name} 행{row} 프레임{col} 가로 중앙 이탈(중심 x={cx:.0f}, 기대 {CELL // 2})")
            if align == "center":
                # 이펙트는 발이 없다 — 세로도 중앙 기준으로 본다.
                cy = (ys.min() + ys.max()) / 2.0
                if abs(cy - CELL / 2.0) > CELL * ALIGN_TOL_BOTTOM:
                    rep.fail(f"{name} 행{row} 프레임{col} 세로 중앙 이탈(중심 y={cy:.0f}, 기대 {CELL // 2})")
            elif (CELL - 1 - ys.max()) > CELL * ALIGN_TOL_BOTTOM:
                rep.fail(f"{name} 행{row} 프레임{col} 하단 정렬 이탈(바닥 여백 {CELL - 1 - ys.max()}px)")


def set_cell(spec: dict) -> None:
    """스펙이 정한 셀 크기를 모듈 전역에 반영한다.

    셀을 함수 인자로 다 흘리는 대신 한 곳에서 바꾼다 — 이 검증기는 파일 하나를 보고
    끝나는 일회성 프로세스라 전역이 더 읽기 쉽다.
    """
    global CELL
    CELL = int(spec.get("sheet_cell", 128))


def main() -> None:
    if len(sys.argv) < 2:
        print("사용: python validate_monster_sheet.py <납품.png>")
        sys.exit(2)
    path = sys.argv[1]
    asset_id = re.sub(r"_v\d+$", "", os.path.splitext(os.path.basename(path))[0])
    rep = Report()

    spec = load_spec(asset_id)
    if not spec:
        rep.fail(f"'{asset_id}' 스펙 없음 — monster_anim_specs.json에 종이 등록돼야 한다")
        print(f"[monster] FAIL — {path}")
        sys.exit(1)

    set_cell(spec)
    cols, rows, layout = sheet_contract(spec)
    want = (cols * CELL, rows * CELL)
    im = Image.open(path).convert("RGBA")
    if im.size != want:
        rep.fail(f"크기 {im.size[0]}x{im.size[1]} — 계약 {want[0]}x{want[1]} ({rows}행 {cols}열)")
        print(f"[monster] FAIL — {path}")
        sys.exit(1)
    rep.ok(f"크기 {im.size[0]}x{im.size[1]} ({rows}행 {cols}열)")

    check_background(im, rep)
    check_grid(im, layout, cols, rep, str(spec.get("align", "bottom_center")))
    check_palette(im, rep)
    for f in dc.run_all(im, CELL, CELL):
        (rep.fail if dc.is_fail(f) else rep.warn)(f.msg)

    if rep.errors:
        print(f"[monster] FAIL {len(rep.errors)}건 — {path}")
        sys.exit(1)
    print(f"[monster] PASS — {path}")
    sys.exit(0)


if __name__ == "__main__":
    main()
