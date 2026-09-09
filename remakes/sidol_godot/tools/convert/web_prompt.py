#!/usr/bin/env python3
"""웹 LLM용 프롬프트 — **첨부 없이 문장만으로** 규격에 맞는 시트를 받아 내기 위한 텍스트.

## 왜 (2026-09-08)

기존 의뢰 패키지(`assets/raw/llm/<cat>/<id>/prompt.md`)는 첨부 5~8장(격자 템플릿·스타일
참조·크기 기준·서브팔레트·원작 그림)을 전제로 쓰였다. 브라우저 챗에 붙여넣는 상황에는
그 첨부가 없고, 그래서 프롬프트의 절반이 "없는 파일을 가리키는 문장"이 된다.

기존 `assets/gen/prompts/MONSTER_WEB_PROMPT_HUB.md`가 그 용도로 손으로 쓰여 있었는데
**규격이 정본과 어긋나 있었다** — mad_eye를 `320×512(셀 64)`로 적어 놨지만 정본 계약은
`640×1024(셀 128)`다(게임 내 프레임 크기 64를 시트 셀로 착각). 저기서 복사해 만든 납품은
크기 위반으로 자동 반려된다. 그래서 손으로 쓰지 않고 **스펙에서 굽는다.**

두 조각으로 나눈다 — 브라우저 챗은 대화가 이어지므로 공통 규칙을 매번 붙일 필요가 없다:

  1. 공통 스타일 프롬프트  — 한 번 붙여넣고 대화 내내 재사용(화풍·픽셀 규칙·팔레트·금지)
  2. 시트 상세 프롬프트    — 이 캐릭터 한 장 분량(정체성·격자 계약·행별 프레임·자가 점검)

첨부가 없으니 **첨부 전제 지시는 뒤집어 준다**: 격자 템플릿을 못 주므로 "그 위에 그려라"
대신 "격자선을 아예 그리지 마라"가 되고, 크기 기준 시트가 없으므로 셀 안 아트 높이를
픽셀 수로 못박는다.

## 왜 (2026-09-09) — 한 문장이 다섯 카테고리를 굽고 있었다

위 구조를 **몬스터 하나를 기준으로** 세운 탓에, 그리드가 있는 카테고리 5종이 전부 같은
캐릭터 어휘를 받았다. 실측(`web_prompt.py effects hit_spark`)이 이렇게 말하고 있었다:

    캐릭터는 칸 하나 안에 온전히 들어가야 하고, 옆 칸을 침범하면 안 된다.
    캐릭터 크기: 칸 128px 안에서 실제 아트 높이 96px 안팎(칸의 70~85%).
    정렬: 각 칸의 정확한 중앙. 프레임마다 발 위치가 오르내리면 캐릭터가 떠 보인다.
    프레임 간 같은 캐릭터여야 한다: 머리 크기·색 배치·장식·비례를 유지하고 포즈만 바꾼다.

타격 스파크는 **프레임마다 형태·크기·밝기가 달라져야** 정상이다(터지고 퍼지고 사라진다).
"같은 크기를 유지하라"·"발 위치"는 정반대 지시였다. 전투 대형 컷(셀 512)도 마찬가지로
필드 도트용 수치(70~85%)를 그대로 받고 있었다.

그래서 **시트 종류(kind)** 로 갈랐다 — 격자 계약이 같아도 그리는 것이 다르면 지시가
달라야 한다(`SHEET_KIND` 참조). 아울러 FLAT 3종(portraits·items·keyart)은 12줄짜리
스텁("설명을 더 적어 주면 이 자리에 붙여 넣는다")이라 쓸 수 없었고 `--write`가 아예
굽지도 않았다 — 스펙이 있는데 코드가 안 읽는, 이 저장소의 지배적 결함 그대로였다.
셋 다 각자의 스펙에서 굽는다.

실행:
  python tools/convert/web_prompt.py --common                 공통 프롬프트만
  python tools/convert/web_prompt.py monsters c_bug           그 시트의 상세 프롬프트
  python tools/convert/web_prompt.py portraits npc_quizman    초상·아이템·키아트도 같은 자리
  python tools/convert/web_prompt.py --write                  둘 다 파일로 굽는다
      -> assets/gen/prompts/WEB_PROMPT_COMMON.md
      -> assets/gen/prompts/web/<cat>__<id>.md
"""
from __future__ import annotations

import argparse
import glob
import io
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import llm_package_common as common  # noqa: E402

## 아이템 분류 설명·수치 문장은 첨부 전제 생성기가 이미 정본으로 들고 있다.
## 여기에 복사하면 둘이 갈라진다(같은 물건에 서로 다른 지시가 나간다) — 그래서 가져다 쓴다.
import export_item_icon_packages as item_pkg  # noqa: E402

ROOT = common.ROOT
OUT_COMMON = os.path.join(ROOT, "assets", "gen", "prompts", "WEB_PROMPT_COMMON.md")
OUT_DIR = os.path.join(ROOT, "assets", "gen", "prompts", "web")

SPEC_FILES = {
    "monsters": "monster_anim_specs.json",
    "npcs": "npc_anim_specs.json",
    "effects": "effect_specs.json",
    "battle_cuts": "battle_cut_specs.json",
    "battle_actors": "battle_actor_specs.json",
}

## 그리드가 있는 카테고리를 **시트 종류**로 가른다. 격자 계약(칸 크기·행·열)을 뽑는
## 방법은 셋 다 같지만, 칸 안에서 무엇이 어떻게 변해야 하는지가 정반대다:
##
##   character — 프레임 간 **같은 것**이 유지돼야 한다(크기·비례·발 접지). 변하는 건 포즈뿐.
##   effect    — 프레임 간 **변하는 것**이 내용이다(형태·크기·밝기). 발도 없고 접지도 없다.
##   cut       — 셀 512짜리 연출 컷. 필드 도트용 수치(70~85%)를 그대로 쓰면 안 된다.
##
## 한 문장으로 다섯을 굽던 시절, hit_spark가 "발 위치가 오르내리면 떠 보인다"는 지시를
## 받고 있었다. 카테고리가 늘면 여기에 종류를 정해 주는 것이 첫 걸음이다.
SHEET_KIND = {
    "monsters": "character",
    "npcs": "character",
    "battle_actors": "character",
    "effects": "effect",
    "battle_cuts": "cut",
}
## 시트가 아닌 카테고리 — (캔버스, 설명). 검증기·편집기의 FLAT_CONTRACTS와 같은 수다.
FLAT = {
    "portraits": ((768, 256), "256×256 셀 3개 가로 배치 = 표정 3종"),
    "items": ((96, 96), "96×96 단일 아이콘 1장"),
    "keyart": ((1920, 1080), "1920×1080 (16:9) 일러스트 1장"),
}
## 시트 셀은 **항상 128**(전투 컷만 스펙의 sheet_cell=512). 스펙의 `cell` 필드는
## 게임 안 프레임 크기(64·48)라 시트 셀이 아니다 — 이걸 혼동해 만든 허브 문서가
## mad_eye를 320×512로 적어 놨고, 그대로 그린 납품이 크기 위반으로 반려됐다.
CELL_DEFAULT = 128

