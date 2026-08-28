#!/usr/bin/env python3
"""전투 대형 컷 LLM 의뢰 패키지 생성 — data/battle_cut_specs.json 기준.

## 왜 신설했나 (2026-08-28)

원작(1995)의 전투는 **320×200 전체 화면 프레임 시퀀스**였다 — 격투게임 패러디의
리미티드 애니메이션. 실측으로 남아 있는 원작 프레임:

  주인공 공격 a1(4) a2(4) a3(3) a4(2) a5(1) = 14프레임
  회피·피격  d1(5) d2(2) d3(3) d4(1)       = 11프레임
  적 공격    e1~e8 각 6                     = 48프레임
  투사체     fire(3) · lth(3)
  대형 PCX   attack1~8(14) · def1~7(12) · ready1~2 · 적 등장 4종(m-r·i-v·m_e·v) 30장

리메이크는 이 층이 통째로 빠져 96px 필드 도트만 움직였다(`battle_presenter.gd`).
`04_game_systems.md`가 원작 연출을 이미 기록해 뒀는데도 의뢰 카테고리가 없어서
**의뢰할 방법 자체가 없던** 자리다.

## 이 패키지가 요구하는 것

배우 하나만 그린 **투명 배경 512 셀 시트**다(원작은 검은 화면이었지만 리메이크에는
`battle_backdrop`이 있다). 컷은 공격·피격 순간에만 뜨고 평소엔 기존 전투 화면이 유지된다.

원작 프레임이 화풍·포즈·타이밍의 1차 근거이므로 스펙의 `reference`(SPR 그룹)와
`pcx_refs`(대형 PCX)를 그대로 첨부한다. 공용 참조는 카테고리 루트 `_ref/`·`_pcx/`에 1부.

실행: python tools/convert/export_battle_cut_packages.py [cut_id ...]
"""
from __future__ import annotations

import io
import json
import os
import shutil
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from PIL import Image

