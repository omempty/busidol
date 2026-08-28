#!/usr/bin/env python3
"""LLM 의뢰 패키지 공통 부품 — 팔레트 스왑치 + 원작 참조 첨부.

세 생성기(portrait/keyart/monster)가 같은 코드를 복제해 갖고 있어서
팔레트 버그가 세 곳에 동시에 존재했다. 여기로 모은다.

## 팔레트 6비트 함정 (2026-08-26 발견)

`assets/palette_master.json`의 colors는 DEFAULT.PAL의 VGA DAC **원값(6비트, 0~63)**을
그대로 hex로 찍은 것이다. 스케일 없이 스왑치를 그리면 전 색이 0x3F(=25% 밝기)에 묶여
**어두침침한 팔레트**가 나오는데, 프롬프트가 "첨부 스왑치 내 색 우선"이라고 못 박고
있어 생성 이미지 전체가 어두워진다. 8비트로 올려서(<<2) 그린다.

## 격자 템플릿이 결함의 발원지였다 (2026-08-28)

`make_grid_template`이 안내선을 **반투명**(마젠타 alpha 110 · 청록 alpha 70)으로 깔고
행 이름을 **글자로** 찍어 줬다. 그림 LLM은 그 위에 그린 뒤 배경째 합성해 납품했고 결과는:

- 안내선 → 불투명 반감광 마젠타(#850080 대)로 구워짐. 정확한 #FF00FF가 아니라
  마젠타 키잉도, near-magenta 검사도 못 지웠다(실납품 8/9장에서 검출).
- 행 라벨 → `null_pointer_v3`가 "Idle / Attack Seg / Fault Claws / Hurt / Death…"
  글자 바를 6칸에 그려 넣었다. 프롬프트의 "캔버스 안 글자 금지"와 정면 충돌.

그래서 템플릿은 **불투명 순수 #FF00FF 선만** 긋고(남아도 키잉으로 지워진다),
라벨·안전 여백 같은 설명은 별도 `grid_guide.png`로 분리한다(그 위에 그리지 못하게).

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

import delivery_checks as dc

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
PALETTE_JSON = os.path.join(ROOT, "assets", "palette_master.json")
ORIGINALS = os.path.join(ROOT, "assets", "originals_ref")
LLM_ROOT = os.path.join(ROOT, "assets", "raw", "llm")
AGENT_PROMPT = os.path.join(ROOT, "assets", "gen", "prompts", "GRAPHIC_AGENT_PROMPT.md")
STYLE_BIBLE = os.path.join(ROOT, "assets", "style_bible.md")
SUBMIT_CATEGORIES = (
    "portraits",
    "keyart",
    "monsters",
    "sprites",
    "npcs",
    "items",
    "effects",
    "battle_cuts",
    "battle_actors",
)

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
    # NPC는 적이 아니라 **사람**이다 — 적 일러스트를 참조로 주면 괴물처럼 그려 온다.
    "npcs": [
        ("face1_2.png", "orig_person_1.png", "원작 인물 초상 — 얼굴 비례·눈매·머리 처리"),
        ("face3.png", "orig_person_2.png", "원작 인물 초상 — 조연 톤"),
        ("hp.png", "orig_scene_hp.png", "원작 동아리방 그림 — 학생들의 옷·소품 분위기"),
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


def copy_original_refs(category: str, out_dir: str, scene_id: str = "", prefix: str = "") -> list:
    """카테고리(+씬)에 맞는 원작 참조를 복사한다.

    out_dir을 **카테고리 루트**로 주고 prefix="../"를 함께 주면 패키지마다 복사되지 않는다.
    같은 그림이 패키지 수만큼 복제되던 것을 1부로 줄이는 자리다(2026-08-28):
    몬스터 11패키지 × (style_ref 23KB + scale_ref 5KB + orig 15KB + subpalette) ≈ 500KB가
    전부 같은 파일이었다. 프롬프트의 "입력(첨부)" 목록이 경로의 단일 근거다.

    반환: 프롬프트에 넣을 [(첨부경로, 설명), ...] — 실제로 복사된 것만.
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
        listed.append((prefix + dst_name, desc))
    return listed


