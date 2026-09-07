"""원작 도트 → 표준 스프라이트 시트 일괄 이관 (정책 ①원작 있음→리마스터).

**알파의 유일한 근거는 팔레트 인덱스 0이다** — 원작 SPR을 직접 읽어(parse_spr)
인덱스 0만 투명으로 방출한 프레임을 받고, 4배 nearest 베이크 → 표준 셀 128(2열×5행)
시트 + 메타 JSON을 assets/sprites/<id>_original.png|.json 으로 출력한다.
SpriteSets 컨벤션(<id>_original.*)에 따라 게임이 즉시 인식하며,
아트모드 REMAKE 신규 시트 미착용 시 폴백 세트로도 동작한다.

## 왜 bmp_spr을 더 이상 읽지 않는가 (2026-09-07 실측)

이 도구는 원래 `originals_ref/bmp_spr/<group>/frame_*.bmp`(알파 없는 RGB 중간물)를
읽고 `extract_sprites.remove_bg_np`(테두리 연결 flood-fill)로 배경을 지웠다.
그런데 **원작 팔레트에는 RGB(0,0,0)인 인덱스가 9개**다 — 투명 키인 0과, 캐릭터
외곽선·그림자로 쓰이는 224~231. 팔레트가 사라진 RGB 위에서는 이 둘을 구별할 수
없어서 flood-fill이 배경에 닿은 **외곽선을 통째로 먹었고**, 반대로 스프라이트에
둘러싸인 배경(인덱스 0)은 flood-fill이 못 닿아 **검은 얼룩으로 남았다**.

실측(현행 시트 vs 원작 SPR 진실값, 알파 마스크 비교):

    id             잃은 외곽선px   남은 배경px
    mad_eye            14,688           320
    o_ray              23,296         1,536
    tutor_dumb          4,320             0   ← 유저 신고 "멍청조교"
    hellcop                 0           448
    (14종 합계)       150,326         4,404

tutor_dumb가 잃은 4,320px는 **전부 정확히 RGB(0,0,0)** 이었다.
같은 결함이 `tools/dev/key_color0_transparent.py`(RGB 순검정 일괄 키잉)와
`tools/convert/migrate_item_icons.py`에도 있었다. 규칙 하나로 정리한다:
**팔레트 인덱스를 잃은 뒤에 RGB만 보고 투명을 정하지 않는다.**

레이아웃(원작 mode 0~7 규약 = 아래/위/좌/우 × 2프레임, docs/01_analysis/04_game_systems.md §1.1):
  행0 walk_down=[0,1] · 행1 walk_up=[2,3] · 행2 walk_left=[4,5] · 행3 walk_right=[6,7]
  행4 idle_down=[0,1] 복제(원작에 idle 전용 프레임 없음)

매핑 근거:
  - I.SPR 블록 1~8 = 필드 몬스터 8종 — 원본 GOODITEM.C `eye[i].mode = 8*(i%8+1)` +
    docs/04_scenario/02_story_bible.md "필드 몬스터 8종"
    (Mad Eye·Vulgar·DWorm·Ozzy·Iron-Voc·HellCop·O-Ray·Sparker)
  - EVENTER.SPR 블록 0~4 = 이벤트 NPC 5인 — 원본 GOODITEM.C `eve_spt`
    (여학생·경비·조교·교수·유령). 여학생/유령 블록은 2명씩 공유하며
    npcs_f*.json의 tint로 변별한다.

실행: python tools/convert/migrate_original_sheets.py [id ...]  (인자 없으면 전체)
"""
from __future__ import annotations
import io
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.normpath(os.path.join(ROOT, "..", "..", "_shared", "src")))
sys.path.insert(0, os.path.join(ROOT, "tools", "dev"))
from spr_extract import parse_spr  # noqa: E402  (알파의 유일한 근거 = 팔레트 인덱스 0)

ORIGINALS = os.path.normpath(os.path.join(ROOT, "..", "..", "originals", "1995_sidol_bsd_dos"))
OUT_DIR = os.path.join(ROOT, "assets", "sprites")
CELL = 128
BAKE = 4  # 원작 24px 도트 → 96px (player_original과 동일 레시피)
COLS = 2
SCALE = 0.6667  # 실효 96px×⅔ = 64px = 타일 2배 (player_original 규약)

# id → (원작 그룹, 시작 프레임 인덱스) — 8프레임 블록
SOURCES: dict[str, tuple[str, int]] = {
    # 필드 몬스터 8종 (I.SPR 블록 1~8)
    "mad_eye": ("i", 8),
    "vulgar": ("i", 16),
    "dworm": ("i", 24),
    "ozzy": ("i", 32),
    "o_ray": ("i", 40),
    "sparker": ("i", 48),
    "iron_voc": ("i", 56),
    "hellcop": ("i", 64),
    # NPC (EVENTER.SPR 블록 0~4)
    "rescue_girl": ("eventer", 0),
    "cafeteria_girl": ("eventer", 0),  # 여학생 블록 공유 — tint 변별
    "guard_idle": ("eventer", 8),
    "tutor_dumb": ("eventer", 16),
    "prof_chem": ("eventer", 24),
    "librarian": ("eventer", 32),
    "nothing_man": ("eventer", 32),  # 유령 블록 공유 — tint 변별
}

