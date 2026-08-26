#!/usr/bin/env python3
"""전체 16종 NPC/교수 리마스터 3표정 포트레이트 생성기.

규격: 768x256 PNG (256x256 셀 3개: 1 normal, 2 worried/special, 3 determined/special)
출력: assets/raw/llm/10_submitted/portraits/<id>_v1.png
"""
from __future__ import annotations

import math
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "raw" / "llm" / "10_submitted" / "portraits"
OUT_DIR.mkdir(parents=True, exist_ok=True)

CELL = 256
SHEET_W = CELL * 3
SHEET_H = CELL

# 공통 마스터 팔레트 색상
C_OUTLINE = (12, 10, 36, 255)       # 짙은 남색 외곽선
C_WHITE = (248, 248, 255, 255)

# 피부 톤들
C_SKIN_LIGHT_SHD = (210, 130, 105, 255)
C_SKIN_LIGHT_MID = (250, 195, 165, 255)
C_SKIN_LIGHT_HIL = (255, 225, 205, 255)

C_SKIN_AGED_SHD = (160, 110, 85, 255)
C_SKIN_AGED_MID = (220, 175, 140, 255)
C_SKIN_AGED_HIL = (240, 205, 175, 255)

# 머리 색상들
C_HAIR_BLK_SHD = (16, 20, 36, 255)
C_HAIR_BLK_MID = (36, 44, 70, 255)
C_HAIR_BLK_HIL = (70, 85, 125, 255)

C_HAIR_BRN_SHD = (65, 35, 20, 255)
C_HAIR_BRN_MID = (120, 75, 45, 255)
C_HAIR_BRN_HIL = (180, 125, 80, 255)

C_HAIR_GRY_SHD = (80, 85, 100, 255)
C_HAIR_GRY_MID = (150, 155, 170, 255)
C_HAIR_GRY_HIL = (215, 220, 230, 255)

C_HAIR_GLD_SHD = (160, 110, 20, 255)
C_HAIR_GLD_MID = (230, 180, 40, 255)
C_HAIR_GLD_HIL = (255, 230, 100, 255)

# 의상 색상들
C_LAB_COAT = (235, 240, 250, 255)
C_LAB_COAT_SHD = (160, 175, 200, 255)
C_SUIT_NAVY = (24, 36, 75, 255)
C_SUIT_MID = (44, 65, 120, 255)
C_VEST_GRN = (35, 75, 45, 255)
C_SHIRT_CHECK = (180, 50, 50, 255)
C_UNIFORM_BLU = (28, 48, 90, 255)


def clear_margins(img: Image.Image) -> None:
    """테두리 2px 마진 영역을 완전 투명으로 클리어하여 키잉 100% 보장."""
    for i in range(3):
        x0 = i * CELL
        x1 = (i + 1) * CELL
        for y in (0, 1, CELL - 2, CELL - 1):
            for x in range(x0, x1):
                img.putpixel((x, y), (0, 0, 0, 0))
        for x in (x0, x0 + 1, x1 - 2, x1 - 1):
            for y in range(CELL):
                img.putpixel((x, y), (0, 0, 0, 0))


