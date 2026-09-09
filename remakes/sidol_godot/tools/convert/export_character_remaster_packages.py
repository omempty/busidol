#!/usr/bin/env python3
"""원작 이관 **인물 NPC** 리마스터 의뢰 패키지 생성 — 정책 ②원작+격상.

## 왜 별도인가

`export_npc_packages.py`(= `export_monster_packages.py` 재사용)는 `source`가
placeholder인 종만 훑고 프롬프트도 "**신규 창작**이다"로 시작한다. 원작
EVENTER.SPR에서 이관한 인물 7종(rescue_girl·cafeteria_girl·guard_idle·
tutor_dumb·prof_chem·librarian·nothing_man)에는 그 계약이 맞지 않는다 —
이미 그림이 있고, 바꾸면 안 되는 것(신원·실루엣·색 정체성)이 있다.
몬스터 8종이 정확히 그 상태였고(`export_monster_remaster_packages.py`가 열어 준
경로), 인물 7종은 **어떤 스펙에도 등록돼 있지 않아** 의뢰할 근거조차 없었다.

## 이 패키지의 계약 (셋으로 가른다)

- **바꾸지 않는 것** — 신원·실루엣·색 정체성. 이걸 바꾸면 다른 사람이 된다.
- **격상하는 것** — 해상도(24px 도트가 4배 베이크로 96px가 됐다) · 명암 단계 · 질감.
- **새로 그리는 것** — 원작에 없던 행. 원작 시트는 보행 4방향 **2프레임**뿐이고
  `idle_down` 행은 `walk_down` 행의 **바이트 단위 복사본**이다(설치본 실측).
  즉 원작에는 대기 자세가 아예 없었다. 목표 계약(주인공 정본과 같은 결,
  walk 4방향 4프레임 + idle 4방향 2프레임)이 요구하는 나머지는 창작이다.

무엇이 "새로 그리는 것"인지는 **문장으로 박지 않고 매번 실측한다**:
설치된 `<id>_original.png`의 행을 서로 비교해 복사본 행을 찾아내고,
스펙의 목표 행/프레임과 설치본의 행/프레임을 대조해 신설·확장 목록을 만든다.
아트가 교체되면 의뢰문도 따라 바뀐다(문서가 낡지 않는다).

첨부의 핵심은 **그 인물 자신의 원작 그림 두 벌**이다: `<id>_original.png`
(게임에 들어가 있는 128 격자 이관 시트)와 원작 SPR 원본 프레임
(`00_reference/eventer/frame_NNN.png`, 24px 도트). 서브팔레트도 그 인물 자신의
색에서 뽑는다 — 계열 평균을 주면 색 정체성이 가장 먼저 깨진다(몬스터와 같은 근거).

원작 참조는 **적 일러스트가 아니라 인물 초상**이다(`llm_package_common`의
`ORIGINAL_REFS["npcs"]`). 사람에게 적 그림을 주면 괴물처럼 그려 온다.

실행: python tools/convert/export_character_remaster_packages.py [npc_id ...]
"""
from __future__ import annotations

import io
import json
import os
import shutil
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import numpy as np
from PIL import Image

from llm_package_common import (
    NEGATIVE_RULES,
    SELF_CHECK,
    copy_original_refs,
    dedupe_package_dirs,
    dominant_colors,
    identity_block,
    make_grid_template,
    make_palette_swatch,
    make_subpalette,
    measure_tone,
    prepare_workspace,
    refs_block,
    style_bible_block,
    tone_block,
)

## 원작 SPR 프레임 범위 파싱·확대 복사는 몬스터 리마스터가 이미 정본으로 갖고 있다.
## 같은 규칙(`<GROUP>.SPR frames NNN-NNN` → 00_reference/<group>/frame_NNN.png)을
## 여기 두 번째로 적으면 한쪽만 고쳐져 갈라진다 — 가져다 쓴다.
from export_monster_remaster_packages import (  # noqa: E402
    FRAME_ZOOM,
    copy_original_frames,
    sheet_meta,
)

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SPECS = os.path.join(ROOT, "data", "npc_anim_specs.json")
## 카테고리는 npcs 그대로다 — 심사 서버·설치기·prompt_audit이 스펙 파일로 카테고리를
## 정하므로(intake.SPEC→CAT), 리마스터라고 새 폴더를 파면 그 흐름에서 떨어져 나간다.
OUT_ROOT = os.path.join(ROOT, "assets", "raw", "llm", "npcs")
REF_CATEGORY = "npcs"
SPRITES = os.path.join(ROOT, "assets", "sprites")
SCALE_REF = os.path.join(SPRITES, "player_original.png")
CELL = 128
## 주인공 아트 실높이(셀 128 안, player_original.png 실측). 모든 크기 지시의 기준선.
PLAYER_ART_H = 96
## 이 값으로 시작하는 source = 원작 이관본. 몬스터 스펙의 original_i_spr /
## original_e_spr 와 같은 규약이다(리마스터 대상 선별의 유일한 근거).
ORIGINAL_MARK = "original_"