## 애니 이름별 기본 동작 설명. 스펙의 `_desc`가 비어 있으면 이걸 쓴다 —
## 표의 '그릴 내용'이 "-"로 비면 생성 모델이 알아서 지어내고, 그 결과 걷기 4칸이
## 서로 다른 포즈 4종(=애니메이션이 아니라 삽화 4장)이 되어 온다.
DEFAULT_MOTION = {
    "walk_down": "정면 보행 사이클 — 팔다리를 좌우 교차, 몸통 1~2px 상하 진동",
    "walk_up": "뒷모습 보행 사이클 — 뒤통수·등이 보인다. 팔다리 교차는 정면과 같은 박자",
    "walk_left": "좌측면 보행 사이클 — 앞다리/뒷다리 교차, 실루엣이 옆으로 뚜렷하게",
    "walk_right": "우측면 보행 사이클 — walk_left의 좌우 대칭이되 세부는 같은 캐릭터",
    "idle_down": "정면 대기 — 아주 작은 호흡(1px 상하)만. 자세는 바뀌지 않는다",
    "idle": "대기 — 아주 작은 호흡(1px 상하)만",
    "idle_phase2": "형태가 변한 뒤의 대기 — 실루엣이 더 불안정하게",
    "attack": "공격 동작 — 예비 자세 → 최대 뻗음 → 되돌아옴. 몸으로만 표현한다",
    "hurt": "피격 — 몸이 뒤로 젖혀지고 자세가 무너진다(1~2칸)",
    "death": "쓰러짐 — 형태가 무너져 내리는 과정. 마지막 칸은 거의 사라진 상태",
    "play": "좌 → 우가 시간 순서. 마지막 칸은 잔상만 남은 상태",
}
## 이펙트 시퀀스의 기본 단계 설명 — 스펙 `_desc`가 비면 이걸 쓴다.
## 캐릭터용 DEFAULT_MOTION["play"]와 나눠 둔다: 이펙트는 "재생"이 아니라 "소멸 과정"이다.
EFFECT_MOTION = "발생 → 확산 → 소멸. 좌 → 우가 시간 순서이고 마지막 칸은 잔상만 남는다"

## 이펙트 속성 → 한국어. 스펙 element 값이 그대로 온다(none은 적지 않는다).
ELEMENT_KO = {
    "physical": "물리",
    "fire": "화염",
    "electric": "전격",
    "ice": "냉기",
    "poison": "독",
    "holy": "신성",
    "dark": "암흑",
}

## 초상 스펙의 표정 이름 → 한국어. 게임(`src/core/portrait_library.gd`)은 스펙의
## `expressions` **순서를 셀 순서로** 읽는다 — 그래서 여기서도 스펙 순서를 그대로 쓴다.
## (첨부 전제 생성기는 normal/worried/determined로 고정돼 있어 퀴즈맨처럼 다른 표정을
##  가진 인물에게 틀린 셀 이름을 준다. 이쪽은 스펙을 따른다.)
EXPRESSION_KO = {
    "normal": "기본 — 평상시 얼굴",
    "worried": "걱정 — 눈썹 안쪽이 올라가고 시선이 살짝 아래로",
    "determined": "결의 — 눈에 힘이 들어가고 입을 다문다",
    "happy": "기쁨 — 눈이 휘고 입꼬리가 올라간다",
    "cheerful": "쾌활 — 활짝 웃는 얼굴, 눈은 반달",
    "serious": "진지 — 표정을 지우고 정면을 본다",
    "laughing": "호탕한 웃음 — 입을 크게 벌리고 눈을 감는다",
    "mighty": "위풍당당 — 턱을 들고 가슴을 편 각도",
    "stoic": "무덤덤 — 감정을 드러내지 않는 굳은 얼굴",
    "injured": "부상 — 이마·볼에 반창고나 멍, 한쪽 눈을 찡그린다",
    "smug": "능글 — 한쪽 입꼬리만 올리고 눈을 가늘게",
    "mysterious": "수수께끼 — 눈이 그늘에 가리고 표정을 읽을 수 없다",
    "tired": "피로 — 눈 밑 그늘, 반쯤 감긴 눈",
    "smiling": "미소 — 입만 옅게 웃는다",
    "apologetic": "미안함 — 눈썹이 처지고 시선을 피한다",
    "confused": "당황 — 눈을 크게 뜨고 입을 벌린다",
    "angry": "분노 — 눈썹이 안쪽으로 내려오고 이를 드러낸다",
    "surprised": "놀람 — 눈이 커지고 눈썹이 위로",
    "annoyed": "짜증 — 한쪽 눈썹만 올리고 입을 삐뚜름하게",
    "shout": "고함 — 입을 크게 벌리고 눈을 부릅뜬다",
    "poetic": "감상 — 먼 곳을 보는 시선, 표정은 부드럽게",
    "proud": "자랑 — 턱을 들고 눈을 감은 채 웃는다",
    "busy": "분주 — 시선이 옆으로 빠지고 땀 한 방울",
    "panicking": "허둥지둥 — 눈이 소용돌이치듯 크게, 땀 여러 방울",
    "stern": "엄격 — 눈매가 가늘고 입이 일자",
    "scheming": "음모 — 눈을 아래로 굴리며 입꼬리만 올린다",
    "coughing": "기침 — 눈을 감고 입을 손등으로 가린다",
    "wise": "현자 — 눈을 지그시 감고 온화하게",
    "drunk": "취기 — 볼이 붉고 눈이 풀린다",
    "sleepy": "졸음 — 눈이 반쯤 감기고 입이 벌어진다",
    "timid": "소심 — 어깨가 움츠러들고 눈을 아래로",
    "sweating": "식은땀 — 이마에 땀줄기, 눈을 크게 뜬다",
}
## 스펙이 표정을 1종만 적어 둔 인물(리메이크 신규 멤버 9종)도 캔버스 계약은
## 768×256 = 3칸이다. 빈 칸을 놀리면 납품이 크기 위반으로 반려되므로 기본 3종으로 채운다.
DEFAULT_EXPRESSIONS = ["normal", "worried", "determined"]


