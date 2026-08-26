"""포트레이트(대화 얼굴) LLM 의뢰 패키지 일괄 생성 — 정책 ②원작+격상→리터칭.

assets/spec/portraits/*.json(16종)을 읽어 assets/raw/llm/portraits/<asset_id>/에
  <asset_id>_source.png   원작 얼굴(nearest 가시화 배율) — LLM 첨부용
  prompt.md               그래픽 LLM 의뢰문(규격·신원 유지·스타일 규칙)
을 생성한다. 공통 첨부로 루트에 palette_swatch.png(마스터 팔레트 256색) 1장.

계약 원칙: 이미지 LLM은 "리터치"가 불가능하므로 **원본 첨부 + 신원 유지 재창작**
으로 의뢰한다(지오메트리 계약 없음 — 스프라이트 시트 1차 반려 교훈 반영).
납품은 assets/raw/llm/10_submitted/portraits/<asset_id>_v<n>.png 규약.

실행: python tools/convert/export_portrait_packages.py [asset_id ...]
"""
from __future__ import annotations
import glob
import io
import json
import os
import sys

from PIL import Image, ImageDraw

from llm_package_common import (
    copy_original_refs,
    make_palette_swatch,
    prepare_workspace,
    refs_block,
)

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SPEC_DIR = os.path.join(ROOT, "assets", "spec", "portraits")
REF_DIR = os.path.join(ROOT, "assets", "originals_ref")
OUT_ROOT = os.path.join(ROOT, "assets", "raw", "llm", "portraits")
PALETTE_JSON = os.path.join(ROOT, "assets", "palette_master.json")

PROMPT_TEMPLATE = """# {name}(`{asset_id}`) 포트레이트 리마스터 의뢰

## 역할
너는 1995년 DOS RPG의 원작 캐릭터 얼굴을 현대 JRPG 톤으로 격상시키는
픽셀 아트 일러스트레이터다. **재창작이 허용되지만 신원 유지가 필수다.**
첨부한 원작 얼굴(`{asset_id}_source.png`)과 같은 인물이어야 한다.

## 캐릭터
- 이름: {name}
- 고정 서술 토큰: {token}

## 입력 (첨부)
1. `{asset_id}_source.png` — {source_desc}
2. `../palette_swatch.png` — 사용 가능한 256색 마스터 팔레트
{orig_refs}

**원작 초상이 화풍의 1차 근거다.** 규칙 문장보다 첨부 그림을 먼저 따른다 —
선 굵기, 음영 단계 수, 눈매·머리카락 처리를 계승하고 해상도만 격상한다.

## 출력 규격
- **768×256 PNG 1장** = 256×256 셀 3개 가로 배치, 표정 3종:
  | 셀 1 normal(기본) | 셀 2 worried(걱정) | 셀 3 determined(결의) |
- 머리부터 어깨 위주의 바스트업 구도, 시선은 정면 계열
- 배경: 완전 투명(alpha=0). 불가 시 **마젠타 #FF00FF 단색**(혼색·AA 금지)

## 신원 유지 (위반 시 반려)
- 실루엣·헤어스타일·의상·색 배치는 원작의 인물과 동일 유지
- 표정 변화는 눈·입·눈썹 중심으로만
- 3셀 간 인물 일관 — 머리 크기/의상/색이 셀마다 달라지면 반려

## 스타일 타깃 (후기 클래식 JRPG — 쯔바이/나르실리온/악튜러스풍)
- 픽셀 아트: 안티에일리어싱 금지 / 그라데이션 금지(색당 4~6단계 밴딩)
- 그림자: 검정 금지 → 남보라 계열(예: #3A285C) 색조 그림자
- 외곽선: 1px 다크 아웃라인 — 순수 블랙 금지, 짙은 남색(예: #0A082E 방향)
- 팔레트: 첨부 스왑치 내 색 우선. 형광/파스텔 붕괴/EGA 원색 유입 금지
- 따뜻하고 채도 있는 톤으로 격상 (어두운 VGA 레트로 그대로 반려)

## 납품물
1. 리마스터 시트 PNG 1장 (768×256)
2. (선택) 변경 요약 3줄 이내
"""


def visible_scale(im: Image.Image, target: int = 256) -> int:
    """원작 소형 크롭은 LLM이 알아볼 정수 nearest 배수로. 전경(320×200)은 그대로."""
    if im.width >= 300:  # 컷신 전경 320×200 — 확대 불필요
        return 1
    return max(1, target // max(im.width, im.height))


def source_desc(im: Image.Image, name: str) -> str:
    """첨부 이미지 성격 설명 — 크롭 초상 vs 컷신 전경 계약 분기."""
    if im.width >= 300:
        return ("원작 컷신 화면(320×200) — 이 속에 등장하는 인물이 "
                f"'{name}'이다. 단체 장면이면 아래 고정 서술 토큰에 해당하는 "
                "인물을 기준으로 삼는다")
    return "원작 얼굴 크롭 (신원·구도·헤어·의상 기준)"


def export_one(spec_path: str) -> None:
    spec = json.load(io.open(spec_path, encoding="utf-8"))
    asset_id = spec["asset_id"]
    src_path = os.path.join(REF_DIR, spec.get("source_ref", ""))
    if not os.path.exists(src_path):
        print(f"!! {asset_id}: source_ref 없음({src_path}) — 스킵")
        return
    out_dir = os.path.join(OUT_ROOT, asset_id)
    os.makedirs(out_dir, exist_ok=True)

    src = Image.open(src_path).convert("RGBA")
    k = visible_scale(src)
    src.resize((src.width * k, src.height * k), Image.NEAREST).save(
        os.path.join(out_dir, f"{asset_id}_source.png"))

    listed = copy_original_refs("portraits", out_dir)
    prompt = PROMPT_TEMPLATE.format(
        asset_id=asset_id,
        name=spec.get("name", asset_id),
        token=spec.get("subject_token", "(미정)"),
        source_desc=source_desc(src, spec.get("name", asset_id)),
        orig_refs=refs_block(listed, 3),
    )
    with io.open(os.path.join(out_dir, "prompt.md"), "w", encoding="utf-8") as f:
        f.write(prompt)
    print(f"{asset_id}: source x{k} + prompt.md")


def main() -> None:
    os.makedirs(OUT_ROOT, exist_ok=True)
    prepare_workspace()
    make_palette_swatch(os.path.join(OUT_ROOT, "palette_swatch.png"))
    targets = sys.argv[1:]
    for spec_path in sorted(glob.glob(os.path.join(SPEC_DIR, "*.json"))):
        asset_id = os.path.splitext(os.path.basename(spec_path))[0]
        if targets and asset_id not in targets:
            continue
        export_one(spec_path)
    print(f"done -> {OUT_ROOT}")


if __name__ == "__main__":
    main()