## 카테고리 안에서 모든 패키지가 똑같이 쓰는 참조 파일 이름 — 패키지 폴더에서 발견되면
## 구판(패키지마다 복사) 잔재이므로 지운다.
SHARED_REF_NAMES = (
    "palette_swatch.png",
    "style_ref.png",
    "scale_ref.png",
    "subpalette.png",
    "tone_anchor.png",
)


def shared_ref_names() -> set:
    names = set(SHARED_REF_NAMES)
    for entries in ORIGINAL_REFS.values():
        for _src, dst, _desc in entries:
            names.add(dst)
    return names


def dedupe_package_dirs(cat_root: str) -> int:
    """패키지 폴더에 남은 공용 참조 복사본을 지운다. 반환: 지운 파일 수.

    씬 전용 참조(orig_this_scene.png)와 패키지 고유 입력(<id>_source.png)은 건드리지 않는다.
    """
    if not os.path.isdir(cat_root):
        return 0
    names = shared_ref_names()
    removed = 0
    for entry in sorted(os.listdir(cat_root)):
        pkg = os.path.join(cat_root, entry)
        if not os.path.isdir(pkg):
            continue
        for f in list(os.listdir(pkg)):
            if f in names:
                os.remove(os.path.join(pkg, f))
                removed += 1
    return removed


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
    # assets/raw/는 **엔진이 스캔하면 안 되는** 작업 폴더다(AGENTS.md 규약).
    # .gdignore가 없으면 Godot이 의뢰 첨부 이미지를 전부 임포트하며 .import를 만든다
    # (2026-08-28 실측 1,274개). raw/는 gitignored라 클론 직후엔 없으므로 여기서 깐다.
    raw_root = os.path.dirname(LLM_ROOT)
    gdignore = os.path.join(raw_root, ".gdignore")
    if not os.path.exists(gdignore):
        os.makedirs(raw_root, exist_ok=True)
        io.open(gdignore, "w", encoding="utf-8").close()
        print(".gdignore 생성: %s (엔진 스캔 제외)" % raw_root)
    if os.path.exists(AGENT_PROMPT):
        shutil.copyfile(AGENT_PROMPT, os.path.join(LLM_ROOT, "README_먼저읽기.md"))
    for cat in SUBMIT_CATEGORIES:
        os.makedirs(os.path.join(LLM_ROOT, "10_submitted", cat), exist_ok=True)
    print("작업 공간 준비: README_먼저읽기.md + 10_submitted/%d개 카테고리" % len(SUBMIT_CATEGORIES))


# ---------------------------------------------------------------------------
# 프롬프트 하네스 (2026-08-28) — "감"이 아니라 실측 수치로 조인다.
#
# 실제 납품이 어긋난 지점: ① 색·톤이 원작과 겉돔 ② 캔버스 크기·프레임 수를 못 맞춤.
# ①은 256색 전체 팔레트를 던지는 게 오히려 지시를 흐려서다 — 대상별 12~16색으로 좁히고
# 원작 아트에서 잰 수치(고유색 수·AA 비율·외곽선 비중)를 계약으로 박는다.
# ②는 문장으로 못 고친다. 격자 템플릿을 첨부해 "이 위에 그려라"로 바꾸고,
# 그래도 어긋난 납품은 후처리(normalize_icon.py)가 규격으로 되돌린다.
# ---------------------------------------------------------------------------

## 고유색 계약 — 프롬프트와 게이트가 같은 수를 봐야 한다("48색으로 그려라"라고 시켜 놓고
## 다른 수로 반려하면 재의뢰가 무한 반복된다). 정본은 delivery_checks.COLOR_BUDGET.
COLOR_BUDGET = dc.COLOR_BUDGET


def identity_block(tokens: list) -> str:
    """정체성 확인 블록 — 고정 서술 토큰을 **체크리스트로 되돌려 준다**.

    왜: `npc_cafeteria_girl`의 토큰은 "앞치마+머리 수건, 활짝 웃는 얼굴"이었는데
    납품물은 금발·맨어깨·앞치마 없음이었다(2026-08-28). 토큰을 본문에 한 줄 적는 것만으론
    안 지켜진다 — 그림에 그 요소가 실제로 보이는지 항목으로 물어야 한다.
    """
    items = [t.strip() for t in tokens if t and t.strip()]
    if not items:
        return ""
    lines = ["### 정체성 확인 — 아래 요소가 **그림에 실제로 보이는가** (없으면 다른 인물이다)"]
    for t in items:
        lines.append(f"- [ ] {t}")
    lines.append("")
    lines.append("재해석은 화풍·완성도에만 허용된다. 인물의 신원 표지(복장·머리·소품·연령대)는 바꾸지 않는다.")
    return chr(10).join(lines)