def _palette_hex(limit: int = 40) -> str:
    """허용 팔레트에서 실제로 많이 쓰이는 색 — 확장 팔레트가 그 목록이다."""
    p = os.path.join(ROOT, "assets", "palette_extended.json")
    if not os.path.exists(p):
        return ""
    cols = json.load(io.open(p, encoding="utf-8")).get("colors", [])[:limit]
    return " ".join(cols)


def common_prompt() -> str:
    """대화 맨 앞에 한 번 붙여넣는 공통 규칙."""
    bible = common.style_bible_block()
    palette = _palette_hex()
    return f"""# [공통 지시] BSD 시돌이의 모험 — 도트 스프라이트 제작 규약

아래는 이 대화에서 만들 **모든 그림**에 적용되는 규약이다. 이후 내가 개별 시트를
요청하면 이 규약을 그대로 지킨 채 그려라. 규약과 개별 요청이 충돌하면 **개별 요청의
숫자(캔버스 크기·프레임 수)** 가 우선이고, 화풍은 이 규약이 우선이다.

## 작품
1995년 한국 공대를 배경으로 한 캠퍼스 호러 JRPG의 리메이크. 원작은 1995년 DOS VGA
게임이고, 리메이크는 그 도트를 **후기 클래식 JRPG 픽셀 아트**(쯔바이!!·나르실리온·
악튜러스 계열)로 격상시킨다. 단순 확대·재채색은 실패다.

{bible}

## 그리기 규칙 (전부 필수)
- **순수 픽셀 아트만.** 3D 렌더·벡터·수채/유화 질감·사진 합성 금지. 확대하면 각진
  도트가 한 칸씩 보여야 한다.
- **안티에일리어싱 금지, 그라데이션 금지.** 명암은 색당 4~6단계의 계단식 밴딩으로.
- **반투명 픽셀 0%.** 픽셀은 켜지거나 꺼진다. 경계를 부드럽게 흐리지 마라.
- **1px 다크 아웃라인.** 순수 검정(#000000) 금지 — 짙은 남색(#0A082E) 계열을 쓴다.
- **그림자는 검정이 아니라 색조 그림자**(남보라 #3A285C 계열).
- **고유색 48색 이하.** 실제 납품이 16,000~50,000색으로 온 적이 있다 — 그건 도트가 아니다.
- **배경은 완전 투명(alpha=0).** 투명을 못 만들면 **단색 마젠타 #FF00FF**로 채운다
  (혼색·반투명·경계 흐림 금지 — 정확히 그 값이어야 지울 수 있다).
- 아래는 허용 팔레트(마스터 + 확장) 중 **자주 쓰이는 색을 발췌한 것**이다. 이 안에서
  고르는 것이 가장 안전하고, 모자라면 이 색들 사이의 중간톤까지 쓸 수 있다.
  (허용 범위 자체는 위 "팔레트 잠금" 절이 정한다 — 이 목록이 전부가 아니다):
  `{palette}`

## 캔버스에 그리면 안 되는 것
- 글자·숫자·로고·서명·워터마크·설명 라벨 — **애니메이션 이름이나 프레임 번호 포함**
- **격자선·안내선·셀 경계선.** 셀은 눈에 보이지 않는 규칙일 뿐이다. 선을 그으면 반려다
- 액자·테두리·둥근 모서리 마스크·배경에 깔린 그림자
- 요청한 것 외의 물건(단품만)
- **공격 프레임의 소품·무기·투사체.** 공격은 몸의 동작으로만 표현한다. 날아가는 물체·
  파편·충격파를 셀 안에 그리면 캐릭터 실루엣과 겹쳐 규격 검사가 어긋나고, 게임에서는
  그 칸이 캐릭터로만 잘려 물체가 몸에 달라붙어 보인다. 타격 이펙트는 따로 만든다.

## 출력 형식
- **PNG 1장**, 요청한 캔버스 크기와 **픽셀 단위로 정확히** 일치.
- 크기를 정확히 못 맞추겠으면 **가로세로 비율만이라도 정확히** 지키고, 셀 격자가
  균등하게 나뉘도록 그려라(내가 리샘플로 교정한다).
- 여러 장으로 쪼개 그리지 마라. 한 장의 시트다.
"""


def _sheet_contract(cat: str, asset_id: str) -> dict:
    """스펙에서 그리드 계약을 뽑는다 — review_server.sheet_contract와 같은 규칙."""
    name = SPEC_FILES.get(cat)
    if not name:
        return {}
    path = os.path.join(ROOT, "data", name)
    if not os.path.exists(path):
        return {}
    for sp in json.load(io.open(path, encoding="utf-8")).get("species", []):
        if sp.get("id") != asset_id:
            continue
        anims = sp.get("animations")
        if not isinstance(anims, dict) or not anims:
            return {}
        rows = sorted(anims.items(), key=lambda kv: int(kv[1].get("row", 0)))
        cell = int(sp.get("sheet_cell") or CELL_DEFAULT)
        cols = max(int(a.get("frames", 1)) for _, a in rows)
        return {
            "spec": sp, "cell": cell, "cols": cols, "rows": len(rows),
            "size": (cols * cell, len(rows) * cell), "layout": rows,
            "align": str(sp.get("align", "bottom_center")),
        }
    return {}


def _frames_line(c: dict) -> str:
    return " · ".join(
        f"{int(a.get('row', 0))}행 {n} {int(a.get('frames', 1))}칸" for n, a in c["layout"])


