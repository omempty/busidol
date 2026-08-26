#!/usr/bin/env python3
"""씨버그(c_bug) 16비트 레트로 도트 스프라이트 시트 생성기 (v1).

규격: 512x896 PNG (128x128 셀, 4열 x 7행)
- Row 0: walk_down (4 frames)
- Row 1: walk_up (4 frames)
- Row 2: walk_left (4 frames)
- Row 3: walk_right (4 frames)
- Row 4: idle_down (2 frames, 2 empty)
- Row 5: attack (3 frames, 1 empty) - 다리 콤보 급타격
- Row 6: death (3 frames, 1 empty) - 부품 산산조각
"""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT_PATH = ROOT / "assets" / "raw" / "llm" / "10_submitted" / "monsters" / "c_bug_v1.png"

CELL_W = 128
CELL_H = 128
COLS = 4
ROWS = 7
SHEET_W = COLS * CELL_W
SHEET_H = ROWS * CELL_H

# 100% 불투명 팔레트 (안티에일리어싱 0건 보장)
C_OUTLINE = (10, 8, 46, 255)       # 짙은 남색 외곽선
C_SHELL_DARK = (24, 48, 56, 255)    # 사이버 쉘 어두운 섀도우
C_SHELL_MID = (40, 96, 104, 255)    # 청록색 금속 중간톤
C_SHELL_LGT = (72, 160, 168, 255)   # 청록색 금속 하이라이트
C_SHELL_HIL = (140, 220, 224, 255)  # 최고 밝은 반사광

C_CIRCUIT = (80, 240, 200, 255)     # 네온 민트 회로선
C_EYE_RED = (255, 32, 64, 255)      # 붉은 광학 렌즈 코어
C_EYE_ORG = (255, 140, 40, 255)     # 렌즈 발광
C_EYE_GLW = (180, 20, 40, 255)      # 렌즈 외곽

C_LEG_DARK = (36, 32, 54, 255)      # 기계 다리 섀도우
C_LEG_MID = (76, 70, 98, 255)       # 다리 금속 중간톤
C_LEG_LGT = (130, 120, 156, 255)    # 다리 관절 하이라이트
C_FINGER_TIP = (220, 170, 150, 255) # 변형된 손가락 끝마디(그로테스크 살색)
C_FINGER_SHD = (160, 100, 90, 255)  # 손가락 관절 그림자


def draw_spider_cell(draw: ImageDraw.ImageDraw, cx: int, cy: int, facing: str,
                      anim: str, frame: int) -> None:
    # 발바닥 접지 Y좌표 (128셀 기준 하단 7px 여백 -> Y = cy + 57)
    base_x = cx
    base_y = cy + 56

    bob = 0
    if anim == "walk":
        bob = -3 if (frame % 2 == 1) else 0
    elif anim == "idle":
        bob = -2 if frame == 1 else 0
    elif anim == "attack":
        bob = 4 if frame == 0 else (-6 if frame == 1 else -2)
    elif anim == "death":
        bob = frame * 6

    body_y = base_y - 36 + bob

    if anim == "death":
        draw_death_frame(draw, base_x, body_y, frame)
        return

    # 1) 뒤쪽 다리
    draw_legs(draw, base_x, body_y, facing, anim, frame, background=True)

    # 2) 중앙 몸체
    draw_body(draw, base_x, body_y, facing, anim, frame)

    # 3) 앞쪽 다리
    draw_legs(draw, base_x, body_y, facing, anim, frame, background=False)


