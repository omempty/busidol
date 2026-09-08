#!/usr/bin/env python3
"""의뢰문 내용 감사 — prompt.md가 **정본 규격과 같은 말을 하고 있는가**.

## 왜 (기존 관문이 못 보는 층)

- `package_check.py`는 첨부가 **있는지**만 본다(파일 존재).
- `validate_*.py` / `delivery_checks.py`는 **납품물**만 본다.
- 그 사이에 아무도 안 보는 층이 있다: **의뢰문에 적힌 숫자**. 시트 크기·행별 프레임 수·
  셀 크기·팔레트 hex는 `data/*_specs.json`에서 뽑아 문장으로 굳힌 값인데, 스펙이 바뀌면
  의뢰문은 그대로 남는다. 틀린 숫자로 그려 온 납품은 검증기가 반려하고, 사람은
  "생성 모델이 규약을 못 지킨다"고 읽는다 — 실제로는 **우리가 틀린 규격을 준 것**이다.

이 도구는 의뢰문의 주장(선언 크기·행 표·격자 템플릿·팔레트)을 정본과 대조한다.

  FAIL  납품이 반드시 어긋난다(크기·프레임 수·템플릿 불일치)
  WARN  틀렸다고 단정할 수 없지만 사람이 봐야 한다(팔레트 이탈·번호 중복·빈 토큰)

실행:
  python tools/review/prompt_audit.py                 전수 감사
  python tools/review/prompt_audit.py --sample 3      카테고리당 3건만(고정 시드)
  python tools/review/prompt_audit.py --cat monsters  카테고리 한정
종료코드: 0=FAIL 없음 / 1=FAIL 있음
"""
from __future__ import annotations

import argparse
import io
import json
import os
import random
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
LLM = os.path.join(ROOT, "assets", "raw", "llm")
SPEC_FILES = (
    "monster_anim_specs.json",
    "npc_anim_specs.json",
    "effect_specs.json",
    "battle_cut_specs.json",
    "battle_actor_specs.json",
)
## 시트가 아닌 카테고리의 고정 규격 — review_server.FLAT_CONTRACTS와 같은 수다.
FLAT = {
    "portraits": (768, 256),
    "items": (96, 96),
    "keyart": (1920, 1080),
}
SKIP_DIR = ("_", "00_", "10_", "20_", "30_")

## "**512×896px PNG**" / "**768×256 PNG 1장**" / "**1920×1080 (16:9) PNG 1장**"
SIZE_RE = re.compile(r"\*\*(\d{2,5})\s*[×x]\s*(\d{2,5})(?:px)?\s*(?:\([^)]*\)\s*)?PNG")
## "(셀 128px, 4열 × 7행)"
GRID_RE = re.compile(r"셀\s*(\d+)\s*px?\s*,\s*(\d+)\s*열\s*[×x]\s*(\d+)\s*행")
## 행 표: "| 0 | walk_down | 4프레임 | ... |"
ROW_RE = re.compile(r"^\|\s*(\d+)\s*\|\s*([A-Za-z0-9_]+)\s*\|\s*(\d+)\s*프레임", re.M)
ATTACH_SEC_RE = re.compile(r"^## 입력 \(첨부\).*?(?=^## )", re.S | re.M)
ATTACH_NUM_RE = re.compile(r"^(\d+)\.\s", re.M)
HEX_RE = re.compile(r"#([0-9A-Fa-f]{6})")
HEAD_RE = re.compile(r"^## (.+)$", re.M)


def load_specs() -> dict:
    """asset_id → 정본 그리드 계약. review_server.sheet_contract와 같은 규칙."""
    out = {}
    for name in SPEC_FILES:
        path = os.path.join(ROOT, "data", name)
        if not os.path.exists(path):
            continue
        for sp in json.load(io.open(path, encoding="utf-8")).get("species", []):
            anims = sp.get("animations")
            if not isinstance(anims, dict) or not anims:
                continue  # 참조 전용 항목(시트가 아니다)
            rows = sorted(anims.items(), key=lambda kv: int(kv[1].get("row", 0)))
            cell = int(sp.get("sheet_cell") or 128)
            cols = max(int(a.get("frames", 1)) for _, a in rows)
            out[sp["id"]] = {
                "cell": cell, "cols": cols, "rows": len(rows),
                "size": (cols * cell, len(rows) * cell),
                "layout": [(n, int(a.get("row", 0)), int(a.get("frames", 1))) for n, a in rows],
                "spec": name,
            }
    return out