def _character_sheet_prompt(asset_id: str, c: dict) -> str:
    """캐릭터 시트(monsters·npcs·battle_actors) — 프레임 간 **동일성**이 계약인 종류.

    걷기 4칸이 서로 다른 삽화 4장으로 오는 사고가 실제로 있었다. 그래서 크기 유지·
    발 접지·동일 인물임을 매번 못박는다.
    """
    sp = c["spec"]
    cell, cols, rows = c["cell"], c["cols"], c["rows"]
    w, h = c["size"]
    name_ko = sp.get("name_ko", asset_id)
    token = sp.get("token", "")
    pattern = sp.get("pattern", "")
    body = sp.get("body_type", "")
    telegraph = sp.get("telegraph_visual", "")
    # 스타일 바이블(WEB_PROMPT_COMMON.md)이 "실높이 약 80~88% 면적 점유, 왜소한 24px
    # 방치 금지"를 **최상위 지시**로 못박는데, 여기서는 오래 0.75(=75%)를 지시해
    # 두 문서가 충돌했다 — 모델은 둘 중 하나를 어길 수밖에 없었다.
    # 실측(20_processed 11종)의 아트 높이는 74~81%(중앙값 75%)라 바이블 하한에도
    # 못 미쳤다. 바이블이 고치려던 것이 바로 그 '왜소함'이므로 이쪽을 올려 맞춘다.
    art_h = int(cell * 0.84)
    # 화면 표시 크기 — **설치기와 같은 함수**로 뽑는다(배율 사다리까지 같아야 한다).
    # 예전에는 프롬프트가 이 값을 아예 말하지 않아서, 화면 64px로 보일 그림을
    # "칸 128px 안에서 96px 안팎"으로만 지시했다. 19종 중 12종이 절반으로 줄어
    # 표시되는데도 전부에게 같은 말을 했고, 그래서 축소하면 사라질 디테일이
    # 잔뜩 담겨 왔다(flying_thesis v5: 세밀도 0.913, 원작 도트는 0.384).
    from install_delivery import sheet_scale  # noqa: PLC0415 — 지연 임포트

    scale, _why = sheet_scale(sp, cell)
    screen = int(round(cell * scale))
    art_screen = int(round(art_h * scale))

    table = ["| 행(위→아래) | 애니메이션 | 프레임 수 | 그릴 내용 |", "|---|---|---|---|"]
    for n, a in c["layout"]:
        desc = common.body_only_note(a.get("_desc", "") or DEFAULT_MOTION.get(n, "")) or "-"
        table.append(f"| {int(a.get('row', 0))} | {n} | {int(a.get('frames', 1))} | {desc} |")
    align_txt = ("각 칸의 **정확한 중앙**" if c["align"] == "center"
                 else "각 칸의 **가로 중앙 · 세로는 바닥에 접지**(아래 여백 4~5px)")

    return f"""# [요청] {name_ko} ({asset_id}) — 스프라이트 시트 1장

## 정체성 (이게 그림에 보여야 한다)
- {token or name_ko}
- 체형 계열: {body or "미지정"} · 행동 패턴: {pattern or "미지정"}
{f"- 공격 예고 연출: {telegraph}" if telegraph else ""}

## 캔버스 — **{w}×{h}px** (정확히)
이 시트는 **{cell}×{cell}px 칸을 {cols}열 × {rows}행**으로 붙인 것이다
({cell}×{cols} = {w}, {cell}×{rows} = {h}). 칸 경계선은 **그리지 않는다** — 보이지 않는
격자일 뿐이다. 캐릭터는 칸 하나 안에 온전히 들어가야 하고, 옆 칸을 침범하면 안 된다.

## 화면 표시 크기 — **{screen}px** (이게 진짜 크기다)
게임은 이 시트를 그려진 크기 그대로 쓰지 않는다. 칸 {cell}px를 **{scale}배**로 줄여
화면에 **{screen}px**로 그린다. 즉 아트 {art_h}px는 화면에서 약 **{art_screen}px**다.
- **{screen}px에서 안 보이는 디테일은 그리지 마라.** 1~2px 폭의 무늬·글자·가는 선,
  미세한 음영 단계는 축소하면 사라지거나 뭉개진 얼룩이 된다. 픽셀을 거기 쓰지 말고
  형태와 대비에 써라.
- **실루엣만으로 무엇인지 읽혀야 한다.** 색을 다 지우고 검은 형태만 남겼을 때
  {name_ko}(으)로 읽히지 않으면 실패다 — 플레이어가 보는 것은 {screen}px짜리 실루엣이다.

## 행별 배치 (좌 → 우가 재생 순서)
{chr(10).join(table)}

- 요약: {_frames_line(c)}
- **각 행에서 요구한 칸 수만 채우고, 남는 칸은 완전히 비운다**(투명).
- 캐릭터 크기: 칸 {cell}px 안에서 실제 아트 높이 **{art_h}px 안팎**(칸의 80~88% —
  스타일 바이블의 "셀을 꽉 채우는 볼륨감"이 이 수치다. 왜소하게 그리면 반려다).
  모든 프레임에서 같은 크기를 유지한다 — 프레임마다 커지거나 작아지면 재생 시 떨린다.
- 정렬: {align_txt}. 프레임마다 발 위치가 오르내리면 캐릭터가 떠 보인다.
- 소멸·사망(death) 행 정렬은 **본체가 남아 있느냐**로 갈린다(검사도 그렇게 잰다):
  - 본체 덩어리가 내용의 **절반 이상**이면 → 그 **본체**를 칸 가로 중앙·바닥 접지에.
    파편이 어디로 튀든 파편을 기준으로 옮기지 마라.
  - 완전히 흩어져 본체라 할 것이 없으면(절반 미만) → **흩어진 조각 전체**가 칸 가로
    중앙에 오게 한다. 이때 큰 조각 하나를 중앙에 두면 오히려 전체가 한쪽으로 쏠린다.
  어느 쪽이든 조각이 칸 밖으로 나가거나 한쪽으로 쏠리면 반려다.
- 프레임 간 **같은 캐릭터**여야 한다: 머리 크기·색 배치·장식·비례를 유지하고
  포즈만 바꾼다.

## 이 시트에서 특히 자주 틀리는 것
1. 칸 경계에 선을 그어 놓는 것 → 반려
2. 행 이름·프레임 번호를 그림 안에 써 넣는 것 → 반려
3. 캔버스 크기를 {w}×{h}가 아닌 값으로 내보내는 것
4. 공격 프레임에 투사체·소품·무기·파편·충격파를 그려 넣는 것 — 공격은 **몸의 동작으로만**
   (날아가는 물체는 effects 담당. 셀 안에 그리면 실루엣이 커져 정렬 검사가 어긋난다)
5. 부드러운 음영·확대복사·리샘플로 색이 수천 개가 되는 것(48색 이하) — **원본 픽셀로
   그려라. 다른 그림을 확대·축소해 붙이면 반려다**
6. 화면 {screen}px에서 사라질 디테일에 픽셀을 쓰는 것 — 크게 그린 일러스트를 칸에
   욱여넣으면 축소했을 때 형태를 못 알아본다. 처음부터 {screen}px에서 읽히게 설계하라.

## 내보내기 전 스스로 확인
- [ ] 캔버스가 정확히 {w}×{h}px인가
- [ ] {rows}개 행 각각에 요구한 칸 수만큼만 그렸는가(남는 칸은 투명)
- [ ] 칸 경계선·글자·워터마크가 한 줄도 없는가
- [ ] 배경이 완전 투명 또는 단색 #FF00FF인가
- [ ] 고유색 48색 이하, 반투명 픽셀 없음인가
- [ ] 공격 프레임에 몸이 아닌 물체(투사체·파편·무기)가 없는가
- [ ] 소멸 행이 정렬 규칙대로인가(본체가 절반 이상이면 본체 기준, 다 흩어졌으면 전체 기준)
- [ ] **{screen}px로 줄여 봤을 때** 실루엣이 {name_ko}(으)로 읽히는가
"""