PROMPT_TEMPLATE = """# {name_ko}(`{sid}`) 인물 NPC 시트 **리마스터** 의뢰

{style_bible}

## 역할
너는 1995년 DOS RPG의 원작 인물 도트를 현대 JRPG 톤으로 격상시키는 픽셀 아티스트다.
**신규 창작이 아니다.** 이 인물은 이미 존재하고, 플레이어가 원작에서 본 얼굴이 있다.
그리고 **사람이다** — 괴물·마스코트가 아니라 1995년 한국 공대 캠퍼스에 있는 인물이다.

## 대상
- 이름: {name_ko} (게임 안 역할: {pattern})
- 신원 토큰: {token}
- 원작 정보: {orig_desc}
- 원작 시트가 가진 것: **보행 4방향 × {orig_frames}프레임 + idle_down 1행**이 전부다{dup_note}
{conflict_note}{shared_note}
## 입력 (첨부) — 아래 경로의 파일이 첨부물의 전부다(`..` = 카테고리 루트, 공용 1부)
1. `{sid}_original.png` — **지금 게임에 들어가 있는 이관 시트**(셀 128, {orig_cols}열 × {orig_rows}행).
   신원·실루엣·색 정체성의 1차 근거다. 이 그림의 인물과 **같은 사람**이어야 한다
2. `orig_frame_*.png` — 원작 SPR 원본 프레임({frame_px}px 도트를 {zoom}배 확대).
   픽셀 하나하나가 원작의 결정이다 — 어디에 눈이 있고 무엇을 들고 있는지 여기서 읽는다
3. `grid_template.png` — **정확한 캔버스 크기의 빈 격자**({sheet_w}×{sheet_h}).
   마젠타 선 = 셀 경계다. **다 그린 뒤 그 선을 전부 지운다**(흐리게 남겨도 반려)
4. `grid_guide.png` — 행 이름·프레임 수를 적은 **설명 그림. 참고만 한다**(글자를 옮겨 그리지 마라)
5. `subpalette.png` — **이 인물이 원작에서 실제로 쓴 색**. 여기서 시작한다:
   `{subpalette_hex}`
6. `../scale_ref.png` — 주인공 시트. 크기의 절대 기준(셀 128 안 아트 높이 {player_h}px)
7. `../palette_swatch.png` — 마스터 팔레트 전체(위 색으로 부족할 때만)
{orig_refs}

## 리마스터 계약 (위반 시 반려)

**바꾸지 않는 것** — 이걸 바꾸면 다른 사람이 된다:
- 신원 표지: 복장·머리 모양과 색·소품·연령대·체형. 첨부 시트에서 읽어 그대로 계승한다
- 실루엣의 성격(무엇을 입고 무엇을 들었는가), 머리·팔다리의 배치
- 색 정체성(원작에서 이 인물을 알아보게 하는 주된 색). 계열을 옮기지 마라
- 화면에서의 크기감(주인공 대비 비율)

**격상하는 것**:
- 명암 단계 2~3단 → **4~6단** + 색조 그림자(검정 대신 남보라·청록)
- 옷 주름·머리카락 결·소품의 재질 등 디테일. 다만 도트의 물성은 유지
- 고유색 원작 20색 안팎 → **24~48색**
- 외곽선 1px 다크 아웃라인(순수 블랙 금지 — 짙은 남색 방향)
- 원작 도트는 24px 원본을 4배로 키운 것이라 **계단이 4px 단위로 뭉쳐 있다**.
  그 뭉침을 1px 단위로 다시 깎아 형태를 또렷하게 만드는 것이 이 의뢰의 핵심이다

**새로 그리는 것**(원작에 없던 것 — 원작 실루엣·복장을 근거로 창작한다):
{new_rows_note}

## 출력 규격 (그리드 계약 — 위반 시 반려)
- 시트: **{sheet_w}×{sheet_h}px PNG** (셀 {cell}px, {cols}열 × {rows}행) — 크기 정확 일치
- 각 행 = 아래 애니메이션, 좌→우가 프레임 순서:

{row_table}

- 프레임 수는 행별로 정확히 — 남는 셀은 **완전 투명**으로 둔다
- 캐릭터는 각 셀 **하단 중앙 정렬**, 실높이 {height_guide}
- **보행은 원작 {orig_frames}프레임의 포즈를 양 끝으로 두고 중간을 채워 {walk_frames}프레임으로 편다**
  (원작에 없던 매끄러움을 만들되 원작 포즈를 버리지 마라)
- 4방향은 같은 사람이어야 한다 — 뒷모습(walk_up)에서도 색 배분과 실루엣 폭이 유지된다
- 배경: 완전 투명(alpha=0). 불가 시 **마젠타 #FF00FF 단색**(혼색·반투명·AA 금지)

{tone_block}

{identity}

{negative_rules}

{self_check}
7. 원작 시트와 나란히 놓았을 때 **같은 사람으로 보이는가?** (가장 중요한 항목이다)
8. idle 4행이 walk 행의 **복사본이 아닌가?** (원작이 그랬다 — 그걸 되풀이하면 반려다)

## 납품물
1. 리마스터 시트 PNG 1장 ({sheet_w}×{sheet_h})
2. (선택) 무엇을 계승하고 무엇을 격상했는지 3줄 이내
"""


