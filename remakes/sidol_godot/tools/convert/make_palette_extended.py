#!/usr/bin/env python3
"""확장 팔레트 생성 — 리메이크 아트가 **실제로 쓰고 있는** 마스터 밖 색을 뽑아 확정한다.

## 왜 (2026-09-08)

스타일 바이블은 "기본: `palette_master.json`의 색만 사용 / JRPG 톤을 위한 확장 팔레트
+64색 신설 가능 — 사용 전 본 문서 개정으로 확정하고 `palette_extended.json`으로 별도 관리"
라고 적어 두었는데, **그 파일이 저장소에 없었다.** 그런데 의뢰문이 첨부로 주는
subpalette(참조 아트에서 실측한 상위 색)에는 마스터 밖 색이 섞여 있다
(`prompt_audit.py` 실측: 패키지 21건에서 #284882 #0A082E #121E3C #508CD2 #080618 #C8202C 등).

즉 의뢰문이 "마스터 색만 써라"라고 말하면서 마스터 밖 색을 예시로 주고 있었다.
지시가 자기모순이면 생성 모델은 둘 중 아무거나 따르고, 그 결과는 사람이 "모델이 규약을
못 지킨다"고 읽는다. 실제로는 **우리가 모순된 지시를 준 것**이다.

해법은 바이블이 이미 정해 둔 절차 그대로다: 실제로 쓰는 색을 확장 팔레트로 확정한다.
손으로 고른 색 목록이 아니라 **설치된 리메이크 아트에서 실측**해 굽는다 — 그래야
아트가 바뀌면 다시 구워 갱신할 수 있고, 목록이 어디서 왔는지 추적된다.

주의: 마스터 팔레트는 원본 DEFAULT.PAL 그대로라 **6비트(0~63)** 값이다("format": "raw768").
의뢰문·이미지의 hex는 8비트라 `<< 2`로 맞춰 비교해야 한다(안 맞추면 전부 "마스터 밖"이 된다).

실행: python tools/convert/make_palette_extended.py [--max 64] [--dry-run]
출력: assets/palette_extended.json
"""
from __future__ import annotations

import argparse
import glob
import io
import json
import os
import sys
from collections import Counter

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
MASTER = os.path.join(ROOT, "assets", "palette_master.json")
OUT = os.path.join(ROOT, "assets", "palette_extended.json")

## 실측 대상 — 의뢰문이 실제로 표본으로 삼는 아트 전부.
## 원작 이관본(`*_original.png`)도 넣는다: "이관본은 정의상 마스터 안"이라는 가정이
## 틀렸다(실측: #C8202C=(50,8,11)·#080618=(2,1,6)은 6비트로 읽어도 마스터에 없다).
## 생성기가 subpalette를 이 시트들에서 뽑으므로, 여기서 빠지면 의뢰문이 확장 팔레트
## 밖의 색을 계속 예시로 주게 된다.
## 키아트(1920x1080 일러스트)는 뺀다 — 도트 팔레트의 근거가 아니라 수천 색짜리 그림이라
## 상위 색을 통째로 잠식한다. 확장 팔레트는 **도트 아트가 쓰는 색**이어야 한다.
SOURCES = (
    "assets/sprites/*_remake.png",
    "assets/sprites/*_original.png",
    "assets/portraits/*.png",
    "assets/effects/*.png",
    "assets/battle_cuts/*.png",
    "assets/icons/*.png",
)
## 근접색 병합 반경(맨해튼 거리). 안 묶으면 #E5B897/#E5BA97/#E5BF97 처럼 1~2 값 차이가
## 팔레트 칸을 셋 먹는다(실측). 팔레트는 "구별되는 색"의 목록이어야 쓸모가 있다.
MERGE_DIST = 24
## 확장 팔레트 후보의 최소 사용량(px). 이보다 적게 쓰인 색은 그림의 색이 아니라
## 경계 찌꺼기로 본다.
MIN_PIXELS = 500


