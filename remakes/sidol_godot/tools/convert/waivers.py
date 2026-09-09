#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""지적 면제(FORCE OK) — **항목 단위**로, 사유를 남기고, 버전을 넘어 유지된다.

## 왜 파일 단위 FORCE OK가 아닌가 (2026-09-09)

flying_thesis_v8을 예로 들면 [ERR]이 3건이었고 그중 2건은 검증기 오탐(정렬),
1건은 진짜 결함(고유색 36702)이었다. 파일 하나를 통째로 통과시키면 **진짜 결함도
같이 통과한다** — 이 저장소가 이미 물린 사고다(규격만 보던 게이트가 결함 9장을
통과시켰다). 그래서 면제는 지적 하나를 콕 집어 건다.

## 왜 키에 버전을 안 쓰나

납품은 저장할 때마다 번호가 오른다(v5 -> v8이 하루 만에 났다). 면제를
`flying_thesis_v8.png`에 걸면 v9에서 사라져 사람이 매번 다시 누르게 된다.
그래서 키는 **에셋 id + 지적 코드**다. 파일명에서 `_v<n>`을 떼면 에셋 id가 된다.

## 무엇은 면제할 수 없나

계약 자체가 어긋난 것은 면제 대상이 아니다. 크기가 다르거나 스펙에 없는 종은
설치 자체가 안 되고, 선언한 프레임이 비면 애니메이션이 멎는다. 이런 것을
"통과"시키면 게임이 깨진 채로 넘어간다 — 면제가 아니라 거짓말이 된다.
"""
from __future__ import annotations

import io
import json
import os
import re
from datetime import datetime

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
## 면제 기록은 `data/`에 둔다 — `assets/raw/*`는 .gitignore에 걸려 있어 거기 두면
## **이 PC에만 남는다**. 면제는 원본 에셋이 아니라 "이 지적은 넘기기로 했다"는
## 프로젝트의 결정이라, 저장소를 따라다녀야 다른 사람·다른 기계에서도 같은 판정이 난다.
WAIVER_PATH = os.path.join(ROOT, "data", "asset_waivers.json")

## 면제할 수 없는 지적 — 통과시키면 설치·재생이 실제로 깨진다.
NON_WAIVABLE = {"size", "no_spec", "cell_empty"}


def asset_id_of(name: str) -> str:
    """파일명 -> 에셋 id. `flying_thesis_v8.png` -> `flying_thesis`."""
    return re.sub(r"_v\d+$", "", os.path.splitext(os.path.basename(name))[0])


def load(path: str = WAIVER_PATH) -> dict:
    if not os.path.exists(path):
        return {}
    try:
        with io.open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def key_of(asset_id: str, code: str) -> str:
    return f"{asset_id}|{code}"


def waived(data: dict, asset_id: str, code: str) -> dict | None:
    """이 에셋의 이 지적이 면제됐으면 그 기록을, 아니면 None."""
    if code in NON_WAIVABLE:
        return None
    return data.get(key_of(asset_id, code))


def add(asset_id: str, code: str, reason: str, by: str = "",
        path: str = WAIVER_PATH) -> dict:
    """면제를 건다. 사유는 필수 — 이유 없는 면제는 나중에 아무도 못 되짚는다."""
    code = (code or "").strip()
    reason = (reason or "").strip()
    if not code:
        raise ValueError("면제할 지적 코드가 없다")
    if code in NON_WAIVABLE:
        raise ValueError(
            f"'{code}'는 면제할 수 없다 — 계약이 어긋난 것이라 통과시키면 설치·재생이 깨진다")
    if not reason:
        raise ValueError("사유를 적어야 한다 — 이유 없는 면제는 되짚을 수 없다")
    data = load(path)
    data[key_of(asset_id, code)] = {
        "asset": asset_id,
        "code": code,
        "reason": reason,
        "by": by or os.environ.get("USERNAME", ""),
        "at": datetime.now().strftime("%Y-%m-%d %H:%M"),
    }
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with io.open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
    return data[key_of(asset_id, code)]


def remove(asset_id: str, code: str, path: str = WAIVER_PATH) -> bool:
    data = load(path)
    if key_of(asset_id, code) not in data:
        return False
    del data[key_of(asset_id, code)]
    with io.open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
    return True


def for_asset(asset_id: str, path: str = WAIVER_PATH) -> list:
    data = load(path)
    return [v for k, v in sorted(data.items()) if v.get("asset") == asset_id]