def _effect_sheet_prompt(asset_id: str, c: dict) -> str:
    """이펙트 시퀀스(effects) — 캐릭터 어휘를 **한 줄도 쓰지 않는다**.

    스파크·폭발·방전은 프레임마다 형태·크기·밝기가 달라지는 것이 정상이고, 발이 없어서
    접지 기준도 없다(스펙의 align이 center인 이유가 그것이다: "이펙트는 발이 없다").
    캐릭터 시트 문장을 그대로 주면 "같은 크기 유지·발 위치 고정"이라는 정반대 지시가 된다.

    `common.body_only_note()`도 여기서는 쓰지 않는다 — 그 함수는 "투사체·파편은 그리지
    않는다(effects 담당)"를 붙이는데, 이 시트가 바로 그 effects다.
    """
    sp = c["spec"]
    cell, cols, rows = c["cell"], c["cols"], c["rows"]
    w, h = c["size"]
    name_ko = sp.get("name_ko", asset_id)
    token = sp.get("token", "")
    element = str(sp.get("element", ""))
    elem_ko = ELEMENT_KO.get(element, element)
    refs = " · ".join(str(r) for r in sp.get("reference", []) if r)
    peak = int(cell * 0.9)

    table = ["| 행 | 시퀀스 | 프레임 수 | 시간 순서로 무엇이 일어나는가 |", "|---|---|---|---|"]
    for n, a in c["layout"]:
        desc = a.get("_desc", "") or EFFECT_MOTION
        table.append(f"| {int(a.get('row', 0))} | {n} | {int(a.get('frames', 1))} | {desc} |")

    return f"""# [요청] {name_ko} ({asset_id}) — 전투 이펙트 시퀀스 1장

## 이 이펙트가 무엇인가 (이게 그림에 보여야 한다)
- {token or name_ko}
{f"- 속성: {elem_ko}" if elem_ko and element != "none" else ""}
{f"- 원작 참조 계열: {refs}" if refs else ""}

## 캔버스 — **{w}×{h}px** (정확히)
**{cell}×{cell}px 칸을 {cols}열 × {rows}행**으로 붙인 것이다
({cell}×{cols} = {w}, {cell}×{rows} = {h}). 칸 경계선은 **그리지 않는다** — 보이지 않는
격자일 뿐이다.

## 프레임 배치 (좌 → 우가 **시간 순서**)
{chr(10).join(table)}

- 요약: {_frames_line(c)}
- **요구한 칸 수만 채우고, 남는 칸은 완전히 비운다**(투명).

## 이펙트 시트 규칙 — 스프라이트 시트와 정반대다
- **프레임마다 형태·크기·밝기가 달라지는 것이 정상이다.** 같은 모양을 유지하지 마라 —
  터지고 퍼지고 흩어지는 **변화 과정 자체가 이 시트의 내용**이다. 같은 그림을
  색만 바꿔 {cols}장 늘어놓으면 반려다.
- **기준은 접지가 아니라 칸의 정확한 중앙이다.** 충돌 지점(임팩트 중심)이 칸 중앙에
  오도록 그린다. 바닥에 세우지 않는다 — 이펙트에는 발이 없다.
- **첫 칸은 작고 밝게** 시작한다(섬광 코어). 중간 칸에서 가장 크게 퍼지고,
  **마지막 칸은 잔상만** 남긴다(거의 사라진 상태 — 옅은 파편·연기 몇 점).
- 가장 커지는 칸도 **칸의 90%({peak}px) 안**에서 끝낸다. 옆 칸을 침범하면
  재생 시 앞 프레임의 파편이 다음 칸에 남아 보인다.
- **밝은 중심에서 바깥으로 어두워지는 계단식 3~4단.** 글로우·블러·반투명 페이드 금지 —
  옅어지는 것은 **단계로 그린 색**이지 알파가 아니다.
- **인물·몬스터·바닥·배경은 그리지 않는다. 이펙트 하나만.**
  게임이 이 그림을 전투 화면 위에 덧그린다.

## 이 시트에서 특히 자주 틀리는 것
1. {cols}칸이 사실상 같은 그림인 것(=애니메이션이 아니라 색 변주)
2. 이펙트를 맞는 대상까지 같이 그리는 것(대상은 게임이 따로 그린다)
3. 칸 경계에 선을 긋거나 프레임 번호를 써 넣는 것 → 반려
4. 반투명 알파로 페이드아웃시키는 것(반투명 픽셀 0%)
5. 캔버스 크기를 {w}×{h}가 아닌 값으로 내보내는 것

## 내보내기 전 스스로 확인
- [ ] 캔버스가 정확히 {w}×{h}px인가
- [ ] {cols}칸이 서로 **다른 단계**인가(형태·크기가 실제로 변하는가)
- [ ] 각 칸의 중심이 칸의 정확한 중앙에 있는가
- [ ] 마지막 칸이 잔상 수준으로 옅어졌는가
- [ ] 이펙트 외에 아무것도 그리지 않았는가(배경·바닥·대상 없음)
- [ ] 칸 경계선·글자가 한 줄도 없고, 배경이 투명 또는 단색 #FF00FF인가
- [ ] 고유색 48색 이하, 반투명 픽셀 없음인가
"""