## 어떤 카테고리든 공통으로 금지되는 것 — 생성 모델이 습관적으로 넣는 것들.
NEGATIVE_RULES = """### 하지 말 것 (하나라도 어기면 반려)
- 그라데이션·글로우·블러·베벨·드롭섀도 등 후처리 효과
- 3D 렌더·벡터 일러스트·수채/유화 질감 — **도트(픽셀) 그림만**
- 흰색/회색 배경, 체커보드를 그림으로 그리는 것, 배경에 깔린 그림자
- 캔버스 안의 글자·숫자·로고·서명·워터마크·설명 라벨
  (**애니 이름·프레임 번호를 그려 넣는 것 포함** — 참고용 `grid_guide.png`의 라벨을
  따라 그린 납품이 실제로 있었다. 라벨은 설명이지 그림이 아니다)
- **격자 안내선(마젠타·청록)을 남기는 것** — 흐리게·반투명으로 남겨도 반려다.
  납품물에 안내선이 남으면 자동 검사가 직선 런으로 잡아낸다
- 액자·테두리 선·둥근 모서리 마스크
- 요청한 것 외의 물건을 곁들여 배치하는 것(단품만)
- 반투명 안티에일리어싱 남발 — 원작 아트의 반투명 픽셀은 **0%**다"""


def measure_tone(paths: list) -> dict:
    """참조 아트의 톤을 실측한다 — 고유색 수·AA 비율·어두운 외곽 비중·채도/명도.

    프롬프트에 "원작 느낌으로"라고 적는 대신 숫자를 준다. 값은 생성 시점에 실제
    파일에서 재므로, 아트가 교체되면 계약도 따라 바뀐다(문서가 낡지 않는다).
    """
    import colorsys

    import numpy as np

    n_colors, aa, dark, sat, val, transparent = [], [], [], [], [], []
    for p in paths:
        try:
            im = Image.open(p).convert("RGBA")
        except Exception:  # noqa: BLE001 — 참조 한 장이 깨져도 계약 생성은 계속
            continue
        a = np.asarray(im)
        rgb, alpha = a[:, :, :3], a[:, :, 3]
        opaque = alpha > 200
        if opaque.sum() == 0:
            continue
        n_colors.append(len({tuple(c) for c in rgb[opaque]}))
        aa.append(((alpha > 0) & (alpha < 200)).mean())
        px = rgb[opaque].astype(float) / 255.0
        dark.append((px.max(axis=1) < 0.22).mean())
        sample = px[::17] if px.shape[0] > 17 else px
        hsv = [colorsys.rgb_to_hsv(*c) for c in sample]
        if hsv:
            sat.append(sum(h[1] for h in hsv) / len(hsv))
            val.append(sum(h[2] for h in hsv) / len(hsv))
        transparent.append((alpha == 0).mean())
    if not n_colors:
        return {}
    avg = lambda xs: sum(xs) / len(xs)  # noqa: E731
    return {
        "n": len(n_colors),
        "colors": round(avg(n_colors)),
        "colors_max": max(n_colors),
        "aa": avg(aa),
        "dark": avg(dark),
        "sat": avg(sat) if sat else 0.0,
        "val": avg(val) if val else 0.0,
        "transparent": avg(transparent),
    }


def style_bible_block() -> str:
    """assets/style_bible.md의 창작 규칙을 프롬프트에 그대로 주입한다.

    스타일 바이블은 스스로 "모든 AI 생성 에셋 프롬프트에 주입되는 최상위 창작 규칙"이라
    적어 두었지만 **2026-08-28까지 어떤 생성기도 이 파일을 읽지 않았다**(참조 0건).
    지향점(원작 도트 → 후기 클래식 JRPG로 격상)이 프롬프트에 없었으니 납품물이
    원작 복사거나 아예 딴 그림이 되는 게 당연했다. 파일이 출처이므로 바이블을 고치면
    다음 패키지부터 자동 반영된다.
    """
    if not os.path.exists(STYLE_BIBLE):
        return ""
    text = io.open(STYLE_BIBLE, encoding="utf-8").read().strip()
    # 문서 머리말(누구 것인지 설명)은 그림 LLM에게 불필요하다 — 규칙 본문부터.
    marker = "## 스타일 타깃"
    if marker in text:
        text = text[text.index(marker):]
    header = "## 최상위 창작 규칙 (스타일 바이블 — 아래 모든 지시보다 우선)"
    return header + chr(10) + chr(10) + text