def master_hex8() -> set:
    data = json.load(io.open(MASTER, encoding="utf-8"))
    raw6 = str(data.get("format", "")).startswith("raw")
    out = set()
    for c in data.get("colors", []):
        v = int(c.lstrip("#"), 16)
        rgb = ((v >> 16) & 255, (v >> 8) & 255, v & 255)
        if raw6:
            # 저장소에 6->8비트 변환이 둘 공존한다(<<2 = 252, *255/63 = 255).
            # 같은 원본 색의 표기 차이일 뿐이므로 둘 다 마스터로 친다 —
            # 안 그러면 #FFFFFF 같은 원작 색이 확장 팔레트 칸을 먹는다.
            out.add(tuple(min(255, x << 2) for x in rgb))
            out.add(tuple(round(x * 255 / 63) for x in rgb))
            continue
        out.add(rgb)
    return out


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser()
    ap.add_argument("--max", type=int, default=64, help="확장 색 상한(바이블 규정 +64)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    master = master_hex8()

    # 카테고리마다 색 성격이 다르다(몬스터 시트는 어두운 외곽선, 아이콘은 채도 높은 원색).
    # 전역 상위로만 뽑으면 픽셀이 많은 시트가 64칸을 다 먹고 아이콘 계열은 한 칸도 못 든다
    # (실측: 그 상태에서 의뢰문 경고 37건이 남았다). 그래서 **카테고리별로 칸을 배분**한다.
    per_cat = {}
    files = 0
    for pat in SOURCES:
        tally: Counter = Counter()
        spread: Counter = Counter()
        n_files = 0
        for path in sorted(glob.glob(os.path.join(ROOT, pat))):
            try:
                im = Image.open(path).convert("RGBA")
            except Exception:  # noqa: BLE001 — 못 여는 파일은 건너뛴다
                continue
            n_files += 1
            a = np.asarray(im)
            rgb, alpha = a[:, :, :3], a[:, :, 3]
            here = set()
            for c in rgb[alpha > 200]:
                t = (int(c[0]), int(c[1]), int(c[2]))
                if t not in master:
                    tally[t] += 1
                    here.add(t)
            for t in here:
                spread[t] += 1
        files += n_files
        if tally:
            per_cat[pat] = (tally, spread, n_files)

    if not per_cat:
        print("[palette_extended] 마스터 밖 색이 없다 — 확장 팔레트가 필요 없다")
        return

    tally = Counter()
    spread = Counter()
    for t, sp_, _n in per_cat.values():
        tally.update(t)
        for c, v in sp_.items():
            spread[c] = max(spread[c], v)

    quota = max(1, args.max // len(per_cat))
    picked = []

    def take(order, limit):
        for c in order:
            if len(picked) >= limit:
                break
            if any(abs(c[0] - q[0]) + abs(c[1] - q[1]) + abs(c[2] - q[2]) <= MERGE_DIST for q in picked):
                continue     # 이미 뽑은 색과 사실상 같은 색
            picked.append(c)

    for pat, (t, sp_, _n) in per_cat.items():
        floor = max(MIN_PIXELS, int(sum(t.values()) * 1e-4))
        cand = [c for c in t if t[c] >= floor] or list(t)
        take(sorted(cand, key=lambda c: (-sp_[c], -t[c])), len(picked) + quota)
    # 남는 칸은 전역 상위로 채운다.
    floor = max(MIN_PIXELS, int(sum(tally.values()) * 1e-5))
    take(sorted([c for c in tally if tally[c] >= floor],
                key=lambda c: (-spread[c], -tally[c])), args.max)

    total_out = sum(tally.values())
    print(f"[palette_extended] 실측 {files}장({len(per_cat)}계열) · 마스터 밖 고유색 {len(tally)}종"
          f"({total_out:,}px) → 계열당 {quota}칸 배분 → {len(picked)}색 확정")
    for c in picked[:8]:
        print(f"    #{c[0]:02X}{c[1]:02X}{c[2]:02X}  에셋 {spread[c]:>3}장 · {tally[c]:>9,}px")

    doc = {
        "schema_version": 1,
        "source": "설치된 리메이크 아트 실측(tools/convert/make_palette_extended.py)",
        "_comment": (
            "스타일 바이블 '팔레트 잠금 + 확장 절차'가 허용한 확장 팔레트(+64색). "
            "palette_master.json(원본 DEFAULT.PAL, 6비트)에 없는 색 중 실제 사용 빈도 상위. "
            "아트가 바뀌면 같은 도구로 다시 굽는다."
        ),
        "format": "rgb8",
        "measured": {"files": files, "unique_outside_master": len(tally), "pixels": total_out,
                     "merge_distance": MERGE_DIST, "rank_by": "에셋 수(spread) -> 픽셀 수"},
        "colors": ["#%02X%02X%02X" % c for c in picked],
    }
    if args.dry_run:
        print("(dry-run — 쓰지 않음)")
        return
    tmp = OUT + ".tmp"
    io.open(tmp, "w", encoding="utf-8", newline="\n").write(
        json.dumps(doc, ensure_ascii=False, indent=1) + "\n"
    )
    os.replace(tmp, OUT)
    print(f"    -> {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
