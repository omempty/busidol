#!/usr/bin/env python3
"""널 포인터(null_pointer) 16비트 레트로 도트 스프라이트 시트 생성기.

규격: 512x1024 PNG (128x128 셀, 4열 x 8행)
- Row 0: walk_down (4 frames)
- Row 1: walk_up (4 frames)
- Row 2: walk_left (4 frames)
- Row 3: walk_right (4 frames)
- Row 4: idle_down (2 frames, 2 empty) - 0x00 빈 얼굴 지직거림
- Row 5: attack (4 frames) - 세그폴트 손아귀
- Row 6: hurt (2 frames, 2 empty) - 주소 비트 뒤엉킴
- Row 7: death (3 frames, 1 empty) - 참조 해제→공중 해체
"""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT_PATH = ROOT / "assets" / "raw" / "llm" / "10_submitted" / "monsters" / "null_pointer_v1.png"

CELL_W = 128
CELL_H = 128
COLS = 4
ROWS = 8
SHEET_W = COLS * CELL_W
SHEET_H = ROWS * CELL_H

# 100% 불투명 팔레트
C_OUTLINE = (10, 8, 46, 255)       # 짙은 남색 외곽선
C_GHOST_DARK = (18, 30, 60, 255)    # 유령 로브 섀도우
C_GHOST_MID = (40, 72, 130, 255)    # 유령 로브 중간톤
C_GHOST_LGT = (80, 140, 210, 255)   # 유령 로브 하이라이트
C_GHOST_HIL = (160, 220, 255, 255)  # 글리치 발광

C_DATA_CYAN = (64, 255, 220, 255)   # 0x00 네온 민트 데이터
C_EYE_GARBAGE = (255, 60, 90, 255)  # 떠도는 가비지 붉은 안광
C_EYE_PUPIL = (255, 220, 100, 255)  # 눈동자 코어

C_VOID_FACE = (8, 6, 24, 255)       # 0x00 텅 빈 얼굴 공허 블랙


def draw_ghost_cell(draw: ImageDraw.ImageDraw, cx: int, cy: int, facing: str,
                    anim: str, frame: int) -> None:
    # 발바닥(로브 자락) 접지 Y좌표 (128셀 기준 하단 7px 여백 -> Y = cy + 57)
    base_x = cx
    base_y = cy + 56

    bob = 0
    if anim == "walk":
        bob = [-3, 0, 3, 0][frame % 4]
    elif anim == "idle":
        bob = -2 if frame == 1 else 0
    elif anim == "attack":
        bob = [3, -5, -3, 0][frame % 4]
    elif anim == "hurt":
        bob = -4 if frame == 0 else 2
    elif anim == "death":
        bob = frame * 6

    center_y = base_y - 48 + bob

    if anim == "death":
        draw_death_frame(draw, base_x, center_y, frame)
        return

    # 1) 로브 뒤쪽 그림자 / 자락
    draw_robe_back(draw, base_x, center_y, facing, anim, frame)

    # 2) 본체 머리/얼굴 (0x00 공허)
    draw_head(draw, base_x, center_y, facing, anim, frame)

    # 3) 앞쪽 로브 자락 및 세그폴트 손아귀
    draw_robe_front(draw, base_x, center_y, facing, anim, frame)


def draw_head(draw: ImageDraw.ImageDraw, x: int, y: int, facing: str, anim: str, frame: int) -> None:
    """후드와 0x00 빈 얼굴."""
    hx, hy = x, y - 26
    # 후드 외곽
    draw.ellipse([hx - 20, hy - 20, hx + 20, hy + 20], fill=C_OUTLINE)
    draw.ellipse([hx - 18, hy - 18, hx + 18, hy + 18], fill=C_GHOST_DARK)
    draw.ellipse([hx - 14, hy - 16, hx + 14, hy + 8], fill=C_GHOST_MID)
    draw.ellipse([hx - 8, hy - 15, hx + 8, hy - 8], fill=C_GHOST_LGT)

    if facing == "up":
        # 뒷모습
        draw.ellipse([hx - 12, hy - 10, hx + 12, hy + 14], fill=C_GHOST_MID)
        draw.line([hx - 8, hy + 2, hx + 8, hy + 2], fill=C_DATA_CYAN, width=1)
        return

    # 공허한 빈 얼굴 (0x00)
    fx0, fy0 = hx - 12, hy - 8
    fx1, fy1 = hx + 12, hy + 14
    if facing == "left":
        fx0 -= 3
        fx1 -= 3
    elif facing == "right":
        fx0 += 3
        fx1 += 3

    draw.ellipse([fx0, fy0, fx1, fy1], fill=C_VOID_FACE)

    # '0x00' 글리치 텍스트 / 떠도는 가비지 눈
    if anim == "idle" and frame == 1:
        # 글리치 지직거림
        draw.line([fx0 + 2, hy + 2, fx1 - 2, hy + 2], fill=C_GHOST_HIL, width=1)
        draw.line([fx0 + 4, hy + 6, fx1 - 4, hy + 6], fill=C_DATA_CYAN, width=1)
    else:
        # 0x00 픽셀 심볼
        draw.rectangle([hx - 7, hy - 1, hx - 3, hy + 5], fill=C_DATA_CYAN)
        draw.rectangle([hx - 6, hy, hx - 4, hy + 4], fill=C_VOID_FACE)
        draw.rectangle([hx + 3, hy - 1, hx + 7, hy + 5], fill=C_DATA_CYAN)
        draw.rectangle([hx + 4, hy, hx + 6, hy + 4], fill=C_VOID_FACE)
        draw.line([hx - 1, hy + 1, hx + 1, hy + 3], fill=C_DATA_CYAN, width=1)

    # 떠도는 붉은 가비지 눈동자 (얼굴 밖으로 부유)
    ey_off = 4 if facing == "down" else (7 if facing == "right" else -7)
    draw.ellipse([hx + ey_off - 3, hy + 6, hx + ey_off + 3, hy + 12], fill=C_OUTLINE)
    draw.ellipse([hx + ey_off - 2, hy + 7, hx + ey_off + 2, hy + 11], fill=C_EYE_GARBAGE)
    draw.point([hx + ey_off, hy + 9], fill=C_EYE_PUPIL)