def render_base_bust(draw: ImageDraw.ImageDraw, cx: int, cy: int, skin_mid: tuple, skin_shd: tuple,
                     coat_color: tuple, coat_shd: tuple, collar_color: tuple = C_WHITE) -> None:
    # 어깨 및 목
    body_poly = [(cx - 28, cy + 45), (cx - 70, cy + 115), (cx - 50, cy + 125),
                 (cx + 50, cy + 125), (cx + 70, cy + 115), (cx + 30, cy + 45)]
    draw.polygon(body_poly, fill=C_OUTLINE)
    draw.polygon([(cx - 26, cy + 45), (cx - 66, cy + 114), (cx - 48, cy + 123),
                  (cx + 48, cy + 123), (cx + 66, cy + 114), (cx + 28, cy + 45)], fill=skin_mid)
    draw.polygon([(cx - 22, cy + 46), (cx + 22, cy + 46), (cx + 16, cy + 72), (cx - 16, cy + 72)], fill=skin_shd)

    # 옷/의상
    draw.polygon([(cx - 65, cy + 85), (cx - 30, cy + 85), (cx, cy + 115), (cx + 30, cy + 85), (cx + 65, cy + 85),
                  (cx + 68, cy + 125), (cx - 68, cy + 125)], fill=C_OUTLINE)
    draw.polygon([(cx - 62, cy + 88), (cx - 28, cy + 88), (cx, cy + 112), (cx + 28, cy + 88), (cx + 62, cy + 88),
                  (cx + 65, cy + 123), (cx - 65, cy + 123)], fill=coat_color)
    # 칼라
    draw.polygon([(cx - 28, cy + 85), (cx, cy + 112), (cx - 12, cy + 85)], fill=collar_color)
    draw.polygon([(cx + 28, cy + 85), (cx, cy + 112), (cx + 12, cy + 85)], fill=collar_color)


def render_face_base(draw: ImageDraw.ImageDraw, cx: int, cy: int, skin_mid: tuple, skin_shd: tuple,
                     jaw_roundness: int = 38) -> None:
    face_poly = [
        (cx - 38, cy - 35), (cx - 40, cy + 10), (cx - jaw_roundness, cy + 38), (cx, cy + 54),
        (cx + jaw_roundness, cy + 38), (cx + 40, cy + 10), (cx + 38, cy - 35)
    ]
    draw.polygon(face_poly, fill=C_OUTLINE)
    draw.polygon([(cx - 36, cy - 33), (cx - 38, cy + 10), (cx - jaw_roundness + 2, cy + 36), (cx, cy + 52),
                  (cx + jaw_roundness - 2, cy + 36), (cx + 38, cy + 10), (cx + 36, cy - 33)], fill=skin_mid)
    draw.line([cx, cy + 14, cx + 2, cy + 20], fill=C_OUTLINE, width=1)
    draw.point([cx - 1, cy + 20], fill=skin_shd)


def draw_glasses(draw: ImageDraw.ImageDraw, cx: int, cy: int, color: tuple = C_OUTLINE) -> None:
    # 좌우 안경알
    draw.rectangle([cx - 28, cy - 2, cx - 10, cy + 12], outline=color, width=2)
    draw.rectangle([cx + 10, cy - 2, cx + 28, cy + 12], outline=color, width=2)
    draw.line([cx - 10, cy + 4, cx + 10, cy + 4], fill=color, width=2)
    # 안경 반사광
    draw.line([cx - 24, cy + 1, cx - 16, cy + 9], fill=C_WHITE, width=1)
    draw.line([cx + 14, cy + 1, cx + 22, cy + 9], fill=C_WHITE, width=1)


# ==============================================================================
# 각 NPC별 렌더러 함수
# ==============================================================================