def _cut_sheet_prompt(asset_id: str, c: dict) -> str:
    """전투 대형 컷(battle_cuts) — 셀 512짜리 **연출 컷**.

    원작(1995)은 전투를 320×200 전체 화면 프레임 시퀀스로 연출했다(격투게임 패러디,
    리미티드 애니메이션). 그래서 이 칸은 "캐릭터가 들어갈 상자"가 아니라 **카메라 프레임**이고,
    필드 도트용 수치(칸의 70~85%)를 그대로 쓰면 안 된다:

      - 필드 도트의 여백은 게임에서 32~64px로 줄어들 때를 대비한 **안전 마진**이다.
      - 512 컷의 여백은 화면에 크게 뜨는 그림의 **머리 위 공간·발밑 자리**, 곧 구도다.

    그래서 첨부 전제 패키지(`assets/raw/llm/battle_cuts/*/prompt.md`)와 같은 값인
    **칸의 75~90%**를 쓴다. 두 경로가 다른 숫자를 부르면 같은 배우가 컷마다 다른
    크기로 온다.
    """
    sp = c["spec"]
    cell, cols, rows = c["cell"], c["cols"], c["rows"]
    w, h = c["size"]
    name_ko = sp.get("name_ko", asset_id)
    token = sp.get("token", "")
    trigger = sp.get("trigger", "")
    actor = sp.get("actor", "")
    lo, hi = int(cell * 0.75), int(cell * 0.90)

    table = ["| 행 | 시퀀스 | 프레임 수 | 키 포즈(좌 → 우) |", "|---|---|---|---|"]
    for n, a in c["layout"]:
        desc = common.body_only_note(a.get("_desc", "") or DEFAULT_MOTION.get(n, "")) or "-"
        table.append(f"| {int(a.get('row', 0))} | {n} | {int(a.get('frames', 1))} | {desc} |")

    return f"""# [요청] {name_ko} ({asset_id}) — 전투 대형 연출 컷 1장

## 이 그림의 성격
원작(1995)은 전투를 **320×200 전체 화면 프레임 시퀀스**로 연출했다 — 격투게임 패러디의
리미티드 애니메이션이다. 이 컷은 그 층을 되살린 것으로, 필드 도트를 확대한 그림이 아니라
**화면에 크게 뜨는 연출 원화**다. 공격·피격 순간에만 재생된다.

## 정체성 (이게 그림에 보여야 한다)
- {token or name_ko}
{f"- 배우: {actor}" if actor else ""}
{f"- 재생 시점: {trigger}" if trigger else ""}

## 캔버스 — **{w}×{h}px** (정확히)
**{cell}×{cell}px 칸을 {cols}열 × {rows}행**으로 붙인 것이다
({cell}×{cols} = {w}, {cell}×{rows} = {h}). 칸 경계선은 **그리지 않는다**.

## 프레임 배치 (좌 → 우가 재생 순서)
{chr(10).join(table)}

- 요약: {_frames_line(c)}
- **요구한 칸 수만 채우고, 남는 칸은 완전히 비운다**(투명).

## 칸 구성 — 전신 + 여백(카메라 프레이밍)
- 칸 하나가 **한 컷의 화면**이다. 인물 **전신**이 들어가고 나머지는 구도용 여백이다.
- 인물 실높이 **{lo}~{hi}px**(칸 {cell}의 75~90%). 필드 도트의 70~85%와 다른 값인 이유:
  필드 도트의 여백은 축소 대비 안전 마진이지만, 이 컷의 여백은 **머리 위 공간과 발밑
  자리**라는 구도 요소다. 인물이 작으면 연출 컷이 아니라 확대된 도트로 보인다.
- 정렬: **가로 중앙 · 세로는 칸 하단 접지**(발이 칸 아래쪽에 닿는다).
- 임팩트 프레임에서 팔·다리가 칸 **위아래 경계 밖으로 잘려 나가도 좋다**(원작이 그랬다).
  다만 **좌우 이웃 칸은 침범하지 않는다** — 옆 프레임에 남의 팔이 남아 보인다.
- **배우만 그린다.** 배경·바닥·풍경·효과선 배경 금지 — 게임이 전투 배경 위에 얹는다.

## 리미티드 애니메이션 규칙
- 부드러운 중간 프레임 대신 **키 포즈의 대비**로 움직임을 만든다. {cols}장뿐이므로
  각 장이 결정적이어야 한다.
- 속도감은 잔상선·궤적 **1~3줄**로 낸다. 블러 금지 — 선으로 그린다.
- 카메라 각도는 프레임마다 바꾸지 않는다(같은 시점 유지).
- 프레임 간 인물 일관: 체형·의상·머리·색은 그대로, **포즈만** 바뀐다.

## 내보내기 전 스스로 확인
- [ ] 캔버스가 정확히 {w}×{h}px인가
- [ ] {cols}칸의 포즈가 서로 확실히 다른가(같은 포즈의 미세 변주가 아닌가)
- [ ] 인물 실높이가 칸의 75~90%인가, 발이 칸 하단에 닿는가
- [ ] 배경·바닥을 그리지 않았는가(투명 또는 단색 #FF00FF)
- [ ] 칸 경계선·글자·워터마크가 한 줄도 없는가
- [ ] 고유색 48색 이하, 반투명 픽셀 없음인가
"""


def _token_bullets(token: str) -> list:
    """고정 서술 토큰 → 확인 항목 목록.

    "식당 아가씨: 앞치마+머리 수건, 활짝 웃는 얼굴" → ["앞치마+머리 수건", "활짝 웃는 얼굴"].
    한 줄로 뭉쳐 적으면 무시된다 — 앞치마·머리 수건이 통째로 빠진 금발 인물이 실제로 왔다.
    (export_portrait_packages.identity_tokens와 같은 규칙. 저쪽은 첨부 패키지용이다.)
    """
    body = token.split(":", 1)[-1]
    return [p.strip() for p in re.split(r"[,·]| / ", body) if p.strip()]


