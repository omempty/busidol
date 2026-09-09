#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""면제(FORCE OK) 시험 — **무엇을 면제할 수 없는가**가 핵심이다.

면제는 관문에 구멍을 내는 기능이라, 정상 동작보다 부정 쪽을 재야 한다:
계약이 어긋난 지적을 못 넘기는가, 사유 없이 못 거는가, 버전이 올라도 유지되는가.

실행: python tools/convert/test_waivers.py
종료코드: 0=전부 통과 / 1=실패 있음
"""
from __future__ import annotations

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import waivers as w  # noqa: E402

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


tmp = os.path.join(tempfile.mkdtemp(), "_waivers.json")

# ---------------------------------------------------------------- 키가 버전을 안 탄다
# 납품은 저장할 때마다 번호가 오른다(실제로 v5 -> v8이 하루 만에 났다). 면제가
# 파일명에 걸리면 다음 납품에서 사라져 사람이 매번 다시 눌러야 한다.
for name in ("flying_thesis_v5.png", "flying_thesis_v8.png", "flying_thesis_v123.png"):
    check(f"에셋 id - {name}", w.asset_id_of(name) == "flying_thesis", w.asset_id_of(name))
check("에셋 id - 버전 없는 이름도 된다",
      w.asset_id_of("keyart.png") == "keyart", w.asset_id_of("keyart.png"))

# ---------------------------------------------------------------- 등록과 조회
w.add("flying_thesis", "color_hard", "리마스터 컨셉상 풀컬러 유지", "시험", path=tmp)
data = w.load(tmp)
check("면제를 걸면 그 지적이 면제된다",
      w.waived(data, "flying_thesis", "color_hard") is not None, str(list(data)))
check("면제는 그 지적에만 걸린다 - 다른 지적은 그대로",
      w.waived(data, "flying_thesis", "align_x") is None, "align_x가 같이 넘어가면 안 된다")
check("면제는 그 에셋에만 걸린다 - 다른 에셋은 그대로",
      w.waived(data, "sparker", "color_hard") is None, "sparker까지 넘어가면 안 된다")
check("사유가 남는다",
      w.waived(data, "flying_thesis", "color_hard")["reason"] == "리마스터 컨셉상 풀컬러 유지")

# ---------------------------------------------------------------- 부정 시험
for code in sorted(w.NON_WAIVABLE):
    try:
        w.add("flying_thesis", code, "그냥 넘기고 싶다", "시험", path=tmp)
        check(f"부정 시험 - {code}는 면제할 수 없다", False, "면제가 걸려 버렸다")
    except ValueError as e:
        check(f"부정 시험 - {code}는 면제할 수 없다", True, str(e)[:40])

# 이미 걸린 면제라도 NON_WAIVABLE이면 조회에서 안 잡혀야 한다(파일을 손으로 고친 경우).
hand = dict(data)
hand[w.key_of("flying_thesis", "size")] = {"asset": "flying_thesis", "code": "size",
                                           "reason": "손으로 넣음"}
check("부정 시험 - 파일을 손으로 고쳐 넣어도 계약 지적은 안 넘어간다",
      w.waived(hand, "flying_thesis", "size") is None, "size가 통과하면 게임이 깨진다")

try:
    w.add("flying_thesis", "scattered", "   ", "시험", path=tmp)
    check("부정 시험 - 사유 없이 못 건다", False, "사유 없이 걸렸다")
except ValueError as e:
    check("부정 시험 - 사유 없이 못 건다", True, str(e)[:30])

try:
    w.add("flying_thesis", "", "사유는 있다", "시험", path=tmp)
    check("부정 시험 - 코드 없이 못 건다", False, "코드 없이 걸렸다")
except ValueError as e:
    check("부정 시험 - 코드 없이 못 건다", True, str(e)[:30])

# ---------------------------------------------------------------- 해제
check("면제를 뗄 수 있다", w.remove("flying_thesis", "color_hard", path=tmp))
check("뗀 뒤에는 다시 지적된다",
      w.waived(w.load(tmp), "flying_thesis", "color_hard") is None)
check("없는 면제를 떼면 False", not w.remove("flying_thesis", "color_hard", path=tmp))

# ---------------------------------------------------------------- 없는 파일
check("면제 파일이 없으면 빈 dict",
      w.load(os.path.join(tempfile.mkdtemp(), "없다.json")) == {})

print(f"\n[test_waivers] 통과 {_pass} · 실패 {_fail}")
sys.exit(1 if _fail else 0)
