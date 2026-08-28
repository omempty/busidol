#!/usr/bin/env python3
"""전투 이펙트 시트 LLM 의뢰 패키지 생성 — data/effect_specs.json 기준.

## 왜 신설했나 (2026-08-28)

전투 연출에 **그림 에셋이 한 장도 없었다.** `battle_presenter.gd`의 fx 채널은
`CPUParticles2D`로 만든 점 스파크(`hit_spark`) 하나뿐이라 물리 타격·화염 비커·
10,000V 아크가 전부 같은 흰 불꽃으로 떴다. 의뢰 카테고리 목록(monsters/items/
npcs/portraits/keyart)에 이펙트가 아예 없어서 "의뢰할 방법조차" 없던 자리다.

원작 참조는 이미 저장소에 들어와 있다 — `assets/raw/llm/00_reference/`의
`effect`·`fire`·`mboom`·`rboom`·`ping1` 프레임(원작 SPR 추출본). 그 그림들이
화풍의 1차 근거이므로 스펙의 `reference` 목록대로 첨부한다.

시트 규격은 몬스터와 같은 128 셀 그리드다(같은 검증기·같은 설치 경로를 쓴다).
다른 점은 정렬: 이펙트는 발이 없으므로 **셀 중앙 정렬**이다(spec.align="center").

실행: python tools/convert/export_effect_packages.py [effect_id ...]
"""
from __future__ import annotations

import io
import json
import os
import shutil
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

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
SPECS = os.path.join(ROOT, "data", "effect_specs.json")
OUT_ROOT = os.path.join(ROOT, "assets", "raw", "llm", "effects")
## 원작 이펙트 프레임 — SPR 추출본. 폴더 이름이 곧 원작의 이펙트 이름이다.
ORIG_FX = os.path.join(ROOT, "assets", "raw", "llm", "00_reference")
CELL = 128
## 한 참조 폴더에서 첨부할 최대 프레임 수 — 시작·중간·끝을 고르게 뽑는다.
REF_FRAMES = 3

ELEMENT_HINT = {
    "physical": "노랑→주황→흰 코어. 차가운 색 금지",
    "fire": "흰-노랑 코어 / 주황 / 진홍 3단. 검은 연기 대신 남보라 연기",
    "electric": "흰 코어 + 하늘색 2단. 곡선 금지 — 전기는 꺾인다",
    "none": "무속성 — 대상 묘사에 맞는 색을 스왑치에서 고른다",
}

PROMPT_TEMPLATE = """# {name_ko}(`{eid}`) 전투 이펙트 시트 생성 의뢰

{style_bible}

## 역할
너는 1995년 한국 공대 배경 캠퍼스 호러 JRPG의 **전투 이펙트** 도트 애니메이터다.
캐릭터가 아니라 **현상**을 그린다 — 타격·폭발·방전처럼 몇 프레임 만에 나타났다 사라지는 그림.

## 이펙트
- 이름: {name_ko} (속성: {element} — {element_hint})
- 컨셉 토큰: {token}

## 입력 (첨부) — 아래 경로의 파일이 첨부물의 전부다(`..` = 카테고리 루트, 공용 1부)
1. `grid_template.png` — **정확한 캔버스 크기의 빈 격자**({sheet_w}×{sheet_h}).
   가능하면 **이 이미지를 열어 그 위에 그린다.** 마젠타 선 = 셀 경계다.
   **다 그린 뒤 그 선을 전부 지운다** — 흐리게 남기는 것도 반려(자동 검출된다)
2. `grid_guide.png` — 프레임 순서를 적은 **설명 그림. 참고만 한다**(글자를 옮겨 그리지 마라)
3. `subpalette.png` — 원작 이펙트에서 실제로 많이 쓰인 색. 아래 hex 안에서 고른다:
   `{subpalette_hex}`
4. `../palette_swatch.png` — 마스터 팔레트 전체(위 색으로 부족할 때만 참고)
{orig_refs}

**원작 이펙트 그림이 화풍의 1차 근거다.** 규칙 문장보다 첨부 그림을 먼저 따른다 —
불꽃·파편의 굵기, 색 단계 수, 프레임 간 형태 변화의 폭을 계승한다.

## 출력 규격 (그리드 계약 — 위반 시 반려)
- 시트: **{sheet_w}×{sheet_h}px PNG** (셀 {cell}px, {cols}열 × {rows}행) — 크기 정확 일치
- 1행 = 재생 순서. 좌 → 우로 {frames}프레임, 마지막 프레임은 거의 사라진 상태
- 각 프레임은 셀 **중앙 정렬**(캐릭터가 아니므로 하단 정렬이 아니다)
- 프레임 간 변화가 실제로 보여야 한다 — 같은 그림을 조금 옮긴 수준이면 반려
- 배경: 완전 투명(alpha=0). 불가 시 **마젠타 #FF00FF 단색**(혼색·반투명·AA 금지)

## 이펙트 전용 규칙
- 게임에서 캐릭터 **위에 겹쳐 뜬다**: 화면을 꽉 채우지 말고 중심에서 퍼지는 형태로
- 글로우·블러로 밝기를 내지 말고 **밝은 색을 실제로 찍어** 낸다(밴딩 3~4단)
- 반투명으로 페이드아웃하지 않는다 — 면적이 줄고 색이 빠지며 사라진다
- 좌우 대칭을 피한다(대칭이면 프레임 변화가 눈에 안 띈다)

{tone_block}

{identity}

{negative_rules}

{self_check}
7. 프레임 수가 {frames}개 맞는가? 남는 셀은 완전 투명인가?

## 납품물
1. 이펙트 시트 PNG 1장 ({sheet_w}×{sheet_h})
2. (선택) 프레임별 의도 3줄 이내
"""


