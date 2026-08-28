#!/usr/bin/env python3
"""에셋 공백 현황 — 정의 대비 실제 파일을 세어 "무엇이 몇 개 비었는가"를 낸다.

world_audit은 **그 층에 실제로 서 있는 액터**만 본다. 그래서 보스처럼 전투에서만
나오는 대상이나 아이템 아이콘·초상은 감사에서 빠지고, 로드맵 문구("플레이스홀더 8종")가
실제 공백(73종)과 크게 어긋난 상태로 오래 남아 있었다. 이 도구가 그 간극을 메운다.

시범 → 전체 → 부분 재생성 사이클에서 "지금 어디까지 왔나"를 보는 용도이기도 하다.

실행: python tools/dev/asset_status.py
"""
from __future__ import annotations

import io
import json
import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))


def load(rel: str) -> dict:
    path = os.path.join(ROOT, rel)
    if not os.path.exists(path):
        return {}
    return json.load(io.open(path, encoding="utf-8"))


def listdir(rel: str, suffix: str = ".png") -> list:
    d = os.path.join(ROOT, rel)
    return sorted(f for f in os.listdir(d) if f.endswith(suffix)) if os.path.isdir(d) else []


def sheet_stems() -> set:
    out = set()
    for f in listdir("assets/sprites"):
        for tag in ("_original.png", "_remake.png", "_placeholder.png"):
            if f.endswith(tag):
                out.add(f[: -len(tag)])
    return out


def row(label: str, ids: list, have: set, note: str = "") -> tuple:
    missing = [i for i in ids if i not in have]
    print(
        "  %-22s %3d종 중 %3d  · 공백 %3d %s"
        % (label, len(ids), len(ids) - len(missing), len(missing), note)
    )
    if missing:
        head = ", ".join(missing[:8])
        print("        └ %s%s" % (head, " …" if len(missing) > 8 else ""))
    return len(ids), len(missing)


def main() -> None:
    stems = sheet_stems()
    total_missing = 0
    print("[asset_status] 정의 대비 실제 파일")

    monsters = load("data/monsters.json")
    species = list(monsters.get("species", {}).keys())
    bosses = list(monsters.get("bosses", {}).keys())
    spec_ids = [s["id"] for s in load("data/monster_anim_specs.json").get("species", [])]
    mid_bosses = [i for i in spec_ids if i not in species and i not in bosses]

    _, m = row("필드 몬스터", species, stems)
    total_missing += m
    _, m = row("보스", bosses, stems, "— 없으면 전투에서 색 사각형")
    total_missing += m
    _, m = row("중간보스(스펙만)", mid_bosses, stems, "— 아직 monsters.json 미배치")
    total_missing += m

    npc_ids = []
    for f in sorted(os.listdir(os.path.join(ROOT, "data", "maps"))):
        if f.startswith("npcs_"):
            npc_ids += [str(n["id"]) for n in load("data/maps/" + f).get("npcs", [])]
    _, m = row("필드 NPC", sorted(set(npc_ids)), stems, "— 없으면 주인공 얼굴")
    total_missing += m

    items = [i["id"] for i in load("data/items.json").get("items", [])]
    icons = {f[:-4] for f in listdir("assets/icons")}
    _, m = row("아이템 아이콘", items, icons, "— 없으면 색 상자 + 글자")
    total_missing += m

    portrait_specs = [f[:-5] for f in listdir("assets/spec/portraits", ".json")]
    _, m = row("대화 초상", portrait_specs, {f[:-4] for f in listdir("assets/portraits")})
    total_missing += m

    keyart_specs = [f[:-5] for f in listdir("assets/spec/keyart", ".json")]
    _, m = row("컷신 키아트", keyart_specs, {f[:-4] for f in listdir("assets/keyart")})
    total_missing += m

    print("  ─ 합계 공백 %d종" % total_missing)
    print("\n[asset_status] 의뢰 패키지 생성 현황(assets/raw/llm)")
    llm = os.path.join(ROOT, "assets", "raw", "llm")
    if not os.path.isdir(llm):
        print("  (없음 — export_*_packages.py로 생성)")
        return
    for cat in sorted(os.listdir(llm)):
        d = os.path.join(llm, cat)
        if not os.path.isdir(d) or cat.startswith(("_", "10_", "20_")):
            continue
        pkgs = [x for x in os.listdir(d) if os.path.isdir(os.path.join(d, x))]
        print("  %-22s 패키지 %d개" % (cat, len(pkgs)))
    for stage in ("10_submitted", "20_processed"):
        base = os.path.join(llm, stage)
        if not os.path.isdir(base):
            continue
        for cat in sorted(os.listdir(base)):
            d = os.path.join(base, cat)
            if os.path.isdir(d) and not cat.startswith("_"):
                n = len([f for f in os.listdir(d) if f.endswith(".png")])
                if n:
                    print("  %-22s %s %d장" % (stage + "/" + cat, "납품" if "10_" in stage else "채택", n))


if __name__ == "__main__":
    main()
