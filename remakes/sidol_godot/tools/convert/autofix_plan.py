#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""검증기 지적 → 자동보정 계획. **이 표가 정본이다.**

## 왜 파이썬에 두나 (2026-09-09)

이 표를 편집기(sprite_fixer.html)에도 두고 시험 하네스에도 두면 두 벌이 된다. 이
저장소가 반복해 물린 결함이 정확히 그것이다 — "편집기는 깨끗한데 검증기는 반려하는"
갈라짐. 그래서 표는 여기 하나만 두고, 서버가 검증 결과에 계획을 실어 편집기로 내린다.
편집기는 계획을 **실행만** 한다.

## 세 가지를 정한다

1. `AUTOFIX_BY_CODE` — 지적을 고치는 연산. 없는 코드는 사람이 봐야 하는 것이다.
2. `AUTOFIX_ORDER`   — 실행 순서. 잔선을 먼저 지워야 정렬이 잔선에 안 끌리고,
   순수검정 치환은 양자화가 외곽선을 검정으로 몰아넣으므로 마지막이다.
3. `AUTOFIX_VETO`    — 어떤 지적은 특정 연산을 **금지한다**. 고치는 표만으로는
   자동보정이 지적을 없애는 대신 그림을 망가뜨릴 수 있다.

## 거부권이 왜 필요한지 — 실측 (flying_thesis_v8)

이 시트는 내용 6177px 중 6169px(99.9%)이 반투명인 소프트 알파 그림이다.
`quantize`는 이름과 달리 알파도 0/255로 이진화한다(sheet_ops.quantize). 돌렸더니:

    attack r1c0  내용 6177 → 5439 (-12%) · 본체 92% → 66% · 중심 74.0 → 82.5
    attack r1c2  내용 5902 → 5244 (-11%) · 본체 84% → 66% · 중심 57.5 → 39.5

없던 정렬 [ERR]이 2건 생겼다. 지적 하나를 지우고 둘을 만든 것이다. 그래서
`semi_alpha_soft`가 있으면 알파를 건드리는 연산을 전부 막는다. 그러면 이런 시트는
"기계가 고칠 수 없다"가 되는데, 그게 사실이다 — 도트로 다시 받아야 한다.
"""
from __future__ import annotations

## 지적 코드 → 그것을 고치는 연산.
## 일부러 빠뜨린 코드와 이유:
##   scattered        소멸 프레임이 흩어진 것은 정상이다. 고칠 게 없다.
##   cell_empty       빈 칸은 그림을 그려 넣어야 한다 — 기계가 만들 수 없다.
##   cell_extra       여분 칸을 지워야 하는데 무엇이 여분인지는 사람이 본다.
##   split_cell       한 칸에 반쪽 둘 — 배치가 틀린 것이라 [행 재배치]가 답이다.
##   flat_placeholder 그림이 아니라 색판이다. 다시 받아야 한다.
##   size, no_spec    계약 자체가 안 맞는다. [크기 자동 조절]·스펙 등록이 먼저다.
##   palette          팔레트 이탈은 색 선택 문제라 양자화로 덮으면 더 틀어진다.
##   magenta_aa       누끼가 깨진 것이라 사람이 값을 보며 [자동 배경 제거]로 잡는다.
##   semi_alpha_soft  그림이 통째로 반투명이다 — 아래 거부권 참고.
##   frame_border     한때 guides로 이었다가 뺐다. clean_guides는 **칸 경계**의 잔선을
##                    지우는데, 이 지적이 가리키는 선은 칸 안쪽이다(실측: flying_thesis_v8
##                    col73·row92, 셀 128 경계는 0/128/…). 돌려도 0px만 지우고 지적이
##                    그대로라 계획이 매 회차 같은 연산을 다시 골라 수렴하지 않았다.
##                    그림 안에 그려진 선이므로 사람이 지워야 한다.
AUTOFIX_BY_CODE = {
    "guide_residue": "guides",
    "align_x": "snapall",
    "align_y": "snapall",
    "semi_alpha": "binarize",
    "color_hard": "quantize",
    "color_budget": "quantize",
    "pure_black": "deblack",
}

AUTOFIX_ORDER = ["guides", "snapall", "binarize", "quantize", "deblack"]

## 지적 → 이 지적이 있으면 돌리면 안 되는 연산들.
AUTOFIX_VETO = {
    # 알파를 0/255로 뭉개는 연산 전부. 소프트 알파 그림에서는 정리가 아니라 삭제다.
    "semi_alpha_soft": ["binarize", "quantize"],
}


def plan_for(codes) -> dict:
    """지적 코드 목록 → {plan, vetoed, manual}.

    plan   순서대로 돌릴 연산
    vetoed {연산: [그것을 막은 지적…]} — 사람에게 이유를 말하려고 함께 돌려준다
    manual 기계가 손댈 수 없는 지적(고치는 표에 없거나, 거부권에 막힌 것)
    """
    codes = list(codes or [])
    vetoed: dict[str, list] = {}
    for c in codes:
        for op in AUTOFIX_VETO.get(c, []):
            vetoed.setdefault(op, []).append(c)

    plan = []
    for op in AUTOFIX_ORDER:
        if op in vetoed:
            continue
        if any(AUTOFIX_BY_CODE.get(c) == op for c in codes):
            plan.append(op)

    manual = [c for c in codes
              if AUTOFIX_BY_CODE.get(c) is None or AUTOFIX_BY_CODE[c] in vetoed]
    return {"plan": plan, "vetoed": vetoed, "manual": manual}
