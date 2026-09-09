#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""autofix_plan 시험 — 계획이 **무엇을 돌리고 무엇을 안 돌리는가**를 못박는다.

정상 케이스만 보는 시험은 쓸모가 없다. 여기서 실제로 재는 것은 부정 쪽이다:
못 고치는 지적에 연산을 붙이지 않는가, 그림을 깎는 연산을 막는가, 같은 연산을
다시 골라 무한히 도는 계획을 만들지 않는가.

실행: python tools/convert/test_autofix_plan.py
종료코드: 0=전부 통과 / 1=실패 있음
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import autofix_plan as ap  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

_pass = _fail = 0


def check(name: str, cond: bool, detail: str = "") -> None:
    global _pass, _fail
    if cond:
        _pass += 1
        print(f"  ok   {name}" + (f" - {detail}" if detail else ""))
    else:
        _fail += 1
        print(f" FAIL  {name}" + (f" - {detail}" if detail else ""))


# ---------------------------------------------------------------- 정상 계획
p = ap.plan_for(["guide_residue", "color_budget", "semi_alpha", "pure_black", "align_x"])
check("보통 시트 - 고칠 수 있는 것을 순서대로 고른다",
      p["plan"] == ["guides", "snapall", "binarize", "quantize", "deblack"],
      " -> ".join(p["plan"]))
check("보통 시트 - 사람 몫이 없다", p["manual"] == [], ", ".join(p["manual"]) or "없음")

# 순서는 표의 ORDER를 따른다 - 지적이 들어온 순서를 따르면 양자화가 이진화보다 먼저 돌아
# 반투명 가장자리가 색으로 굳는다.
p = ap.plan_for(["pure_black", "color_hard", "guide_residue"])
check("순서 - 지적이 들어온 순서가 아니라 정해진 순서다",
      p["plan"] == ["guides", "quantize", "deblack"], " -> ".join(p["plan"]))

# ---------------------------------------------------------------- 거부권
# 소프트 알파 그림에 quantize를 돌리면 알파가 0/255로 뭉개져 그림이 깎인다.
# 실측(flying_thesis_v8): 내용 6177->5439, 본체 92%->66%, 중심 74.0->82.5, 없던 ERR 2건.
p = ap.plan_for(["color_hard", "semi_alpha_soft"])
check("부정 시험 - 소프트 알파면 양자화를 막는다",
      "quantize" not in p["plan"] and "quantize" in p["vetoed"],
      f"plan={p['plan']} vetoed={list(p['vetoed'])}")
check("거부권 - 무엇이 막았는지 말한다",
      p["vetoed"].get("quantize") == ["semi_alpha_soft"], str(p["vetoed"]))
check("거부권 - 막힌 지적은 사람 몫으로 넘어간다",
      "color_hard" in p["manual"], ", ".join(p["manual"]))

p = ap.plan_for(["semi_alpha", "semi_alpha_soft"])
check("부정 시험 - 소프트 알파면 이진화도 막는다",
      "binarize" not in p["plan"], f"plan={p['plan']}")

# ---------------------------------------------------------------- 못 고치는 지적
for code in ("scattered", "cell_empty", "cell_extra", "split_cell",
             "flat_placeholder", "size", "no_spec", "palette", "magenta_aa",
             "frame_border"):
    p = ap.plan_for([code])
    check(f"사람 몫 - {code}에는 연산을 붙이지 않는다",
          p["plan"] == [] and p["manual"] == [code], f"plan={p['plan']}")

# frame_border를 guides로 이으면 계획이 수렴하지 않는다(clean_guides는 칸 경계만 지운다).
# 실측: 매 회차 plan=["guides"], 제거 0px, 지적 그대로 -> 3회차까지 안 끝남.
check("수렴 - frame_border가 guides를 다시 부르지 않는다",
      ap.AUTOFIX_BY_CODE.get("frame_border") is None,
      str(ap.AUTOFIX_BY_CODE.get("frame_border")))

# ---------------------------------------------------------------- 빈 입력
p = ap.plan_for([])
check("지적이 없으면 계획도 없다", p == {"plan": [], "vetoed": {}, "manual": []}, str(p))

# ---------------------------------------------------------------- 표 자체의 건전성
check("표가 가리키는 연산은 모두 실행 순서에 있다",
      all(op in ap.AUTOFIX_ORDER for op in ap.AUTOFIX_BY_CODE.values()),
      str(sorted(set(ap.AUTOFIX_BY_CODE.values()) - set(ap.AUTOFIX_ORDER))) or "빠짐 없음")
check("거부권이 가리키는 연산도 모두 실행 순서에 있다",
      all(op in ap.AUTOFIX_ORDER for ops in ap.AUTOFIX_VETO.values() for op in ops),
      "빠짐 없음")

print(f"\n[test_autofix_plan] 통과 {_pass} · 실패 {_fail}")
sys.exit(1 if _fail else 0)
