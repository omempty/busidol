#!/usr/bin/env python3
"""원작 이관 몬스터 **리마스터** 의뢰 패키지 생성 — 정책 ②원작+격상.

## 왜 별도인가

`export_monster_packages.py`는 `source`가 placeholder인 종만 훑고, 프롬프트도
"**신규 창작**이다"로 시작한다. 원작에서 이관한 8종(sparker·mad_eye·vulgar·dworm·
ozzy·iron_voc·hellcop·o_ray)에는 그 계약이 맞지 않는다 — 이미 그림이 있고,
바꾸면 안 되는 것(신원·실루엣·색 정체성)이 있다. 그래서 **의뢰할 방법이 없어**
8종이 1995년 도트 그대로 남아 있었다(`_remake` 0장).

## 이 패키지의 계약

- 신원·실루엣·색 정체성은 원작 그대로. 해상도·명암 단계·질감만 격상한다.
- **원작에 없던 행은 신규 창작이다.** 원작 시트는 보행 4방향 2프레임 + idle뿐이고
  공격·피격·사망 모션이 없었다(원작 전투는 대형 컷이 담당했다). 리메이크는 그 행들을
  요구하므로(프리젠터가 attack/hurt/death 행을 재생한다) 원작 실루엣을 근거로 채운다.
- 보행은 원작 2프레임의 포즈를 계승하되 중간 프레임을 넣어 4프레임으로 편다.

첨부의 핵심은 **그 몬스터 자신의 원작 그림 두 벌**이다:
`<id>_original.png`(게임에 들어가 있는 128 격자 이관 시트)와 원작 SPR 원본 프레임
(`00_reference/<spr>/frame_NNN.png`, 24~26px 도트). 서브팔레트도 그 몬스터 자신의
색에서 뽑는다 — 색 정체성이 리마스터에서 가장 먼저 깨지는 부분이다.

실행: python tools/convert/export_monster_remaster_packages.py [species_id ...]
"""
from __future__ import annotations

import io
import json
import os
import re
import shutil
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from PIL import Image

from llm_package_common import (
    NEGATIVE_RULES,
    SELF_CHECK,
    dedupe_package_dirs,
    dominant_colors,
    identity_block,
    make_grid_template,
    make_palette_swatch,
    make_subpalette,
    measure_tone,
    prepare_workspace,
    style_bible_block,
    tone_block,
)

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SPECS = os.path.join(ROOT, "data", "monster_anim_specs.json")
OUT_ROOT = os.path.join(ROOT, "assets", "raw", "llm", "monsters")
SPRITES = os.path.join(ROOT, "assets", "sprites")
ORIG_FRAMES = os.path.join(ROOT, "assets", "raw", "llm", "00_reference")
SCALE_REF = os.path.join(SPRITES, "player_original.png")
CELL = 128
## 이관 시트 메타의 source 문자열 예: "I.SPR frames 048-055 (원작 도트 26x26, 4배 nearest 베이크)"
SOURCE_RE = re.compile(r"([A-Za-z0-9_]+)\.SPR frames (\d+)-(\d+)")
## 원작 프레임은 24~26px라 그대로 첨부하면 LLM이 못 알아본다 — 정수배로 키워 붙인다.
FRAME_ZOOM = 8

