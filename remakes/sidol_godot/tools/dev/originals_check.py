"""원본 대조 관문 — 변환된 맵이 원본 F*.MAP과 바이트 단위로 같은가.

이 프로젝트의 맵은 "변환"이 아니라 **그대로 옮긴 것**이다(TILE/OBJ/ATT 3평면, 200×65).
그 전제가 깨지면 감사 도구가 보고하는 고립 구역·차단 셀의 의미가 통째로 바뀐다
(원작 고증이 아니라 변환 버그가 된다). 2026-08-28 대조에서 6층 78,000셀 불일치 0을
확인했고, 그 사실을 여기서 상시 고정한다. MANIFEST.sha256 무결성도 함께 본다.

원본은 저장소에 없다(gitignored). 없으면 SKIP — CI를 빨간불로 만들지 않는다.

사용: python tools/dev/originals_check.py
"""

import hashlib
import json
import os
import sys

# 콘솔 코드페이지가 cp949여도 한글·em대시가 깨지지 않게 한다(bash·cmd 양쪽).
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ORIGINALS = os.path.normpath(os.path.join(ROOT, "..", "..", "originals", "1995_sidol_bsd_dos"))
PLANES = ("ground", "object", "attr")  # 원본 F*.MAP의 저장 순서 = TILE, OBJ, ATT
WIDTH, HEIGHT = 200, 65
CELLS = WIDTH * HEIGHT


def check_manifest(fails: list) -> int:
    path = os.path.join(ORIGINALS, "MANIFEST.sha256")
    if not os.path.exists(path):
        fails.append("MANIFEST.sha256 없음 — 원본 무결성을 증명할 수 없다")
        return 0
    checked = 0
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            digest, rel = line.split(None, 1)
            target = os.path.join(ORIGINALS, rel.replace("\\", os.sep))
            if not os.path.exists(target):
                fails.append("원본 누락: %s" % rel)
                continue
            with open(target, "rb") as bf:
                got = hashlib.sha256(bf.read()).hexdigest()
            if got.upper() != digest.upper():
                fails.append("원본 변조: %s" % rel)
            checked += 1
    return checked


def check_maps(fails: list) -> int:
    compared = 0
    for floor in range(6):
        conv_path = os.path.join(ROOT, "data", "maps", "f%d.json" % floor)
        orig_path = os.path.join(ORIGINALS, "F%d.MAP" % floor)
        if not os.path.exists(orig_path):
            fails.append("원본 맵 없음: F%d.MAP" % floor)
            continue
        with open(orig_path, "rb") as fh:
            raw = fh.read()
        if len(raw) < CELLS * 3:
            fails.append("F%d.MAP 크기 이상: %d바이트" % (floor, len(raw)))
            continue
        with open(conv_path, encoding="utf-8") as fh:
            layers = json.load(fh)["layers"]
        for i, name in enumerate(PLANES):
            rows = layers[name]
            flat = [c for row in rows for c in row] if rows and isinstance(rows[0], list) else rows
            orig = raw[i * CELLS:(i + 1) * CELLS]
            if len(flat) != CELLS:
                fails.append("f%d %s 셀 수 %d (기대 %d)" % (floor, name, len(flat), CELLS))
                continue
            diff = sum(1 for a, b in zip(flat, orig) if a != b)
            if diff:
                fails.append("f%d %s 원본과 불일치 %d셀" % (floor, name, diff))
            compared += CELLS
    return compared


def main() -> int:
    if not os.path.isdir(ORIGINALS):
        print("[originals_check] SKIP — 원본 없음(%s)" % ORIGINALS)
        return 0
    fails: list = []
    files = check_manifest(fails)
    cells = check_maps(fails)
    for f in fails:
        print("[originals_check] FAIL — %s" % f)
    if fails:
        return 1
    print("[originals_check] ok — 원본 %d파일 해시 일치 · 맵 %d셀 원본과 바이트 일치" % (files, cells))
    return 0


if __name__ == "__main__":
    sys.exit(main())
