#!/usr/bin/env python3
"""타일셋 납품 시트의 **계약 정본** — 격자·묶음 배치를 여기 한 곳에서 도출한다.

## 왜 생겼나 (2026-09-09)

`assets/spec/sprites/tileset_campus.json`은 필요한 타일 17종과 **다중 타일 소품 6종**
(desk_lab 2×1 · desk_pc 2×2 · shelf_books 1×3 · vending_machine 2×3 · lockers 3×2 ·
bed_dorm 2×3)을 적어 두었는데, **그 파일을 읽는 코드가 저장소에 하나도 없었다.**
의뢰 생성기·검증기·셀 편집기 어디에도 타일셋 계약이 없었다(이 저장소의 지배적 결함
그대로 — 선언은 있는데 읽는 코드가 없다).

그리고 스펙은 타일 목록만 적을 뿐 **시트 배치를 정하지 않는다**. 배치를 정하지 않으면
생성 모델은 매번 다른 자리에 그려 오고, 편집기는 어디가 무엇인지 모른다. 그래서 배치를
여기서 **결정론적으로** 굽는다. 같은 스펙이면 언제 돌려도 같은 좌표가 나온다.

## 왜 별도 모듈인가

이 배치를 쓰는 곳이 셋이다 — 의뢰 프롬프트(무엇을 어디에 그릴지), 심사 서버의 계약 API
(편집기 격자), 검증기. 세 곳이 각자 배치를 계산하면 한쪽만 고쳐져 갈라진다. `sheet_ops.py`를
만든 이유와 같은 함정이라 계약 도출도 정본을 하나 둔다.

## 배치 규칙 (바꾸면 이미 받은 납품이 어긋난다 — 바꿀 때는 버전을 올려라)

1. 가로 `COLS`칸 고정.
2. **단일 타일 먼저** — 스펙의 `required_tiles` 순서대로 왼쪽→오른쪽, 위→아래.
3. 그다음 **소품 묶음**. 높이가 같은 것끼리 묶어 띠(band)를 만들고 큰 것부터 놓는다.
   높이를 섞으면 띠의 마지막 줄에 구멍이 생겨 "그 줄에서 왼쪽부터 연속"이 깨진다 —
   그 연속성이 깨지면 행별 `frames`(계약의 '이 줄에 몇 칸을 채워라')를 못 쓴다.
4. 띠의 가로 합이 `COLS`를 넘으면 같은 높이로 띠를 하나 더 만든다.

실행:
  python tools/convert/tileset_contract.py            계약을 사람이 읽게 찍는다
  python tools/convert/tileset_contract.py --json     그대로 JSON
"""
from __future__ import annotations

import io
import json
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SPEC_DIR = os.path.join(ROOT, "assets", "spec", "sprites")
## 가로 칸 수. 32px 타일 × 8 = 256px — 웹 챗이 한 장으로 다루기 좋은 폭이다.
COLS = 8
## 계약 배치 규칙의 버전. 규칙을 바꾸면 올린다(이미 받은 납품과 좌표가 달라진다).
LAYOUT_VERSION = 1


def spec_path(asset_id: str) -> str:
    return os.path.join(SPEC_DIR, f"{asset_id}.json")


def load_spec(asset_id: str) -> dict:
    p = spec_path(asset_id)
    if not os.path.exists(p):
        return {}
    spec = json.load(io.open(p, encoding="utf-8"))
    return spec if str(spec.get("kind")) == "tileset" else {}