def palette_master() -> tuple:
    """(허용 hex 집합, 확장 팔레트 존재 여부).

    palette_master.json은 원본 DEFAULT.PAL 그대로라 **6비트(0~63) 값**이다("format": "raw768").
    의뢰문에 적히는 hex는 8비트로 늘린 값(0x3F -> 0xFC)이라 그냥 비교하면 전부 불일치로
    잡힌다 — 실제로 첫 판에서 그렇게 나왔다. 여기서 <<2로 맞춰 비교한다.
    """
    path = os.path.join(ROOT, "assets", "palette_master.json")
    if not os.path.exists(path):
        return set(), False
    data = json.load(io.open(path, encoding="utf-8"))
    raw6 = str(data.get("format", "")).startswith("raw")
    out = set()
    for c in data.get("colors", []):
        v = int(c.lstrip("#"), 16)
        rgb = ((v >> 16) & 255, (v >> 8) & 255, v & 255)
        if raw6:
            rgb = tuple(min(255, x << 2) for x in rgb)
        out.add("#%02X%02X%02X" % rgb)
    # 스타일 바이블이 약속한 확장 팔레트(+64색). 있으면 허용 집합에 더한다.
    ext_path = None
    for cand in (os.path.join(ROOT, "assets", "palette_extended.json"),
                 os.path.join(ROOT, "data", "palette_extended.json")):
        if os.path.exists(cand):
            ext_path = cand
            break
    if ext_path:
        for c in json.load(io.open(ext_path, encoding="utf-8")).get("colors", []):
            out.add("#" + c.lstrip("#").upper())
    return out, bool(ext_path)


