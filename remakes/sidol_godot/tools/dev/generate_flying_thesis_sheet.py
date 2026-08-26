#!/usr/bin/env python3
"""플라잉 논문(flying_thesis) 16비트 레트로 도트 스프라이트 시트 생성기.

규격: 512x384 PNG (128x128 셀, 4열 x 3행)
- Row 0: walk (4 frames) - 공중 부유, 페이지 펄럭임
- Row 1: attack (3 frames, 1 empty) - 종이 날림/베기 공격
- Row 2: death (3 frames, 1 empty) - 제본 폭발, 페이지 산화 소멸
"""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT_PATH = ROOT / "assets" / "raw" / "llm" / "10_submitted" / "monsters" / "flying_thesis_v1.png"

CELL_W = 128
CELL_H = 128
COLS = 4
ROWS = 3
SHEET_W = COLS * CELL_W
SHEET_H = ROWS * CELL_H

# 100% 불투명 팔레트
C_OUTLINE = (10, 8, 46, 255)       # 짙은 남색 외곽선
C_BINDING_DARK = (16, 28, 64, 255)  # 짙은 남청색 가죽 하드커버
C_BINDING_MID = (32, 56, 120, 255)  # 하드커버 중간톤
C_BINDING_LGT = (60, 96, 180, 255)  # 하드커버 하이라이트
C_GOLD = (235, 190, 60, 255)        # 금박 논문 타이틀

C_PAPER_DARK = (160, 150, 136, 255) # 종이 그림자 밴딩
C_PAPER_MID = (210, 202, 186, 255)  # 고서적 종이 중간톤
C_PAPER_LGT = (248, 244, 232, 255)  # 종이 하이라이트

C_BLOOD = (185, 20, 36, 255)        # 코피 얼룩/손톱 자국
C_BLOOD_DARK = (110, 10, 20, 255)   # 굳은 피
C_EYE_RED = (255, 40, 60, 255)      # 페이지 틈새 광기 안광
C_EYE_ORG = (255, 160, 50, 255)


def draw_thesis_cell(draw: ImageDraw.ImageDraw, cx: int, cy: int, anim: str, frame: int) -> None:
    # 발바닥 접지 Y좌표 (128셀 기준 하단 8px 여백 -> Y = cy + 56)
    base_x = cx
    base_y = cy + 56

    float_bob = 0
    if anim == "walk":
        # 4프레임 부유 모션 (위아래 펄럭임)
        float_bob = [-4, 0, 4, 0][frame % 4]
    elif anim == "attack":
        float_bob = [2, -6, -2][frame % 3]
    elif anim == "death":
        float_bob = frame * 4

    center_y = base_y - 42 + float_bob

    if anim == "death":
        draw_death_frame(draw, base_x, center_y, frame)
        return

    # 공중 부유 그림자 (바닥 접지선 근처에 작고 짙게)
    draw.rectangle([base_x - 14, base_y - 2, base_x + 14, base_y], fill=C_OUTLINE)

    if anim == "attack":
        draw_attack_frame(draw, base_x, center_y, frame)
    else:
        draw_walk_frame(draw, base_x, center_y, frame)


def draw_walk_frame(draw: ImageDraw.ImageDraw, x: int, y: int, frame: int) -> None:
    """부유하며 페이지를 펄럭이는 논문 본체."""
    wing_flap = [0, 4, 8, 4][frame % 4]
    
    # 1) 뒤쪽 펼쳐진 페이지들
    draw.polygon([(x - 30, y - 20 - wing_flap), (x, y - 5), (x - 24, y + 16)], fill=C_OUTLINE)
    draw.polygon([(x - 28, y - 18 - wing_flap), (x - 2, y - 5), (x - 22, y + 14)], fill=C_PAPER_MID)
    draw.polygon([(x + 30, y - 20 - wing_flap), (x, y - 5), (x + 24, y + 16)], fill=C_OUTLINE)
    draw.polygon([(x + 28, y - 18 - wing_flap), (x + 2, y - 5), (x + 22, y + 14)], fill=C_PAPER_MID)

    # 2) 주 논문 뭉치 몸체 (두꺼운 하드커버 + 종이 층)
    bx0, by0 = x - 26, y - 16
    bx1, by1 = x + 26, y + 22

    draw.rectangle([bx0 - 1, by0 - 1, bx1 + 1, by1 + 1], fill=C_OUTLINE)
    draw.rectangle([bx0, by0, bx1, by1], fill=C_BINDING_DARK)
    draw.rectangle([bx0 + 2, by0 + 2, bx1 - 2, by0 + 7], fill=C_BINDING_LGT)
    draw.rectangle([bx0 + 2, by0 + 7, bx1 - 2, by1 - 2], fill=C_BINDING_MID)

    # 금박 글씨 (학위 논문)
    draw.line([x - 14, by0 + 4, x + 14, by0 + 4], fill=C_GOLD, width=1)
    draw.line([x - 10, by0 + 9, x + 10, by0 + 9], fill=C_GOLD, width=1)

    # 3) 앞쪽 벌어진 종이 단면 & 광기 안광
    draw.rectangle([bx0 + 4, by0 + 13, bx1 - 4, by1 - 4], fill=C_OUTLINE)
    draw.rectangle([bx0 + 5, by0 + 14, bx1 - 5, by1 - 5], fill=C_PAPER_LGT)
    # 종이 결 라인
    for py in range(by0 + 15, by1 - 5, 2):
        draw.line([bx0 + 6, py, bx1 - 6, py], fill=C_PAPER_DARK, width=1)

    # 코피 얼룩 & 손톱 긁힌 자국
    draw.polygon([(x - 8, by0 + 16), (x - 2, by0 + 25), (x - 5, by0 + 28), (x - 12, by0 + 20)], fill=C_BLOOD)
    draw.line([x - 14, by0 + 16, x - 9, by0 + 27], fill=C_BLOOD_DARK, width=1)
    draw.line([x + 6, by0 + 18, x + 16, by0 + 26], fill=C_BLOOD, width=1)
    draw.line([x + 10, by0 + 17, x + 18, by0 + 23], fill=C_BLOOD, width=1)

    # 틈새 붉은 눈 (폴터가이스트 안광)
    ey_y = by0 + 19
    draw.ellipse([x - 4, ey_y - 2, x + 4, ey_y + 3], fill=C_OUTLINE)
    draw.ellipse([x - 3, ey_y - 1, x + 3, ey_y + 2], fill=C_EYE_RED)
    draw.point([x, ey_y], fill=C_EYE_ORG)