def draw_robe_back(draw: ImageDraw.ImageDraw, x: int, y: int, facing: str, anim: str, frame: int) -> None:
    # 펄럭이는 하단 자락
    sway = [0, 4, 0, -4][frame % 4] if anim == "walk" else 0
    draw.polygon([(x - 22, y - 6), (x + 22, y - 6), (x + 26 + sway, y + 48), (x - 26 + sway, y + 48)], fill=C_OUTLINE)
    draw.polygon([(x - 20, y - 4), (x + 20, y - 4), (x + 24 + sway, y + 46), (x - 24 + sway, y + 46)], fill=C_GHOST_DARK)


def draw_robe_front(draw: ImageDraw.ImageDraw, x: int, y: int, facing: str, anim: str, frame: int) -> None:
    sway = [0, 4, 0, -4][frame % 4] if anim == "walk" else 0

    # 몸통 앞 로브
    draw.polygon([(x - 16, y - 8), (x + 16, y - 8), (x + 20 + sway, y + 44), (x - 20 + sway, y + 44)], fill=C_GHOST_MID)
    draw.polygon([(x - 10, y - 6), (x + 10, y - 6), (x + 12 + sway, y + 36), (x - 12 + sway, y + 36)], fill=C_GHOST_LGT)

    # 데이터 회로 줄기
    draw.line([x - 12, y + 8, x - 4, y + 26], fill=C_DATA_CYAN, width=1)
    draw.line([x + 12, y + 10, x + 6, y + 28], fill=C_DATA_CYAN, width=1)

    # 세그폴트 손아귀
    arm_ext = 0
    if anim == "attack":
        arm_ext = [0, 16, 24, 8][frame % 4]

    # 좌우 손아귀
    lx = x - 22 - (arm_ext if facing in ("left", "down") else 0)
    ly = y + 8 + (arm_ext // 2)
    rx = x + 22 + (arm_ext if facing in ("right", "down") else 0)
    ry = y + 8 + (arm_ext // 2)

    # 왼손
    draw.ellipse([lx - 6, ly - 6, lx + 6, ly + 6], fill=C_OUTLINE)
    draw.ellipse([lx - 5, ly - 5, lx + 5, ly + 5], fill=C_GHOST_HIL)
    draw.polygon([(lx - 6, ly + 4), (lx - 12, ly + 12), (lx - 2, ly + 8)], fill=C_DATA_CYAN)

    # 오른손
    draw.ellipse([rx - 6, ry - 6, rx + 6, ry + 6], fill=C_OUTLINE)
    draw.ellipse([rx - 5, ry - 5, rx + 5, ry + 5], fill=C_GHOST_HIL)
    draw.polygon([(rx + 6, ry + 4), (rx + 12, ry + 12), (rx + 2, ry + 8)], fill=C_DATA_CYAN)


def draw_death_frame(draw: ImageDraw.ImageDraw, x: int, y: int, frame: int) -> None:
    if frame == 0:
        # 주소 비트 붕괴 플래시
        draw.ellipse([x - 24, y - 24, x + 24, y + 24], fill=C_OUTLINE)
        draw.ellipse([x - 22, y - 22, x + 22, y + 22], fill=C_GHOST_HIL)
        draw.line([x - 30, y, x + 30, y], fill=C_DATA_CYAN, width=2)
    elif frame == 1:
        # 데이터 비트가 공중으로 비산
        draw.rectangle([x - 28, y - 36, x - 18, y - 26], fill=C_GHOST_LGT)
        draw.rectangle([x + 18, y - 40, x + 30, y - 28], fill=C_DATA_CYAN)
        draw.rectangle([x - 20, y + 10, x - 8, y + 22], fill=C_GHOST_MID)
        draw.rectangle([x + 10, y + 6, x + 22, y + 18], fill=C_GHOST_DARK)
        draw.ellipse([x - 4, y - 10, x + 6, y], fill=C_EYE_GARBAGE)
    elif frame == 2:
        # 소멸 잔여 코드 라인
        draw.line([x - 16, y + 20, x + 16, y + 20], fill=C_DATA_CYAN, width=1)
        draw.line([x - 8, y + 26, x + 8, y + 26], fill=C_GHOST_DARK, width=1)


def generate_null_pointer_sheet() -> None:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    row_specs = [
        (0, "down", "walk", 4),
        (1, "up", "walk", 4),
        (2, "left", "walk", 4),
        (3, "right", "walk", 4),
        (4, "down", "idle", 2),
        (5, "down", "attack", 4),
        (6, "down", "hurt", 2),
        (7, "down", "death", 3),
    ]

    for row_idx, facing, anim, valid_count in row_specs:
        for col_idx in range(valid_count):
            cx = col_idx * CELL_W + CELL_W // 2
            cy = row_idx * CELL_H + CELL_H // 2
            draw_ghost_cell(draw, cx, cy, facing, anim, col_idx)

    img.save(OUT_PATH, "PNG")
    print(f"[generate_null_pointer] 완료: {OUT_PATH} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    generate_null_pointer_sheet()
