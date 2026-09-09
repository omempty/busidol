#!/usr/bin/env python3
"""주인공(부싯돌) 시트 **리터칭/리마스터** 의뢰 패키지 — 원작 도트를 근거로 격상한다.

## 왜 다시 썼나 (2026-09-09)

이 자리에는 `export_player_gen_package.py`가 있었는데 **실행하면 그 자리에서 죽었다**:

    cell = int(spec["cell"])
    TypeError: int() argument must be a string ... not 'dict'

정본 스펙(`assets/spec/sprites/player_sidol.json`)의 `cell`은 `{"w":128,"h":128}` 딕셔너리인데
`int()`에 그대로 넣고 있었다. 즉 **주인공을 의뢰할 경로가 통째로 없었다** — 원작 이관 몬스터
8종이 같은 상태였던 것과 같은 모양이다(그쪽은 `export_monster_remaster_packages.py`가 풀었다).

선언이 세 곳에서 갈라져 있던 것도 함께 정리한다. 정본은 **`player_sidol.json` 하나**다:

| 어디 | 무엇이라 했나 |
|---|---|
| `assets/spec/sprites/player_sidol.json` | 셀 128 · **4열 × 8행** = 512×1024 ← **정본** |
| `assets/gen/prompts/player_retouch_prompt.md` | 2열 × 5행 (128×320 또는 256×640) |
| 옛 `export_player_gen_package.py` 독스트링 | 셀 64 · 256×512 |

## 신규 창작이 아니라 리터칭이다

주인공은 플레이어가 원작에서 본 얼굴이 있다. 그래서 몬스터 리마스터와 **같은 계약**을 쓴다 —
바꾸지 않는 것(신원·실루엣·색 정체성) / 격상하는 것(해상도·명암·질감) / 새로 그리는 것
(원작에 없던 행)을 갈라 준다. 규칙 블록(스타일 바이블·금지 목록·자기 점검·서브팔레트)은
`llm_package_common`의 것을 그대로 쓴다 — 화풍이 카테고리마다 갈라지면 안 된다.

원작에 **없던 것이 무엇인지**가 이 의뢰의 핵심이다(실측):
  · 원작 이관 시트는 `walk_* 2프레임 × 4방향 + idle_down`뿐이다.
  · 그 `idle_down` 행은 `walk_down` 행과 **바이트 단위로 동일**하다 — 아이들이 아니라
    걷기에 이름만 붙인 것이다. 그래서 **진짜 대기 자세는 4방향 전부 새로 그려야 한다.**

실행:
  python tools/convert/export_player_remaster_package.py
  -> assets/raw/llm/sprites/player_sidol/  (prompt.md + 첨부)
"""
from __future__ import annotations

import io
import json
import os
import shutil
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from llm_package_common import (  # noqa: E402
    NEGATIVE_RULES,
    SELF_CHECK,
    dominant_colors,
    identity_block,
    make_grid_guide,
    make_grid_template,
    make_palette_swatch,
    make_subpalette,
    measure_tone,
    style_bible_block,
    tone_block,
)

# 원작 SPR 프레임 확대 복사는 몬스터 리마스터 생성기가 이미 한다 — 같은 규칙을 두 번
# 구현하지 않는다(이 저장소가 반복해 물린 결함이다).
from export_monster_remaster_packages import (  # noqa: E402
    copy_original_frames,
    sheet_meta,
)

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SPEC = os.path.join(ROOT, "assets", "spec", "sprites", "player_sidol.json")
SPRITES = os.path.join(ROOT, "assets", "sprites")
OUT_ROOT = os.path.join(ROOT, "assets", "raw", "llm", "sprites")
ASSET_ID = "player_sidol"
ORIG_ID = "player_original"

## 원작에 대응 그림이 있는 행. 나머지는 "새로 그리는 것"으로 분류된다.
## idle_down이 여기 없는 이유: 원작 시트의 그 행은 walk_down과 바이트 동일이라
## 대기 자세로 쓸 그림이 실제로는 존재하지 않는다(실측).
ORIG_ROWS = {"walk_down", "walk_up", "walk_left", "walk_right"}