# 행 → (애니 이름, 프레임 인덱스 2개, fps)
# 원작 인덱스 매핑 (GOODITEM.C move_you / eye[i] 및 EVENT.C move_eventer 기준):
#   DOWN={0,1} LEFT={2,3} RIGHT={4,5} UP={6,7}
ROWS: list[tuple[str, tuple[int, int], int]] = [
    ("walk_down", (0, 1), 6),
    ("walk_up", (6, 7), 6),
    ("walk_left", (2, 3), 6),
    ("walk_right", (4, 5), 6),
    ("idle_down", (0, 1), 2),
]


_SPR_CACHE: dict[str, list] = {}


def spr_frames(group: str) -> list:
    """<group>.SPR 전 프레임 — 팔레트 인덱스 0만 alpha 0."""
    if group not in _SPR_CACHE:
        path = os.path.join(ORIGINALS, f"{group.upper()}.SPR")
        if not os.path.exists(path):
            raise SystemExit(
                f"원본 없음: {path}\n"
                "이 도구는 원작 SPR만 읽는다(알파 근거 = 팔레트 인덱스 0). "
                "bmp_spr의 RGB 중간물로는 외곽선 검정과 배경 검정을 구별할 수 없다."
            )
        with open(path, "rb") as fh:
            _SPR_CACHE[group] = parse_spr(fh.read())[1]
    return _SPR_CACHE[group]


def load_frame(group: str, idx: int) -> Image.Image:
    """원작 SPR 1프레임 → RGBA(인덱스 0만 투명)."""
    w, h, rgba = spr_frames(group)[idx]
    return Image.frombytes("RGBA", (w, h), rgba)


def bake_cell(frame: Image.Image) -> Image.Image:
    """프레임 1장을 4배 nearest 베이크해 표준 셀(하단 중앙)에 배치.

    오프셋은 프레임 내용과 무관하게 고정(24×24 → 96px → (16,32)) —
    프레임 간 떨림 방지. 원작 도트는 24×24(장비류 최대 32×32)로 균일.
    """
    w, h = frame.width * BAKE, frame.height * BAKE
    if w > CELL or h > CELL:
        raise ValueError(f"베이크 {w}x{h}가 셀 {CELL} 초과 — BAKE 조정 필요")
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    cell.paste(frame.resize((w, h), Image.NEAREST), ((CELL - w) // 2, CELL - h), frame.resize((w, h), Image.NEAREST))
    return cell


def build_sheet_image(asset_id: str) -> Image.Image:
    """시트 1장을 메모리로만 굽는다 — 관문(tools/dev/spr_alpha_check.py)이 이걸 쓴다.

    "게임에 들어 있는 파일 == 지금 원작 SPR로 구운 것"을 관문이 바이트로 비교할 수
    있게 굽기와 저장을 나눠 둔다. 레시피를 관문 쪽에 베껴 두면 소스가 둘이 되고,
    이 저장소가 반복해 겪은 "사문화·갈라짐"이 관문 자신에게 재현된다.
    """
    group, start = SOURCES[asset_id]
    frames = [load_frame(group, start + k) for k in range(8)]
    sheet = Image.new("RGBA", (COLS * CELL, len(ROWS) * CELL), (0, 0, 0, 0))
    for row, (_anim, (f0, f1), _fps) in enumerate(ROWS):
        for col, fi in enumerate((f0, f1)):
            sheet.paste(bake_cell(frames[fi]), (col * CELL, row * CELL))
    return sheet


def build_sheet(asset_id: str, group: str, start: int) -> None:
    frames = [load_frame(group, start + k) for k in range(8)]
    sheet = build_sheet_image(asset_id)
    out_png = os.path.join(OUT_DIR, f"{asset_id}_original.png")
    sheet.save(out_png)

    anims: dict[str, dict] = {}
    for row, (anim, (_f0, _f1), fps) in enumerate(ROWS):
        anims[anim] = {"row": row, "frames": 2, "fps": fps, "loop": True}
    meta = {
        "schema_version": 2,
        "source": f"{group.upper()}.SPR frames {start:03d}-{start + 7:03d} "
                  f"(원작 도트 {frames[0].width}x{frames[0].height}, {BAKE}배 nearest 베이크)",
        "cell": CELL,
        "cell_w": CELL,
        "cell_h": CELL,
        "cols": COLS,
        "scale": SCALE,
        "animations": anims,
    }
    out_json = os.path.join(OUT_DIR, f"{asset_id}_original.json")
    with io.open(out_json, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print(f"{asset_id}: {group} frames {start:03d}-{start + 7:03d} -> {os.path.basename(out_png)}")


def main() -> None:
    targets = sys.argv[1:] or list(SOURCES)
    unknown = [t for t in targets if t not in SOURCES]
    if unknown:
        raise SystemExit(f"알 수 없는 id: {unknown} — SOURCES에 매핑 추가 후 실행")
    os.makedirs(OUT_DIR, exist_ok=True)
    for asset_id in targets:
        group, start = SOURCES[asset_id]
        build_sheet(asset_id, group, start)
    print(f"done -> {OUT_DIR} ({len(targets)} sheets)")


if __name__ == "__main__":
    main()
