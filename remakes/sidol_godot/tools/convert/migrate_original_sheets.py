"""원작 도트 → 표준 스프라이트 시트 일괄 이관 (정책 ①원작 있음→리마스터).

originals_ref/bmp_spr/<group>/frame_*.bmp (원작 크롭 도트, RGB)를 받아
테두리 배경 제거(extract_sprites.remove_bg_np 재사용) → 4배 nearest 베이크 →
표준 셀 128(2열×5행) 시트 + 메타 JSON을 assets/sprites/<id>_original.png|.json
으로 출력한다. SpriteSets 컨벤션(<id>_original.*)에 따라 게임이 즉시 인식하며,
아트모드 REMAKE 신규 시트 미착용 시 폴백 세트로도 동작한다.

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
sys.path.insert(0, HERE)
import extract_sprites as es  # noqa: E402  (remove_bg_np 재사용)

ROOT = es.ROOT
REF = es.REF  # originals_ref/bmp_spr
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
ROWS: list[tuple[str, tuple[int, int], int]] = [
    ("walk_down", (0, 1), 6),
    ("walk_up", (2, 3), 6),
    ("walk_left", (4, 5), 6),
    ("walk_right", (6, 7), 6),
    ("idle_down", (0, 1), 2),
]


def load_frame(group: str, idx: int) -> Image.Image:
    """원작 크롭 bmp 1프레임 → 배경 제거 RGBA."""
    path = os.path.join(REF, group, f"frame_{idx:03d}.bmp")
    return es.remove_bg_np(Image.open(path))


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


def build_sheet(asset_id: str, group: str, start: int) -> None:
    frames = [load_frame(group, start + k) for k in range(8)]
    sheet = Image.new("RGBA", (COLS * CELL, len(ROWS) * CELL), (0, 0, 0, 0))
    for row, (anim, (f0, f1), _fps) in enumerate(ROWS):
        for col, fi in enumerate((f0, f1)):
            sheet.paste(bake_cell(frames[fi]), (col * CELL, row * CELL))
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
