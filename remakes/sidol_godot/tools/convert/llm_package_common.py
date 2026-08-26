#!/usr/bin/env python3
"""LLM 의뢰 패키지 공통 부품 — 팔레트 스왑치 + 원작 참조 첨부.

세 생성기(portrait/keyart/monster)가 같은 코드를 복제해 갖고 있어서
팔레트 버그가 세 곳에 동시에 존재했다. 여기로 모은다.

## 팔레트 6비트 함정 (2026-08-26 발견)

`assets/palette_master.json`의 colors는 DEFAULT.PAL의 VGA DAC **원값(6비트, 0~63)**을
그대로 hex로 찍은 것이다. 스케일 없이 스왑치를 그리면 전 색이 0x3F(=25% 밝기)에 묶여
**어두침침한 팔레트**가 나오는데, 프롬프트가 "첨부 스왑치 내 색 우선"이라고 못 박고
있어 생성 이미지 전체가 어두워진다. 8비트로 올려서(<<2) 그린다.

## 원작 참조 (2026-08-26 추가)

원작 일러스트(`assets/originals_ref/`)가 어느 패키지에도 첨부되지 않고 있었다.
신규 생성물이 원작 화풍과 겉도는 주원인 — 규칙 문장보다 그림 한 장이 강하다.
카테고리별로 맞는 원작 그림을 같이 보낸다.
"""
from __future__ import annotations

import io
import json
import os
import shutil

from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
PALETTE_JSON = os.path.join(ROOT, "assets", "palette_master.json")
ORIGINALS = os.path.join(ROOT, "assets", "originals_ref")
LLM_ROOT = os.path.join(ROOT, "assets", "raw", "llm")
AGENT_PROMPT = os.path.join(ROOT, "assets", "gen", "prompts", "GRAPHIC_AGENT_PROMPT.md")
SUBMIT_CATEGORIES = ("portraits", "keyart", "monsters", "sprites")

## 카테고리별 원작 참조 — (원본 파일, 첨부 이름, 프롬프트에 적을 설명)
ORIGINAL_REFS = {
    "portraits": [
        ("face1_2.png", "orig_portrait_1.png", "원작 대화 초상 — 주인공(선 굵기·음영 단계·눈매 처리 기준)"),
        ("face3.png", "orig_portrait_2.png", "원작 대화 초상 — 조연"),
        ("face5.png", "orig_portrait_3.png", "원작 대화 초상 — 조연"),
    ],
    "keyart": [
        ("hp.png", "orig_scene_hp.png", "원작 HP실(부싯돌 동아리방) 그림 — 실내 구도·인물 배치·색 감각"),
        ("store.png", "orig_scene_store.png", "원작 상점 그림 — 실내 배경 처리"),
        ("face1_2.png", "orig_portrait.png", "원작 대화 초상 — 인물 화풍"),
    ],
    "monsters": [
        ("v-0.png", "orig_enemy_1.png", "원작 적 등장 일러스트 — 실루엣·발광 처리"),
        ("m-r-0.png", "orig_enemy_2.png", "원작 적 등장 일러스트 — 기계형"),
    ],
}

## 씬 id → 그 씬에 정확히 대응하는 원작 그림(있는 경우만).
SCENE_ORIGINALS = {
    "scene_02_hp_room": ("hp.png", "orig_this_scene.png", "**이 씬의 원작 그림** — 구도·인물 구성의 직접 근거"),
}


def scale6to8(hex_color: str) -> tuple:
    """6비트 DAC 원값 hex → 8비트 RGB. 0x3F(63)가 최대치라 <<2로 편다.

    스왑치 생성과 납품 검증이 **같은 변환**을 써야 한다 — 한쪽만 고치면
    "밝게 그리라고 시켜 놓고 어둡다고 반려하는" 상태가 된다.
    """
    v = hex_color.lstrip("#")
    ch = [int(v[i:i + 2], 16) for i in (0, 2, 4)]
    return tuple(min(255, c << 2) for c in ch)


def make_palette_swatch(out_path: str) -> None:
    colors = json.load(io.open(PALETTE_JSON, encoding="utf-8"))["colors"]
    cols, sw = 32, 12
    rows = (len(colors) + cols - 1) // cols
    img = Image.new("RGB", (cols * sw, rows * sw), (24, 24, 28))
    d = ImageDraw.Draw(img)
    for i, hexc in enumerate(colors):
        x, y = (i % cols) * sw, (i // cols) * sw
        d.rectangle([x, y, x + sw - 1, y + sw - 1], fill=scale6to8(hexc))
    img.save(out_path)
    print(f"palette_swatch.png ({len(colors)} colors, 6bit->8bit 보정)")


def copy_original_refs(category: str, out_dir: str, scene_id: str = "") -> list:
    """카테고리(+씬)에 맞는 원작 참조를 패키지 폴더에 복사한다.

    반환: 프롬프트에 넣을 [(첨부이름, 설명), ...] — 실제로 복사된 것만.
    """
    listed = []
    entries = list(ORIGINAL_REFS.get(category, []))
    if scene_id in SCENE_ORIGINALS:
        entries.insert(0, SCENE_ORIGINALS[scene_id])
    for src_name, dst_name, desc in entries:
        src = os.path.join(ORIGINALS, src_name)
        if not os.path.exists(src):
            continue
        shutil.copyfile(src, os.path.join(out_dir, dst_name))
        listed.append((dst_name, desc))
    return listed


def refs_block(listed: list, start_index: int) -> str:
    """프롬프트 '입력(첨부)' 목록에 이어 붙일 번호 매긴 블록."""
    if not listed:
        return ""
    lines = []
    for i, (name, desc) in enumerate(listed):
        lines.append(f"{start_index + i}. `{name}` — {desc}")
    return "\n".join(lines)


def prepare_workspace() -> None:
    """폴더째 그래픽 에이전트에게 넘길 수 있게 작업 공간을 갖춘다.

    - `README_먼저읽기.md` — 지시서(git 추적본을 복사). 폴더만 받은 쪽이 뭘 해야
      하는지 알 수 있는 유일한 단서다.
    - `10_submitted/<카테고리>/` — 납품 폴더. 심사 보드가 자동 생성하지 않아
      없으면 목록이 빈 채로 뜬다(사람이 mkdir 하던 것을 여기서 없앤다).
    """
    os.makedirs(LLM_ROOT, exist_ok=True)
    if os.path.exists(AGENT_PROMPT):
        shutil.copyfile(AGENT_PROMPT, os.path.join(LLM_ROOT, "README_먼저읽기.md"))
    for cat in SUBMIT_CATEGORIES:
        os.makedirs(os.path.join(LLM_ROOT, "10_submitted", cat), exist_ok=True)
    print("작업 공간 준비: README_먼저읽기.md + 10_submitted/%d개 카테고리" % len(SUBMIT_CATEGORIES))