def cell_rows(png_path: str, meta: dict) -> dict:
    """설치 시트를 행 단위 배열로 쪼갠다 — {애니 이름: ndarray}.

    행이 진짜 다른 그림인지 **재서** 판단하기 위한 것이다. 원작 이관 시트는
    idle 행을 walk 행에서 복제해 만들었고(migrate_original_sheets.ROWS),
    그 사실을 의뢰문에 손으로 적어 두면 아트가 바뀌어도 문장만 남는다.
    """
    try:
        arr = np.asarray(Image.open(png_path).convert("RGBA"))
    except Exception:  # noqa: BLE001 — 시트 한 장이 깨져도 나머지 의뢰는 나가야 한다
        return {}
    out = {}
    for name, a in meta.get("animations", {}).items():
        r = int(a.get("row", 0))
        y0, y1 = r * CELL, (r + 1) * CELL
        if y1 <= arr.shape[0]:
            out[name] = arr[y0:y1]
    return out


def duplicate_rows(rows: dict, meta: dict) -> dict:
    """{복사본 행: 원본 행} — 픽셀 단위로 같은 행 쌍을 찾는다.

    **행 번호 순으로** 훑어야 한다. 이름 순으로 훑었더니 idle_down(행 4)이 먼저 와서
    walk_down(행 0)이 "idle_down의 복사본"으로 뒤집혀 나왔다(첫 판 실측). 시트를 만든
    쪽(migrate_original_sheets.ROWS)이 앞 행을 뒤 행으로 복제했으므로 **앞 행이 원본**이다.
    """
    dup, seen = {}, {}
    order = sorted(rows, key=lambda n: int(meta.get("animations", {}).get(n, {}).get("row", 0)))
    for name in order:
        blob = rows[name].tobytes()
        if blob in seen:
            dup[name] = seen[blob]
        else:
            seen[blob] = name
    return dup


def art_height(png_path: str) -> int:
    """셀 (0,0)에 그려진 아트의 실높이(px). 크기 계약의 유일한 근거다."""
    try:
        arr = np.asarray(Image.open(png_path).convert("RGBA"))[0:CELL, 0:CELL]
    except Exception:  # noqa: BLE001
        return 0
    ys = np.nonzero(arr[:, :, 3] > 0)[0]
    return int(ys.max() - ys.min() + 1) if ys.size else 0


def shared_art_ids(sid: str, all_ids: list) -> list:
    """같은 원작 그림을 쓰는 다른 종 — 이관이 EVENTER.SPR 블록을 2명씩 공유했다.

    의뢰문에 이 사실을 적지 않으면 두 인물이 **똑같은 리마스터**로 돌아온다
    (원작에서는 tint로만 갈랐다). 파일을 실제로 비교해 찾는다.
    """
    def digest(i: str) -> bytes:
        p = os.path.join(SPRITES, f"{i}_original.png")
        return open(p, "rb").read() if os.path.exists(p) else b""

    mine = digest(sid)
    if not mine:
        return []
    return [i for i in all_ids if i != sid and digest(i) == mine]