def _portrait_prompt(asset_id: str) -> str:
    """대화 초상(portraits) — 768×256 = 256 칸 3개.

    칸 순서가 곧 표정 순서다: `src/core/portrait_library.gd`가 스펙의 `expressions`
    배열 순서를 셀 인덱스로 읽는다. 그래서 표정 이름을 고정하지 않고 **스펙에서 뽑는다**.
    """
    path = os.path.join(ROOT, "assets", "spec", "portraits", asset_id + ".json")
    if not os.path.exists(path):
        return f"(스펙에 portraits/{asset_id} 없음 — assets/spec/portraits/{asset_id}.json)"
    sp = json.load(io.open(path, encoding="utf-8"))
    name = sp.get("name", asset_id)
    token = sp.get("subject_token", "")
    exprs = [str(e) for e in sp.get("expressions", []) if e] or list(DEFAULT_EXPRESSIONS)
    padded = list(exprs)
    for e in DEFAULT_EXPRESSIONS:
        if len(padded) >= 3:
            break
        if e not in padded:
            padded.append(e)
    padded = padded[:3]
    (w, h), _ = FLAT["portraits"]
    cell = h

    table = ["| 칸(좌→우) | 표정 이름 | 그릴 표정 |", "|---|---|---|"]
    for i, e in enumerate(padded, start=1):
        table.append(f"| {i} | {e} | {EXPRESSION_KO.get(e, e)} |")
    extra = ""
    if len(exprs) < 3:
        extra = ("\n- 스펙에 적힌 표정은 `" + "` / `".join(exprs) + "` 뿐이라 나머지 칸은 "
                 "프로젝트 기본 표정으로 채웠다. **1번 칸이 게임이 실제로 쓰는 기본값**이다.")
    bullets = "\n".join(f"  - [ ] {b}" for b in _token_bullets(token)) or "  - [ ] (토큰 없음)"

    return f"""# [요청] {name} ({asset_id}) — 대화 초상 시트 1장

## 인물 (이게 그림에 보여야 한다)
- 고정 서술 토큰: {token or name}
- 신원 표지 — 하나라도 빠지면 **다른 인물**이다:
{bullets}

## 캔버스 — **{w}×{h}px** (정확히)
{cell}×{cell}px 칸 **3개를 가로로** 붙인 것이다({cell}×3 = {w}). 칸 경계선은
**그리지 않는다** — 보이지 않는 격자일 뿐이다. 세로로 쌓거나 3장으로 나눠 내지 마라.

## 칸별 표정 (칸 순서 = 표정 순서. 게임이 이 순서로 잘라 쓴다)
{chr(10).join(table)}
{extra}

## 구도 (숫자로 못박는다 — 참조 그림이 없다)
- **바스트업**: 머리부터 어깨까지. 가슴 아래·손·전신 금지.
- 머리 꼭대기는 칸 위 경계에서 **16~32px 아래**, 어깨 선은 **칸 아래 경계에 닿는다**.
- 얼굴(턱~정수리)이 칸 높이의 **45~60%**. 얼굴이 작으면 대화창(98px)에서 뭉개진다.
- 시선은 정면 계열(정면~살짝 3/4 각도). 3칸 모두 **같은 각도**.
- 좌우 여백은 칸 폭의 10% 안팎으로 균등하게.

## 3칸 일관성 (위반 시 반려)
- 머리 크기·헤어스타일·의상·색 배치는 **완전히 동일**하다. 칸마다 인물이 커지거나
  머리 모양이 달라지면 대화 중 표정이 바뀔 때 다른 사람으로 보인다.
- 표정 변화는 **눈·눈썹·입**으로만 만든다. 얼굴 각도·크기를 바꾸지 않는다.
- 게임은 이 시트를 98×98px로 줄여 쓴다 — 눈·입은 축소해도 읽히도록 굵게.

## 내보내기 전 스스로 확인
- [ ] 캔버스가 정확히 {w}×{h}px인가(가로 3칸)
- [ ] 3칸의 인물이 같은 크기·같은 각도인가(표정만 다른가)
- [ ] 위 신원 표지가 3칸 모두에 실제로 보이는가
- [ ] 칸 경계선·글자·표정 이름이 한 줄도 없는가
- [ ] 배경이 완전 투명 또는 단색 #FF00FF인가
- [ ] 고유색 48색 이하, 반투명 픽셀 없음인가
"""


def _item_prompt(asset_id: str) -> str:
    """아이템 아이콘(items) — 96×96 단품.

    이름·분류·수치는 `data/items.json`이 정본이고, 분류별 그리기 지침과 수치 문장은
    첨부 전제 생성기(export_item_icon_packages)의 것을 그대로 가져다 쓴다 —
    같은 물건에 두 경로가 다른 지시를 내리면 아이콘이 서로 다른 화풍으로 온다.
    """
    path = os.path.join(ROOT, "data", "items.json")
    if not os.path.exists(path):
        return "(data/items.json 없음 — 아이템 정의를 만들 근거가 없다)"
    items = json.load(io.open(path, encoding="utf-8")).get("items", [])
    item = next((i for i in items if i.get("id") == asset_id), None)
    if item is None:
        return f"(data/items.json에 {asset_id} 없음)"
    kind = str(item.get("kind", ""))
    kind_ko, kind_hint = item_pkg.KIND_GUIDE.get(kind, (kind or "기타", "이름에 맞는 형태로"))
    (w, h), _ = FLAT["items"]

    return f"""# [요청] {item.get("name_ko", asset_id)} ({asset_id}) — 아이템 아이콘 1장

## 그릴 것
- 이름: **{item.get("name_ko", asset_id)}**
- 분류: {kind_ko} — {kind_hint}
{item_pkg.stat_lines(item)}

수치가 그림에 반영돼야 한다 — 공격력이 높은 무기는 더 크고 험하게, 회복량이 큰 약은
더 큰 용기로. 같은 분류 안에서 강약이 실루엣으로 구별돼야 한다.

## 캔버스 — **{w}×{h}px** (정확히)
단일 아이콘 1장. 시트가 아니다 — 여러 칸으로 나누거나 변형을 나열하지 마라.

## 아이콘 규약 (인벤토리·상점·단축 슬롯에서 그대로 쓰인다)
- **물건 하나만.** 손·인물·받침대·그림자 바닥·설명 글자·액자 테두리 금지.
- **정면(또는 살짝 3/4) 단품 구도.** 원근을 깊게 주지 않는다.
- 캔버스 **가장자리 6px는 비운다** — 목록에서 더 작게 줄어도 형태가 뭉개지지 않게.
- 물건은 남는 영역을 꽉 채우되(가로세로 중 긴 쪽이 **80px 안팎**) 잘리지 않게.
- **실루엣만으로 무엇인지 읽혀야 한다.** 색을 지우고 검은 형태만 남겼을 때
  다른 아이템과 구별되지 않으면 다시 그린다 — 목록에서 사람은 형태를 먼저 본다.
- 외곽 1px 다크 아웃라인, 내부 음영 2~4단. 채도는 높게(작아서 탁하면 안 보인다).

## 내보내기 전 스스로 확인
- [ ] 캔버스가 정확히 {w}×{h}px인가(1장, 시트 아님)
- [ ] 물건 하나만 있는가(손·인물·글자·액자 없음)
- [ ] 가장자리 6px가 비어 있는가
- [ ] 24px로 줄여도 무엇인지 알아볼 수 있는가
- [ ] 배경이 완전 투명 또는 단색 #FF00FF인가
- [ ] 고유색 48색 이하, 반투명 픽셀 없음인가
"""