PROMPT_TEMPLATE = """# {name_ko}(`{sid}`) 몬스터 시트 **리마스터** 의뢰

{style_bible}

## 역할
너는 1995년 DOS RPG의 원작 몬스터 도트를 현대 JRPG 톤으로 격상시키는 픽셀 아티스트다.
**신규 창작이 아니다.** 이 몬스터는 이미 존재하고, 플레이어가 원작에서 본 얼굴이 있다.

## 대상
- 이름: {name_ko} (행동 패턴: {pattern})
- 컨셉 토큰: {token}
- 원작 정보: {orig_desc} · 원작은 **보행 4방향 2프레임 + 정지**뿐이었다(공격·피격·사망 모션 없음)

## 입력 (첨부) — 아래 경로의 파일이 첨부물의 전부다(`..` = 카테고리 루트, 공용 1부)
1. `{sid}_original.png` — **지금 게임에 들어가 있는 이관 시트**(셀 128, {orig_cols}열 × {orig_rows}행).
   신원·실루엣·색 정체성의 1차 근거다. 이 그림의 몬스터와 **같은 개체**여야 한다
2. `orig_frame_*.png` — 원작 SPR 원본 프레임({frame_px}px 도트를 {zoom}배 확대).
   픽셀 하나하나가 원작의 결정이다 — 어디에 눈이 있고 어디가 잘렸는지 여기서 읽는다
3. `grid_template.png` — **정확한 캔버스 크기의 빈 격자**({sheet_w}×{sheet_h}).
   마젠타 선 = 셀 경계다. **다 그린 뒤 그 선을 전부 지운다**(흐리게 남겨도 반려)
4. `grid_guide.png` — 행 이름·프레임 수를 적은 **설명 그림. 참고만 한다**(글자를 옮겨 그리지 마라)
5. `subpalette.png` — **이 몬스터가 원작에서 실제로 쓴 색**. 여기서 시작한다:
   `{subpalette_hex}`
6. `../scale_ref.png` — 주인공 시트. 크기의 절대 기준(셀 128 안 아트 높이 96px)
7. `../palette_swatch.png` — 마스터 팔레트 전체(위 색으로 부족할 때만)

## 리마스터 계약 (위반 시 반려)

**바꾸지 않는 것** — 이걸 바꾸면 다른 몬스터가 된다:
- 실루엣의 성격(무엇으로 보이는가), 머리·눈·팔다리의 개수와 배치
- 색 정체성(원작에서 이 몬스터를 알아보게 하는 주된 색). 계열을 옮기지 마라
- 화면에서의 크기감(주인공 대비 비율)

**격상하는 것**:
- 명암 단계 2~3단 → **4~6단** + 색조 그림자(검정 대신 남보라·청록)
- 질감·디테일(금속 이음새, 표면 요철, 발광 처리). 다만 도트의 물성은 유지
- 고유색 원작 20색 안팎 → **24~48색**
- 외곽선 1px 다크 아웃라인(순수 블랙 금지 — 짙은 남색 방향)

**새로 그리는 것**(원작에 없던 행 — 원작 실루엣을 근거로 창작한다):
{new_rows_note}

## 출력 규격 (그리드 계약 — 위반 시 반려)
- 시트: **{sheet_w}×{sheet_h}px PNG** (셀 {cell}px, {cols}열 × {rows}행) — 크기 정확 일치
- 각 행 = 아래 애니메이션, 좌→우가 프레임 순서:

{row_table}

- 프레임 수는 행별로 정확히 — 남는 셀은 **완전 투명**으로 둔다
- 캐릭터는 각 셀 **하단 중앙 정렬**, 실높이 {height_guide}
- **보행은 원작 2프레임의 포즈를 양 끝으로 두고 중간을 채워 4프레임으로 편다**
  (원작에 없던 매끄러움을 만들되 원작 포즈를 버리지 마라)
- 4방향은 같은 개체여야 한다 — 뒷모습(walk_up)에서도 색 배분과 실루엣 폭이 유지된다
- 배경: 완전 투명(alpha=0). 불가 시 **마젠타 #FF00FF 단색**(혼색·반투명·AA 금지)

{tone_block}

{identity}

{negative_rules}

{self_check}
7. 원작 시트와 나란히 놓았을 때 **같은 몬스터로 보이는가?** (가장 중요한 항목이다)

## 납품물
1. 리마스터 시트 PNG 1장 ({sheet_w}×{sheet_h})
2. (선택) 무엇을 계승하고 무엇을 격상했는지 3줄 이내
"""


def sheet_meta(sid: str) -> dict:
    path = os.path.join(SPRITES, f"{sid}_original.json")
    if not os.path.exists(path):
        return {}
    return json.load(io.open(path, encoding="utf-8"))


def copy_original_frames(sid: str, meta: dict, out_dir: str) -> tuple:
    """이관 시트의 source 문자열에서 원작 SPR 프레임 범위를 읽어 확대 복사한다."""
    m = SOURCE_RE.search(str(meta.get("source", "")))
    if not m:
        return 0, 0
    group, first, last = m.group(1).lower(), int(m.group(2)), int(m.group(3))
    src_dir = os.path.join(ORIG_FRAMES, group)
    if not os.path.isdir(src_dir):
        return 0, 0
    n, px = 0, 0
    for idx in range(first, last + 1):
        src = os.path.join(src_dir, "frame_%03d.png" % idx)
        if not os.path.exists(src):
            continue
        im = Image.open(src).convert("RGBA")
        px = max(px, im.width)
        im.resize((im.width * FRAME_ZOOM, im.height * FRAME_ZOOM), Image.NEAREST).save(
            os.path.join(out_dir, "orig_frame_%03d.png" % idx)
        )
        n += 1
    return n, px


def new_rows_note(anims: dict, orig_rows: int) -> str:
    """원작 시트에 없던 행을 골라 안내 문구를 만든다(원작은 walk 4 + idle뿐이었다)."""
    known = {"walk_down", "walk_up", "walk_left", "walk_right", "idle_down"}
    extra = [(n, a) for n, a in anims.items() if n not in known]
    if not extra:
        return "- (없음 — 원작 행 구성 그대로다)"
    lines = []
    for name, a in sorted(extra, key=lambda kv: int(kv[1].get("row", 0))):
        desc = a.get("_desc", "")
        lines.append(
            "- `%s` %d프레임 — %s" % (name, int(a.get("frames", 1)), desc or "원작에 대응 모션이 없다")
        )
    lines.append(
        "  원작 도트의 관절·부위 구성을 그대로 쓰되 동작만 새로 만든다. "
        "다른 몬스터의 어휘(무기·날개 등)를 새로 붙이지 마라"
    )
    return chr(10).join(lines)


