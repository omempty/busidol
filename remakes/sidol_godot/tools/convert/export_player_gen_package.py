"""주인공 스프라이트 신규 생성(스펙 B) 의뢰 패키지 - G-ART B안(32px 타일/64px 캐릭터).

출력(assets/gen/prompts/):
  player_gen_guide.png     256x512 빈 격자 템플릿(4열x8행, 마젠타 배경, 행/프레임 라벨)
  player_gen_prompt.md     그래픽 LLM 생성 지시 프롬프트

스펙: assets/spec/sprites/player_sidol.json (cell 64, 4열, walk 4프레임/idle 2프레임)
리터칭(24x24 유지)과 달리 이 경로는 64x64 캐릭터 신규 도트 생성이다.
사용: python tools/convert/export_player_gen_package.py
"""
from __future__ import annotations
import io
import json
import os
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SPEC = os.path.join(ROOT, "assets", "spec", "sprites", "player_sidol.json")
OUT_DIR = os.path.join(ROOT, "assets", "gen", "prompts")
MAGENTA = (255, 0, 255)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    spec = json.load(io.open(SPEC, encoding="utf-8"))
    cell = int(spec["cell"])
    cols = int(spec["grid"]["cols"])
    rows = int(spec["grid"]["rows"])
    W, H = cols * cell, rows * cell

    # 1) 가이드 템플릿 - 마젠타 배경 + 격자 + 라벨
    img = Image.new("RGBA", (W, H), (*MAGENTA, 255))
    d = ImageDraw.Draw(img)
    for r in range(rows + 1):
        d.line([(0, r * cell), (W, r * cell)], fill=(140, 0, 140, 255))
    for c in range(cols + 1):
        d.line([(c * cell, 0), (c * cell, H)], fill=(140, 0, 140, 255))
    anims = spec["animations"]
    for name, a in anims.items():
        row = int(a["row"])
        for f in range(int(a["frames"])):
            d.text((f * cell + 6, row * cell + 4),
                   f"{name[:9]}#{f + 1}", fill=(40, 0, 40, 255))
    img.save(os.path.join(OUT_DIR, "player_gen_guide.png"))

    # 2) 프롬프트
    subject = str(spec.get("prompt_vars", {}).get("subject", ""))
    anim_lines = []
    for name, a in anims.items():
        anim_lines.append(f"| {int(a['row'])} | {name} | "
                          f"{a['frames']}프레임 | {a.get('fps', '-')} |")
    anim_table = "\n".join(anim_lines)
    constraints = "\n".join(f"- {c}" for c in spec.get("constraints", []))

    prompt = f"""# 주인공 스프라이트 시트 신규 생성 (64x64 캐릭터, 4프레임)

## 역할
너는 1995년 DOS RPG 주인공을 현대 클래식 JRPG(쯔바이/나르실리온/악튜러스풍)
감각의 픽셀 아트로 재탄생시키는 도트 아티스트다. 이번 작업은 **신규 생성**이다
- 원작 24x24 도트는 구도 참고용으로만 쓰고, 캐릭터는 {cell}x{cell}에 크게 그린다.

## 캐릭터 (고정 서술 토큰 - 모든 프레임에서 동일 유지)
{subject}

## 출력 형식
- 첨부 가이드(player_gen_guide.png)와 동일한 **{W}x{H}px PNG 1장**
- {cols}열 x {rows}행, 셀 {cell}x{cell}, 각 셀에 프레임 1개
- 배경: **마젠타 #FF00FF 단색** (누끼용). 캐릭터와 마젠타 사이
  혼색/반투명/안티에일리어싱 금지 - 경계는 하드 엣지
- 캐릭터는 셀 하단 중앙 정렬(발이 셀 바닥), 상단 10~20% 여백

## 애니메이션 배치

| 행 | 애니 | 프레임 | FPS |
|---|---|---|---|
{anim_table}

- walk 4프레임 사이클: 접지 -> 착지(중간) -> 도약(다리 교차 최대) -> 중간
  (좌->우 순서). 4프레임이 자연스러운 보행 루프가 되도록.
- idle 2프레임: 숨쉬기(어깨/가슴 미세 상하).
- **모든 프레임에서 머리 크기·의상·색 배치가 동일해야 한다.** 프레임 간
  캐릭터가 다르게 그려지면 최대 반려 사유다.

## 스타일 규칙
- 큰 머리 비율(약 1:1.2 머리:몸), 부드러운 실루엣
- 명암: 색상당 하이라이트~그림자 4~6단계 밴딩 (그라데이션 금지)
- 그림자: 검정 금지 -> 남보라 계열(#3A285C 방향) 색조 그림자
- 외곽선: 1px 다크 아웃라인, 순수 블랙 대신 짙은 남색(#0A082E 방향)
- 색: 따뜻하고 채도 있는 톤. 파스텔 붕괴/형광/EGA 원색 금지
- 안티에일리어싱 금지 (마젠타 경계 제외 전부 하드 엣지)

## 캐릭터 내부 검정 처리
눈·입 등 검정 디테일은 투명이 아니라 아주 어두운 남색으로 채워 그린다.
(마젠타만 유일한 투명 예약색이다)

## 기존 제약(스펙)
{constraints}

## 납품물
1. {W}x{H}px PNG 1장 (위 배치 그대로)
2. (선택) 캐릭터 해석 요약 3줄
"""
    with open(os.path.join(OUT_DIR, "player_gen_prompt.md"), "w",
              encoding="utf-8", newline="\n") as fh:
        fh.write(prompt)
    print(f"ok -> {OUT_DIR} (guide {W}x{H}, prompt md)")


if __name__ == "__main__":
    main()
