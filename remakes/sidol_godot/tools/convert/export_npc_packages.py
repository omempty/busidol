#!/usr/bin/env python3
"""필드 NPC 스프라이트 LLM 의뢰 패키지 생성 — data/npc_anim_specs.json 기준.

전용 시트가 없어 **주인공 얼굴 플레이스홀더로 나오는 NPC 4종**이 대상이다
(world_audit이 "전용 시트 없음"으로 상시 보고하던 항목).

시트 규격·프롬프트 골격은 몬스터 생성기와 같다 — 필드 캐릭터라 요구가 동일하기 때문.
다른 것은 둘뿐이다: 스펙 파일과 **원작 참조**(적 일러스트가 아니라 인물 초상).

실행: python tools/convert/export_npc_packages.py [npc_id ...]
"""
from __future__ import annotations

import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import export_monster_packages as gen

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))


def main() -> None:
    gen.SPECS = os.path.join(ROOT, "data", "npc_anim_specs.json")
    gen.OUT_ROOT = os.path.join(ROOT, "assets", "raw", "llm", "npcs")
    gen.REF_CATEGORY = "npcs"
    gen.main()


if __name__ == "__main__":
    main()