def tone_block(tone: dict, what: str) -> str:
    """measure_tone 결과 → '베이스라인' 문단.

    주의: 이 수치는 **따라야 할 목표가 아니라 계승할 하한선**이다.
    원작 이관 아트는 앞으로 리마스터로 교체될 예정이고, 리메이크 타깃은
    스타일 바이블대로 원작보다 풍부해야 한다. 수치로 원작에 묶어 버리면
    "단순 확대·재채색"(바이블이 반려 사유로 못 박은 것)이 나온다.
    """
    if not tone:
        return ""
    outline = (
        "1px 다크 아웃라인을 두른다(순수 블랙 금지 — 짙은 남색·갈색)"
        if tone["dark"] > 0.05
        else "외곽선보다 색 경계로 형태를 낸다"
    )
    return f"""### 베이스라인 — {what} {tone['n']}장 실측값 (계승할 하한선이지 목표치가 아니다)
| 항목 | 원작 실측 | **리메이크 타깃** |
|---|---|---|
| 고유색 수 | 평균 {tone['colors']}색(최대 {tone['colors_max']}) | **24~48색** — 원작보다 풍부하게. 단 수백 색 그라데이션은 금지 |
| 명암 단계 | 2~3단 | **4~6단** + 색조 그림자(검정 대신 남보라·청록) |
| 반투명 픽셀 | {tone['aa'] * 100:.1f}% | **0%** — 이건 그대로. 픽셀은 켜지거나 꺼진다 |
| 외곽 처리 | 어두운 픽셀 {tone['dark'] * 100:.0f}% | {outline} |
| 채도·명도 | {tone['sat']:.2f} / {tone['val']:.2f} | 비슷하거나 **조금 더 선명하게**(탁하게 가라앉히지 말 것) |
| 배경 여백 | 투명 {tone['transparent'] * 100:.0f}% | 그대로 — 물체가 캔버스를 꽉 채우지 않는다 |

**계승할 것**: 실루엣의 성격, 무엇이 무엇인지 알아보게 하는 색 정체성, 도트라는 매체.
**격상할 것**: 명암 단계, 질감 디테일, 색의 풍부함. 원작 그림의 단순 확대·재채색은 반려된다.
"""


def dominant_colors(paths: list, count: int = 16) -> list:
    """참조 아트에서 실제로 많이 쓰인 색 상위 N개(불투명 픽셀 기준).

    256색 마스터 팔레트를 통째로 주면 "아무 색이나 써도 된다"로 읽힌다.
    대상과 같은 계열의 기존 아트에서 뽑은 좁은 팔레트가 훨씬 잘 먹는다.
    """
    from collections import Counter

    import numpy as np

    tally = Counter()
    for p in paths:
        try:
            im = Image.open(p).convert("RGBA")
        except Exception:  # noqa: BLE001
            continue
        a = np.asarray(im)
        rgb, alpha = a[:, :, :3], a[:, :, 3]
        for c in rgb[alpha > 200][::3]:
            tally[tuple(int(v) for v in c)] += 1
    # 순수 검정은 프롬프트가 외곽선·그림자에 금지한 색이다(원작 SPR 배경이 검정이라
    # 그냥 세면 1위로 올라온다). 금지해 놓고 추천하면 지시가 서로 싸운다.
    tally.pop((0, 0, 0), None)
    return [c for c, _ in tally.most_common(count)]