PROMPT_TEMPLATE = """# 주인공 부싯돌(`{sid}`) 스프라이트 시트 **리터칭** 의뢰

{style_bible}

## 역할
너는 1995년 DOS RPG 주인공의 원작 도트를 후기 클래식 JRPG 톤으로 격상시키는 픽셀
아티스트다. **신규 창작이 아니다.** 이 캐릭터는 이미 존재하고, 플레이어가 원작에서 본
얼굴이 있다. 원작을 알아볼 수 있어야 하고, 동시에 지금 게임의 다른 그림들과 같은
화풍 안에 있어야 한다.

## 대상
- 이름: 부싯돌(시돌이) — 이 게임의 주인공이자 **화면에 가장 오래 보이는 그림**이다
- 컨셉 토큰: {subject}
- 원작 정보: {orig_desc}

## 입력 (첨부)
1. `{orig_id}.png` — **지금 게임에 들어가 있는 이관 시트**(셀 128, {orig_cols}열 × {orig_rows}행).
   신원·실루엣·색 정체성의 1차 근거다. 이 그림의 인물과 **같은 사람**이어야 한다
2. `orig_frame_*.png` — 원작 SPR 원본 프레임({frame_px}px 도트를 8배 확대).
   픽셀 하나하나가 원작의 결정이다 — 머리 비율·의상 색 배분·발 위치를 여기서 읽는다
3. `grid_template.png` — **정확한 캔버스 크기의 빈 격자**({sheet_w}×{sheet_h}).
   마젠타 선 = 셀 경계다. **다 그린 뒤 그 선을 전부 지운다**(흐리게 남겨도 반려)
4. `grid_guide.png` — 행 이름·프레임 수를 적은 **설명 그림. 참고만 한다**(글자를 옮겨 그리지 마라)
5. `subpalette.png` — **주인공이 원작에서 실제로 쓴 색**. 여기서 시작한다:
   `{subpalette_hex}`
6. `palette_swatch.png` — 마스터 팔레트 전체(위 색으로 부족할 때만)

## 리터칭 계약 (위반 시 반려)

**바꾸지 않는 것** — 이걸 바꾸면 다른 사람이 된다:
- 누구인지 알아보게 하는 것: 머리 모양·의상 구성(잿빛 공대 자켓 + 청바지 + 흰 운동화)
- 색 정체성 — 원작에서 주인공을 알아보게 하는 주된 색. 계열을 옮기지 마라
- 4방향 보행이라는 구성과 각 방향의 실루엣 성격(정면/뒷모습/측면이 서로 구별된다)

**격상하는 것**:
- 원작 24×24 도트 → 셀 128 안에 **실높이 {art_h}px 안팎**. 왜소한 빈 공간을 없애고
  셀을 밀도 있게 채운다(2.5~3등신 SD 체형, 쯔바이!!·나르실리온·악튜러스 계열)
- 명암 2~3단 → **4~6단 계단식 밴딩** + 색조 그림자(검정 대신 남보라 방향)
- 고유색 원작 20색 안팎 → **24~48색**
- 얼굴이 읽히게: 눈매·표정이 128 셀에서 또렷해야 한다(원작에서는 몇 픽셀이었다)

**새로 그리는 것**(원작에 대응 그림이 없다 — 원작 실루엣을 근거로 창작한다):
{new_rows_note}

## 출력 규격 (그리드 계약 — 위반 시 반려)
- 시트: **{sheet_w}×{sheet_h}px PNG** (셀 {cell}px, {cols}열 × {rows}행) — 크기 정확 일치
- 각 행 = 아래 애니메이션, 좌→우가 프레임 순서:

{row_table}

- 프레임 수는 행별로 정확히 — 남는 셀은 **완전 투명**으로 둔다
  (특히 idle 행은 4칸 중 **2칸만** 채우고 나머지 2칸은 비운다)
- 캐릭터는 각 셀 **하단 중앙 정렬**(발이 셀 바닥에서 {foot_pad}px 위)
- **보행 4프레임**: 접지 → 중간(착지) → 도약(다리 교차 최대) → 중간. 원작 2프레임의
  포즈를 양 끝으로 두고 사이를 채운다 — 원작에 없던 매끄러움을 만들되 원작 포즈를 버리지 마라
- **4방향은 같은 사람이어야 한다** — 뒷모습(walk_up)에서도 색 배분과 어깨 폭이 유지된다
- 프레임 사이에 키·머리 크기가 흔들리면 재생 시 떨린다. 바뀌는 것은 자세뿐이다
- 배경: 완전 투명(alpha=0). 불가 시 **마젠타 #FF00FF 단색**(혼색·반투명·AA 금지)

{tone_block}

{identity}

{negative_rules}

{self_check}
7. 원작 시트와 나란히 놓았을 때 **같은 사람으로 보이는가?** (가장 중요한 항목이다)
8. idle 행 4개가 walk 행의 복사본이 아니라 **실제 대기 자세**인가?
   (원작 시트가 정확히 그 결함을 갖고 있다 — 되풀이하면 반려다)

## 납품물
1. 리터칭 시트 PNG 1장 ({sheet_w}×{sheet_h})
2. (선택) 무엇을 계승하고 무엇을 격상했는지 3줄 이내
"""


def _new_rows_note(anims: dict) -> str:
    lines = []
    for name, a in sorted(anims.items(), key=lambda kv: int(kv[1].get("row", 0))):
        if name in ORIG_ROWS:
            continue
        why = (
            "원작 시트의 이 행은 walk_down 복사본이라 대기 그림이 사실상 없다"
            if name == "idle_down"
            else "원작에 대응 모션이 없다"
        )
        lines.append("- `%s` %d프레임 — %s" % (name, int(a.get("frames", 1)), why))
    if not lines:
        return "- (없음)"
    lines.append(
        "  대기는 **서 있는 자세**다 — 걷는 도중 한 컷을 떼어다 쓰지 마라. "
        "두 프레임은 호흡(어깨·가슴 1~2px 상하)만 다르고 발 위치는 같다"
    )
    return chr(10).join(lines)


