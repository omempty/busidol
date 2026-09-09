#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""웹 프롬프트 시험 — 스펙에 있는 값을 프롬프트가 **실제로 읽는가**.

## 왜 (2026-09-09)

시트 프롬프트는 화면 표시 크기를 한 번도 말하지 않았다. 값은 스펙에 있었는데
(`cell: {w,h}`) 설치기만 읽고 프롬프트는 안 읽었다 — 선언은 있고 읽는 코드가 없는,
이 저장소의 지배적 결함이다. 그래서 19종 중 12종이 화면에서 절반으로 줄어드는데도
전부에게 "칸 128px 안에서 96px 안팎"으로만 지시했고, 축소하면 사라질 디테일이
담겨 왔다(flying_thesis v5 세밀도 0.913 · 원작 도트 0.384 · 채택본 0.217).

여기서 재는 것은 문장의 품질이 아니라 **배선**이다: 프롬프트가 말하는 표시 크기가
설치기가 실제로 쓰는 배율과 같은가. 두 곳이 갈라지면 프롬프트가 거짓말을 한다.

실행: python tools/convert/test_web_prompt.py
종료코드: 0=전부 통과 / 1=실패 있음
"""
from __future__ import annotations

import io
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import web_prompt as wp  # noqa: E402
from install_delivery import sheet_scale  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CATS = (("monsters", "monster_anim_specs.json"),
        ("npcs", "npc_anim_specs.json"),
        ("battle_actors", "battle_actor_specs.json"))
SIZE_RE = re.compile(r"## 화면 표시 크기 — \*\*(\d+)px")

_pass = _fail = 0


def check(name: str, cond: bool, detail: str = "") -> None:
    global _pass, _fail
    if cond:
        _pass += 1
        print(f"  ok   {name}" + (f" - {detail}" if detail else ""))
    else:
        _fail += 1
        print(f" FAIL  {name}" + (f" - {detail}" if detail else ""))


def species(fname: str) -> list:
    p = os.path.join(ROOT, "data", fname)
    if not os.path.exists(p):
        return []
    with io.open(p, encoding="utf-8") as f:
        return json.load(f).get("species", [])


total = 0
mismatch: list[str] = []
missing: list[str] = []
no_silhouette: list[str] = []
sizes: dict[int, int] = {}

for cat, fname in CATS:
    for sp in species(fname):
        asset_id = sp.get("id")
        if not asset_id:
            continue
        total += 1
        try:
            text = wp.sheet_prompt(cat, asset_id)
        except Exception as exc:  # noqa: BLE001 — 어떤 종이 터지는지 이름과 함께 봐야 한다
            missing.append(f"{asset_id}: 생성 실패 {exc!r}")
            continue
        m = SIZE_RE.search(text)
        if not m:
            missing.append(f"{asset_id}: 표시 크기를 말하지 않는다")
            continue
        said = int(m.group(1))
        cell = int(sp.get("sheet_cell", 128))
        scale, _why = sheet_scale(sp, cell)
        want = int(round(cell * scale))
        sizes[said] = sizes.get(said, 0) + 1
        if said != want:
            mismatch.append(f"{asset_id}: 프롬프트 {said}px vs 설치기 {want}px")
        # 실루엣 가독성 요구가 시트 프롬프트에도 있어야 한다(예전에는 아이콘에만 있었다).
        if "실루엣" not in text or "읽히" not in text:
            no_silhouette.append(asset_id)

check("모든 캐릭터 시트 프롬프트가 화면 표시 크기를 말한다",
      not missing, "; ".join(missing[:3]) or f"{total}종")
check("프롬프트의 표시 크기가 설치기 배율과 일치한다",
      not mismatch, "; ".join(mismatch[:3]) or f"{total}종 일치")
check("시트 프롬프트가 실루엣 가독성을 요구한다",
      not no_silhouette, ", ".join(no_silhouette[:3]) or f"{total}종")
check("표시 크기가 한 값으로 뭉개지지 않는다(종별 차등이 산다)",
      len(sizes) >= 2, str(sizes))

# 부정 시험 — 게임 cell을 지우면 설치기 기본 배율로 떨어지고, 프롬프트도 그 값을 따라야 한다.
# (프롬프트가 스펙을 안 읽고 128을 박아 두면 여기서 걸린다.)
probe = None
for cat, fname in CATS:
    for sp in species(fname):
        if isinstance(sp.get("cell"), dict) and int(sp["cell"].get("w", 0)) not in (0, 128):
            probe = (cat, sp)
            break
    if probe:
        break
if probe:
    cat, sp = probe
    cell = int(sp.get("sheet_cell", 128))
    scale, _ = sheet_scale(sp, cell)
    text = wp.sheet_prompt(cat, sp["id"])
    said = int(SIZE_RE.search(text).group(1))
    check(f"부정 시험 - 축소되는 종({sp['id']})이 칸 크기를 그대로 말하지 않는다",
          said != cell and said == int(round(cell * scale)),
          f"칸 {cell}px · 프롬프트 {said}px · 배율 {scale}")
else:
    check("부정 시험 - 축소되는 종이 있다", False, "축소되는 종을 못 찾았다(시험이 무의미해진다)")

print(f"\n[test_web_prompt] 통과 {_pass} · 실패 {_fail}")
sys.exit(1 if _fail else 0)
