#!/usr/bin/env python3
"""식당 아가씨(npc_cafeteria_girl) 리마스터 3표정 포트레이트 생성기.

규격: 768x256 PNG (256x256 셀 3개: 1 normal, 2 worried, 3 determined)
"""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT_PATH = ROOT / "assets" / "raw" / "llm" / "10_submitted" / "portraits" / "npc_cafeteria_girl_v1.png"

CELL = 256
SHEET_W = CELL * 3
SHEET_H = CELL

# 팔레트
C_OUTLINE = (12, 10, 36, 255)       # 짙은 남색 외곽선
C_HAIR_DARK = (160, 110, 20, 255)   # 금발 섀도우
C_HAIR_MID = (230, 180, 40, 255)    # 금발 중간톤
C_HAIR_LGT = (255, 230, 100, 255)   # 금발 하이라이트

C_SKIN_SHD = (210, 130, 105, 255)   # 피부 그림자 (남보라/웜톤 섀도우)
C_SKIN_MID = (250, 195, 165, 255)   # 피부 베이스
C_SKIN_LGT = (255, 225, 205, 255)   # 피부 하이라이트

C_EYE_BLU = (40, 100, 210, 255)     # 벽안 눈동자
C_EYE_WHT = (250, 250, 255, 255)
C_LIP_ROSE = (230, 90, 110, 255)    # 입술

C_DRESS_DARK = (100, 40, 140, 255)  # 라벤더 드레스 섀도우
C_DRESS_MID = (170, 80, 210, 255)   # 라벤더 드레스 중간톤
C_DRESS_LGT = (220, 150, 245, 255)  # 드레스 하이라이트


def draw_cafeteria_girl_cell(draw: ImageDraw.ImageDraw, offset_x: int, expression: str) -> None:
    cx = offset_x + 128
    cy = 124

    # 1) 뒤쪽 풍성한 웨이브 금발
    hair_back_poly = [
        (cx - 65, cy - 30), (cx - 75, cy + 50), (cx - 60, cy + 95), (cx - 40, cy + 90),
        (cx + 40, cy + 90), (cx + 60, cy + 95), (cx + 75, cy + 50), (cx + 65, cy - 30),
        (cx + 45, cy - 75), (cx - 45, cy - 75)
    ]
    draw.polygon(hair_back_poly, fill=C_OUTLINE)
    draw.polygon([(x, y) for (x, y) in hair_back_poly[1:-1]], fill=C_HAIR_DARK)

    # 2) 목 및 어깨 / 쇄골 / 바스트업 (Y 최대 250으로 제한하여 2px 테두리 여백 확보)
    body_poly = [
        (cx - 30, cy + 45), (cx - 70, cy + 115), (cx - 50, cy + 125),
        (cx + 50, cy + 125), (cx + 70, cy + 115), (cx + 30, cy + 45)
    ]
    draw.polygon(body_poly, fill=C_OUTLINE)
    draw.polygon([(cx - 28, cy + 45), (cx - 66, cy + 114), (cx - 48, cy + 123),
                  (cx + 48, cy + 123), (cx + 66, cy + 114), (cx + 28, cy + 45)], fill=C_SKIN_MID)
    # 목 그림자
    draw.polygon([(cx - 24, cy + 46), (cx + 24, cy + 46), (cx + 18, cy + 70), (cx - 18, cy + 70)], fill=C_SKIN_SHD)

    # 3) 라벤더 탑 드레스
    dress_poly = [
        (cx - 55, cy + 85), (cx - 25, cy + 95), (cx, cy + 85), (cx + 25, cy + 95), (cx + 55, cy + 85),
        (cx + 48, cy + 125), (cx - 48, cy + 125)
    ]
    draw.polygon(dress_poly, fill=C_OUTLINE)
    draw.polygon([(x, y) for (x, y) in dress_poly], fill=C_DRESS_DARK)
    draw.polygon([(cx - 48, cy + 88), (cx - 20, cy + 96), (cx, cy + 88), (cx + 20, cy + 96), (cx + 48, cy + 88),
                  (cx + 44, cy + 123), (cx - 44, cy + 123)], fill=C_DRESS_MID)
    draw.line([cx - 36, cy + 92, cx - 15, cy + 98], fill=C_DRESS_LGT, width=2)
    draw.line([cx + 15, cy + 98, cx + 36, cy + 92], fill=C_DRESS_LGT, width=2)

    # 4) 얼굴 윤곽
    face_poly = [
        (cx - 38, cy - 35), (cx - 40, cy + 10), (cx - 30, cy + 38), (cx, cy + 56),
        (cx + 30, cy + 38), (cx + 40, cy + 10), (cx + 38, cy - 35)
    ]
    draw.polygon(face_poly, fill=C_OUTLINE)
    draw.polygon([(cx - 36, cy - 33), (cx - 38, cy + 10), (cx - 28, cy + 36), (cx, cy + 54),
                  (cx + 28, cy + 36), (cx + 38, cy + 10), (cx + 36, cy - 33)], fill=C_SKIN_MID)
    # 볼터치 웜톤
    draw.ellipse([cx - 32, cy + 12, cx - 18, cy + 24], fill=C_SKIN_SHD)
    draw.ellipse([cx + 18, cy + 12, cx + 32, cy + 24], fill=C_SKIN_SHD)

    # 5) 앞머리 (풍성한 90s 볼륨 헤어)
    draw.polygon([(cx - 48, cy - 40), (cx - 35, cy - 8), (cx - 20, cy - 25), (cx, cy - 5),
                  (cx + 20, cy - 25), (cx + 35, cy - 8), (cx + 48, cy - 40), (cx, cy - 70)], fill=C_OUTLINE)
    draw.polygon([(cx - 45, cy - 40), (cx - 33, cy - 10), (cx - 18, cy - 26), (cx, cy - 7),
                  (cx + 18, cy - 26), (cx + 33, cy - 10), (cx + 45, cy - 40), (cx, cy - 68)], fill=C_HAIR_MID)
    draw.line([cx - 25, cy - 45, cx - 10, cy - 30], fill=C_HAIR_LGT, width=3)
    draw.line([cx + 10, cy - 30, cx + 25, cy - 45], fill=C_HAIR_LGT, width=3)

    # 6) 코
    draw.line([cx, cy + 14, cx + 2, cy + 20], fill=C_OUTLINE, width=1)
    draw.point([cx - 1, cy + 20], fill=C_SKIN_SHD)

    # 7) 표정 분기 (눈, 눈썹, 입)
    if expression == "normal":
        draw.line([cx - 28, cy - 6, cx - 12, cy - 8], fill=C_OUTLINE, width=2)
        draw.line([cx + 12, cy - 8, cx + 28, cy - 6], fill=C_OUTLINE, width=2)
        draw_eye(draw, cx - 20, cy + 4, False)
        draw_eye(draw, cx + 20, cy + 4, True)
        draw.polygon([(cx - 12, cy + 32), (cx + 12, cy + 32), (cx, cy + 40)], fill=C_OUTLINE)
        draw.polygon([(cx - 10, cy + 33), (cx + 10, cy + 33), (cx, cy + 38)], fill=C_LIP_ROSE)
        draw.line([cx - 6, cy + 34, cx + 6, cy + 34], fill=C_EYE_WHT, width=1)

    elif expression == "worried":
        draw.line([cx - 28, cy - 9, cx - 12, cy - 5], fill=C_OUTLINE, width=2)
        draw.line([cx + 12, cy - 5, cx + 28, cy - 9], fill=C_OUTLINE, width=2)
        draw_eye(draw, cx - 20, cy + 5, False)
        draw_eye(draw, cx + 20, cy + 5, True)
        draw.ellipse([cx - 6, cy + 32, cx + 6, cy + 40], fill=C_OUTLINE)
        draw.ellipse([cx - 4, cy + 33, cx + 4, cy + 39], fill=C_LIP_ROSE)

    elif expression == "determined":
        draw.line([cx - 28, cy - 5, cx - 12, cy - 10], fill=C_OUTLINE, width=2)
        draw.line([cx + 12, cy - 10, cx + 28, cy - 5], fill=C_OUTLINE, width=2)
        draw_eye(draw, cx - 20, cy + 3, False)
        draw_eye(draw, cx + 20, cy + 3, True)
        draw.line([cx - 10, cy + 35, cx + 10, cy + 35], fill=C_OUTLINE, width=2)
        draw.line([cx - 6, cy + 36, cx + 6, cy + 36], fill=C_LIP_ROSE, width=1)


