"""그래픽 LLM 납품 스프라이트 시트 검증기.

검사 항목:
  1) 크기 = 원본 아틀라스와 동일 (128x320)
  2) 배경 완전 투명 — 테두리에 불투명 픽셀 없음, 마젠타/키컬러 감지
  3) 셀별 실루엣 드리프트 — 원본 같은 셀과 불투명 픽셀 수/중심/bbox 비교
     (임계값 초과 시 재창작 판정)

사용: python tools/convert/validate_retouch_sheet.py <납품.png>
exit 0=통과 / 1=반려
"""
from __future__ import annotations
import json
import os
import sys
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ATLAS = os.path.join(ROOT, "assets", "sprites", "player_original.png")
META = os.path.join(ROOT, "assets", "sprites", "player_original.json")
DRIFT_LIMIT = 0.20   # 불투명 픽셀 수 허용 편차
MAGENTA = (255, 0, 255)


def main() -> None:
    if len(sys.argv) < 2:
        print("사용: python validate_retouch_sheet.py <납품.png>")
        sys.exit(2)
    sub_path = sys.argv[1]
    errors: list[str] = []
    warns: list[str] = []

    orig = Image.open(ATLAS).convert("RGBA")
    with open(os.path.join(ROOT, "assets", "sprites", "player_original.json"),
              encoding="utf-8") as fh:
        meta = json.load(fh)
    cell = int(meta["cell"])
    cols = int(meta["cols"])
    rows = orig.height // cell

    sub = Image.open(sub_path).convert("RGBA")
    # 1) 크기
    if sub.size != orig.size:
        errors.append(f"크기 불일치: {sub.size} != {orig.size}")

    # 2) 배경 — 테두리 불투명/마젠타 검사
    px = sub.load()
    w, h = sub.size
    border_opaque = 0
    magenta_cnt = 0
    for x in range(w):
        for y in (0, h - 1):
            if px[x, y][3] > 0:
                border_opaque += 1
                if px[x, y][:3] == MAGENTA:
                    magenta_cnt += 1
    for y in range(h):
        for x in (0, w - 1):
            if px[x, y][3] > 0:
                border_opaque += 1
                if px[x, y][:3] == MAGENTA:
                    magenta_cnt += 1
    if border_opaque > 0:
        errors.append(f"테두리에 불투명 픽셀 {border_opaque}개 — 배경 미투명")
    if magenta_cnt > 0:
        errors.append(f"마젠타(키컬러) 픽셀 {magenta_cnt}개 — 완전 투명으로 교체 필요")
    # 내부 마젠타도 카운트(색 규약 위반)
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if px[x, y][:3] == MAGENTA and px[x, y][3] > 0:
                magenta_cnt += 1
    if magenta_cnt > border_opaque:
        warns.append(f"내부 마젠타 픽셀 다수: {magenta_cnt}")

    # 3) 셀별 실루엣 드리프트 + 도트 영역(24x24 @ 오프셋) 검사
    op = sub.load()
    og = orig.load()

    def content_bbox(img_px, box):
        xs, ys = [], []
        for y in range(box[1], box[3]):
            for x in range(box[0], box[2]):
                if img_px[x, y][3] > 0:
                    xs.append(x - box[0])
                    ys.append(y - box[1])
        if not xs:
            return None
        return (min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1)

    for r in range(rows):
        for c in range(cols):
            box = (c * cell, r * cell, (c + 1) * cell, (r + 1) * cell)
            o_cnt = sum(1 for y in range(box[1], box[3]) for x in range(box[0], box[2])
                        if og[x, y][3] > 0)
            s_cnt = sum(1 for y in range(box[1], box[3]) for x in range(box[0], box[2])
                        if op[x, y][3] > 0)
            if o_cnt == 0 and s_cnt == 0:
                continue
            if o_cnt == 0 or s_cnt == 0:
                errors.append(f"셀({r},{c}) 한쪽만 비어있음 orig={o_cnt} sub={s_cnt}")
                continue
            drift = abs(s_cnt - o_cnt) / o_cnt
            ob = content_bbox(og, box)
            sb = content_bbox(op, box)
            if ob != sb:
                errors.append(f"셀({r},{c}) 도트 영역 불일치: orig bbox={ob} "
                              f"sub bbox={sb} (24x24 @(20,40) 유지 필요)")
            flag = "ERR" if drift > DRIFT_LIMIT else "ok"
            line = (f"셀({r},{c}) 픽셀수 orig={o_cnt} sub={s_cnt} "
                    f"편차={drift:.0%} {flag}")
            if drift > DRIFT_LIMIT:
                errors.append(line)
            elif drift > DRIFT_LIMIT / 2:
                warns.append(line)

    print("=== 납품 검증:", sub_path)
    for w_ in warns:
        print("  [warn]", w_)
    if errors:
        for e in errors:
            print("  [ERR ]", e)
        print(f"결과: 반려 ({len(errors)}건)")
        sys.exit(1)
    print("결과: 통과")


if __name__ == "__main__":
    main()
