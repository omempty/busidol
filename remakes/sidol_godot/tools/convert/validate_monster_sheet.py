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
import waivers
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
## 본체가 셀 내용에서 차지해야 할 최소 비율 — 미만이면 조각이 흩어진 것으로 보고 알린다
## (사망·폭발 프레임은 정상적으로 낮으므로 경고에 머문다).
## 정본은 delivery_checks — 계측·정렬 스냅이 같은 값을 써야 자동보정이 수렴한다.
MAIN_BLOB_MIN = dc.MAIN_BLOB_MIN


## 면제 사유를 지적 바로 아래 줄에 붙여 찍는다.
NL_INDENT = "\n         "


class Report:
    """사람이 읽는 줄과 **기계가 읽는 코드**를 함께 모은다.

    코드가 없으면 편집기는 "무엇을 고치면 되는지"를 문장에서 되짚어야 한다 —
    문구를 조금만 바꿔도 조용히 끊기는 배선이라, 지적마다 코드를 달아 내보낸다.
    편집기는 이 코드로 [지적 자동보정]이 돌릴 연산을 고른다(AUTOFIX_BY_CODE).
    """

    def __init__(self, waived: dict | None = None) -> None:
        self.errors: list[str] = []
        self.warns: list[str] = []
        self.codes: list[str] = []
        self.waived_hits: list[str] = []
        # {코드: 면제기록} — 이 에셋에 걸린 면제. 없으면 빈 dict다.
        self._waived = waived or {}

    def fail(self, msg: str, code: str = "") -> None:
        if code:
            self.codes.append(code)
        hit = self._waived.get(code) if code else None
        if hit:
            # **조용히 통과시키지 않는다.** 면제는 결함이 사라진 것이 아니라 사람이
            # 책임지고 넘긴 것이라, 무엇을 왜 넘겼는지 매번 눈에 보여야 한다.
            self.waived_hits.append(code)
            print(f"  [면제] {msg}"
                  f"{NL_INDENT}└ 면제: {hit.get('reason', '')}"
                  f" ({hit.get('by', '')} {hit.get('at', '')})")
            return
        self.errors.append(msg)
        print(f"  [ERR ] {msg}")

    def warn(self, msg: str, code: str = "") -> None:
        self.warns.append(msg)
        if code:
            self.codes.append(code)
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
        rep.fail(f"마젠타 혼색/AA {ratio * 100:.1f}% — 누끼가 깨진다(단색 #FF00FF만 허용)",
                 "magenta_aa")
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
        rep.warn(f"팔레트 평균 거리 {mean_d:.0f} — 마스터 팔레트 이탈 의심", "palette")
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
                rep.fail(f"{name} 행{row} 프레임{col} 비어 있음 — {frames}프레임 선언", "cell_empty")
                continue
            if not declared and has:
                rep.fail(f"{name} 행{row} 셀{col}은 여분 — 완전 투명이어야 한다", "cell_extra")
                continue
            if not declared:
                continue
            # 정렬 기준은 **한 곳**에서 고른다(dc.align_anchor) — 본체가 뚜렷하면 본체,
            # 소멸 프레임처럼 흩어졌으면 내용 전체. 편집기 계측·정렬 스냅도 같은 함수를 쓴다.
            main, scattered, ratio = dc.align_anchor(mask, MAIN_BLOB_MIN)
            if main is None:
                continue
            if scattered:
                # 본체가 없는 것이 정상인 프레임이다. 최대 조각은 본체가 아니라 파편이라
                # 그걸 기준 삼으면 멀쩡한 프레임이 이탈로 잡힌다(실측: flying_thesis
                # death r2c2 — 조각 기준 x=38/바닥66 vs 내용 전체 x=63/바닥5).
                rep.warn(
                    "%s 행%d 프레임%d 본체가 내용의 %d%% — 조각이 흩어져 있다(정렬은 내용 전체로 판정)"
                    % (name, row, col, int(ratio * 100)),
                    "scattered",
                )
            ys = np.array([main["y0"], main["y1"]])
            xs = np.array([main["x0"], main["x1"]])
            cx = (xs.min() + xs.max()) / 2.0
            if abs(cx - CELL / 2.0) > CELL * ALIGN_TOL_X:
                rep.fail(f"{name} 행{row} 프레임{col} 가로 중앙 이탈(중심 x={cx:.0f}, 기대 {CELL // 2})",
                         "align_x")
            if align == "center":
                # 이펙트는 발이 없다 — 세로도 중앙 기준으로 본다.
                cy = (ys.min() + ys.max()) / 2.0
                if abs(cy - CELL / 2.0) > CELL * ALIGN_TOL_BOTTOM:
                    rep.fail(f"{name} 행{row} 프레임{col} 세로 중앙 이탈(중심 y={cy:.0f}, 기대 {CELL // 2})",
                             "align_y")
            elif (CELL - 1 - ys.max()) > CELL * ALIGN_TOL_BOTTOM:
                rep.fail(f"{name} 행{row} 프레임{col} 하단 정렬 이탈(바닥 여백 {CELL - 1 - ys.max()}px)",
                         "align_y")


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
    asset_id = waivers.asset_id_of(path)
    # 면제는 **에셋 id**에 걸린다 — 저장할 때마다 오르는 버전(v5->v8)에 걸면
    # 다음 납품에서 사라져 사람이 매번 다시 눌러야 한다.
    hits = {w["code"]: w for w in waivers.for_asset(asset_id)}
    rep = Report(hits)

    spec = load_spec(asset_id)
    if not spec:
        rep.fail(f"'{asset_id}' 스펙 없음 — monster_anim_specs.json에 종이 등록돼야 한다",
                 "no_spec")
        print(f"[monster] FAIL — {path}")
        sys.exit(1)

    set_cell(spec)
    cols, rows, layout = sheet_contract(spec)
    want = (cols * CELL, rows * CELL)
    im = Image.open(path).convert("RGBA")
    if im.size != want:
        rep.fail(f"크기 {im.size[0]}x{im.size[1]} — 계약 {want[0]}x{want[1]} ({rows}행 {cols}열)",
                 "size")
        print(f"[monster] FAIL — {path}")
        sys.exit(1)
    rep.ok(f"크기 {im.size[0]}x{im.size[1]} ({rows}행 {cols}열)")

    check_background(im, rep)
    check_grid(im, layout, cols, rep, str(spec.get("align", "bottom_center")))
    check_palette(im, rep)
    for f in dc.run_all(im, CELL, CELL):
        (rep.fail if dc.is_fail(f) else rep.warn)(f.msg, f.code)

    # 기계가 읽는 줄 — 편집기가 이 코드로 [지적 자동보정]이 돌릴 연산을 고른다.
    # 사람이 읽는 줄과 따로 두는 이유: 문구를 다듬을 때마다 배선이 조용히 끊기면 안 된다.
    print("[codes] " + ",".join(sorted(set(rep.codes))))
    # 면제로 넘긴 지적도 기계가 알아야 한다 — 편집기가 "면제됨"으로 구분해 보여 준다.
    print("[waived] " + ",".join(sorted(set(rep.waived_hits))))
    tail = f" (면제 {len(set(rep.waived_hits))}건)" if rep.waived_hits else ""
    if rep.errors:
        print(f"[monster] FAIL {len(rep.errors)}건{tail} — {path}")
        sys.exit(1)
    print(f"[monster] PASS{tail} — {path}")
    sys.exit(0)


if __name__ == "__main__":
    main()