def render_npc_cafeteria_girl(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    # 금발 백헤어
    hair_back = [(cx - 65, cy - 30), (cx - 75, cy + 50), (cx - 60, cy + 95), (cx + 60, cy + 95), (cx + 75, cy + 50), (cx + 65, cy - 30), (cx, cy - 75)]
    draw.polygon(hair_back, fill=C_HAIR_GLD_SHD)
    render_base_bust(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, (170, 80, 210, 255), (100, 40, 140, 255), C_WHITE)
    render_face_base(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, 30)
    # 앞머리
    draw.polygon([(cx - 45, cy - 40), (cx - 33, cy - 10), (cx - 18, cy - 26), (cx, cy - 7),
                  (cx + 18, cy - 26), (cx + 33, cy - 10), (cx + 45, cy - 40), (cx, cy - 68)], fill=C_HAIR_GLD_MID)
    # 머리 수건
    draw.polygon([(cx - 42, cy - 50), (cx + 42, cy - 50), (cx + 38, cy - 30), (cx - 38, cy - 30)], fill=(240, 180, 200, 255))
    draw.rectangle([cx - 40, cy - 32, cx + 40, cy - 30], fill=C_OUTLINE)

    # 눈/입 표정
    if expr == "worried":
        draw.line([cx - 26, cy - 8, cx - 12, cy - 4], fill=C_OUTLINE, width=2)
        draw.line([cx + 12, cy - 4, cx + 26, cy - 8], fill=C_OUTLINE, width=2)
        draw.ellipse([cx - 4, cy + 34, cx + 4, cy + 40], fill=(230, 90, 110, 255))
    elif expr == "determined":
        draw.line([cx - 26, cy - 4, cx - 12, cy - 9], fill=C_OUTLINE, width=2)
        draw.line([cx + 12, cy - 9, cx + 26, cy - 4], fill=C_OUTLINE, width=2)
        draw.line([cx - 10, cy + 36, cx + 10, cy + 36], fill=C_OUTLINE, width=2)
    else: # normal
        draw.line([cx - 26, cy - 6, cx - 12, cy - 8], fill=C_OUTLINE, width=2)
        draw.line([cx + 12, cy - 8, cx + 26, cy - 6], fill=C_OUTLINE, width=2)
        draw.polygon([(cx - 10, cy + 33), (cx + 10, cy + 33), (cx, cy + 40)], fill=(230, 90, 110, 255))


def render_npc_friend_jeongsun(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    # 짧은 흑발
    draw.ellipse([cx - 48, cy - 65, cx + 48, cy + 10], fill=C_HAIR_BLK_MID)
    render_base_bust(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, C_SHIRT_CHECK, (110, 30, 30, 255))
    render_face_base(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, 34)
    # 체크 셔츠 무늬 선
    draw.line([cx - 50, cy + 100, cx + 50, cy + 100], fill=C_WHITE, width=1)
    draw.line([cx - 20, cy + 85, cx - 20, cy + 123], fill=C_WHITE, width=1)
    draw.line([cx + 20, cy + 85, cx + 20, cy + 123], fill=C_WHITE, width=1)
    # 앞머리
    draw.polygon([(cx - 40, cy - 40), (cx - 20, cy - 15), (cx, cy - 25), (cx + 20, cy - 15), (cx + 40, cy - 40)], fill=C_HAIR_BLK_SHD)
    draw_glasses(draw, cx, cy, (20, 20, 30, 255))
    # 표정
    if expr == "worried":
        draw.line([cx - 8, cy + 35, cx + 8, cy + 33], fill=C_OUTLINE, width=2)
    elif expr == "determined":
        draw.line([cx - 10, cy + 34, cx + 10, cy + 34], fill=C_OUTLINE, width=2)
    else:
        draw.line([cx - 10, cy + 33, cx + 10, cy + 36], fill=C_OUTLINE, width=2)


def render_npc_girl(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    # 단발 갈색 머리
    draw.polygon([(cx - 55, cy - 50), (cx + 55, cy - 50), (cx + 60, cy + 60), (cx + 40, cy + 65),
                  (cx - 40, cy + 65), (cx - 60, cy + 60)], fill=C_HAIR_BRN_MID)
    render_base_bust(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, (50, 110, 160, 255), (30, 70, 110, 255))
    render_face_base(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, 28)
    # 볼터치
    draw.ellipse([cx - 30, cy + 12, cx - 18, cy + 22], fill=C_SKIN_LIGHT_SHD)
    draw.ellipse([cx + 18, cy + 12, cx + 30, cy + 22], fill=C_SKIN_LIGHT_SHD)
    # 눈/입
    if expr == "worried":
        draw.ellipse([cx - 4, cy + 34, cx + 4, cy + 40], fill=(210, 70, 90, 255))
    elif expr == "determined":
        draw.line([cx - 8, cy + 36, cx + 8, cy + 36], fill=C_OUTLINE, width=2)
    else:
        draw.polygon([(cx - 8, cy + 33), (cx + 8, cy + 33), (cx, cy + 38)], fill=(210, 70, 90, 255))


def render_npc_guard(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    # 든든한 경비원 노인 (경비 모자 + 턱수염)
    render_base_bust(draw, cx, cy, C_SKIN_AGED_MID, C_SKIN_AGED_SHD, C_UNIFORM_BLU, (16, 28, 56, 255))
    render_face_base(draw, cx, cy, C_SKIN_AGED_MID, C_SKIN_AGED_SHD, 40)
    # 흰 콧수염
    draw.polygon([(cx - 20, cy + 28), (cx, cy + 24), (cx + 20, cy + 28), (cx + 15, cy + 34), (cx - 15, cy + 34)], fill=C_HAIR_GRY_MID)
    # 경비 모자
    draw.rectangle([cx - 48, cy - 60, cx + 48, cy - 35], fill=C_UNIFORM_BLU)
    draw.polygon([(cx - 56, cy - 35), (cx + 56, cy - 35), (cx + 45, cy - 25), (cx - 45, cy - 25)], fill=C_OUTLINE)
    draw.ellipse([cx - 6, cy - 50, cx + 6, cy - 40], fill=(240, 200, 40, 255)) # 금빛 배지


def render_npc_man1_oxx(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    draw.ellipse([cx - 44, cy - 60, cx + 44, cy + 5], fill=C_HAIR_BLK_MID)
    render_base_bust(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, C_LAB_COAT, C_LAB_COAT_SHD)
    render_face_base(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, 32)
    draw_glasses(draw, cx, cy, (40, 40, 50, 255))
    # 볼에 밴드
    draw.rectangle([cx + 18, cy + 18, cx + 28, cy + 24], fill=(235, 215, 180, 255))


def render_npc_quizman(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    # 보라색 망토 후드 + 거대 물음표 (?)
    draw.ellipse([cx - 52, cy - 65, cx + 52, cy + 20], fill=(70, 30, 110, 255))
    render_base_bust(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, (90, 40, 140, 255), (50, 20, 80, 255))
    render_face_base(draw, cx, cy, (20, 15, 35, 255), (10, 8, 20, 255), 36) # 어두운 그림자 얼굴
    # 빛나는 황금 물음표 '?'
    draw.arc([cx - 14, cy - 20, cx + 14, cy + 4], 180, 360, fill=(255, 220, 40, 255), width=4)
    draw.line([cx, cy + 4, cx, cy + 14], fill=(255, 220, 40, 255), width=4)
    draw.ellipse([cx - 3, cy + 20, cx + 3, cy + 26], fill=(255, 220, 40, 255))


def render_npc_student_council(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    draw.ellipse([cx - 46, cy - 65, cx + 46, cy + 10], fill=(50, 30, 25, 255))
    render_base_bust(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, C_SUIT_NAVY, (14, 20, 45, 255))
    # 붉은 넥타이
    draw.polygon([(cx - 5, cy + 88), (cx + 5, cy + 88), (cx + 8, cy + 123), (cx - 8, cy + 123)], fill=(180, 30, 40, 255))
    render_face_base(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, 30)
    # 다크서클
    draw.line([cx - 24, cy + 15, cx - 12, cy + 15], fill=C_SKIN_LIGHT_SHD, width=2)
    draw.line([cx + 12, cy + 15, cx + 24, cy + 15], fill=C_SKIN_LIGHT_SHD, width=2)


def render_npc_tutor_dumb(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    render_base_bust(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, (70, 80, 95, 255), (40, 45, 55, 255))
    render_face_base(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, 30)
    # 니트 비니 모자
    draw.ellipse([cx - 46, cy - 65, cx + 46, cy - 20], fill=(160, 60, 45, 255))
    draw.rectangle([cx - 44, cy - 35, cx + 44, cy - 22], fill=(120, 40, 30, 255))
    # 강아지 처진 눈
    draw.line([cx - 24, cy + 4, cx - 12, cy + 8], fill=C_OUTLINE, width=2)
    draw.line([cx + 12, cy + 8, cx + 24, cy + 4], fill=C_OUTLINE, width=2)


def render_prof_chem(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    # 흰머리 희끗한 50대 화공과 교수
    draw.ellipse([cx - 48, cy - 65, cx + 48, cy + 10], fill=C_HAIR_GRY_MID)
    render_base_bust(draw, cx, cy, C_SKIN_AGED_MID, C_SKIN_AGED_SHD, C_LAB_COAT, C_LAB_COAT_SHD)
    # 목에 건 보안경
    draw.ellipse([cx - 25, cy + 60, cx + 25, cy + 76], outline=(50, 180, 220, 255), width=3)
    render_face_base(draw, cx, cy, C_SKIN_AGED_MID, C_SKIN_AGED_SHD, 36)
    draw_glasses(draw, cx, cy, (140, 140, 150, 255))


def render_prof_hong(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    # 신경질적인 중년 홍춘발 교수 (삐뚤어진 넥타이)
    draw.ellipse([cx - 44, cy - 60, cx + 44, cy + 5], fill=C_HAIR_BLK_MID)
    render_base_bust(draw, cx, cy, C_SKIN_AGED_MID, C_SKIN_AGED_SHD, (90, 80, 70, 255), (50, 45, 40, 255))
    # 삐뚤어진 노란 넥타이
    draw.polygon([(cx - 2, cy + 88), (cx + 8, cy + 88), (cx + 14, cy + 123), (cx + 2, cy + 123)], fill=(220, 160, 30, 255))
    render_face_base(draw, cx, cy, C_SKIN_AGED_MID, C_SKIN_AGED_SHD, 32)
    # 치켜올라간 눈썹
    draw.line([cx - 24, cy - 8, cx - 10, cy - 14], fill=C_OUTLINE, width=2)
    draw.line([cx + 10, cy - 14, cx + 24, cy - 8], fill=C_OUTLINE, width=2)


def render_prof_hwang(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    # 위엄 있는 올백 백발 노박사
    draw.ellipse([cx - 50, cy - 70, cx + 50, cy + 15], fill=C_HAIR_GRY_HIL)
    render_base_bust(draw, cx, cy, C_SKIN_AGED_MID, C_SKIN_AGED_SHD, (50, 40, 60, 255), (30, 25, 40, 255))
    render_face_base(draw, cx, cy, C_SKIN_AGED_MID, C_SKIN_AGED_SHD, 38)
    # 풍성한 턱수염
    draw.polygon([(cx - 30, cy + 36), (cx, cy + 62), (cx + 30, cy + 36), (cx + 20, cy + 20), (cx - 20, cy + 20)], fill=C_HAIR_GRY_MID)


def render_prof_kim(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    # 바쁜 인상의 김경선 교수 (서류 파일)
    draw.ellipse([cx - 44, cy - 60, cx + 44, cy + 5], fill=C_HAIR_BLK_MID)
    render_base_bust(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, (60, 100, 80, 255), (30, 60, 45, 255))
    render_face_base(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, 34)
    # 땀방울 연출
    draw.ellipse([cx + 28, cy - 15, cx + 34, cy - 7], fill=(100, 200, 255, 255))


def render_prof_mo(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    # 5층 통제실 연구책임자 모교수 (서늘한 카리스마, 금테 안경)
    draw.ellipse([cx - 46, cy - 68, cx + 46, cy + 10], fill=(20, 24, 40, 255))
    render_base_bust(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, (20, 20, 30, 255), (10, 10, 18, 255))
    render_face_base(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, 32)
    # 날카로운 금테 안경
    draw_glasses(draw, cx, cy, (230, 190, 50, 255))


def render_prof_na(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    # 은퇴 노교수 (니트 조끼, 콜록거림)
    draw.ellipse([cx - 46, cy - 65, cx + 46, cy + 15], fill=C_HAIR_GRY_MID)
    render_base_bust(draw, cx, cy, C_SKIN_AGED_MID, C_SKIN_AGED_SHD, (120, 90, 60, 255), (70, 50, 35, 255))
    render_face_base(draw, cx, cy, C_SKIN_AGED_MID, C_SKIN_AGED_SHD, 36)
    # 목도리
    draw.rectangle([cx - 24, cy + 46, cx + 24, cy + 62], fill=(160, 40, 40, 255))


def render_prof_nam(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    # 술병 든 반쯤 감긴 눈의 남앵골 교수
    draw.ellipse([cx - 46, cy - 60, cx + 46, cy + 10], fill=C_HAIR_GRY_MID)
    render_base_bust(draw, cx, cy, C_SKIN_AGED_MID, C_SKIN_AGED_SHD, (60, 70, 85, 255), (35, 40, 50, 255))
    render_face_base(draw, cx, cy, C_SKIN_AGED_MID, C_SKIN_AGED_SHD, 38)
    # 붉은 코
    draw.ellipse([cx - 4, cy + 15, cx + 4, cy + 22], fill=(220, 80, 80, 255))
    # 실눈
    draw.line([cx - 24, cy + 5, cx - 10, cy + 5], fill=C_OUTLINE, width=2)
    draw.line([cx + 10, cy + 5, cx + 24, cy + 5], fill=C_OUTLINE, width=2)


def render_prof_quan(draw: ImageDraw.ImageDraw, ox: int, expr: str) -> None:
    cx, cy = ox + 128, 124
    # 소심한 권영칠 교수 (짜장면 그릇 옆)
    draw.ellipse([cx - 42, cy - 55, cx + 42, cy + 5], fill=C_HAIR_BLK_MID)
    render_base_bust(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, (140, 130, 110, 255), (80, 75, 60, 255))
    render_face_base(draw, cx, cy, C_SKIN_LIGHT_MID, C_SKIN_LIGHT_SHD, 32)
    # 둥근 안경
    draw.ellipse([cx - 26, cy - 2, cx - 8, cy + 14], outline=C_OUTLINE, width=2)
    draw.ellipse([cx + 8, cy - 2, cx + 26, cy + 14], outline=C_OUTLINE, width=2)
    draw.line([cx - 8, cy + 6, cx + 8, cy + 6], fill=C_OUTLINE, width=2)


PORTRAIT_RENDERERS = {
    "npc_cafeteria_girl": render_npc_cafeteria_girl,
    "npc_friend_jeongsun": render_npc_friend_jeongsun,
    "npc_girl": render_npc_girl,
    "npc_guard": render_npc_guard,
    "npc_man1_oxx": render_npc_man1_oxx,
    "npc_quizman": render_npc_quizman,
    "npc_student_council": render_npc_student_council,
    "npc_tutor_dumb": render_npc_tutor_dumb,
    "prof_chem": render_prof_chem,
    "prof_hong": render_prof_hong,
    "prof_hwang": render_prof_hwang,
    "prof_kim": render_prof_kim,
    "prof_mo": render_prof_mo,
    "prof_na": render_prof_na,
    "prof_nam": render_prof_nam,
    "prof_quan": render_prof_quan,
}


def generate_all_portraits() -> None:
    expressions = ["normal", "worried", "determined"]
    for pid, fn in PORTRAIT_RENDERERS.items():
        img = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)

        for idx, expr in enumerate(expressions):
            fn(draw, idx * CELL, expr)

        clear_margins(img)
        out_file = OUT_DIR / f"{pid}_v1.png"
        img.save(out_file, "PNG")
        print(f"[portrait] 생성 완료: {out_file.name}")


if __name__ == "__main__":
    generate_all_portraits()