from llm_package_common import (
    NEGATIVE_RULES,
    SELF_CHECK,
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
SPECS = os.path.join(ROOT, "data", "battle_cut_specs.json")
OUT_ROOT = os.path.join(ROOT, "assets", "raw", "llm", "battle_cuts")
## 원작 SPR 프레임(전체 화면 320×200)과 PCX 대형 컷의 위치.
ORIG_SPR = os.path.join(ROOT, "assets", "raw", "llm", "00_reference")
ORIG_PCX = os.path.join(ROOT, "assets", "originals_ref", "bmp")
## 주인공 필드 도트 — 얼굴·옷 색의 신원 근거(대형 컷도 같은 인물이어야 한다).
IDENTITY_REF = os.path.join(ROOT, "assets", "sprites", "player_original.png")

PROMPT_TEMPLATE = """# {name_ko}(`{cid}`) 전투 대형 컷 의뢰

{style_bible}

## 역할
너는 1995년 한국 공대 배경 캠퍼스 호러 JRPG의 **전투 연출 원화가**다.
원작의 전투는 전체 화면을 채우는 큰 그림 몇 장으로 동작을 만드는
**리미티드 애니메이션**(격투게임 패러디)이었다. 그 감각을 되살린다.

## 그릴 것
- 컷: {name_ko} (재생 시점: {trigger})
- 컨셉 토큰: {token}
- 프레임: **{frames}장**. 적을수록 각 장이 결정적이어야 한다 —
  중간 동작을 채우지 말고 **키 포즈**만 그린다(원작이 그렇게 했다)

## 입력 (첨부) — 아래 경로의 파일이 첨부물의 전부다(`..` = 카테고리 루트, 공용 1부)
1. `grid_template.png` — **정확한 캔버스 크기의 빈 격자**({sheet_w}×{sheet_h}, 셀 {cell}).
   마젠타 선 = 셀 경계다. **다 그린 뒤 그 선을 전부 지운다**(흐리게 남겨도 반려)
2. `grid_guide.png` — 프레임 순서를 적은 **설명 그림. 참고만 한다**(글자를 옮겨 그리지 마라)
3. `subpalette.png` — 원작 전투 컷에서 실제로 많이 쓰인 색. 아래 hex 안에서 고른다:
   `{subpalette_hex}`
4. `../identity_ref.png` — 주인공 필드 도트. **같은 인물**임을 유지할 근거(머리·옷 색)
5. `../palette_swatch.png` — 마스터 팔레트 전체(위 색으로 부족할 때만 참고)
{orig_refs}

**원작 프레임이 포즈·타이밍의 1차 근거다.** 규칙 문장보다 첨부 그림을 먼저 따른다 —
어느 정도로 몸을 비트는지, 팔이 화면 밖으로 얼마나 나가는지, 몇 장으로 끊는지를 계승한다.

## 출력 규격 (그리드 계약 — 위반 시 반려)
- 시트: **{sheet_w}×{sheet_h}px PNG** (셀 {cell}px, {cols}열 × 1행) — 크기 정확 일치
- 좌 → 우가 재생 순서. 프레임 {frames}장을 정확히 채운다
- **배우 하나만** 그린다. 배경·바닥·효과선 배경은 그리지 않는다 —
  게임이 전투 배경 위에 이 그림을 얹는다. 배경은 **완전 투명**(불가 시 마젠타 #FF00FF 단색)
- 인물은 셀 **하단 중앙 정렬**(발이 셀 아래쪽에 닿는다). 실높이는 셀의 75~90%
- 프레임 간 인물 일관(체형·의상·머리·색) 절대 유지. 포즈만 바뀐다

## 리미티드 애니메이션 규칙
- 부드럽게 이어지는 중간 프레임 대신 **포즈 대비**로 움직임을 만든다
- 속도감은 잔상선·궤적(1~3줄)으로 낸다. 블러 금지 — 선으로 그린다
- 원작처럼 팔·다리가 셀 밖으로 잘려 나가도 좋다(박력이 우선)
- 카메라 각도를 프레임마다 바꾸지 않는다(같은 시점 유지)

{tone_block}

{identity}

{negative_rules}

{self_check}
7. 프레임이 {frames}장인가? 배경에 바닥·풍경을 그리지 않았는가?

## 납품물
1. 컷 시트 PNG 1장 ({sheet_w}×{sheet_h})
2. (선택) 프레임별 의도 3줄 이내
"""


def copy_spr_refs(groups: list) -> tuple:
    """원작 SPR 프레임을 카테고리 루트 `_ref/<그룹>/`에 1부 복사."""
    listed, paths = [], []
    for g in groups:
        src_dir = os.path.join(ORIG_SPR, g)
        if not os.path.isdir(src_dir):
            continue
        frames = sorted(f for f in os.listdir(src_dir) if f.lower().endswith(".png"))
        if not frames:
            continue
        dst_dir = os.path.join(OUT_ROOT, "_ref", g)
        os.makedirs(dst_dir, exist_ok=True)
        for f in frames:
            shutil.copyfile(os.path.join(src_dir, f), os.path.join(dst_dir, f))
            paths.append(os.path.join(dst_dir, f))
        names = " · ".join("`../_ref/%s/%s`" % (g, f) for f in frames)
        listed.append((names, "원작 `%s` 시퀀스 %d프레임 — 포즈·프레임 수의 1차 근거" % (g, len(frames))))
    return listed, paths


def copy_pcx_refs(names: list) -> tuple:
    """원작 PCX 대형 컷(BMP 보관본)을 `_pcx/`에 PNG로 1부 복사."""
    listed, paths = [], []
    dst_dir = os.path.join(OUT_ROOT, "_pcx")
    os.makedirs(dst_dir, exist_ok=True)
    for n in names:
        src = os.path.join(ORIG_PCX, f"{n}.bmp")
        if not os.path.exists(src):
            continue
        dst = os.path.join(dst_dir, f"{n}.png")
        Image.open(src).convert("RGB").save(dst)
        paths.append(dst)
    if paths:
        listed.append((
            " · ".join("`../_pcx/%s`" % os.path.basename(p) for p in paths),
            "원작 대형 컷(320×200 PCX) — 화면을 채우는 크기감·구도의 근거",
        ))
    return listed, paths


def refs_text(listed: list, start: int) -> str:
    return chr(10).join("%d. %s — %s" % (start + i, names, desc) for i, (names, desc) in enumerate(listed))


def export_one(sp: dict) -> None:
    cid = sp["id"]
    cell = int(sp.get("sheet_cell", 512))
    anim: dict = sp["animations"]["play"]
    frames = int(anim.get("frames", 1))
    sheet_w, sheet_h = frames * cell, cell
    out_dir = os.path.join(OUT_ROOT, cid)
    os.makedirs(out_dir, exist_ok=True)

    spr_listed, spr_paths = copy_spr_refs(sp.get("reference", []))
    pcx_listed, pcx_paths = copy_pcx_refs(sp.get("pcx_refs", []))
    make_grid_template(
        os.path.join(out_dir, "grid_template.png"), frames, 1, cell,
        ["play x%d (좌->우 재생)" % frames],
    )
    ref_paths = spr_paths + pcx_paths
    sub_hex = make_subpalette(
        dominant_colors(ref_paths, 14) if ref_paths else [],
        os.path.join(out_dir, "subpalette.png"),
    )
    prompt = PROMPT_TEMPLATE.format(
        cid=cid,
        name_ko=sp.get("name_ko", cid),
        trigger=sp.get("trigger", ""),
        token=sp.get("token", ""),
        frames=frames,
        cell=cell,
        cols=frames,
        sheet_w=sheet_w,
        sheet_h=sheet_h,
        style_bible=style_bible_block(),
        subpalette_hex=sub_hex or "(참조 없음 — 마스터 팔레트에서 고른다)",
        orig_refs=refs_text(spr_listed + pcx_listed, 6),
        tone_block=tone_block(measure_tone(ref_paths), "원작 전투 컷"),
        identity=identity_block([sp.get("token", "")]),
        negative_rules=NEGATIVE_RULES,
        self_check=SELF_CHECK,
    )
    io.open(os.path.join(out_dir, "prompt.md"), "w", encoding="utf-8").write(prompt)
    print(
        "%s: %dx%d (%d프레임) prompt.md + grid 2장 + 원작참조 %d장"
        % (cid, sheet_w, sheet_h, frames, len(ref_paths))
    )


def main() -> None:
    os.makedirs(OUT_ROOT, exist_ok=True)
    prepare_workspace()
    make_palette_swatch(os.path.join(OUT_ROOT, "palette_swatch.png"))
    if os.path.exists(IDENTITY_REF):
        shutil.copyfile(IDENTITY_REF, os.path.join(OUT_ROOT, "identity_ref.png"))
    targets = set(sys.argv[1:])
    data = json.load(io.open(SPECS, encoding="utf-8"))
    for sp in data["species"]:
        if targets and sp["id"] not in targets:
            continue
        export_one(sp)
    print(f"done -> {OUT_ROOT}")


if __name__ == "__main__":
    main()