def make_subpalette(colors: list, out_path: str, swatch: int = 48) -> str:
    """상위 색 목록 → 큰 스왑치 PNG. 반환: 프롬프트에 넣을 hex 목록 문자열."""
    if not colors:
        return ""
    cols = min(8, len(colors))
    rows = (len(colors) + cols - 1) // cols
    img = Image.new("RGB", (cols * swatch, rows * swatch), (18, 18, 22))
    d = ImageDraw.Draw(img)
    for i, c in enumerate(colors):
        x, y = (i % cols) * swatch, (i // cols) * swatch
        d.rectangle([x, y, x + swatch - 2, y + swatch - 2], fill=tuple(c))
    img.save(out_path)
    return " ".join("#%02X%02X%02X" % tuple(c) for c in colors)


def make_grid_template(out_path: str, cols: int, rows: int, cell: int, labels: list) -> None:
    """정확한 캔버스 크기의 격자 템플릿 — "이 그림 위에 그려라"로 크기를 강제한다.

    크기·프레임 수는 문장으로 지시해도 계속 어긋난다(실납품 확인). 정답 크기의
    빈 격자를 주고 그 위에 그리게 하면 편집형 모델에서 실패율이 크게 떨어진다.

    선은 **불투명 순수 #FF00FF**만 쓴다. 반투명으로 깔면 납품물에 반감광 보라(#850080 대)로
    구워져 키잉도 검사도 못 지운다(2026-08-28 실납품 8/9장). 순수 마젠타면 남아도
    배경 키잉이 같이 지운다 — 실수의 비용을 0으로 만드는 쪽을 택한다.
    라벨·안전 여백 설명은 같은 폴더의 `grid_guide.png`로 뺀다(그 위에 그리지 않게).
    """
    w, h = cols * cell, rows * cell
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for r in range(rows):
        for c in range(cols):
            x0, y0 = c * cell, r * cell
            d.rectangle([x0, y0, x0 + cell - 1, y0 + cell - 1], outline=(255, 0, 255, 255))
    img.save(out_path)
    # 단일 셀 캔버스(아이콘)는 설명할 격자가 없다 — 가이드를 만들지 않는다.
    if cols * rows > 1 or labels:
        make_grid_guide(os.path.join(os.path.dirname(out_path), "grid_guide.png"),
                        cols, rows, cell, labels)


def make_grid_guide(out_path: str, cols: int, rows: int, cell: int, labels: list) -> None:
    """설명용 격자 — 행 라벨·안전 여백·프레임 수를 적은 **참고 이미지**.

    캔버스 크기를 일부러 다르게(우측에 설명 여백을 붙여) 만든다: 이 그림 위에 그리면
    규격이 안 맞아 자동으로 반려되므로, "참고용"이라는 지시가 그림으로도 강제된다.
    """
    pad_right = max(160, cell)
    img = Image.new("RGBA", (cols * cell + pad_right, rows * cell), (16, 16, 20, 255))
    d = ImageDraw.Draw(img)
    for r in range(rows):
        for c in range(cols):
            x0, y0 = c * cell, r * cell
            d.rectangle([x0, y0, x0 + cell - 1, y0 + cell - 1], outline=(255, 0, 255, 200))
            pad = max(4, cell // 16)
            d.rectangle(
                [x0 + pad, y0 + pad, x0 + cell - 1 - pad, y0 + cell - 1 - pad],
                outline=(0, 255, 255, 140),
            )
        if r < len(labels):
            d.text((cols * cell + 6, r * cell + 6), labels[r], fill=(255, 255, 0, 255))
    d.text((cols * cell + 6, rows * cell - 14), "GUIDE ONLY - DO NOT DRAW HERE", fill=(255, 80, 80, 255))
    img.save(out_path)


SELF_CHECK = """### 납품 전 스스로 확인 (하나라도 아니오면 다시 그려라)
1. 캔버스 크기가 요구 규격과 **픽셀 단위로 정확히** 같은가?
2. 배경이 완전 투명 또는 마젠타 단색인가? (흰색·회색·체커보드 아님)
3. 고유색이 **%d색 이하**인가? 부드러운 그라데이션·리샘플 흔적이 없는가?
   (실납품이 16,000~50,000색으로 온 적이 있다. 그건 도트 그림이 아니다)
4. 반투명(부분 투명) 픽셀이 거의 없는가? (계약 0%%)
5. 캔버스 안에 글자·워터마크·액자가 없는가?
6. **격자 안내선을 전부 지웠는가?** 셀 경계·안전 여백 선, 행 라벨 글자가
   한 줄도 남아 있으면 안 된다(흐리게 남은 것도 검출된다)""" % COLOR_BUDGET
