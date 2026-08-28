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


## 카테고리별 집계 — CLI 출력과 현황판(HTML)이 **같은 함수**를 쓴다.
## 두 곳에서 따로 세면 수치가 갈라지고, 그 순간 둘 다 신뢰를 잃는다.
def collect() -> list:
    """[{label, cat, ids, have, missing, note}] — 정의 대비 실제 파일."""
    stems = sheet_stems()
    rows = []

    def add(label: str, cat: str, ids: list, have: set, note: str = "") -> None:
        rows.append({
            "label": label,
            "cat": cat,
            "ids": list(ids),
            "have": sorted(i for i in ids if i in have),
            "missing": [i for i in ids if i not in have],
            "note": note,
        })

    monsters_d = load("data/monsters.json")
    species = list(monsters_d.get("species", {}).keys())
    bosses = list(monsters_d.get("bosses", {}).keys())
    spec_ids = [x["id"] for x in load("data/monster_anim_specs.json").get("species", [])]
    add("필드 몬스터", "monsters", species, stems)
    add("보스", "monsters", bosses, stems, "없으면 전투에서 색 사각형")
    add("중간보스(스펙만)", "monsters",
        [i for i in spec_ids if i not in species and i not in bosses], stems,
        "아직 monsters.json 미배치")

    npc_ids = []
    for f in sorted(os.listdir(os.path.join(ROOT, "data", "maps"))):
        if f.startswith("npcs_"):
            npc_ids += [str(n["id"]) for n in load("data/maps/" + f).get("npcs", [])]
    add("필드 NPC", "npcs", sorted(set(npc_ids)), stems, "없으면 주인공 얼굴")
    add("아이템 아이콘", "items", [i["id"] for i in load("data/items.json").get("items", [])],
        {f[:-4] for f in listdir("assets/icons")}, "없으면 색 상자 + 글자")
    add("대화 초상", "portraits", [f[:-5] for f in listdir("assets/spec/portraits", ".json")],
        {f[:-4] for f in listdir("assets/portraits")}, "없으면 대화창에 얼굴 없음")
    add("전투 이펙트", "effects", [e["id"] for e in load("data/effect_specs.json").get("species", [])],
        {f[:-4] for f in listdir("assets/effects")}, "없으면 점 파티클 폴백")
    add("전투 SD 시트", "battle_actors",
        [a["id"] for a in load("data/battle_actor_specs.json").get("species", [])], stems,
        "없으면 주인공이 전투에서 idle만 토글")
    add("전투 대형 컷", "battle_cuts",
        [c["id"] for c in load("data/battle_cut_specs.json").get("species", [])],
        {f[:-4] for f in listdir("assets/battle_cuts")}, "없으면 공격·피격 컷 없이 도트만")
    add("컷신 키아트", "keyart", [f[:-5] for f in listdir("assets/spec/keyart", ".json")],
        {f[:-4] for f in listdir("assets/keyart")}, "없으면 컷신에 그림 없음")
    return rows


def main() -> None:
    total_missing = 0
    print("[asset_status] 정의 대비 실제 파일")
    for r in collect():
        note = ("— " + r["note"]) if r["note"] else ""
        row(r["label"], r["ids"], set(r["have"]), note)
        total_missing += len(r["missing"])

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