def new_rows_note(target: dict, installed: dict, dup: dict) -> str:
    """목표 계약 - 설치본 = 새로 그려야 하는 것. 전부 실측에서 나온다."""
    lines = []
    for name, a in sorted(target.items(), key=lambda kv: int(kv[1].get("row", 0))):
        frames = int(a.get("frames", 1))
        desc = a.get("_desc", "")
        have = installed.get(name)
        if have is None:
            lines.append("- `%s` %d프레임 — **원작에 대응 행이 없다.** %s"
                         % (name, frames, desc or "원작 실루엣·복장을 근거로 새로 만든다"))
        elif name in dup:
            lines.append(
                "- `%s` %d프레임 — 설치본에 같은 이름의 행이 있지만 **`%s` 행의 픽셀 단위 복사본이다**"
                "(실측). 원작에는 대기 자세가 없었다는 뜻이므로 **진짜 대기 자세를 새로 그린다**. %s"
                % (name, frames, dup[name], desc or "보행 포즈를 그대로 쓰면 반려다"))
        elif frames > int(have.get("frames", 1)):
            lines.append("- `%s` — 원작 %d프레임을 **%d프레임으로 편다**(중간 포즈 신규). %s"
                         % (name, int(have.get("frames", 1)), frames, desc or ""))
    lines.append("  원작 도트의 복장·소품·머리 모양을 그대로 쓰되 **자세만** 새로 만든다. "
                 "다른 인물의 어휘(안경·가방·무기 등)를 새로 붙이지 마라")
    return chr(10).join(lines)