def draw_eye(draw: ImageDraw.ImageDraw, ex: int, ey: int, is_right: bool) -> None:
    draw.polygon([(ex - 8, ey), (ex, ey - 5), (ex + 8, ey), (ex, ey + 4)], fill=C_OUTLINE)
    draw.polygon([(ex - 6, ey), (ex, ey - 4), (ex + 6, ey), (ex, ey + 3)], fill=C_EYE_WHT)
    draw.ellipse([ex - 4, ey - 4, ex + 4, ey + 3], fill=C_EYE_BLU)
    draw.ellipse([ex - 2, ey - 2, ex + 2, ey + 2], fill=C_OUTLINE)
    draw.point([ex - 2, ey - 2], fill=(255, 255, 255, 255))
    draw.line([ex - 7, ey - 3, ex + 7, ey - 3], fill=C_OUTLINE, width=2)


def generate_cafeteria_girl_sheet() -> None:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    expressions = ["normal", "worried", "determined"]
    for idx, expr in enumerate(expressions):
        draw_cafeteria_girl_cell(draw, idx * CELL, expr)

    # 2px 테두리 마진 영역을 완전히 비워 키잉 통과 보장
    for i in range(3):
        x0 = i * CELL
        x1 = (i + 1) * CELL
        # 상하 2줄 클리어
        for y in (0, 1, CELL - 2, CELL - 1):
            for x in range(x0, x1):
                img.putpixel((x, y), (0, 0, 0, 0))
        # 좌우 2열 클리어
        for x in (x0, x0 + 1, x1 - 2, x1 - 1):
            for y in range(CELL):
                img.putpixel((x, y), (0, 0, 0, 0))

    img.save(OUT_PATH, "PNG")
    print(f"[generate_cafeteria_girl] 완료: {OUT_PATH} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    generate_cafeteria_girl_sheet()