def main() -> None:
    spec = json.load(io.open(SPEC, encoding="utf-8"))
    cell = int(spec["cell"]["w"])  # 정본의 cell은 {w,h} 딕셔너리다 — 옛 코드가 여기서 죽었다
    cols = int(spec["grid"]["cols"])
    rows = int(spec["grid"]["rows"])
    sheet_w, sheet_h = cols * cell, rows * cell
    anims = spec["animations"]

    out_dir = os.path.join(OUT_ROOT, ASSET_ID)
    os.makedirs(out_dir, exist_ok=True)

    orig_png = os.path.join(SPRITES, f"{ORIG_ID}.png")
    if not os.path.exists(orig_png):
        print(f"[player_remaster] 원판이 없다: {orig_png}")
        sys.exit(1)
    shutil.copyfile(orig_png, os.path.join(out_dir, f"{ORIG_ID}.png"))
    # sheet_meta는 "<sid>_original.json"을 찾는다 — ORIG_ID를 넘기면
    # player_original_original.json을 뒤져 조용히 빈 dict를 돌려준다(원작 프레임 0장).
    meta = sheet_meta("player")
    n_frames, frame_px = copy_original_frames("player", meta, out_dir)
    if n_frames == 0:
        print("[player_remaster] 경고: 원작 SPR 프레임을 못 붙였다 — source=%r"
              % str(meta.get("source", "")))

    labels = [""] * rows
    for name, a in anims.items():
        labels[int(a["row"])] = "%s x%d" % (name, int(a.get("frames", 1)))
    make_grid_template(os.path.join(out_dir, "grid_template.png"), cols, rows, cell, labels)
    make_grid_guide(os.path.join(out_dir, "grid_guide.png"), cols, rows, cell, labels)
    make_palette_swatch(os.path.join(out_dir, "palette_swatch.png"))

    # 서브팔레트는 **주인공 자신의 색**에서 뽑는다 — 계열 평균을 주면 색 정체성이 흐려진다.
    colors = dominant_colors([orig_png], 16)
    sub_hex = make_subpalette(colors, os.path.join(out_dir, "subpalette.png"))
    tone = measure_tone([orig_png])

    # 표 형식은 다른 의뢰 패키지와 같아야 한다 — prompt_audit의 ROW_RE가
    # `| 행 | 이름 | N프레임` 을 찾아 정본과 대조한다. 형식이 다르면 "행 표가 없다"로 잡힌다.
    row_lines = ["| 행 | 애니메이션 | 프레임 수 | 그릴 내용 |", "|---|---|---|---|"]
    for name, a in sorted(anims.items(), key=lambda kv: int(kv[1].get("row", 0))):
        what = "원작 포즈 계승 + 중간 프레임" if name in ORIG_ROWS else "**신규** 대기 자세"
        row_lines.append(
            "| %d | %s | %d프레임 | %sfps · %s |"
            % (int(a["row"]), name, int(a.get("frames", 1)), a.get("fps", "-"), what)
        )

    prompt = PROMPT_TEMPLATE.format(
        sid=ASSET_ID,
        orig_id=ORIG_ID,
        style_bible=style_bible_block(),
        subject=str(spec.get("prompt_vars", {}).get("subject", "")),
        orig_desc=str(meta.get("source", "원작 이관본")),
        orig_cols=int(meta.get("cols", 2)),
        orig_rows=len(meta.get("animations", {})) or 5,
        frame_px=frame_px or 24,
        sheet_w=sheet_w,
        sheet_h=sheet_h,
        cell=cell,
        cols=cols,
        rows=rows,
        art_h=int(cell * 0.78),
        foot_pad=max(int(cell * 0.04), 1),
        row_table=chr(10).join(row_lines),
        new_rows_note=_new_rows_note(anims),
        subpalette_hex=sub_hex,
        tone_block=tone_block(tone, "원작 주인공"),
        identity=identity_block([str(spec.get("prompt_vars", {}).get("subject", ""))]),
        negative_rules=NEGATIVE_RULES,
        self_check=SELF_CHECK,
    )
    io.open(os.path.join(out_dir, "prompt.md"), "w", encoding="utf-8", newline="\n").write(prompt)
    print(
        "[player_remaster] %s: %d×%d (%d행 %d열) · 원작 프레임 %d장(%dpx) · 색 %d개 -> %s"
        % (
            ASSET_ID,
            sheet_w,
            sheet_h,
            rows,
            cols,
            n_frames,
            frame_px,
            len(colors),
            os.path.relpath(out_dir, ROOT).replace("\\", "/"),
        )
    )


if __name__ == "__main__":
    main()