def ref_frames(folder: str) -> list:
    """원작 참조 폴더에서 프레임을 고르게 REF_FRAMES장 뽑는다."""
    d = os.path.join(ORIG_FX, folder)
    if not os.path.isdir(d):
        return []
    files = sorted(f for f in os.listdir(d) if f.lower().endswith(".png"))
    if not files:
        return []
    if len(files) <= REF_FRAMES:
        return [os.path.join(d, f) for f in files]
    step = (len(files) - 1) / float(REF_FRAMES - 1)
    idx = sorted({int(round(i * step)) for i in range(REF_FRAMES)})
    return [os.path.join(d, files[i]) for i in idx]


def copy_refs(sp: dict) -> tuple:
    """참조 프레임을 카테고리 루트 `_ref/<폴더>/`에 1부 복사. 반환 (프롬프트 목록, 경로들)."""
    listed, paths = [], []
    for folder in sp.get("reference", []):
        frames = ref_frames(folder)
        if not frames:
            continue
        dst_dir = os.path.join(OUT_ROOT, "_ref", folder)
        os.makedirs(dst_dir, exist_ok=True)
        for src in frames:
            dst = os.path.join(dst_dir, os.path.basename(src))
            shutil.copyfile(src, dst)
            paths.append(dst)
        names = " · ".join(f"`../_ref/{folder}/{os.path.basename(p)}`" for p in frames)
        listed.append((folder, names, len(frames)))
    return listed, paths


def refs_text(listed: list, start: int) -> str:
    lines = []
    for i, (folder, names, n) in enumerate(listed):
        lines.append(f"{start + i}. {names} — 원작 이펙트 `{folder}` 프레임 {n}장(화풍의 1차 근거)")
    return chr(10).join(lines)


def export_one(sp: dict) -> None:
    eid = sp["id"]
    anims = sorted(sp["animations"].items(), key=lambda kv: int(kv[1].get("row", 0)))
    rows = len(anims)
    cols = max(int(a.get("frames", 1)) for _, a in anims)
    sheet_w, sheet_h = cols * CELL, rows * CELL
    out_dir = os.path.join(OUT_ROOT, eid)
    os.makedirs(out_dir, exist_ok=True)

    listed, ref_paths = copy_refs(sp)
    labels = [f"{n} x{int(a.get('frames', 1))} (좌->우 재생)" for n, a in anims]
    make_grid_template(os.path.join(out_dir, "grid_template.png"), cols, rows, CELL, labels)
    sub_hex = make_subpalette(
        dominant_colors(ref_paths, 12) if ref_paths else [],
        os.path.join(out_dir, "subpalette.png"),
    )
    frames = int(anims[0][1].get("frames", 1))
    prompt = PROMPT_TEMPLATE.format(
        eid=eid,
        name_ko=sp.get("name_ko", eid),
        element=sp.get("element", "none"),
        element_hint=ELEMENT_HINT.get(str(sp.get("element", "none")), ELEMENT_HINT["none"]),
        token=sp.get("token", ""),
        style_bible=style_bible_block(),
        orig_refs=refs_text(listed, 5),
        subpalette_hex=sub_hex or "(참조 없음 — 마스터 팔레트에서 고른다)",
        sheet_w=sheet_w,
        sheet_h=sheet_h,
        cell=CELL,
        cols=cols,
        rows=rows,
        frames=frames,
        tone_block=tone_block(measure_tone(ref_paths), "원작 이펙트 프레임"),
        identity=identity_block([sp.get("token", "")]),
        negative_rules=NEGATIVE_RULES,
        self_check=SELF_CHECK,
    )
    io.open(os.path.join(out_dir, "prompt.md"), "w", encoding="utf-8").write(prompt)
    print(f"{eid}: {sheet_w}x{sheet_h} ({rows}행 {cols}열) prompt.md + grid 2장 + 원작참조 {len(ref_paths)}장")


def main() -> None:
    os.makedirs(OUT_ROOT, exist_ok=True)
    prepare_workspace()
    make_palette_swatch(os.path.join(OUT_ROOT, "palette_swatch.png"))
    targets = set(sys.argv[1:])
    data = json.load(io.open(SPECS, encoding="utf-8"))
    for sp in data["species"]:
        if targets and sp["id"] not in targets:
            continue
        export_one(sp)
    print(f"done -> {OUT_ROOT}")


if __name__ == "__main__":
    main()