def draw_body(draw: ImageDraw.ImageDraw, x: int, y: int, facing: str, anim: str, frame: int) -> None:
    # 돔형 몸체 (40x30 픽셀)
    bx0, by0 = x - 20, y - 15
    bx1, by1 = x + 20, y + 15

    # 외곽선
    draw.ellipse([bx0 - 1, by0 - 1, bx1 + 1, by1 + 1], fill=C_OUTLINE)
    draw.ellipse([bx0, by0, bx1, by1], fill=C_SHELL_DARK)
    draw.ellipse([bx0 + 3, by0 + 3, bx1 - 3, by1 - 4], fill=C_SHELL_MID)
    draw.ellipse([bx0 + 6, by0 + 4, bx1 - 6, by0 + 13], fill=C_SHELL_LGT)
    draw.ellipse([bx0 + 9, by0 + 5, bx1 - 9, by0 + 9], fill=C_SHELL_HIL)

    # 네온 회로선
    draw.line([x - 12, y - 3, x - 5, y - 8], fill=C_CIRCUIT, width=1)
    draw.line([x + 12, y - 3, x + 5, y - 8], fill=C_CIRCUIT, width=1)
    draw.point([x - 5, y - 8], fill=C_SHELL_HIL)
    draw.point([x + 5, y - 8], fill=C_SHELL_HIL)

    if facing == "down" or (anim == "attack" and facing == "down"):
        # 정면: 거대 단안 광학 센서
        ey_y = y + 2
        draw.ellipse([x - 8, ey_y - 7, x + 8, ey_y + 7], fill=C_OUTLINE)
        draw.ellipse([x - 7, ey_y - 6, x + 7, ey_y + 6], fill=C_EYE_GLW)
        draw.ellipse([x - 4, ey_y - 4, x + 4, ey_y + 4], fill=C_EYE_RED)
        draw.ellipse([x - 2, ey_y - 3, x + 3, ey_y + 2], fill=C_EYE_ORG)
        draw.point([x + 2, ey_y - 2], fill=(255, 255, 220, 255))
        # 턱/송곳니
        draw.polygon([(x - 10, y + 12), (x - 6, y + 19), (x - 4, y + 12)], fill=C_OUTLINE)
        draw.polygon([(x - 9, y + 12), (x - 6, y + 18), (x - 5, y + 12)], fill=C_LEG_LGT)
        draw.polygon([(x + 4, y + 12), (x + 6, y + 19), (x + 10, y + 12)], fill=C_OUTLINE)
        draw.polygon([(x + 5, y + 12), (x + 6, y + 18), (x + 9, y + 12)], fill=C_LEG_LGT)

    elif facing == "up":
        # 후면: 배기구
        draw.rectangle([x - 10, y - 3, x + 10, y + 8], fill=C_OUTLINE)
        draw.rectangle([x - 9, y - 2, x + 9, y + 7], fill=C_SHELL_DARK)
        draw.line([x - 8, y + 1, x + 8, y + 1], fill=C_CIRCUIT, width=1)
        draw.line([x - 8, y + 4, x + 8, y + 4], fill=C_CIRCUIT, width=1)

    elif facing in ("left", "right"):
        dir_sgn = -1 if facing == "left" else 1
        ey_x = x + dir_sgn * 13
        ey_y = y + 1
        draw.ellipse([ey_x - 6, ey_y - 6, ey_x + 6, ey_y + 6], fill=C_OUTLINE)
        draw.ellipse([ey_x - 5, ey_y - 5, ey_x + 5, ey_y + 5], fill=C_EYE_RED)
        draw.ellipse([ey_x - 2, ey_y - 3, x + dir_sgn * 15, ey_y + 2], fill=C_EYE_ORG)
        draw.polygon([(ey_x - 3, y + 11), (ey_x + dir_sgn * 4, y + 18), (ey_x + 4, y + 11)], fill=C_OUTLINE)


