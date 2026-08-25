"""LLM 납품 시트 재가공 - assets/raw/llm 워크플로우 [4]단계.

10_submitted/<캐릭터>_v<n>.png (마젠타 배경 납품)을 받아:
  1) 마젠타 키잉(sprite_retouch.key_magenta 재사용)
  2) 스펙 그리드(기본 셀 128x128) 컷팅
  3) 빈 셀 제외 프레임 검출
  4) 표준 규격 검증(_standard.md: 실높이/폭/정렬/AA/프레임 수)
-> 20_processed/<캐릭터>/ 에 프레임 PNG + 정리 시트 + 리포트 기록.

스펙 우선순위: --spec 인자 > assets/spec/sprites/<캐릭터>.json > 기본 표준.
첫 실제 납품 형식을 보고 임계값을 조정하는 것이 정확하다(HANDOFF 교훈).

사용: python tools/convert/process_llm_sheet.py <납품.png> [--spec 스펙.json]
exit 0=통과 / 1=오류 있음 / 2=사용법 오류
"""
from __future__ import annotations

import json
import os
import re
import sys

from PIL import Image

from sprite_retouch import key_magenta

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = os.path.join(ROOT, "assets", "raw", "llm")
SPEC_DIR = os.path.join(ROOT, "assets", "spec", "sprites")

DEFAULT_CELL = 128
# _standard.md §1~§4 임계값(셀 비율)
H_RANGE = (0.72, 0.95)      # 캐릭터 실높이 96~118px @128 (여유 포함 밴드)
W_MAX = 0.65                # 실폭 ≤80px
TOP_MARGIN = (0.08, 0.25)   # 상단 여백 10~20% 내외
BOTTOM_MARGIN_MAX = 0.12    # 발바닥 접지(하단 여백 소량 허용)
AA_WARN = 40                # 프레임당 반투명(AA) 픽셀 경고 문턱
JITTER_PX = 8               # 같은 행 프레임 간 캐릭터 높이 흔들림 경고
MIN_OPAQUE = 50             # 이 미만 불투명 픽셀 셀은 노이즈로 무시


def load_spec(path: str | None, char: str) -> tuple[dict | None, str]:
    """스펙 JSON 로드. 반환: (스펙dict|None, 출경로 설명)."""
    candidates = []
    if path:
        candidates.append(path if os.path.isabs(path)
                          else os.path.join(ROOT, path))
    candidates.append(os.path.join(SPEC_DIR, f"{char}.json"))
    for cand in candidates:
        if os.path.isfile(cand):
            with open(cand, encoding="utf-8") as fh:
                return json.load(fh), os.path.relpath(cand, ROOT)
    return None, "기본 표준(셀 128, 애니맵 없음)"


def analyze_cell(cell: Image.Image) -> dict:
    """셀 1개 통계: 불투명수/bbox/반투명수."""
    w, h = cell.size
    alpha = cell.getchannel("A")
    hist = alpha.histogram()
    opaque = sum(hist[255:])
    semi = sum(hist[1:255])
    bbox = alpha.getbbox()  # (l,t,r,b) 또는 None
    stats = {
        "opaque_px": opaque,
        "semi_alpha": semi,
        "bbox": None,
        "h_ratio": 0.0,
        "w_ratio": 0.0,
        "top_margin": 1.0,
        "bottom_margin": 1.0,
    }
    if bbox:
        bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]
        stats["bbox"] = [bbox[0], bbox[1], bw, bh]
        stats["h_ratio"] = bh / h
        stats["w_ratio"] = bw / w
        stats["top_margin"] = bbox[1] / h
        stats["bottom_margin"] = (h - bbox[3]) / h
    return stats


