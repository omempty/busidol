#!/usr/bin/env python3
"""전투 전용 SD 시트 의뢰 패키지 생성 — data/battle_actor_specs.json 기준.

주인공 시트는 필드용이라 walk 4방향 + idle_down뿐이고 **공격·피격 행이 없다.**
적 시트에는 attack/hurt/death 행이 이미 있는데(c_bug·null_pointer·rogue_vending 실측)
주인공만 없어서 전투에서 주인공은 idle 2프레임 토글 + 위치 트윈으로 때우고 있었다.

대형 컷(`battle_cuts`)이 "결정적 순간의 큰 그림"이라면 이쪽은 **평소 화면의 SD 동작**이다.
둘은 폴백 관계다 — 컷이 없으면 이 시트가, 이 시트도 없으면 기존 트윈이 돈다.

시트 규격·프롬프트 골격은 몬스터 생성기와 같다(같은 128 격자·같은 검증기·같은 설치 경로).
다른 것은 스펙 파일과 원작 참조뿐이다.

실행: python tools/convert/export_battle_actor_packages.py [id ...]
"""
from __future__ import annotations

import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import export_monster_packages as gen

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))


def main() -> None:
    gen.SPECS = os.path.join(ROOT, "data", "battle_actor_specs.json")
    gen.OUT_ROOT = os.path.join(ROOT, "assets", "raw", "llm", "battle_actors")
    # 인물이므로 적 일러스트가 아니라 원작 인물 그림을 화풍 근거로 준다(NPC와 같은 묶음).
    gen.REF_CATEGORY = "npcs"
    gen.main()


if __name__ == "__main__":
    main()