def draw_attack_frame(draw: ImageDraw.ImageDraw, x: int, y: int, frame: int) -> None:
    """종이 날림/칼날 베기 공격 모션."""
    if frame == 0:
        # 응축 준비 (책이 꽉 닫히며 붉은빛 발산)
        draw.rectangle([x - 22, y - 18, x + 22, y + 20], fill=C_OUTLINE)
        draw.rectangle([x - 20, y - 16, x + 20, y + 18], fill=C_BINDING_DARK)
        draw.line([x - 18, y + 2, x + 18, y + 2], fill=C_EYE_RED, width=2)
    elif frame == 1:
        # 전면 전개 + 날카로운 종이 칼날 3개 투척
        draw.polygon([(x - 36, y - 24), (x, y - 8), (x - 28, y + 20)], fill=C_OUTLINE)
        draw.polygon([(x - 34, y - 22), (x - 2, y - 8), (x - 26, y + 18)], fill=C_PAPER_LGT)
        draw.polygon([(x + 36, y - 24), (x, y - 8), (x + 28, y + 20)], fill=C_OUTLINE)
        draw.polygon([(x + 34, y - 22), (x + 2, y - 8), (x + 26, y + 18)], fill=C_PAPER_LGT)
        # 피 묻은 종이 칼날 3장
        draw.polygon([(x - 38, y - 10), (x - 48, y - 20), (x - 32, y - 16)], fill=C_PAPER_LGT)
        draw.polygon([(x + 38, y - 10), (x + 48, y - 20), (x + 32, y - 16)], fill=C_PAPER_LGT)
        draw.polygon([(x - 8, y - 32), (x, y - 44), (x + 8, y - 32)], fill=C_PAPER_LGT)
        draw.line([x, y - 42, x, y - 34], fill=C_BLOOD, width=1)
    elif frame == 2:
        # 휘두르기 여운
        draw.polygon([(x - 28, y - 12), (x, y - 4), (x - 22, y + 18)], fill=C_PAPER_MID)
        draw.polygon([(x + 28, y - 12), (x, y - 4), (x + 22, y + 18)], fill=C_PAPER_MID)
        draw.rectangle([x - 18, y - 12, x + 18, y + 16], fill=C_BINDING_MID)


def draw_death_frame(draw: ImageDraw.ImageDraw, x: int, y: int, frame: int) -> None:
    """제본 폭발 및 종이 산화."""
    if frame == 0:
        # 커버 균열 + 핏빛 방출
        draw.rectangle([x - 24, y - 14, x + 24, y + 18], fill=C_OUTLINE)
        draw.rectangle([x - 22, y - 12, x + 22, y + 16], fill=C_BINDING_DARK)
        draw.line([x - 20, y - 10, x + 20, y + 14], fill=C_BLOOD, width=2)
        draw.line([x + 18, y - 10, x - 18, y + 14], fill=C_BLOOD, width=2)
    elif frame == 1:
        # 사방으로 흩날리는 낱장 페이지들
        draw.polygon([(x - 34, y - 28), (x - 20, y - 34), (x - 24, y - 18)], fill=C_PAPER_LGT)
        draw.polygon([(x + 20, y - 32), (x + 36, y - 24), (x + 24, y - 16)], fill=C_PAPER_LGT)
        draw.polygon([(x - 36, y + 4), (x - 24, y + 16), (x - 18, y + 2)], fill=C_PAPER_MID)
        draw.polygon([(x + 18, y + 4), (x + 32, y + 14), (x + 36, y + 2)], fill=C_PAPER_MID)
        # 찢겨나간 커버 조각
        draw.rectangle([x - 10, y - 8, x + 10, y + 8], fill=C_BINDING_DARK)
    elif frame == 2:
        # 바닥에 흩어진 타버린 종이 재와 핏자국
        draw.rectangle([x - 28, y + 20, x - 14, y + 26], fill=C_PAPER_DARK)
        draw.rectangle([x + 10, y + 18, x + 26, y + 24], fill=C_PAPER_DARK)
        draw.line([x - 8, y + 22, x + 8, y + 22], fill=C_BLOOD_DARK, width=2)


def generate_flying_thesis_sheet() -> None:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    row_specs = [
        (0, "walk", 4),
        (1, "attack", 3),
        (2, "death", 3),
    ]

    for row_idx, anim, valid_count in row_specs:
        for col_idx in range(valid_count):
            cx = col_idx * CELL_W + CELL_W // 2
            cy = row_idx * CELL_H + CELL_H // 2
            draw_thesis_cell(draw, cx, cy, anim, col_idx)

    img.save(OUT_PATH, "PNG")
    print(f"[generate_flying_thesis] 완료: {OUT_PATH} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    generate_flying_thesis_sheet()