def main() -> None:
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        print("사용: python process_llm_sheet.py <납품.png> [--spec 스펙.json]")
        sys.exit(2)
    sub_path = args[0]
    spec_path = args[args.index("--spec") + 1] if "--spec" in args else None

    stem = os.path.splitext(os.path.basename(sub_path))[0]
    m = re.match(r"^(.+?)_v\d+$", stem)
    char = m.group(1) if m else stem
    spec, spec_src = load_spec(spec_path, char)

    cell_w = int(spec["cell"]["w"]) if spec else DEFAULT_CELL
    cell_h = int(spec["cell"]["h"]) if spec else DEFAULT_CELL
    row_anim: dict[int, str] = {}
    spec_frames: dict[str, int] = {}
    spec_grid: dict | None = None
    if spec:
        for name, a in spec.get("animations", {}).items():
            row_anim[int(a["row"])] = name
            spec_frames[name] = int(a.get("frames", 2))
        spec_grid = {k: int(v) for k, v in spec.get("grid", {}).items()} \
            if spec.get("grid") else None

    img = Image.open(sub_path).convert("RGBA")
    w, h = img.size
    errors: list[str] = []
    warns: list[str] = []

    print(f"=== 납품 재가공: {os.path.relpath(sub_path, ROOT)}")
    print(f"  캐릭터={char}  스펙={spec_src}")

    # 그리드 정합성 — 컷팅 불가 구조는 즉시 반려
    if w % cell_w != 0 or h % cell_h != 0:
        errors.append(f"크기가 셀({cell_w}x{cell_h})의 배수가 아님: {w}x{h}")
    cols, rows = w // cell_w, h // cell_h
    if spec_grid and (cols != spec_grid["cols"] or rows != spec_grid["rows"]):
        errors.append(
            f"그리드 불일치: 납품 {cols}열 x {rows}행 != 스펙 "
            f"{spec_grid['cols']}열 x {spec_grid['rows']}행")
    print(f"  크기={w}x{h}  그리드={cols}열 x {rows}행  셀={cell_w}x{cell_h}")
    if errors:
        _finish(img, char, [], [], errors, warns, sub_path, spec_src,
                (w, h), (cell_w, cell_h), cols, rows, 0, [])
        sys.exit(1)

    before = sum(img.getchannel("A").histogram()[255:])
    key_magenta(img)
    after = sum(img.getchannel("A").histogram()[255:])
    keyed = before - after
    print(f"  마젠타 키잉: {keyed}px 제거")

    out_dir = os.path.join(RAW, "20_processed", char)
    frames_dir = os.path.join(out_dir, "frames")
    os.makedirs(frames_dir, exist_ok=True)

    frames: list[dict] = []
    empty_cells: list[list[int]] = []
    row_cells: dict[int, list[tuple[int, dict]]] = {}

    for r in range(rows):
        seq = 0
        for c in range(cols):
            box = (c * cell_w, r * cell_h,
                   (c + 1) * cell_w, (r + 1) * cell_h)
            st = analyze_cell(img.crop(box))
            if st["opaque_px"] == 0:
                empty_cells.append([r, c])
                continue
            if st["opaque_px"] < MIN_OPAQUE:
                warns.append(
                    f"셀({r},{c}) 미세 내용 {st['opaque_px']}px — 노이즈 의심")
                empty_cells.append([r, c])
                continue
            anim = row_anim.get(r)
            name = f"{anim}_f{seq}" if anim else f"row{r}_c{c}"
            seq += 1
            rel = os.path.join("frames", f"{name}.png")
            img.crop(box).save(os.path.join(out_dir, rel))
            frames.append({"row": r, "col": c, "anim": anim, "name": name,
                           "file": rel.replace(os.sep, "/"), **st})
            row_cells.setdefault(r, []).append((c, st))
            if st["semi_alpha"] > AA_WARN:
                warns.append(f"{name}: 반투명(AA) 픽셀 {st['semi_alpha']}개"
                             " — 혼색/AA 금지 위반 의심")

    # 행 단위 규격 검사
    for r, cells in sorted(row_cells.items()):
        anim = row_anim.get(r, f"행{r}")
        hs = [st["h_ratio"] for _, st in cells]
        if max(hs) - min(hs) > JITTER_PX / cell_h:
            warns.append(f"{anim}: 프레임 간 높이 흔들림 "
                         f"{round((max(hs) - min(hs)) * cell_h)}px > {JITTER_PX}px")
        cols_used = [c for c, _ in cells]
        if cols_used != list(range(cols_used[0], cols_used[0] + len(cols_used))):
            warns.append(f"{anim}: 열 중간 빈칸(비연속) — {cols_used}")
        for c, st in cells:
            nm = next(f["name"] for f in frames
                      if f["row"] == r and f["col"] == c)
            if not H_RANGE[0] <= st["h_ratio"] <= H_RANGE[1]:
                warns.append(f"{nm}: 실높이 {st['h_ratio']:.0%}"
                             f" (표준 75~92%)")
            if st["w_ratio"] > W_MAX:
                warns.append(f"{nm}: 실폭 {st['w_ratio']:.0%} (표준 ≤65%)")
            if not TOP_MARGIN[0] <= st["top_margin"] <= TOP_MARGIN[1]:
                warns.append(f"{nm}: 상단 여백 {st['top_margin']:.0%}"
                             " (표준 10~20%)")
            if st["bottom_margin"] > BOTTOM_MARGIN_MAX:
                warns.append(f"{nm}: 하단 여백 {st['bottom_margin']:.0%}"
                             " — 발 접지 안 됨(하단 중앙 정렬 필요)")

    # 스펙 대비 프레임 수 검사
    for anim, want in spec_frames.items():
        got = sum(1 for f in frames if f["anim"] == anim)
        if got == 0:
            errors.append(f"{anim}: 프레임 0개 — 행 누락(스펙 요구 {want})")
        elif got < want:
            warns.append(f"{anim}: {got}/{want}프레임 — 부족(가변 최소 2)")
    unknown = sorted({f["row"] for f in frames} - set(row_anim))
    for r in unknown:
        warns.append(f"행{r}: 스펙에 없는 행에 프레임 존재")

    img.save(os.path.join(out_dir, "processed_sheet.png"))
    _finish(img, char, frames, empty_cells, errors, warns, sub_path, spec_src,
            (w, h), (cell_w, cell_h), cols, rows, keyed,
            [f["file"] for f in frames])
    sys.exit(1 if errors else 0)


