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

실행:
  python tools/convert/web_prompt.py --common                 공통 프롬프트만
  python tools/convert/web_prompt.py monsters c_bug           그 시트의 상세 프롬프트
  python tools/convert/web_prompt.py --write                  둘 다 파일로 굽는다
      -> assets/gen/prompts/WEB_PROMPT_COMMON.md
      -> assets/gen/prompts/web/<cat>__<id>.md
"""
from __future__ import annotations

import argparse
import io
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import llm_package_common as common  # noqa: E402

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
## 시트가 아닌 카테고리 — (캔버스, 설명). 검증기·편집기의 FLAT_CONTRACTS와 같은 수다.
FLAT = {
    "portraits": ((768, 256), "256×256 셀 3개 가로 배치 = 표정 3종(normal / worried / determined)"),
    "items": ((96, 96), "96×96 단일 아이콘 1장"),
    "keyart": ((1920, 1080), "1920×1080 (16:9) 일러스트 1장"),
}
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
- 색은 아래 팔레트 안에서 고른다(모자라면 이 색들 사이의 중간톤까지만 허용):
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


def sheet_prompt(cat: str, asset_id: str) -> str:
    """이 시트 한 장을 위한 상세 프롬프트(공통 프롬프트 다음에 붙여넣는다)."""
    c = _sheet_contract(cat, asset_id)
    if not c:
        size, desc = FLAT.get(cat, ((0, 0), ""))
        if not size[0]:
            return f"(스펙에 {cat}/{asset_id} 없음 — 계약을 만들 근거가 없다)"
        return f"""# [요청] {asset_id} — {cat}

- **캔버스: {size[0]}×{size[1]}px PNG 1장** (정확히)
- 구성: {desc}
- 배경: 완전 투명 또는 단색 마젠타 #FF00FF
- 위 공통 규약(픽셀 규칙·팔레트·금지 목록)을 그대로 지킨다.

## 그릴 대상
{asset_id}

(설명을 더 적어 주면 이 자리에 붙여 넣는다.)
"""

    sp = c["spec"]
    cell, cols, rows = c["cell"], c["cols"], c["rows"]
    w, h = c["size"]
    name_ko = sp.get("name_ko", asset_id)
    token = sp.get("token", "")
    pattern = sp.get("pattern", "")
    body = sp.get("body_type", "")
    telegraph = sp.get("telegraph_visual", "")
    art_h = int(cell * 0.75)

    table = ["| 행(위→아래) | 애니메이션 | 프레임 수 | 그릴 내용 |", "|---|---|---|---|"]
    for n, a in c["layout"]:
        desc = common.body_only_note(a.get("_desc", "") or DEFAULT_MOTION.get(n, "")) or "-"
        table.append(f"| {int(a.get('row', 0))} | {n} | {int(a.get('frames', 1))} | {desc} |")
    frames_line = " · ".join(
        f"{int(a.get('row', 0))}행 {n} {int(a.get('frames', 1))}칸" for n, a in c["layout"])
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

## 행별 배치 (좌 → 우가 재생 순서)
{chr(10).join(table)}

- 요약: {frames_line}
- **각 행에서 요구한 칸 수만 채우고, 남는 칸은 완전히 비운다**(투명).
- 캐릭터 크기: 칸 {cell}px 안에서 실제 아트 높이 **{art_h}px 안팎**(칸의 70~85%).
  모든 프레임에서 같은 크기를 유지한다 — 프레임마다 커지거나 작아지면 재생 시 떨린다.
- 정렬: {align_txt}. 프레임마다 발 위치가 오르내리면 캐릭터가 떠 보인다.
- 프레임 간 **같은 캐릭터**여야 한다: 머리 크기·색 배치·장식·비례를 유지하고
  포즈만 바꾼다.

## 이 시트에서 특히 자주 틀리는 것
1. 칸 경계에 선을 그어 놓는 것 → 반려
2. 행 이름·프레임 번호를 그림 안에 써 넣는 것 → 반려
3. 캔버스 크기를 {w}×{h}가 아닌 값으로 내보내는 것
4. 공격 프레임에 투사체·소품을 그려 넣는 것(몸의 동작으로만)
5. 부드러운 음영으로 색이 수천 개가 되는 것(48색 이하)

## 내보내기 전 스스로 확인
- [ ] 캔버스가 정확히 {w}×{h}px인가
- [ ] {rows}개 행 각각에 요구한 칸 수만큼만 그렸는가(남는 칸은 투명)
- [ ] 칸 경계선·글자·워터마크가 한 줄도 없는가
- [ ] 배경이 완전 투명 또는 단색 #FF00FF인가
- [ ] 고유색 48색 이하, 반투명 픽셀 없음인가
"""


def _all_ids() -> list:
    out = []
    for cat, name in SPEC_FILES.items():
        path = os.path.join(ROOT, "data", name)
        if not os.path.exists(path):
            continue
        for sp in json.load(io.open(path, encoding="utf-8")).get("species", []):
            if isinstance(sp.get("animations"), dict) and sp["animations"]:
                out.append((cat, sp["id"]))
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
        n = 0
        for cat, sid in _all_ids():
            path = os.path.join(OUT_DIR, f"{cat}__{sid}.md")
            io.open(path, "w", encoding="utf-8", newline="\n").write(sheet_prompt(cat, sid))
            n += 1
        print(f"[web_prompt] 공통 1건 + 시트 {n}건 -> assets/gen/prompts/")
        return
    if args.common or not args.cat:
        print(common_prompt())
        return
    print(sheet_prompt(args.cat, args.asset_id))


if __name__ == "__main__":
    main()
