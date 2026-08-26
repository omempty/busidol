"""신규 몬스터 스프라이트 LLM 의뢰 패키지 생성 — 정책 ③신규→컨셉+프롬프트.

data/monster_anim_specs.json에서 source가 placeholder 계열인 종을 읽어
assets/raw/llm/monsters/<id>/에 prompt.md + style_ref.png(원작 이관 시트 앵커)를
생성한다. 공통 첨부로 루트에 palette_swatch.png.

그리드 계약은 스프라이트 시트와 동일하게 강제한다(1차 주인공 납품 반려 교훈):
시트 크기 = 최대프레임×128 × 행수×128, 행별 프레임 수 준수, 빈 셀 완전 투명,
캐릭터 하단 중앙 정렬. 배경은 투명 또는 마젠타 #FF00FF 단색.

실행: python tools/convert/export_monster_packages.py [species_id ...]
"""
from __future__ import annotations
import io
import json
import os
import shutil
import sys

from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SPECS = os.path.join(ROOT, "data", "monster_anim_specs.json")
OUT_ROOT = os.path.join(ROOT, "assets", "raw", "llm", "monsters")
PALETTE_JSON = os.path.join(ROOT, "assets", "palette_master.json")
STYLE_ANCHOR = os.path.join(ROOT, "assets", "sprites", "mad_eye_original.png")
CELL = 128

PROMPT_TEMPLATE = """# {name_ko}(`{sid}`) 몬스터 스프라이트 시트 생성 의뢰

## 역할
너는 1995년 한국 공대 배경 캠퍼스 호러 JRPG의 몬스터 도트 디자이너다.
**신규 창작**이다 — 아래 컨셉 토큰을 원작 도트 감각으로 시각화한다.

## 몬스터
- 이름: {name_ko} (행동 패턴: {pattern}{boss_line})
- 컨셉 토큰: {token}

## 입력 (첨부)
1. `style_ref.png` — 원작에서 이관한 기존 몬스터 시트(스타일·크기·정렬 기준)
2. `../palette_swatch.png` — 사용 가능한 256색 마스터 팔레트

## 출력 규격 (그리드 계약 — 위반 시 반려)
- 시트: **{sheet_w}×{sheet_h}px PNG** (셀 {cell}px, {cols}열 × {rows}행) — 크기 정확 일치
- 각 행 = 아래 애니메이션, 좌→우가 프레임 순서:

{row_table}

- 프레임 수는 행별로 정확히 — 남는 셀은 **완전 투명**으로 둔다
- 캐릭터는 각 셀 **하단 중앙 정렬**, 실높이 {height_guide}(스타일 참조 시트와 비교해 크기 감각 유지)
- 프레임 간 캐릭터 일관(머리 크기·색 배치·디테일) 절대 유지 — 떨림/크기 변조 반려
- 배경: 완전 투명(alpha=0). 불가 시 **마젠타 #FF00FF 단색**(혼색·반투명·AA 금지)

## 스타일 타깃 (후기 클래식 JRPG + 캠퍼스 호러 그로테스크)
- 픽셀 아트: 안티에일리어싱 금지 / 그라데이션 금지(색당 4~6단계 밴딩)
- 그림자: 검정 금지 → 남보라 계열(예: #3A285C) 색조 그림자
- 외곽선: 1px 다크 아웃라인 — 순수 블랙 금지, 짙은 남색(예: #0A082E 방향)
- 팔레트: 첨부 스왑치 내 색 우선. 형광/파스텔 붕괴/EGA 원색 유입 금지
- SD 어휘 준용: 큰 머리(머리:몸 ≈ 1:1.2), 눈은 얼굴 하단 1/3에 크게
- 연출 참고(telegraph): {telegraph}

## 납품물
1. 스프라이트 시트 PNG 1장 ({sheet_w}×{sheet_h})
2. (선택) 디자인 포인트 요약 3줄 이내
"""


def size_class(cell_w: int) -> str:
    if cell_w <= 48:
        return "56~80px(소형 — 셀의 45~65%)"
    if cell_w <= 64:
        return "88~112px(중형 — 셀의 70~88%)"
    return "115~128px(대형 — 셀을 가득 채움)"


def make_palette_swatch(out_path: str) -> None:
    colors = json.load(io.open(PALETTE_JSON, encoding="utf-8"))["colors"]
    cols, sw = 32, 12
    rows = (len(colors) + cols - 1) // cols
    img = Image.new("RGB", (cols * sw, rows * sw), (24, 24, 28))
    d = ImageDraw.Draw(img)
    for i, hexc in enumerate(colors):
        x, y = (i % cols) * sw, (i // cols) * sw
        d.rectangle([x, y, x + sw - 1, y + sw - 1], fill=hexc)
    img.save(out_path)
    print(f"palette_swatch.png ({len(colors)} colors)")


def export_one(sp: dict) -> None:
    sid = sp["id"]
    anims = sorted(sp["animations"].items(), key=lambda kv: int(kv[1].get("row", 0)))
    rows = len(anims)
    cols = max(int(a.get("frames", 1)) for _, a in anims)
    sheet_w, sheet_h = cols * CELL, rows * CELL

    table_lines = ["| 행 | 애니 | 프레임 | 내용 |", "|---|---|---|---|"]
    for a_name, a in anims:
        desc = a.get("_desc", "")
        table_lines.append(
            f"| {int(a.get('row', 0))} | {a_name} | {int(a.get('frames', 1))}프레임 | {desc} |")
    row_table = "\n".join(table_lines)

    boss_line = " · **보스**" if sp.get("is_boss") else ""
    prompt = PROMPT_TEMPLATE.format(
        sid=sid,
        name_ko=sp.get("name_ko", sid),
        pattern=sp.get("pattern", ""),
        boss_line=boss_line,
        token=sp.get("token", ""),
        sheet_w=sheet_w,
        sheet_h=sheet_h,
        cell=CELL,
        cols=cols,
        rows=rows,
        row_table=row_table,
        height_guide=size_class(int(sp.get("cell", {}).get("w", 64))),
        telegraph=sp.get("telegraph_visual", "") or "(없음)",
    )
    out_dir = os.path.join(OUT_ROOT, sid)
    os.makedirs(out_dir, exist_ok=True)
    with io.open(os.path.join(out_dir, "prompt.md"), "w", encoding="utf-8") as f:
        f.write(prompt)
    if os.path.exists(STYLE_ANCHOR):
        shutil.copyfile(STYLE_ANCHOR, os.path.join(out_dir, "style_ref.png"))
    print(f"{sid}: {sheet_w}x{sheet_h} ({rows}행 {cols}열) prompt.md")


def main() -> None:
    os.makedirs(OUT_ROOT, exist_ok=True)
    make_palette_swatch(os.path.join(OUT_ROOT, "palette_swatch.png"))
    targets = set(sys.argv[1:])
    data = json.load(io.open(SPECS, encoding="utf-8"))
    for sp in data["species"]:
        if sp.get("source") not in ("placeholder", "placeholder_procedural"):
            continue
        if targets and sp["id"] not in targets:
            continue
        export_one(sp)
    print(f"done -> {OUT_ROOT}")


if __name__ == "__main__":
    main()