def png_size(path: str):
    """PNG 헤더만 읽어 크기를 잰다 — PIL 없이도 도는 편이 관문으로 쓰기 좋다."""
    try:
        with open(path, "rb") as f:
            head = f.read(26)
        if head[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        return (int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big"))
    except OSError:
        return None


def spec_section(md: str) -> str:
    """'## 출력 규격' 절만 잘라 낸다 — 프레임 수는 여기 적힌 것만 계약이다."""
    m = re.search(r"^## 출력 규격.*?(?=^## |\Z)", md, re.S | re.M)
    return m.group(0) if m else md


def audit_one(cat: str, asset_id: str, pkg: str, specs: dict, palette: set, has_ext: bool = False) -> list:
    """한 패키지의 (등급, 메시지) 목록."""
    md_path = os.path.join(pkg, "prompt.md")
    if not os.path.exists(md_path):
        return [("FAIL", "prompt.md 없음")]
    md = io.open(md_path, encoding="utf-8").read()
    out = []

    # --- 1. 선언 크기 ------------------------------------------------------
    sizes = [(int(a), int(b)) for a, b in SIZE_RE.findall(md)]
    declared = sizes[0] if sizes else None
    truth = specs.get(asset_id, {}).get("size") or FLAT.get(cat)
    if not declared:
        out.append(("FAIL", "출력 크기 선언(**W×H PNG**)을 못 찾았다"))
    elif truth and declared != tuple(truth):
        out.append(("FAIL", f"선언 크기 {declared[0]}×{declared[1]} ≠ 정본 {truth[0]}×{truth[1]}"
                            f" ({specs.get(asset_id, {}).get('spec', '고정 규격')})"))
    elif not truth:
        out.append(("WARN", f"정본 스펙에 {asset_id} 없음 — 선언 {declared[0]}×{declared[1]}만 있고 대조 근거가 없다"))
    if len(set(sizes)) > 1:
        out.append(("WARN", "크기 선언이 문서 안에서 여러 개다: "
                            + ", ".join(f"{w}×{h}" for w, h in dict.fromkeys(sizes))))

    # --- 2. 격자 선언(셀·열·행)과 크기의 자체 일관성 -----------------------
    g = GRID_RE.search(md)
    if g:
        cell, cols, rows = (int(x) for x in g.groups())
        if declared and (cols * cell, rows * cell) != declared:
            out.append(("FAIL", f"격자 선언(셀 {cell}·{cols}열×{rows}행 = {cols*cell}×{rows*cell})이"
                                f" 선언 크기 {declared[0]}×{declared[1]}와 안 맞는다"))
        sp = specs.get(asset_id)
        if sp and (cell, cols, rows) != (sp["cell"], sp["cols"], sp["rows"]):
            out.append(("FAIL", f"격자 선언(셀 {cell}·{cols}열×{rows}행) ≠ 정본"
                                f"(셀 {sp['cell']}·{sp['cols']}열×{sp['rows']}행)"))

    # --- 3. 행 표 vs 정본 애니메이션 --------------------------------------
    sp = specs.get(asset_id)
    table = [(int(r), n, int(f)) for r, n, f in ROW_RE.findall(md)]
    if sp:
        if not table and sp["rows"] == 1:
            # 1행 시트(이펙트·전투컷)는 표 대신 산문으로 적는다("프레임 4장" / "좌->우 5프레임").
            # 프레임 수의 1차 근거는 **격자 선언**(N열 x 1행)이고 그건 위에서 이미 정본과
            # 대조했다. 본문 숫자를 또 세면 첨부 설명의 "원작 d1 시퀀스 5프레임" 같은
            # 문장을 프레임 수로 오인한다(첫 판에서 dodge/finisher가 그렇게 오탐났다).
            if not g:
                got = {int(n) for n in re.findall(r"(\d+)\s*(?:프레임|장)", spec_section(md))}
                if not got:
                    out.append(("FAIL", "프레임 수 지시가 없다(격자 선언도 산문도 없음)"))
                elif sp["cols"] not in got:
                    out.append(("FAIL", f"출력 규격 절의 프레임 수 {sorted(got)} 에 정본 {sp['cols']}장이 없다"))
        elif not table:
            out.append(("FAIL", f"행 표가 없다 — {sp['rows']}행짜리 시트인데 행별 프레임 수를 지시하지 않았다"))
        else:
            truth_rows = {row: (n, f) for n, row, f in sp["layout"]}
            if len(table) != sp["rows"]:
                out.append(("FAIL", f"행 표 {len(table)}행 ≠ 정본 {sp['rows']}행"))
            for row, name, frames in table:
                t = truth_rows.get(row)
                if not t:
                    out.append(("FAIL", f"행 {row}은 정본에 없다({name})"))
                elif t[0] != name:
                    out.append(("FAIL", f"행 {row} 애니 이름 {name} ≠ 정본 {t[0]}"))
                elif t[1] != frames:
                    out.append(("FAIL", f"행 {row}({name}) {frames}프레임 ≠ 정본 {t[1]}프레임"))
            if table and max(f for _, _, f in table) != sp["cols"]:
                out.append(("WARN", f"행 표 최대 프레임 {max(f for _, _, f in table)} ≠ 열 수 {sp['cols']}"))

    # --- 4. 격자 템플릿 실측 vs 선언 --------------------------------------
    tpl = os.path.join(pkg, "grid_template.png")
    if not os.path.exists(tpl):  # 카테고리 공용 템플릿
        tpl = os.path.join(os.path.dirname(pkg), "grid_template.png")
    if os.path.exists(tpl) and declared:
        s = png_size(tpl)
        if s and s != declared:
            out.append(("FAIL", f"grid_template.png 실측 {s[0]}×{s[1]} ≠ 선언 {declared[0]}×{declared[1]}"
                                " — 그 위에 그리면 규격 위반이 된다"))
    guide = os.path.join(pkg, "grid_guide.png")
    if os.path.exists(guide) and declared and png_size(guide) == declared:
        out.append(("WARN", "grid_guide.png가 선언 크기와 같다 — 설명 그림 위에 그려 오는 사고가 난다"
                            "(일부러 다른 크기여야 한다)"))

    # --- 5. 첨부 번호 -----------------------------------------------------
    sec = ATTACH_SEC_RE.search(md)
    if sec:
        nums = [int(n) for n in ATTACH_NUM_RE.findall(sec.group(0))]
        if nums and nums != list(range(1, len(nums) + 1)):
            out.append(("WARN", f"첨부 번호가 어긋난다: {nums} — 사람이 세는 순서와 파일이 밀린다"))
    else:
        out.append(("WARN", "'## 입력 (첨부)' 절이 없다 — 첨부 검사(package_check)가 이 패키지를 건너뛴다"))

    # --- 6. 팔레트 hex ----------------------------------------------------
    if palette:
        block = re.search(r"subpalette\.png.*?\n(?:.*\n){0,3}?\s*`([^`]*#[^`]*)`", md)
        if block:
            hexes = {("#" + h).upper() for h in HEX_RE.findall(block.group(1))}
            stray = sorted(hexes - palette)
            if stray:
                why = ("확장 팔레트(palette_extended.json)가 없다 — 의뢰문은 "
                       "'마스터 팔레트 색만'이라 해 놓고 그 밖의 색을 첨부 목록으로 준다"
                       if not has_ext else "마스터·확장 어느 쪽에도 없다")
                out.append(("WARN", f"팔레트 밖 hex {len(stray)}개({why}): {', '.join(stray[:6])}"))

    # --- 7. 정체성 토큰 ---------------------------------------------------
    for label in ("컨셉 토큰:", "신원 토큰:", "고정 토큰:"):
        m = re.search(re.escape(label) + r"\s*(.*)", md)
        if m and not m.group(1).strip():
            out.append(("FAIL", f"'{label}' 가 비어 있다 — 무엇을 그릴지 지시가 없다"))

    # --- 8. 필수 금지·확인 문구 -------------------------------------------
    for needle, why in (("48색", "고유색 상한"), ("격자 안내선", "잔선 제거 지시"),
                        ("반투명", "알파 이진화 지시")):
        if needle not in md:
            out.append(("WARN", f"'{needle}'({why}) 문구가 없다 — 게이트는 이걸로 반려한다"))

    # --- 9. 중복 섹션 -----------------------------------------------------
    heads = [h.split("(")[0].strip() for h in HEAD_RE.findall(md)]
    dup = sorted({h for h in heads if heads.count(h) > 1})
    if dup:
        out.append(("WARN", "같은 제목의 절이 두 번 이상: " + ", ".join(dup)))

    return out


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser()
    ap.add_argument("--cat", default="", help="카테고리 한정")
    ap.add_argument("--sample", type=int, default=0, help="카테고리당 표본 수(0=전수)")
    ap.add_argument("--seed", type=int, default=20260908)
    ap.add_argument("--quiet", action="store_true", help="이상 있는 패키지만 출력")
    args = ap.parse_args()

    if not os.path.isdir(LLM):
        print("[prompt_audit] assets/raw/llm 없음 — 의뢰생성.bat 으로 패키지를 먼저 만들어라")
        sys.exit(0)

    specs = load_specs()
    palette, has_ext = palette_master()
    rng = random.Random(args.seed)
    cats = [args.cat] if args.cat else sorted(
        d for d in os.listdir(LLM)
        if os.path.isdir(os.path.join(LLM, d)) and not d.startswith(SKIP_DIR)
    )

    n_pkg = n_fail = n_warn = 0
    bad_pkgs = []
    for cat in cats:
        cat_dir = os.path.join(LLM, cat)
        pkgs = sorted(d for d in os.listdir(cat_dir)
                      if os.path.isdir(os.path.join(cat_dir, d)) and not d.startswith("_"))
        if args.sample and len(pkgs) > args.sample:
            pkgs = sorted(rng.sample(pkgs, args.sample))
        if not pkgs:
            continue
        print(f"\n== {cat} ({len(pkgs)}건{' 표본' if args.sample else ''})")
        for asset_id in pkgs:
            n_pkg += 1
            findings = audit_one(cat, asset_id, os.path.join(cat_dir, asset_id), specs, palette, has_ext)
            f = sum(1 for g, _ in findings if g == "FAIL")
            w = len(findings) - f
            n_fail += f
            n_warn += w
            if f or w:
                bad_pkgs.append(f"{cat}/{asset_id}")
            if args.quiet and not findings:
                continue
            mark = "FAIL" if f else ("warn" if w else " ok ")
            print(f"  [{mark}] {asset_id}")
            for grade, msg in findings:
                print(f"        {'✗' if grade == 'FAIL' else '·'} {msg}")

    print(f"\n[prompt_audit] 패키지 {n_pkg}건 · FAIL {n_fail} · WARN {n_warn}"
          f" · 지적 있는 패키지 {len(bad_pkgs)}건")
    sys.exit(1 if n_fail else 0)


if __name__ == "__main__":
    main()