def draw_legs(draw: ImageDraw.ImageDraw, x: int, y: int, facing: str, anim: str, frame: int, background: bool) -> None:
    leg_configs = [
        (-1, 0, True),
        (-1, 1, False),
        (1, 0, True),
        (1, 1, False),
    ]
    phase_offsets = [0, 2, 2, 0] if anim == "walk" else [0, 0, 0, 0]

    for (side, idx, is_rear), p_off in zip(leg_configs, phase_offsets):
        if is_rear != background:
            continue

        step = (frame + p_off) % 4 if anim == "walk" else 0
        leg_sweep = (step - 1.5) * 5.0 if anim == "walk" else 0.0

        if anim == "attack":
            if frame == 0:
                leg_sweep = -4.0
            elif frame == 1:
                leg_sweep = 12.0 if not is_rear else -8.0
            elif frame == 2:
                leg_sweep = -5.0

        hip_x = x + side * (12 if is_rear else 15)
        hip_y = y + (-3 if is_rear else 6)

        knee_x = hip_x + side * (20 + idx * 5) + (leg_sweep * 0.4)
        knee_y = hip_y - 16 - (5 if anim == "walk" and step in (1, 3) else 0)

        foot_x = hip_x + side * (24 + idx * 6) + leg_sweep
        foot_y = y + 36 - (8 if anim == "walk" and step == 1 else 0)

        if facing == "left":
            knee_x -= 5
            foot_x -= 8
        elif facing == "right":
            knee_x += 5
            foot_x += 8

        # 굵은 다리 관절
        draw.line([hip_x, hip_y, knee_x, knee_y], fill=C_OUTLINE, width=3)
        draw.line([hip_x, hip_y, knee_x, knee_y], fill=C_LEG_MID, width=1)

        draw.line([knee_x, knee_y, foot_x, foot_y], fill=C_OUTLINE, width=3)
        draw.line([knee_x, knee_y, foot_x, foot_y], fill=C_LEG_LGT, width=1)

        draw.ellipse([knee_x - 3, knee_y - 3, knee_x + 3, knee_y + 3], fill=C_SHELL_HIL)

        # 발끝 감염 손가락
        draw.ellipse([foot_x - 4, foot_y - 5, foot_x + 4, foot_y + 3], fill=C_OUTLINE)
        draw.ellipse([foot_x - 3, foot_y - 4, foot_x + 3, foot_y + 2], fill=C_FINGER_TIP)
        draw.point([foot_x, foot_y - 2], fill=C_FINGER_SHD)


def draw_death_frame(draw: ImageDraw.ImageDraw, x: int, y: int, frame: int) -> None:
    if frame == 0:
        draw.ellipse([x - 18, y - 13, x + 18, y + 13], fill=C_OUTLINE)
        draw.ellipse([x - 16, y - 11, x + 16, y + 11], fill=C_EYE_ORG)
        draw.line([x - 25, y - 20, x + 25, y + 20], fill=(255, 255, 255, 255), width=2)
        draw.line([x + 25, y - 20, x - 25, y + 20], fill=(255, 255, 255, 255), width=2)
    elif frame == 1:
        draw.polygon([(x - 24, y - 20), (x - 10, y - 30), (x - 5, y - 15)], fill=C_SHELL_MID)
        draw.polygon([(x + 8, y - 28), (x + 24, y - 18), (x + 12, y - 10)], fill=C_SHELL_LGT)
        draw.line([x - 30, y + 5, x - 42, y + 18], fill=C_LEG_LGT, width=2)
        draw.line([x + 25, y + 3, x + 40, y + 20], fill=C_LEG_MID, width=2)
        draw.ellipse([x - 3, y - 5, x + 8, y + 5], fill=C_EYE_RED)
    elif frame == 2:
        draw.ellipse([x - 20, y + 15, x + 20, y + 28], fill=C_SHELL_DARK)
        draw.rectangle([x - 12, y + 18, x - 5, y + 23], fill=C_LEG_DARK)
        draw.rectangle([x + 5, y + 19, x + 15, y + 24], fill=C_FINGER_SHD)
        draw.ellipse([x - 10, y - 3, x, y + 7], fill=(120, 130, 150, 255))
        draw.ellipse([x + 3, y - 10, x + 15, y + 2], fill=(150, 160, 180, 255))


def generate_c_bug_sheet() -> None:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    row_specs = [
        (0, "down", "walk", 4),
        (1, "up", "walk", 4),
        (2, "left", "walk", 4),
        (3, "right", "walk", 4),
        (4, "down", "idle", 2),
        (5, "down", "attack", 3),
        (6, "down", "death", 3),
    ]

    for row_idx, facing, anim, valid_count in row_specs:
        for col_idx in range(valid_count):
            cx = col_idx * CELL_W + CELL_W // 2
            cy = row_idx * CELL_H + CELL_H // 2
            draw_spider_cell(draw, cx, cy, facing, anim, col_idx)

    img.save(OUT_PATH, "PNG")
    print(f"[generate_c_bug] 완료: {OUT_PATH} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    generate_c_bug_sheet()