def tileset_ids() -> list:
    """`kind: tileset`인 스펙 전부 — 편집기의 [계약] 드롭다운이 쓴다."""
    if not os.path.isdir(SPEC_DIR):
        return []
    out = []
    for f in sorted(os.listdir(SPEC_DIR)):
        if not f.endswith(".json"):
            continue
        try:
            spec = json.load(io.open(os.path.join(SPEC_DIR, f), encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if str(spec.get("kind")) == "tileset":
            out.append(str(spec.get("asset_id") or f[:-5]))
    return out


def _pack_groups(objs: list, start_row: int) -> tuple:
    """소품 묶음을 띠로 눕힌다. 반환 (배치 목록, 마지막 행 다음 줄).

    높이가 같은 것끼리만 한 띠에 넣는다 — 섞으면 띠의 아래쪽 줄에 구멍이 생기고,
    "각 줄은 왼쪽부터 연속으로 찬다"는 전제가 깨진다(계약의 행별 frames가 그 전제 위에 있다).
    """
    placed = []
    row = start_row
    # 큰 것부터: 높이 내림차순 → 너비 내림차순 → id(같은 조건에서 순서가 흔들리지 않게).
    by_h: dict = {}
    for o in objs:
        by_h.setdefault(int(o["h"]), []).append(o)
    for h in sorted(by_h, reverse=True):
        band = sorted(by_h[h], key=lambda o: (-int(o["w"]), str(o["id"])))
        col = 0
        for o in band:
            w = int(o["w"])
            if col + w > COLS:            # 이 띠가 꽉 찼다 — 같은 높이로 띠를 하나 더
                row += h
                col = 0
            placed.append({"id": str(o["id"]), "r": row, "c": col, "w": w, "h": h,
                           "hint": str(o.get("_hint") or "")})
            col += w
        row += h
    return placed, row


def contract(asset_id: str = "tileset_campus") -> dict:
    """납품 시트의 그리드 계약 — 셀 편집기·검증기·의뢰문이 같이 쓴다.

    돌려주는 모양은 `review_server.sheet_contract`와 같다(cell/rows/cols/size/align/layout)
    + 타일셋에만 있는 `groups`·`tiles`. 편집기는 계약을 한 모양으로만 다루므로
    여기서 모양을 맞춰 준다.
    """
    spec = load_spec(asset_id)
    if not spec:
        return {}
    cell = int(spec.get("tile_px") or 32)
    tiles = [str(t) for t in (spec.get("required_tiles") or [])]
    objs = [o for o in (spec.get("multi_tile_objects") or [])
            if isinstance(o, dict) and o.get("id")]

    # 1) 단일 타일 — 왼쪽→오른쪽, 위→아래.
    singles = [{"id": t, "r": i // COLS, "c": i % COLS} for i, t in enumerate(tiles)]
    next_row = (len(tiles) + COLS - 1) // COLS if tiles else 0

    # 2) 소품 묶음.
    groups, rows = _pack_groups(objs, next_row)

    # 3) 행별로 "왼쪽부터 몇 칸이 차는가" — 계약의 frames.
    used = [0] * max(rows, 1)
    for s in singles:
        used[s["r"]] = max(used[s["r"]], s["c"] + 1)
    for g in groups:
        for dr in range(g["h"]):
            used[g["r"] + dr] = max(used[g["r"] + dr], g["c"] + g["w"])

    layout = []
    for r in range(rows):
        names = [s["id"] for s in singles if s["r"] == r]
        names += [g["id"] for g in groups if g["r"] <= r < g["r"] + g["h"] and g["r"] == r]
        layout.append({"row": r, "name": ", ".join(names) or f"행 {r}", "frames": used[r]})

    return {
        "cell": cell,
        "cols": COLS,
        "rows": rows,
        "size": [COLS * cell, rows * cell],
        # 타일은 칸을 가득 채운다 — 중앙/하단으로 밀면 이음새가 어긋난다.
        "align": "none",
        "layout": layout,
        "kind": "tileset",
        "layout_version": LAYOUT_VERSION,
        "tiles": singles,
        "groups": groups,
    }


def describe(asset_id: str = "tileset_campus") -> str:
    """사람이 읽는 배치표 — 의뢰문에도 이 표를 그대로 실을 수 있다."""
    c = contract(asset_id)
    if not c:
        return f"({asset_id}: kind=tileset 스펙을 못 찾았다)"
    out = [f"# {asset_id} 시트 계약 (배치 규칙 v{c['layout_version']})",
           f"- 캔버스 {c['size'][0]}×{c['size'][1]}px · 타일 {c['cell']}px · "
           f"{c['cols']}열 × {c['rows']}행 · 정렬 {c['align']}",
           "",
           "## 단일 타일 (한 칸씩)",
           "| 행 | 열 | 타일 |", "|---|---|---|"]
    for s in c["tiles"]:
        out.append(f"| {s['r']} | {s['c']} | {s['id']} |")
    out += ["", "## 소품 묶음 (여러 칸에 걸친다 — 칸 경계를 가로질러 이어져야 한다)",
            "| 행 | 열 | 크기 | 소품 | 설명 |", "|---|---|---|---|---|"]
    for g in c["groups"]:
        out.append(f"| {g['r']} | {g['c']} | {g['w']}×{g['h']} | {g['id']} | {g['hint']} |")
    out += ["", "## 행별로 왼쪽부터 채우는 칸 수",
            " · ".join(f"{l['row']}행 {l['frames']}칸" for l in c["layout"])]
    return "\n".join(out)


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    aid = "tileset_campus"
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if args:
        aid = args[0]
    if "--json" in sys.argv:
        print(json.dumps(contract(aid), ensure_ascii=False, indent=2))
    else:
        print(describe(aid))


if __name__ == "__main__":
    main()
