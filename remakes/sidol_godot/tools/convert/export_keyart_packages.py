"""키아트/컷씬 일러스트 LLM 의뢰 패키지 일괄 생성 — 정책 ③신규→컨셉+프롬프트.

assets/spec/keyart/*.json(6종)을 읽어 assets/raw/llm/keyart/<scene_id>/에
  prompt.md            그래픽 LLM 의뢰문(씬 설명·규격·톤·금지규칙)
  tone_anchor.png      톤/색 감각 앵커(원작 리마스터 필드 아트)
를 생성한다. 공통 첨부로 루트에 palette_swatch.png 1장.

완전 신규 창작 구간 — 지오메트리 계약 없음. 다만 게임 삽입 시
480×270 nearest 축소되므로 실루엣·명암 대비가 크게 읽혀야 함을 명시.

실행: python tools/convert/export_keyart_packages.py [scene_id ...]
"""
from __future__ import annotations
import glob
import io
import json
import os
import shutil
import sys

from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SPEC_DIR = os.path.join(ROOT, "assets", "spec", "keyart")
OUT_ROOT = os.path.join(ROOT, "assets", "raw", "llm", "keyart")
PALETTE_JSON = os.path.join(ROOT, "assets", "palette_master.json")
TONE_ANCHOR = os.path.join(ROOT, "assets", "originals_ref", "remastered", "i_field_64.png")

PROMPT_TEMPLATE = """# {title}(`{scene_id}`) 키아트 의뢰

## 역할
너는 1995년 한국 공대 배경 캠퍼스 호러 JRPG의 컷씬 일러스트레이터다.
**완전 신규 창작** 구간이다 — 원작 그래픽 제약은 없으나 아래 톤 규칙이 바인딩된다.

## 씬
- 제목: {title}
- 묘사: {description}

## 입력 (첨부)
1. `../palette_swatch.png` — 사용 가능한 256색 마스터 팔레트
2. `tone_anchor.png` — 게임 필드 아트(톤·채도·명암 감각 기준)

## 출력 규격
- **1920×1080 (16:9) PNG 1장**
- 게임 삽입 시 480×270 nearest 축소된다: 실루엣과 명암 대비는 크게·
  명확하게 — 미세 텍스처는 축소에서 소실된다
- 인물이 등장 시 SD 비율(머리:몸 ≈ 1:1.2) 캐릭터 어휘 준용

## 스타일 타깃 (후기 클래식 JRPG — 쯔바이/나르실리온/악튜러스풍)
- 인상: 어두운 VGA 레트로 → **따뜻하고 채도 있는 JRPG 화면**으로 격상.
  단 이 씬의 묘사가 요구하는 무드(폭우·공포·긴장)는 유지
- 픽셀 아트 감성: 안티에일리어싱 금지, 그라데이션은 밴딩 단계로
- 그림자: 검정 금지 → 남보라 계열(예: #3A285C) 색조 그림자
- 외곽선: 짙은 남색 계열 다크 아웃라인, 순수 블랙 면 금지
- 팔레트: 첨부 스왑치 내 색 우선. 형광/파스텔 붕괴/EGA 원색 유입 금지
- 무드 태그 체계: 레트로 / 개그(B급 공대 유머) / 모험 / 감동 / 메타픽션

## 납품물
1. 키아트 PNG 1장 (1920×1080)
2. (선택) 연출 의도 요약 3줄 이내
"""


def make_palette_swatch(out_path: str) -> None:
    colors = json.load(io.open(PALETTE_JSON, encoding="utf-8"))["colors"]
    cols, sw = 32, 12
    rows = (len(colors) + cols - 1) // cols
    img = Image.new("RGB", (cols * sw, rows * sw), (24, 24, 28))
    d = ImageDraw.Draw(img)
    for i, hexc in enumerate(colors):
        x, y = (i % cols) * sw, (i // cols) * sw
        d.rectangle([x, y, x + sw - 1, y + sw - 1], fill=hexc)
    img.save(out_path)
    print(f"palette_swatch.png ({len(colors)} colors)")


def export_one(spec_path: str) -> None:
    spec = json.load(io.open(spec_path, encoding="utf-8"))
    scene_id = spec["scene_id"]
    out_dir = os.path.join(OUT_ROOT, scene_id)
    os.makedirs(out_dir, exist_ok=True)

    prompt = PROMPT_TEMPLATE.format(
        scene_id=scene_id,
        title=spec.get("title", scene_id),
        description=spec.get("description", ""),
    )
    with io.open(os.path.join(out_dir, "prompt.md"), "w", encoding="utf-8") as f:
        f.write(prompt)
    if os.path.exists(TONE_ANCHOR):
        shutil.copyfile(TONE_ANCHOR, os.path.join(out_dir, "tone_anchor.png"))
    print(f"{scene_id}: prompt.md" + (" + tone_anchor.png" if os.path.exists(TONE_ANCHOR) else ""))


def main() -> None:
    os.makedirs(OUT_ROOT, exist_ok=True)
    make_palette_swatch(os.path.join(OUT_ROOT, "palette_swatch.png"))
    targets = sys.argv[1:]
    for spec_path in sorted(glob.glob(os.path.join(SPEC_DIR, "*.json"))):
        scene_id = os.path.splitext(os.path.basename(spec_path))[0]
        if targets and scene_id not in targets:
            continue
        export_one(spec_path)
    print(f"done -> {OUT_ROOT}")


if __name__ == "__main__":
    main()
