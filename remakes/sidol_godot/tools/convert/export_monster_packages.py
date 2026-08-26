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

from llm_package_common import (
    copy_original_refs,
    make_palette_swatch,
    prepare_workspace,
    refs_block,
)

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SPECS = os.path.join(ROOT, "data", "monster_anim_specs.json")
OUT_ROOT = os.path.join(ROOT, "assets", "raw", "llm", "monsters")
PALETTE_JSON = os.path.join(ROOT, "assets", "palette_master.json")
STYLE_ANCHOR = os.path.join(ROOT, "assets", "sprites", "mad_eye_original.png")
## 주인공 시트 — 크기 기준. 이게 없으면 그림 LLM은 시돌이가 얼마나 큰지 모른 채 그린다.
SCALE_REF = os.path.join(ROOT, "assets", "sprites", "player_original.png")
## 주인공 아트 실높이(셀 128 안, player_original.png 실측). 모든 크기 지시의 기준선.
PLAYER_ART_H = 96
CELL = 128

PROMPT_TEMPLATE = """# {name_ko}(`{sid}`) 몬스터 스프라이트 시트 생성 의뢰

## 역할
너는 1995년 한국 공대 배경 캠퍼스 호러 JRPG의 몬스터 도트 디자이너다.
**신규 창작**이다 — 아래 컨셉 토큰을 원작 도트 감각으로 시각화한다.

## 몬스터
- 이름: {name_ko} (행동 패턴: {pattern}{boss_line})
- 컨셉 토큰: {token}

## 입력 (첨부)
1. `style_ref.png` — 원작에서 이관한 기존 몬스터 시트(도트 스타일·정렬 기준)
2. `scale_ref.png` — **주인공 시돌이 시트. 크기의 절대 기준**(셀 128 안 아트 높이 96px)
3. `../palette_swatch.png` — 사용 가능한 256색 마스터 팔레트
{orig_refs}

**원작 그림이 화풍의 1차 근거다.** 규칙 문장보다 첨부 그림을 먼저 따른다 —
실루엣의 굵기, 색 단계 수, 발광·질감 처리를 계승한다. 단 크기·정렬은
`style_ref.png`(도트 시트) 기준을 따른다.

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
{sd_clause}
- 연출 참고(telegraph): {telegraph}

## 납품물
1. 스프라이트 시트 PNG 1장 ({sheet_w}×{sheet_h})
2. (선택) 디자인 포인트 요약 3줄 이내
"""


## 체형별 SD 조항 — 인간형 어휘를 거미·자판기에 붙이면 해가 된다(2026-08-26).
SD_CLAUSE = {
    "humanoid": (
        "- SD 등신 준용: 머리:몸 ≈ 1:1.2(약 2.2등신), 눈은 얼굴 하단 1/3에 크게 — "
        "**주인공 시돌이와 같은 등신 체계**다(`scale_ref.png` 참조)"
    ),
    "creature": (
        "- SD는 등신이 아니라 **밀도**로 적용한다: 몸통을 크고 둥글게, 말단(다리·촉수·날개)은 "
        "짧고 굵게, 눈·핵심 기관을 과장해 크게. **인간형 등신 규칙은 적용하지 않는다**"
    ),
    "object": (
        "- 사물·기계형이라 등신 규칙이 없다. 대신 SD 감성을 형태로 준다: 모서리를 둥글리고, "
        "얼굴 역할을 하는 요소(화면·투입구·렌즈·틈)를 과장해 크게"
    ),
}


def sd_clause(body_type: str) -> str:
    return SD_CLAUSE.get(body_type, SD_CLAUSE["creature"])


def size_class(cell_w: int) -> str:
    """셀 대비가 아니라 **주인공 대비**로 지시한다.

    원작 몬스터 8종 실측(화면 높이 기준)은 주인공의 87~100%로, 거의 같은 등신이다.
    "셀의 45~65%" 같은 절대 비율만 주면 주인공보다 한참 작은 종이 나와 계열이 깨진다.
    """
    if cell_w <= 48:
        return f"78~90px (주인공 {PLAYER_ART_H}px의 80~94% — 소형)"
    if cell_w <= 64:
        return f"90~106px (주인공 {PLAYER_ART_H}px의 94~110% — 중형)"
    return f"106~124px (주인공 {PLAYER_ART_H}px의 110~129% — 대형)"


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
    out_dir = os.path.join(OUT_ROOT, sid)
    os.makedirs(out_dir, exist_ok=True)
    listed = copy_original_refs("monsters", out_dir)
    prompt = PROMPT_TEMPLATE.format(
        orig_refs=refs_block(listed, 4),
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
        sd_clause=sd_clause(str(sp.get("body_type", "creature"))),
        telegraph=sp.get("telegraph_visual", "") or "(없음)",
    )
    with io.open(os.path.join(out_dir, "prompt.md"), "w", encoding="utf-8") as f:
        f.write(prompt)
    if os.path.exists(STYLE_ANCHOR):
        shutil.copyfile(STYLE_ANCHOR, os.path.join(out_dir, "style_ref.png"))
    if os.path.exists(SCALE_REF):
        shutil.copyfile(SCALE_REF, os.path.join(out_dir, "scale_ref.png"))
    print(f"{sid}: {sheet_w}x{sheet_h} ({rows}행 {cols}열) prompt.md")


def main() -> None:
    os.makedirs(OUT_ROOT, exist_ok=True)
    prepare_workspace()
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
