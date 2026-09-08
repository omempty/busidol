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


def external_stems() -> set:
    """외부 스탠드인(<id>_external.png) — 공백은 공백대로 세되 표시는 구분한다.
    _remake가 설치되면 로더가 외부팩을 밀어내므로(tools/dev/bake_external_bosses.py),
    여기의 표시는 '자작 납품이 아직'이라는 뜻이다."""
    return {f[: -len("_external.png")] for f in listdir("assets/sprites")
            if f.endswith("_external.png")}


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
    # 원작 이관 8종은 _original이 있어 "보유"로 세어지지만 1995년 도트 그대로다.
    # 리마스터(=_remake) 진행률은 따로 봐야 보인다.
    remaster_ids = [x["id"] for x in load("data/monster_anim_specs.json").get("species", [])
                    if str(x.get("source", "")).startswith("original_")]
    add("원작 몬스터 리마스터", "monsters", remaster_ids,
        {f[: -len("_remake.png")] for f in listdir("assets/sprites") if f.endswith("_remake.png")},
        "없으면 원작 도트 그대로(게임은 돈다)")
    add("아이템 아이콘", "items", [i["id"] for i in load("data/items.json").get("items", [])],
        {f[:-4] for f in listdir("assets/icons")}, "없으면 색 상자 + 글자")
    add("대화 초상", "portraits", [f[:-5] for f in listdir("assets/spec/portraits", ".json")],
        {f[:-4] for f in listdir("assets/portraits")}, "없으면 대화창에 얼굴 없음")
    add("전투 이펙트", "effects", [e["id"] for e in load("data/effect_specs.json").get("species", [])],
        {f[:-4] for f in listdir("assets/effects")}, "없으면 점 파티클 폴백")
    # 적 전투 대형 시트 — 2026-09-07 신설. 이 줄이 없던 동안 현황판은 "필드 몬스터 12/12 ·
    # 공백 0"이라고만 말했고, **적의 전투 표현 갭은 숫자에 잡히지도 않았다.**
    # 원작 대응 7종은 구우면 끝이지만(bake_battle_sheets.py) 신설 5종·보스 2종은 의뢰가 필요하다.
    add("적 전투 대형 시트", "battle_actors",
        [e["id"] for e in load("data/battle_actor_specs.json").get("enemies", [])],
        {f[: -len("_battle.png")] for f in listdir("assets/sprites") if f.endswith("_battle.png")},
        "없으면 필드 도트를 96px로 축소 — 원작 압박감 없음")
    add("전투 SD 시트", "battle_actors",
        [a["id"] for a in load("data/battle_actor_specs.json").get("species", [])], stems,
        "없으면 주인공이 전투에서 idle만 토글")
    add("전투 대형 컷", "battle_cuts",
        [c["id"] for c in load("data/battle_cut_specs.json").get("species", [])],
        {f[:-4] for f in listdir("assets/battle_cuts")}, "없으면 공격·피격 컷 없이 도트만")
    add("컷신 키아트", "keyart", [f[:-5] for f in listdir("assets/spec/keyart", ".json")],
        {f[:-4] for f in listdir("assets/keyart")}, "없으면 컷신에 그림 없음")
    ext = external_stems()
    if ext:
        for r in rows:
            sub = sorted(set(r["missing"]) & ext)
            if sub:
                r["note"] += " · 외부 스탠드인 사용중(%s)" % ", ".join(sub)
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
