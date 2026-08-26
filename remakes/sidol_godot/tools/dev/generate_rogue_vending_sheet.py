#!/usr/bin/env python3
"""로그 벤딩(rogue_vending) 16비트 레트로 도트 스프라이트 시트 생성기.

규격: 640x512 PNG (128x128 셀, 5열 x 4행)
- Row 0: idle (2 frames, 3 empty) - 평범한 자판기 위장
- Row 1: awaken (3 frames, 2 empty) - 위장 해제, 눈 깜빡임
- Row 2: attack (5 frames) - 캔 연발 발사
- Row 3: death (4 frames, 1 empty) - 캔 쏟아지며 무너짐 → 마지막에 정상 작동(개그)
"""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT_PATH = ROOT / "assets" / "raw" / "llm" / "10_submitted" / "monsters" / "rogue_vending_v1.png"

CELL_W = 128
CELL_H = 128
COLS = 5
ROWS = 4
SHEET_W = COLS * CELL_W
SHEET_H = ROWS * CELL_H

# 100% 불투명 팔레트
C_OUTLINE = (10, 8, 46, 255)       # 짙은 남색 외곽선
C_BODY_DARK = (140, 16, 28, 255)   # 90s 레드 자판기 섀도우
C_BODY_MID = (200, 32, 44, 255)    # 자판기 레드 중간톤
C_BODY_LGT = (240, 80, 70, 255)    # 자판기 레드 하이라이트

C_GLASS_DARK = (24, 48, 72, 255)   # 디스플레이 쇼케이스 어두운 유리
C_GLASS_LGT = (70, 140, 190, 255)  # 유리 반사광
C_CAN_BLU = (40, 110, 220, 255)    # 파란색 캔 (포카리풍)
C_CAN_YEL = (240, 190, 40, 255)    # 노란색 캔
C_CAN_GRN = (40, 190, 100, 255)    # 초록색 사이다 캔

C_MOUTH_DARK = (8, 6, 24, 255)     # 괴물 입 벌어진 틈
C_EYE_RED = (255, 30, 60, 255)     # 붉은 눈알
C_EYE_WHT = (245, 240, 230, 255)   # 흰자위
C_COIN_SLOT = (220, 200, 80, 255)  # 동전 투입구 골드


def draw_vending_cell(draw: ImageDraw.ImageDraw, cx: int, cy: int, anim: str, frame: int) -> None:
    base_x = cx
    base_y = cy + 56

    shake = 0
    if anim == "awaken":
        shake = [-1, 2, -1][frame % 3]
    elif anim == "attack":
        shake = [0, -3, 3, -2, 0][frame % 5]

    draw_x = base_x + shake
    center_y = base_y - 50

    if anim == "death":
        draw_death_frame(draw, base_x, center_y, frame)
        return

    # 바닥 접지 그림자
    draw.rectangle([base_x - 22, base_y - 2, base_x + 22, base_y], fill=C_OUTLINE)

    # 1) 자판기 본체 박스 (44x84 픽셀)
    vx0, vy0 = draw_x - 22, center_y - 42
    vx1, vy1 = draw_x + 22, center_y + 42

    draw.rectangle([vx0 - 1, vy0 - 1, vx1 + 1, vy1 + 1], fill=C_OUTLINE)
    draw.rectangle([vx0, vy0, vx1, vy1], fill=C_BODY_DARK)
    draw.rectangle([vx0 + 2, vy0 + 2, vx1 - 2, vy1 - 2], fill=C_BODY_MID)
    draw.line([vx0 + 2, vy0 + 2, vx1 - 2, vy0 + 2], fill=C_BODY_LGT, width=2)
    draw.line([vx0 + 2, vy0 + 2, vx0 + 2, vy1 - 2], fill=C_BODY_LGT, width=2)

    # 2) 상단 쇼케이스 디스플레이 유리 (캔 진열)
    gx0, gy0 = vx0 + 4, vy0 + 6
    gx1, gy1 = vx1 - 4, vy0 + 34
    draw.rectangle([gx0, gy0, gx1, gy1], fill=C_OUTLINE)
    draw.rectangle([gx0 + 1, gy0 + 1, gx1 - 1, gy1 - 1], fill=C_GLASS_DARK)
    # 진열 캔 3개
    draw.rectangle([draw_x - 14, gy0 + 6, draw_x - 6, gy1 - 4], fill=C_CAN_BLU)
    draw.rectangle([draw_x - 4, gy0 + 6, draw_x + 4, gy1 - 4], fill=C_CAN_YEL)
    draw.rectangle([draw_x + 6, gy0 + 6, draw_x + 14, gy1 - 4], fill=C_CAN_GRN)
    # 유리 사선 반사광
    draw.line([gx0 + 3, gy0 + 3, gx0 + 16, gy1 - 3], fill=C_GLASS_LGT, width=2)

    # 3) 동전 투입구 & 가격 버튼
    draw.rectangle([draw_x + 10, vy0 + 40, draw_x + 14, vy0 + 48], fill=C_COIN_SLOT)
    draw.line([draw_x - 14, vy0 + 42, draw_x + 6, vy0 + 42], fill=(60, 220, 100, 255), width=2)

    # 4) 하단 음료 배출구 (평상시: 배출구 도어 / 각성 시: 이빨 달린 괴물 입)
    mx0, my0 = vx0 + 5, vy0 + 54
    mx1, my1 = vx1 - 5, vy1 - 6

    if anim == "idle":
        # 평범한 자판기 도어
        draw.rectangle([mx0, my0, mx1, my1], fill=C_OUTLINE)
        draw.rectangle([mx0 + 1, my0 + 1, mx1 - 1, my1 - 1], fill=(40, 40, 50, 255))
        draw.line([mx0 + 4, my1 - 4, mx1 - 4, my1 - 4], fill=(180, 180, 190, 255), width=2)

    elif anim == "awaken" or anim == "attack":
        # 벌어진 괴물 입 & 눈알
        draw.rectangle([mx0, my0, mx1, my1], fill=C_OUTLINE)
        draw.rectangle([mx0 + 1, my0 + 1, mx1 - 1, my1 - 1], fill=C_MOUTH_DARK)

        # 뾰족한 금속 이빨
        for tx in range(mx0 + 3, mx1 - 3, 5):
            draw.polygon([(tx, my0 + 1), (tx + 2, my0 + 6), (tx + 4, my0 + 1)], fill=C_EYE_WHT)
            draw.polygon([(tx, my1 - 1), (tx + 2, my1 - 6), (tx + 4, my1 - 1)], fill=C_EYE_WHT)

        # 배출구 안에서 번뜩이는 붉은 눈알
        ey_open = (frame != 1) if anim == "awaken" else True
        if ey_open:
            draw.ellipse([draw_x - 6, my0 + 8, draw_x + 6, my1 - 8], fill=C_EYE_WHT)
            draw.ellipse([draw_x - 3, my0 + 10, draw_x + 3, my1 - 10], fill=C_EYE_RED)
            draw.point([draw_x, my0 + 12], fill=(255, 255, 200, 255))

        if anim == "attack":
            # 캔/눈알 발사 투사체
            can_pos = [0, 8, 20, 34, 46][frame % 5]
            draw.rectangle([draw_x - 4, my1 + can_pos - 8, draw_x + 4, my1 + can_pos + 4], fill=C_OUTLINE)
            draw.rectangle([draw_x - 3, my1 + can_pos - 7, draw_x + 3, my1 + can_pos + 3], fill=C_CAN_YEL)
            draw.ellipse([draw_x - 2, my1 + can_pos - 4, draw_x + 2, my1 + can_pos], fill=C_EYE_RED)