def _finish(img: Image.Image, char: str, frames: list[dict],
            empty_cells: list[list[int]], errors: list[str],
            warns: list[str], sub_path: str, spec_src: str,
            size: tuple[int, int], cell: tuple[int, int],
            cols: int, rows: int, keyed: int,
            files: list[str]) -> None:
    """리포트 기록 + 결과 판정 출력."""
    out_dir = os.path.join(RAW, "20_processed", char)
    os.makedirs(out_dir, exist_ok=True)
    report = {
        "input": sub_path,
        "character": char,
        "spec": spec_src,
        "size": list(size),
        "cell": list(cell),
        "grid_detected": {"cols": cols, "rows": rows},
        "keyed_pixels": keyed,
        "frames": frames,
        "empty_cells": empty_cells,
        "warnings": warns,
        "errors": errors,
        "verdict": "rejected" if errors else "pass",
    }
    rp = os.path.join(out_dir, "report.json")
    with open(rp, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(report, fh, ensure_ascii=False, indent=2)

    for w_ in warns:
        print("  [warn]", w_)
    if errors:
        for e in errors:
            print("  [ERR ]", e)
        print(f"결과: 반려 ({len(errors)}건) -> {rp}")
    else:
        print(f"결과: 통과 — 프레임 {len(frames)}개, 빈 셀 "
              f"{len(empty_cells)}개 -> {rp}")
        for f in files:
            print("   ", f)


if __name__ == "__main__":
    main()
