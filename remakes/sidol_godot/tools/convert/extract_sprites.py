"""원작 스프라이트 일괄 추출 - assets/raw/llm/00_reference/ 생성.

originals_ref/bmp_spr/<그룹>/frame_*.bmp (320x200 풀프레임)에서:
  1) 배경(경계색, flood) 제거 -> 투명 PNG 프레임 단위 저장 (내부 검정은 보존 -
     LLM이 캐릭터 디테일로 인식해야 하므로)
  2) 동일 프레임 해시 중복 제거
  3) 그룹별 컨택트 시트(마젠타 배경, 셀 128 표준, 내용 맞춤 축소) 생성

numpy 벡터화 flood-fill 로 935프레임을 수십 초 내 처리.
사용: python tools/convert/extract_sprites.py [그룹명 ...]  (생략 시 전체)
"""
from __future__ import annotations
import hashlib
import os
import sys
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
REF = os.path.join(ROOT, "assets", "originals_ref", "bmp_spr")
OUT = os.path.join(ROOT, "assets", "raw", "llm", "00_reference")
CELL = 128


def remove_bg_np(img: Image.Image) -> Image.Image:
    """경계 연결 배경 제거(numpy 벡터화). **게임에 들어갈 에셋에는 쓰지 말 것.**

    2026-09-07 실측: 원작 팔레트에는 RGB(0,0,0)인 인덱스가 9개다 — 투명 키인 0과
    외곽선·그림자로 쓰이는 224~231. 알파가 없는 bmp_spr RGB 중간물 위에서는 이 둘을
    구별할 수 없어서, 이 flood-fill은 **배경에 닿은 외곽선을 통째로 먹고**(캐릭터 시트
    15종 155,840px · 아이콘 35종 36,939px 손실) 반대로 스프라이트에 둘러싸인 배경은
    닿지 못해 검은 얼룩으로 남긴다(각각 4,864px · 9,465px).

    그래서 `migrate_original_sheets.py`와 `migrate_item_icons.py`는 이 함수를 버리고
    원작 SPR을 직접 읽는다(`spr_extract.parse_spr` — 팔레트 인덱스 0만 alpha 0).
    이 함수는 assets/raw/llm 프롬프트용 참고 이미지 생성에만 남는다. 그쪽 산출물도
    외곽선이 얇아진 상태이므로 참고 이미지를 다시 뽑을 일이 생기면 parse_spr로 옮길 것.
    관문: tools/dev/spr_alpha_check.py
    """
    a = np.asarray(img.convert("RGBA")).copy()
    h, w = a.shape[:2]
    border_colors = np.concatenate([
        a[0, :, :3], a[-1, :, :3], a[:, 0, :3], a[:, -1, :3]])
    bg = np.zeros(3)
    vals, counts = np.unique(border_colors, axis=0, return_counts=True)
    bg = vals[counts.argmax()]
    is_bg = (np.abs(a[:, :, :3].astype(int) - bg.astype(int)).sum(axis=2) < 30)
    reach = np.zeros((h, w), dtype=bool)
    reach[0, :] = is_bg[0, :]
    reach[-1, :] = is_bg[-1, :]
    reach[:, 0] |= is_bg[:, 0]
    reach[:, -1] |= is_bg[:, -1]
    while True:
        prev = reach
        grow = (np.roll(reach, 1, 0) | np.roll(reach, -1, 0) |
                np.roll(reach, 1, 1) | np.roll(reach, -1, 1))
        reach = (reach | grow) & is_bg
        if np.array_equal(reach, prev):
            break
    a[reach, 3] = 0
    return Image.fromarray(a)


def content_bbox(img: Image.Image):
    bbox = img.getchannel("A").getbbox()
    if not bbox:
        return None
    return bbox


def fit_cell(img: Image.Image, margin: int = 4) -> Image.Image:
    """내용을 128 셀에 맞춰 nearest 축소(확대는 하지 않음), 하단 중앙 정렬."""
    bbox = content_bbox(img)
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    if not bbox:
        return cell
    content = img.crop(bbox)
    max_side = CELL - margin * 2
    scale = min(1.0, max_side / content.width, max_side / content.height)
    if scale < 1.0:
        content = content.resize((max(1, int(content.width * scale)),
                                  max(1, int(content.height * scale))),
                                 Image.NEAREST)
    x = (CELL - content.width) // 2
    y = CELL - margin - content.height
    cell.paste(content, (x, y), content)
    return cell


def process_group(group: str) -> None:
    src_dir = os.path.join(REF, group)
    out_dir = os.path.join(OUT, group)
    os.makedirs(out_dir, exist_ok=True)
    frames = sorted(f for f in os.listdir(src_dir) if f.lower().endswith(".bmp"))
    seen: set[str] = set()
    cells: list[tuple[str, Image.Image]] = []
    for f in frames:
        img = remove_bg_np(Image.open(os.path.join(src_dir, f)))
        digest = hashlib.sha256(img.tobytes()).hexdigest()[:12]
        if digest in seen:
            continue
        seen.add(digest)
        stem = os.path.splitext(f)[0]
        img.save(os.path.join(out_dir, f"{stem}.png"))
        cells.append((stem, fit_cell(img)))
    if not cells:
        return
    # 컨택트 시트: 한 행 6셀, 마젠타 배경
    per_row = 6
    rows = (len(cells) + per_row - 1) // per_row
    sheet = Image.new("RGBA", (per_row * CELL, rows * (CELL + 14)),
                      (255, 0, 255, 255))
    d = ImageDraw.Draw(sheet)
    for i, (stem, cell_img) in enumerate(cells):
        x = (i % per_row) * CELL
        y = (i // per_row) * (CELL + 14)
        sheet.paste(cell_img, (x, y), cell_img)
        d.text((x + 3, y + CELL + 1), stem, fill=(30, 0, 30, 255))
    sheet.save(os.path.join(OUT, f"{group}_sheet.png"))
    print(f"{group}: {len(cells)} frames (dedup {len(frames) - len(cells)})")


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    groups = sys.argv[1:]
    if not groups:
        groups = sorted(d for d in os.listdir(REF)
                        if os.path.isdir(os.path.join(REF, d)))
    for g in groups:
        if os.path.isdir(os.path.join(REF, g)):
            process_group(g)
    print("done ->", OUT)


if __name__ == "__main__":
    main()