def _keyart_prompt(asset_id: str) -> str:
    """키아트(keyart) — 1920×1080 컷씬 일러스트. 스펙의 장면 서술이 내용의 전부다."""
    path = os.path.join(ROOT, "assets", "spec", "keyart", asset_id + ".json")
    if not os.path.exists(path):
        return f"(스펙에 keyart/{asset_id} 없음 — assets/spec/keyart/{asset_id}.json)"
    sp = json.load(io.open(path, encoding="utf-8"))
    title = sp.get("title", asset_id)
    desc = sp.get("description", "")
    res = sp.get("resolution", {}) or {}
    w = int(res.get("width", 1920))
    h = int(res.get("height", 1080))
    native = str(res.get("render_native", "480x270_nearest"))

    return f"""# [요청] {title} ({asset_id}) — 키아트 1장

## 장면 (이게 그림에 보여야 한다)
- 제목: {title}
- 묘사: {desc}

이 묘사에 적힌 사물·인물·시간대·날씨가 **전부** 화면에 있어야 한다. 하나라도 빠지면
다른 장면이다. 묘사에 없는 것을 새로 들여놓지도 마라.

## 캔버스 — **{w}×{h}px (16:9) PNG 1장** (정확히)
- 게임 삽입 시 **{native}**로 축소된다: 실루엣과 명암 대비를 **크게·명확하게** 잡아라.
  미세 텍스처는 축소에서 통째로 사라지고 지저분한 노이즈만 남는다.
- 이 그림은 **배경을 포함한 완성 화면**이다(투명 배경이 아니다 — 스프라이트가 아니다).
  화면 전체를 채워 그린다.

## 구도 (숫자로 못박는다 — 참조 그림이 없다)
- 주 피사체를 화면 높이의 **40~70%** 크기로. 화면 어디가 주인공인지 한눈에 보여야 한다.
- 명암 대비 3층으로 나눈다: 밝은 광원부 / 중간 톤 / 어두운 전경 실루엣.
- 인물이 등장하면 **SD 비율**(머리:몸 ≈ 1:1.2)을 쓴다 — 게임 안 캐릭터와 같은 어휘다.
- 글자·자막·타이틀 로고를 그려 넣지 않는다. 텍스트는 게임이 따로 얹는다.

## 톤
- 1995년 한국 공대 캠퍼스 호러. 어두운 VGA 레트로를 **따뜻하고 채도 있는 JRPG 화면**으로
  격상시키되, 이 장면의 묘사가 요구하는 무드(폭우·공포·긴장·감동)는 그대로 지킨다.
- 픽셀 아트 감성 유지: 안티에일리어싱 금지, 그라데이션은 계단식 밴딩으로.
- 그림자는 검정이 아니라 남보라 계열(#3A285C 방향) 색조 그림자.

## 내보내기 전 스스로 확인
- [ ] 캔버스가 정확히 {w}×{h}px인가
- [ ] 묘사에 적힌 요소가 전부 화면에 있는가
- [ ] {native}로 줄였을 때도 무슨 장면인지 읽히는가
- [ ] 캔버스 안에 글자·로고·서명이 없는가
- [ ] 그라데이션 대신 계단식 밴딩인가, 반투명 픽셀이 없는가
"""


## FLAT 카테고리별 전용 생성기. 세 종류가 크기만 다른 게 아니라 **그리는 물건이 다르다** —
## 하나의 문구로 묶으면 예전처럼 "설명을 더 적어 주면 이 자리에 붙여 넣는다"로 끝난다.
FLAT_BUILDERS = {
    "portraits": _portrait_prompt,
    "items": _item_prompt,
    "keyart": _keyart_prompt,
}
## 시트 종류 → 생성기.
SHEET_BUILDERS = {
    "character": _character_sheet_prompt,
    "effect": _effect_sheet_prompt,
    "cut": _cut_sheet_prompt,
}


def sheet_prompt(cat: str, asset_id: str) -> str:
    """이 에셋 한 장을 위한 상세 프롬프트(공통 프롬프트 다음에 붙여넣는다).

    이름과 인자는 고정이다 — `tools/review/review_server.py`의 `/api/fixer/webprompt`와
    셀 편집기의 [웹 챗용 프롬프트] 패널이 이 서명을 그대로 부른다.
    """
    if cat in FLAT_BUILDERS:
        return FLAT_BUILDERS[cat](asset_id)
    c = _sheet_contract(cat, asset_id)
    if not c:
        return f"(스펙에 {cat}/{asset_id} 없음 — 계약을 만들 근거가 없다)"
    return SHEET_BUILDERS[SHEET_KIND.get(cat, "character")](asset_id, c)


def _all_ids() -> list:
    """`--write`가 구울 (카테고리, id) 전부 — **8개 카테고리 모두**.

    2026-09-09까지 이 함수는 SPEC_FILES 5종만 훑었고, 그래서 portraits·items·keyart는
    스펙이 25·65·6건 있는데도 웹 프롬프트가 0장이었다. 설치 여부로 거르지 않는다 —
    몬스터도 시트가 이미 설치된 종을 포함해 전부 굽는다(재의뢰가 이 도구의 용도다).
    """
    out = []
    for cat, name in SPEC_FILES.items():
        path = os.path.join(ROOT, "data", name)
        if not os.path.exists(path):
            continue
        for sp in json.load(io.open(path, encoding="utf-8")).get("species", []):
            if isinstance(sp.get("animations"), dict) and sp["animations"]:
                out.append((cat, sp["id"]))
    # 스펙 폴더 이름이 곧 카테고리 이름이다. id 필드 이름만 다르다(asset_id / scene_id).
    for cat, key in (("portraits", "asset_id"), ("keyart", "scene_id")):
        for p in sorted(glob.glob(os.path.join(ROOT, "assets", "spec", cat, "*.json"))):
            sp = json.load(io.open(p, encoding="utf-8"))
            out.append((cat, str(sp.get(key) or os.path.splitext(os.path.basename(p))[0])))
    items_json = os.path.join(ROOT, "data", "items.json")
    if os.path.exists(items_json):
        for it in json.load(io.open(items_json, encoding="utf-8")).get("items", []):
            if it.get("id"):
                out.append(("items", it["id"]))
    return out


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser()
    ap.add_argument("cat", nargs="?", default="")
    ap.add_argument("asset_id", nargs="?", default="")
    ap.add_argument("--common", action="store_true", help="공통 프롬프트만 출력")
    ap.add_argument("--write", action="store_true", help="파일로 굽는다")
    args = ap.parse_args()

    if args.write:
        os.makedirs(OUT_DIR, exist_ok=True)
        io.open(OUT_COMMON, "w", encoding="utf-8", newline="\n").write(common_prompt())
        per = {}
        n = 0
        for cat, sid in _all_ids():
            path = os.path.join(OUT_DIR, f"{cat}__{sid}.md")
            io.open(path, "w", encoding="utf-8", newline="\n").write(sheet_prompt(cat, sid))
            per[cat] = per.get(cat, 0) + 1
            n += 1
        # 카테고리별 수를 찍는다 — 총계만 보면 어느 종류가 통째로 빠졌는지 안 보인다.
        detail = " · ".join(f"{c} {per[c]}" for c in sorted(per))
        print(f"[web_prompt] 공통 1건 + 상세 {n}건 -> assets/gen/prompts/")
        print(f"[web_prompt] 카테고리별: {detail}")
        return
    if args.common or not args.cat:
        print(common_prompt())
        return
    print(sheet_prompt(args.cat, args.asset_id))


if __name__ == "__main__":
    main()