def export_one(sp: dict, all_ids: list, orig_refs: str) -> None:
    sid = sp["id"]
    meta = sheet_meta(sid)
    if not meta:
        print(f"!! {sid}: 이관 시트 메타 없음 — 스킵")
        return
    orig_png = os.path.join(SPRITES, f"{sid}_original.png")
    if not os.path.exists(orig_png):
        print(f"!! {sid}: {sid}_original.png 없음 — 스킵")
        return

    anims = sorted(sp["animations"].items(), key=lambda kv: int(kv[1].get("row", 0)))
    rows = len(anims)
    cols = max(int(a.get("frames", 1)) for _, a in anims)
    sheet_w, sheet_h = cols * CELL, rows * CELL
    out_dir = os.path.join(OUT_ROOT, sid)
    os.makedirs(out_dir, exist_ok=True)

    shutil.copyfile(orig_png, os.path.join(out_dir, f"{sid}_original.png"))
    n_frames, frame_px = copy_original_frames(sid, meta, out_dir)

    installed = meta.get("animations", {})
    dup = duplicate_rows(cell_rows(orig_png, meta), meta)
    shared = shared_art_ids(sid, all_ids)
    art_h = art_height(orig_png)

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
    # 서브팔레트는 **그 인물 자신의 색**에서 뽑는다 — 계열 평균을 주면 정체성이 흐려진다.
    sub_hex = make_subpalette(
        dominant_colors([orig_png], 14), os.path.join(out_dir, "subpalette.png")
    )

    orig_walk = int(installed.get("walk_down", {}).get("frames", 2))
    walk_frames = int(sp["animations"].get("walk_down", {}).get("frames", cols))
    dup_note = ""
    if dup:
        dup_note = " — 그나마 " + " · ".join(
            "`%s` 행은 `%s` 행의 픽셀 단위 복사본이다" % (k, v)
            for k, v in sorted(dup.items())) + "(실측)"
    # 스펙이 "이 그림과 이 역할이 서로 안 맞는다"고 적어 둔 항목은 **의뢰문 맨 앞에 세운다**.
    # 조용히 넘기면 그림 LLM은 둘 중 아무거나 골라 그리고, 사람은 납품을 보고서야 안다.
    conflict = str(sp.get("_art_conflict", "")).strip()
    conflict_note = ""
    if conflict:
        conflict_note = (
            "- **미결 항목(그리기 전에 읽어라)**: %s\n"
            "  → 지시가 확정되기 전이라면 **첨부 시트의 형상을 그대로 계승**하고 "
            "격상(해상도·명암·질감)만 한다. 임의로 사람으로 바꾸지 마라.\n" % conflict)
    shared_note = ""
    if shared:
        shared_note = (
            "- **주의**: 원작 이관은 EVENTER.SPR의 같은 블록을 두 인물이 나눠 썼다. "
            "첨부 시트는 `%s`와 **바이트 단위로 같은 그림**이다. 원작에서는 색조(tint)로만 갈랐으니, "
            "리마스터에서는 위 신원 토큰이 가리키는 **이 인물 쪽**으로 그린다 "
            "— 다른 쪽과 같은 그림을 내면 두 NPC가 다시 한 사람이 된다.\n"
            % " · ".join(shared))

    pct = round(art_h * 100.0 / PLAYER_ART_H) if art_h else 0
    height_guide = (
        "**%dpx 안팎(±4px)** — 원작 이관 시트 실측 %dpx, 주인공 %dpx의 %d%%. "
        "성인/학생 인물이라 주인공과 눈높이가 비슷해야 한다"
        % (art_h, art_h, PLAYER_ART_H, pct)
    ) if art_h else "주인공(%dpx)과 비슷하게" % PLAYER_ART_H

    prompt = PROMPT_TEMPLATE.format(
        sid=sid,
        name_ko=sp.get("name_ko", sid),
        pattern=sp.get("pattern", ""),
        token=sp.get("token", ""),
        orig_desc=str(meta.get("source", "")).strip(),
        orig_cols=int(meta.get("cols", 2)),
        orig_rows=len(installed),
        orig_frames=orig_walk,
        walk_frames=walk_frames,
        dup_note=dup_note,
        conflict_note=conflict_note,
        shared_note=shared_note,
        frame_px=frame_px or 24,
        zoom=FRAME_ZOOM,
        player_h=PLAYER_ART_H,
        style_bible=style_bible_block(),
        subpalette_hex=sub_hex,
        orig_refs=orig_refs,
        sheet_w=sheet_w,
        sheet_h=sheet_h,
        cell=CELL,
        cols=cols,
        rows=rows,
        row_table=chr(10).join(row_lines),
        new_rows_note=new_rows_note(sp["animations"], installed, dup),
        height_guide=height_guide,
        tone_block=tone_block(measure_tone([orig_png]), "이 인물의 원작 이관 시트"),
        identity=identity_block([sp.get("token", "")]),
        negative_rules=NEGATIVE_RULES,
        self_check=SELF_CHECK,
    )
    io.open(os.path.join(out_dir, "prompt.md"), "w", encoding="utf-8").write(prompt)
    print(
        "%s: %dx%d (%d행 %d열) prompt.md + 원작 시트 + SPR 프레임 %d장 · 아트 %dpx"
        " · 새로 그릴 행 %d · 복사본 행 %d%s"
        % (sid, sheet_w, sheet_h, rows, cols, n_frames, art_h,
           len([n for n in sp["animations"] if n not in installed]), len(dup),
           (" · 그림 공유 " + ",".join(shared)) if shared else "")
    )


def main() -> None:
    os.makedirs(OUT_ROOT, exist_ok=True)
    prepare_workspace()
    make_palette_swatch(os.path.join(OUT_ROOT, "palette_swatch.png"))
    if os.path.exists(SCALE_REF):
        shutil.copyfile(SCALE_REF, os.path.join(OUT_ROOT, "scale_ref.png"))
    # 원작 참조는 **인물 초상**이다(적 일러스트를 주면 사람을 괴물로 그려 온다).
    # 카테고리 루트에 1부만 두고 프롬프트가 `../`로 가리킨다.
    listed = copy_original_refs(REF_CATEGORY, OUT_ROOT, prefix="../")
    orig_refs = refs_block(listed, 8)
    removed = dedupe_package_dirs(OUT_ROOT)
    if removed:
        print(f"공용 참조 정리: 패키지 폴더에서 중복 {removed}개 제거")

    data = json.load(io.open(SPECS, encoding="utf-8"))
    species = data["species"]
    original_ids = [s["id"] for s in species
                    if str(s.get("source", "")).startswith(ORIGINAL_MARK)]
    targets = set(sys.argv[1:])
    n = 0
    for sp in species:
        if sp["id"] not in original_ids:
            continue
        if targets and sp["id"] not in targets:
            continue
        export_one(sp, original_ids, orig_refs)
        n += 1
    print(f"done -> {OUT_ROOT} (리마스터 대상 {n}종 / 원작 이관 {len(original_ids)}종)")


if __name__ == "__main__":
    main()