def draw_death_frame(draw: ImageDraw.ImageDraw, x: int, y: int, frame: int) -> None:
    if frame == 0:
        # 외벽 균열 + 캔 폭발 전조
        draw.rectangle([x - 22, y - 40, x + 22, y + 42], fill=C_OUTLINE)
        draw.rectangle([x - 20, y - 38, x + 20, y + 40], fill=C_BODY_MID)
        draw.line([x - 16, y - 30, x + 16, y + 20], fill=C_OUTLINE, width=3)
    elif frame == 1:
        # 본체 붕괴 + 캔 와르르 쏟아짐
        draw.polygon([(x - 28, y - 10), (x, y - 36), (x + 24, y - 18), (x + 18, y + 36), (x - 24, y + 38)], fill=C_BODY_MID)
        # 사방으로 튕겨나가는 색색 캔들
        draw.rectangle([x - 34, y + 10, x - 26, y + 22], fill=C_CAN_BLU)
        draw.rectangle([x + 26, y + 14, x + 34, y + 26], fill=C_CAN_GRN)
        draw.rectangle([x - 14, y + 28, x - 6, y + 40], fill=C_CAN_YEL)
        draw.rectangle([x + 10, y + 26, x + 18, y + 38], fill=C_CAN_BLU)
    elif frame == 2:
        # 완전히 납작하게 무너진 자판기 잔해
        draw.rectangle([x - 26, y + 20, x + 26, y + 42], fill=C_OUTLINE)
        draw.rectangle([x - 24, y + 22, x + 24, y + 40], fill=C_BODY_DARK)
        draw.rectangle([x - 16, y + 28, x - 8, y + 38], fill=C_CAN_BLU)
        draw.rectangle([x + 8, y + 28, x + 16, y + 38], fill=C_CAN_GRN)
    elif frame == 3:
        # 개그 엔딩: 잔해 속에서 정상 작동하며 "덜컹~" 캔 하나가 또르르 나옴
        draw.rectangle([x - 26, y + 20, x + 26, y + 42], fill=C_OUTLINE)
        draw.rectangle([x - 24, y + 22, x + 24, y + 40], fill=C_BODY_DARK)
        # 반짝이는 정상 시원한 캔 1개
        draw.rectangle([x - 5, y + 30, x + 5, y + 44], fill=C_OUTLINE)
        draw.rectangle([x - 4, y + 31, x + 4, y + 43], fill=C_CAN_BLU)
        draw.point([x - 1, y + 33], fill=(255, 255, 255, 255))
        draw.line([x + 10, y + 26, x + 14, y + 22], fill=C_GLASS_LGT, width=1)


def generate_rogue_vending_sheet() -> None:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    row_specs = [
        (0, "idle", 2),
        (1, "awaken", 3),
        (2, "attack", 5),
        (3, "death", 4),
    ]

    for row_idx, anim, valid_count in row_specs:
        for col_idx in range(valid_count):
            cx = col_idx * CELL_W + CELL_W // 2
            cy = row_idx * CELL_H + CELL_H // 2
            draw_vending_cell(draw, cx, cy, anim, col_idx)

    img.save(OUT_PATH, "PNG")
    print(f"[generate_rogue_vending] 완료: {OUT_PATH} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    generate_rogue_vending_sheet()
