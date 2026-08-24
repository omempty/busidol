"""주인공 스프라이트 시트 그래픽 LLM 리터칭 의뢰 패키지 생성.

출력(assets/gen/prompts/):
  player_sheet_original.png    원본 아틀라스 그대로 (128x320, 투명화 없음 - 원판)
  player_sheet_annotated.png   격자+행 라벨 오버레이(LLM 레이아웃 안내용)
  player_retouch_prompt.md     그래픽 LLM 지시 프롬프트

사용: python tools/convert/export_player_sheet.py
"""
from __future__ import annotations
import io
import json
import os
import shutil
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ATLAS = os.path.join(ROOT, "assets", "sprites", "player_original.png")
META = os.path.join(ROOT, "assets", "sprites", "player_original.json")
SPEC = os.path.join(ROOT, "assets", "spec", "sprites", "player_sidol.json")
OUT_DIR = os.path.join(ROOT, "assets", "gen", "prompts")

ROW_LABELS_EN = ["WALK_DOWN", "WALK_UP", "WALK_LEFT", "WALK_RIGHT",
                 "IDLE_DOWN", "IDLE_UP?", "IDLE_LEFT?", "IDLE_RIGHT?"]


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    meta = json.load(io.open(META, encoding="utf-8"))
    try:
        spec = json.load(io.open(SPEC, encoding="utf-8"))
    except FileNotFoundError:
        spec = {}
    cell = int(meta["cell"])
    atlas = Image.open(ATLAS).convert("RGBA")
    rows = atlas.height // cell

    # 1) 원판 복사 (무손실 원본 전달)
    shutil.copyfile(ATLAS, os.path.join(OUT_DIR, "player_sheet_original.png"))

    # 2) 주석 버전 - 격자 + 행 라벨 + 실제 도트 영역(24x24) 표시
    band = 110
    ann = Image.new("RGBA", (atlas.width + band, atlas.height), (18, 20, 26, 255))
    ann.paste(atlas, (band, 0))
    d = ImageDraw.Draw(ann)
    for r in range(rows + 1):
        y = r * cell
        d.line([(band, y), (ann.width, y)], fill=(90, 100, 130, 255))
    for c in range(int(meta["cols"]) + 1):
        x = band + c * cell
        d.line([(x, 0), (x, atlas.height)], fill=(90, 100, 130, 255))
    # 실제 도트 영역 표시(녹색 점선 상자) + 셀 대비 흐리게
    overlay = Image.new("RGBA", ann.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    for r in range(rows):
        for c in range(int(meta["cols"])):
            x0 = band + c * cell
            y0 = r * cell
            od.rectangle((x0, y0, x0 + cell - 1, y0 + cell - 1),
                         fill=(40, 44, 60, 160))
    ann = Image.alpha_composite(ann, overlay)
    d = ImageDraw.Draw(ann)
    for r in range(rows):
        for c in range(int(meta["cols"])):
            x0 = band + c * cell + 20
            y0 = r * cell + 40
            d.rectangle((x0 - 1, y0 - 1, x0 + 24, y0 + 24),
                        outline=(120, 220, 120, 255))
    label = Image.new("RGBA", (band * 4, 20), (0, 0, 0, 0))
    ld = ImageDraw.Draw(label)
    anims = meta.get("animations", {})
    for r in range(rows):
        name = ""
        for k, v in anims.items():
            if int(v.get("row", -1)) == r:
                name = k.upper()
                break
        if not name and r < len(ROW_LABELS_EN):
            name = ROW_LABELS_EN[r]
        ld.text((2, 2), name, fill=(255, 213, 79, 255))
        ann.paste(label.resize((band, 20)), (2, r * cell + cell // 2 - 10))
        ld.rectangle((0, 0, band * 4, 20), fill=(0, 0, 0, 0))
    ann.save(os.path.join(OUT_DIR, "player_sheet_annotated.png"))

    # 3) 프롬프트 생성
    anim_lines = []
    for k, v in anims.items():
        anim_lines.append(f"| {int(v['row'])} | {k} | {v['frames']}프레임 | "
                          f"{v.get('fps', '-')} |")
    anim_table = "\n".join(anim_lines)
    subject = str(spec.get("prompt_vars", {}).get("subject", ""))
    constraints = "\n".join(f"- {c}" for c in spec.get("constraints", []))

    prompt = f"""# 주인공 스프라이트 시트 리터칭 의뢰

## 역할
너는 1995년 DOS RPG의 원작 도트 스프라이트를 현대 JRPG 톤으로 격상시키는
픽셀 아트 리터처러다. **재창작이 아니라 리터칭**이다. 실루엣과 픽셀 배치는
원작을 그대로 유지하며 색감·명암·디테일만 끌어올린다.

## 캐릭터
{subject}

## 입력 (첨부: player_sheet_original.png / 레이아웃 안내: player_sheet_annotated.png)
- 시트: {atlas.width}x{atlas.height}px, 셀 {cell}x{cell}px, {meta['cols']}열 x {rows}행
- **실제 캐릭터 도트는 24x24px**이며 각 셀 내 (20,40) 오프셋에 위치한다.
  셀의 나머지 영역은 전부 투명 패딩이다. 캐릭터를 키워 셀을 채우지 마라.
- 권장 작업법: 각 셀의 24x24 도트만 잘라 **8배(192x192) 확대** 후 리터치하고,
  납품 시 축소해 원래 오프셋에 배치한다.
- 각 행 = 한 애니메이션, 좌→우가 프레임 순서:

| 행 | 애니 | 프레임 | FPS |
|---|---|---|---|
{anim_table}

## 절대 규칙 (위반 시 반려)
1. **지오메트리 무변경**: 픽셀 위치·실루엣·머리-몸 비율을 한 픽셀도 옮기지 않는다.
   캐릭터는 24x24 도트 그대로 — 크게 그리거나 셀을 채우면 즉시 반려된다.
2. **그리드 무변경**: 납품은 반드시 동일 {atlas.width}x{atlas.height} PNG,
   같은 셀 위치에 같은 프레임, 캐릭터도 같은 (20,40) 오프셋.
   프레임 추가/삭제/이동 금지.
3. **배경 완전 투명**: 셀 바깥은 alpha=0. 체커보드/흰색/**마젠타 등 키컬러** 채움 금지.
4. **검정(0,0,0) 투명 처리 금지**: 캐릭터 내부의 검정 디테일(눈·입·틈)은
   투명으로 만들지 말고 아웃라인색 또는 아주 어두운 남색으로 채워 유지한다.
5. 안티에일리어싱 금지 / 그라데이션 금지(반드시 단계 밴딩).

## 스타일 타깃 (후기 클래식 JRPG - 쯔바이/나르실리온/악튜러스풍)
- 전체 인상: 어두운 VGA 레트로 -> 따뜻하고 채도 있는 필드 톤으로 격상
- 명암: 색상당 하이라이트~그림자 **4~6단계 밴딩**
- 그림자: 검정 금지 -> **남보라 계열**(예: #3A285C) 색조 그림자
- 하이라이트: 따뜻한 톤(예: #FFF4D6 방향)으로 미세 리프트
- 외곽선: 기존 1px 다크 아웃라인 유지, 순수 블랙 대신 짙은 남색(예: #0A082E)
- 색 범위: 원본에 없던 파스텔/형광/EGA 원색 유입 금지. 원본 색상 세트 내에서
  채도·명도 조정만 허용.

## 기존 제약(스펙 명세)
{constraints}

## 납품물
1. 리터치된 시트 PNG 1장 ({atlas.width}x{atlas.height}, 투명 배경)
2. (선택) 변경 요약: 어떤 부위를 어떻게 고쳤는지 3줄 이내
"""
    with open(os.path.join(OUT_DIR, "player_retouch_prompt.md"), "w",
              encoding="utf-8", newline="\n") as fh:
        fh.write(prompt)

    print("ok ->", OUT_DIR)
    print("files: player_sheet_original.png, player_sheet_annotated.png,",
          "player_retouch_prompt.md")


if __name__ == "__main__":
    main()