def export_one(sp: dict) -> None:
    sid = sp["id"]
    meta = sheet_meta(sid)
    if not meta:
        print(f"!! {sid}: 이관 시트 메타 없음 — 스킵")
        return
    anims = sorted(sp["animations"].items(), key=lambda kv: int(kv[1].get("row", 0)))
    rows = len(anims)
    cols = max(int(a.get("frames", 1)) for _, a in anims)
    sheet_w, sheet_h = cols * CELL, rows * CELL
    out_dir = os.path.join(OUT_ROOT, sid)
    os.makedirs(out_dir, exist_ok=True)

    orig_png = os.path.join(SPRITES, f"{sid}_original.png")
    shutil.copyfile(orig_png, os.path.join(out_dir, f"{sid}_original.png"))
    n_frames, frame_px = copy_original_frames(sid, meta, out_dir)

    row_lines = ["| 행 | 애니 | 프레임 | 내용 |", "|---|---|---|---|"]
    for name, a in anims:
        row_lines.append(
            "| %d | %s | %d프레임 | %s |"
            % (int(a.get("row", 0)), name, int(a.get("frames", 1)), a.get("_desc", ""))
        )

    make_grid_template(
        os.path.join(out_dir, "grid_template.png"), cols, rows, CELL,
        ["%d %s x%d" % (int(a.get("row", 0)), n, int(a.get("frames", 1))) for n, a in anims],
    )
    # 서브팔레트는 **그 몬스터 자신의 색**에서 뽑는다 — 계열 평균을 주면 정체성이 흐려진다.
    sub_hex = make_subpalette(
        dominant_colors([orig_png], 14), os.path.join(out_dir, "subpalette.png")
    )
    height_map = {48: "78~90px (주인공 96px의 80~94% — 소형)",
                  64: "90~106px (주인공 96px의 94~110% — 중형)"}
    prompt = PROMPT_TEMPLATE.format(
        sid=sid,
        name_ko=sp.get("name_ko", sid),
        pattern=sp.get("pattern", ""),
        token=sp.get("token", ""),
        orig_desc=str(meta.get("source", "")).strip(),
        orig_cols=int(meta.get("cols", 2)),
        orig_rows=len(meta.get("animations", {})),
        frame_px=frame_px or 24,
        zoom=FRAME_ZOOM,
        style_bible=style_bible_block(),
        subpalette_hex=sub_hex,
        sheet_w=sheet_w,
        sheet_h=sheet_h,
        cell=CELL,
        cols=cols,
        rows=rows,
        row_table=chr(10).join(row_lines),
        new_rows_note=new_rows_note(sp["animations"], len(meta.get("animations", {}))),
        height_guide=height_map.get(int(sp.get("cell", {}).get("w", 64)), height_map[64]),
        tone_block=tone_block(measure_tone([orig_png]), "이 몬스터의 원작 이관 시트"),
        identity=identity_block([sp.get("token", "")]),
        negative_rules=NEGATIVE_RULES,
        self_check=SELF_CHECK,
    )
    io.open(os.path.join(out_dir, "prompt.md"), "w", encoding="utf-8").write(prompt)
    print(
        "%s: %dx%d (%d행 %d열) prompt.md + 원작 시트 + SPR 프레임 %d장"
        % (sid, sheet_w, sheet_h, rows, cols, n_frames)
    )


def main() -> None:
    os.makedirs(OUT_ROOT, exist_ok=True)
    prepare_workspace()
    make_palette_swatch(os.path.join(OUT_ROOT, "palette_swatch.png"))
    if os.path.exists(SCALE_REF):
        shutil.copyfile(SCALE_REF, os.path.join(OUT_ROOT, "scale_ref.png"))
    removed = dedupe_package_dirs(OUT_ROOT)
    if removed:
        print(f"공용 참조 정리: 패키지 폴더에서 중복 {removed}개 제거")
    targets = set(sys.argv[1:])
    data = json.load(io.open(SPECS, encoding="utf-8"))
    n = 0
    for sp in data["species"]:
        if not str(sp.get("source", "")).startswith("original_"):
            continue
        if targets and sp["id"] not in targets:
            continue
        export_one(sp)
        n += 1
    print(f"done -> {OUT_ROOT} (리마스터 대상 {n}종)")


if __name__ == "__main__":
    main()
