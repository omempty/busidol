#!/usr/bin/env python3
"""의뢰 묶음 포장 — 폴더 하나를 그대로 그림 LLM에 넘길 수 있게 만든다.

## 왜 필요했나 (2026-08-28)

공용 참조를 카테고리 루트에 1부만 두도록 정리하면서(중복 127개 제거) 패키지 폴더는
`../style_ref.png` 같은 **상대 경로**를 가리키게 됐다. 저장소에는 그게 맞지만,
"폴더를 통째로 LLM에 던진다"에는 불편하다. 여기서 **전달용 사본만 평탄화**한다 —
저장소는 1부, 전달 묶음은 자기완결.

또 이미지 생성은 토큰이 비싸서 **몇 개만 시범 발주**하는 일이 잦다. 그래서 기본이
"전량"이 아니라 **골라 담기**다(`--pick N` 또는 id 나열).

## 산출물

  assets/raw/llm/_batch/<이름>/
    작업지시.md            무엇을 몇 장, 어떤 순서로, 어디에 저장할지 (LLM이 첫 줄부터 읽는다)
    먼저읽기.md            그래픽 담당 지시서 사본
    <카테고리>__<id>/      prompt.md(경로 평탄화) + 첨부 이미지 전부
      └ 웹붙여넣기.md      **웹 채팅용 축약본** — 한 메시지에 붙여넣고 이미지 3~4장만 첨부
    _제출/                 여기에 납품 PNG를 저장하게 한다(그대로 intake.py에 넘긴다)

## 웹 LLM(무료·토큰 절약) 경로

파일 접근이 없는 웹 채팅에도 의뢰할 수 있어야 한다. 전문(prompt.md)은 9KB 안팎이라
무료 티어에서 부담이므로, 같은 계약을 **2KB 안쪽으로 줄인 축약본**을 함께 낸다.
줄이되 톤·규격의 뼈대는 남긴다: 스타일 타깃 요약 · 출력 규격 · 금지 목록 · 자기검증 ·
서브팔레트 hex. 첨부는 우선순위 3~4장만 고른다(격자 → 원작 화풍 → 스왑치).

## 사용

  python tools/dev/pack_request.py --pick 3                    비어 있는 것부터 3건
  python tools/dev/pack_request.py monsters:sys_builder effects:hit_spark
  python tools/dev/pack_request.py --cat portraits --pick 2 --name 시범1
"""
from __future__ import annotations

import io
import os
import re
import shutil
import sys
from datetime import datetime

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
LLM = os.path.join(ROOT, "assets", "raw", "llm")
BATCH_ROOT = os.path.join(LLM, "_batch")
AGENT_DOC = os.path.join(ROOT, "assets", "gen", "prompts", "GRAPHIC_AGENT_PROMPT.md")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

## 카테고리 → (설명, 게임에서 비는 것). 우선순위는 asset_status의 공백 순서를 따른다.
CATEGORIES = [
    ("portraits", "대화 초상", "대화창에 얼굴이 안 뜬다"),
    ("effects", "전투 이펙트", "물리·화염·전격이 전부 같은 점 파티클"),
    ("battle_cuts", "전투 대형 컷", "공격·피격 순간의 큰 그림이 없다"),
    ("battle_actors", "전투 SD 시트", "주인공이 전투에서 idle만 토글"),
    ("monsters", "몬스터·보스", "전투에서 색 사각형"),
    ("npcs", "필드 NPC", "주인공 얼굴로 대체 출력"),
    ("keyart", "컷신 키아트", "컷신에 그림이 없다"),
    ("items", "아이템 아이콘", "인벤토리에 색 상자 + 글자"),
]
PATH_RE = re.compile(r"`((?:\.\./)+)([^`]+)`")


def package_dirs(cat: str) -> list:
    base = os.path.join(LLM, cat)
    if not os.path.isdir(base):
        return []
    return sorted(
        d for d in os.listdir(base)
        if os.path.isdir(os.path.join(base, d))
        and not d.startswith("_")
        and os.path.exists(os.path.join(base, d, "prompt.md"))
    )


def flatten(cat: str, asset_id: str, dst_dir: str) -> tuple:
    """패키지 하나를 자기완결 폴더로 복사한다. 반환 (첨부 수, 프롬프트 본문).

    prompt.md의 `../foo.png`를 `foo.png`로 고치고 그 파일을 같이 복사한다 —
    경로가 남아 있으면 LLM이 없는 파일을 찾다가 지시를 건너뛴다.
    """
    src_dir = os.path.join(LLM, cat, asset_id)
    os.makedirs(dst_dir, exist_ok=True)
    text = io.open(os.path.join(src_dir, "prompt.md"), encoding="utf-8").read()
    copied = 0

    # ① 패키지 자체 파일
    for f in sorted(os.listdir(src_dir)):
        if f == "prompt.md":
            continue
        shutil.copyfile(os.path.join(src_dir, f), os.path.join(dst_dir, f))
        copied += 1

    # ② 프롬프트가 가리키는 상위 경로 파일(공용 참조)
    for up, rel in set(PATH_RE.findall(text)):
        depth = up.count("../")
        base = os.path.join(LLM, cat) if depth == 1 else LLM
        src = os.path.join(base, rel.replace("/", os.sep))
        if not os.path.exists(src):
            continue
        flat = os.path.basename(rel)
        shutil.copyfile(src, os.path.join(dst_dir, flat))
        text = text.replace(f"`{up}{rel}`", f"`{flat}`")
        copied += 1
    text = text.replace("(`..` = 카테고리 루트, 공용 1부)", "(전부 이 폴더 안에 있다)")
    io.open(os.path.join(dst_dir, "prompt.md"), "w", encoding="utf-8").write(text)
    return copied, text


## 웹 축약본 머리말 — 스타일 바이블 전문 대신 뼈대만. 톤 일관성은 이 6줄과
## 서브팔레트 hex, 그리고 첨부한 원작 그림이 함께 유지한다.
WEB_STYLE_HEAD = """[프로젝트] 1995년 한국 공대 배경 캠퍼스 호러 JRPG 「BSD 시돌이의 모험」 리메이크.
[스타일] 원작 DOS VGA 도트를 베이스로 후기 클래식 JRPG 픽셀 아트로 격상
 - 픽셀 아트만. 3D 렌더·벡터·수채 금지. 안티에일리어싱·그라데이션 금지(색당 4~6단 밴딩)
 - 외곽선 1px 다크 — 순수 블랙 금지, 짙은 남색(#0A082E 방향)
 - 그림자는 검정 대신 남보라(#3A285C 방향) 색조 그림자
 - 고유색 24~48색. 따뜻하고 채도 있는 톤(어둡게 가라앉히지 말 것)
 - 배경은 완전 투명. 불가하면 마젠타 #FF00FF 단색(혼색·반투명 금지)"""

## 첨부 우선순위 — 웹 채팅은 첨부 수 제한이 있으므로 이 순서로 3~4장만 고른다.
WEB_ATTACH_PRIORITY = (
    "grid_template.png",
    "style_ref.png",
    "orig_enemy_1.png",
    "orig_portrait_1.png",
    "orig_person_1.png",
    "scale_ref.png",
    "subpalette.png",
)


def extract_section(text: str, start: str, stops: tuple) -> str:
    """프롬프트에서 한 절만 잘라 온다(축약본 조립용).

    제목은 **줄 전체가 일치**해야 한다 — 접두 일치로 찾으면 "## 캐릭터"가 스타일 바이블의
    "## 캐릭터 일관성"을 먼저 물어서 정작 인물 설명이 빠진다(실측).
    """
    marker = chr(10) + start + chr(10)
    if not text.startswith(start + chr(10)) and marker not in text:
        return ""
    idx = 0 if text.startswith(start + chr(10)) else text.index(marker) + 1
    body = text[idx:]
    cut = len(body)
    for stop in stops:
        idx = body.find(stop, len(start))
        if idx != -1:
            cut = min(cut, idx)
    return body[:cut].strip()


def web_prompt(cat: str, asset_id: str, text: str, files: list) -> str:
    """웹 채팅에 한 번에 붙여넣을 축약 의뢰문."""
    stops = ("\n## ", "\n### ")
    parts = [WEB_STYLE_HEAD, ""]
    for head in ("## 그릴 것", "## 대상", "## 몬스터", "## 캐릭터", "## 이펙트", "## 씬"):
        sec = extract_section(text, head, stops)
        if sec:
            parts += [sec, ""]
            break
    for head in ("## 출력 규격 (그리드 계약 — 위반 시 반려)", "## 출력 규격"):
        sec = extract_section(text, head, stops)
        if sec:
            parts += [sec, ""]
            break
    # 카테고리별 핵심 계약 절 — 하나라도 빠지면 축약본이 계약을 잃는다(리마스터 계약 누락 실측).
    for head in ("## 리마스터 계약 (위반 시 반려)", "## 리미티드 애니메이션 규칙",
                 "## 이펙트 전용 규칙", "## 신원 유지 (위반 시 반려)"):
        sec = extract_section(text, head, stops)
        if sec:
            parts += [sec, ""]
    sub = extract_section(text, "### 정체성 확인", stops)
    if sub:
        parts += [sub, ""]
    neg = extract_section(text, "### 하지 말 것", stops)
    if neg:
        parts += [neg, ""]
    chk = extract_section(text, "### 납품 전 스스로 확인", stops)
    if chk:
        parts += [chk, ""]

    attach = [f for f in WEB_ATTACH_PRIORITY if f in files][:4]
    guide = [
        "---",
        "## 이 파일 쓰는 법 (사람용 — LLM에 붙여넣을 때는 이 절을 빼도 된다)",
        "",
        "1. 웹 채팅에 위 본문을 **그대로 붙여넣는다**",
        "2. 같은 폴더에서 아래 이미지를 첨부한다(순서대로, 첨부 제한이 있으면 앞쪽부터):",
    ]
    for i, f in enumerate(attach, start=1):
        role = {
            "grid_template.png": "정확한 캔버스 크기의 빈 격자 — 이 위에 그리고 선은 지운다",
            "style_ref.png": "기존 게임 도트 — 화풍·정렬 기준",
            "scale_ref.png": "주인공 시트 — 크기의 절대 기준",
            "subpalette.png": "쓸 색 스왑치",
        }.get(f, "원작 그림 — 화풍의 1차 근거")
        guide.append(f"   {i}. `{f}` — {role}")
    guide += [
        "3. 첨부가 아예 안 되는 채팅이면: 본문만으로 진행하되 **크기·프레임 수·색 수**를 반드시 지키게 한다",
        f"4. 결과 PNG를 `_제출/{asset_id}_v1.png` 로 저장한다(재납품은 _v2, _v3)",
        "",
        "검증·설치: `python tools/convert/intake.py --from <이 묶음>/_제출`",
    ]
    return "\n".join(parts + guide) + "\n"


def spec_line(text: str) -> str:
    """프롬프트에서 규격 한 줄만 뽑아 작업지시에 요약한다."""
    for line in text.splitlines():
        if line.startswith("- 시트:") or line.startswith("- **768×256") or line.startswith("- **1920×1080"):
            return line.lstrip("- ").strip()
        if "PNG" in line and "×" in line and line.startswith("-"):
            return line.lstrip("- ").strip()
    return "prompt.md의 '출력 규격' 절 참조"


def pick_targets(args: list, cat_filter: str, pick: int) -> list:
    """(카테고리, id) 목록 결정 — 명시 인자 > 카테고리 필터 > 공백 우선순위."""
    explicit = []
    for a in args:
        if ":" in a:
            cat, aid = a.split(":", 1)
            explicit.append((cat, aid))
    if explicit:
        return explicit
    order = [c for c in CATEGORIES if not cat_filter or c[0] == cat_filter]
    out = []
    for cat, _label, _why in order:
        for aid in package_dirs(cat):
            out.append((cat, aid))
            if pick and len(out) >= pick:
                return out
    return out[:pick] if pick else out


def main() -> None:
    args = [a for a in sys.argv[1:]]
    pick = 0
    cat_filter = ""
    name = ""
    for flag, setter in (("--pick", "pick"), ("--cat", "cat"), ("--name", "name")):
        if flag in args:
            i = args.index(flag)
            val = args[i + 1]
            del args[i:i + 2]
            if setter == "pick":
                pick = int(val)
            elif setter == "cat":
                cat_filter = val
            else:
                name = val

    targets = pick_targets(args, cat_filter, pick)
    if not targets:
        print("담을 패키지가 없다 — 먼저 의뢰생성.bat 으로 패키지를 만들어라")
        sys.exit(1)

    batch_name = name or datetime.now().strftime("%m%d_%H%M")
    out_root = os.path.join(BATCH_ROOT, batch_name)
    if os.path.isdir(out_root):
        shutil.rmtree(out_root)
    os.makedirs(out_root)
    os.makedirs(os.path.join(out_root, "_제출"), exist_ok=True)
    if os.path.exists(AGENT_DOC):
        shutil.copyfile(AGENT_DOC, os.path.join(out_root, "먼저읽기.md"))

    lines = [
        f"# 작업지시 — {batch_name}",
        "",
        f"그릴 것 **{len(targets)}건**. 한 번에 하나씩, 아래 순서대로 진행한다.",
        "",
        "각 폴더의 `prompt.md`가 계약이다. **그 폴더의 이미지 전부**를 함께 보고 그린다",
        "(참조가 폴더 안에 다 들어 있다 — 밖을 찾을 필요 없다).",
        "",
        "| # | 폴더 | 무엇 | 규격 | 저장할 파일명 |",
        "|---|---|---|---|---|",
    ]
    for i, (cat, aid) in enumerate(targets, start=1):
        dst = os.path.join(out_root, f"{cat}__{aid}")
        n, text = flatten(cat, aid, dst)
        # 웹 채팅용 축약본 — 무료 LLM·토큰 절약 경로(첨부 제한도 고려해 3~4장만 고른다)
        io.open(os.path.join(dst, "웹붙여넣기.md"), "w", encoding="utf-8").write(
            web_prompt(cat, aid, text, sorted(os.listdir(dst)))
        )
        label = next((c[1] for c in CATEGORIES if c[0] == cat), cat)
        lines.append(
            "| %d | `%s__%s/` | %s | %s | `_제출/%s_v1.png` |"
            % (i, cat, aid, label, spec_line(text), aid)
        )
        print(f"  {cat}/{aid}: 첨부 {n}장 -> {os.path.relpath(dst, ROOT)}")

    lines += [
        "",
        "## 저장",
        "",
        "완성본은 이 묶음의 `_제출/` 폴더에 위 표의 파일명 그대로 저장한다.",
        "재납품은 `_v2`, `_v3`로 번호를 올린다.",
        "",
        "## 공통 규칙 (자세한 것은 각 prompt.md)",
        "",
        "- 캔버스 크기는 **한 픽셀도** 어긋나면 자동 반려된다",
        "- 배경은 완전 투명(불가 시 마젠타 `#FF00FF` 단색). 흰색·체커보드 금지",
        "- **격자 안내선(마젠타·청록)을 전부 지운다** — 흐리게 남겨도 검출·반려",
        "- 캔버스 안에 글자·라벨·워터마크 금지(`grid_guide.png`의 글자를 옮겨 그리지 마라)",
        "- 고유색 48색 이하. 안티에일리어싱·그라데이션 금지",
        "",
        "작업이 끝나면 사람이 `납품처리.bat`(또는 `python tools/convert/intake.py`)로",
        "검증·설치를 돌린다. 반려되면 사유가 적힌 md가 돌아온다.",
        "",
        "## 웹 채팅(무료 LLM)으로 의뢰할 때",
        "",
        "각 폴더의 `웹붙여넣기.md`를 쓴다 — 계약을 2KB 안쪽으로 줄인 축약본이라",
        "무료 티어에서도 한 메시지에 들어간다. 첨부는 그 문서가 지정한 3~4장만 올린다.",
        "톤 일관성은 축약본의 스타일 6줄 + 서브팔레트 hex + 원작 참조 그림이 함께 유지한다.",
    ]
    io.open(os.path.join(out_root, "작업지시.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")

    print()
    print("묶음 완성: %s" % os.path.relpath(out_root, ROOT).replace("\\", "/"))
    print("  이 폴더를 통째로 그림 LLM에 넘긴다(작업지시.md가 첫 문서다).")
    print("  납품은 %s/_제출/ 에 받고, 다음을 실행한다:" % os.path.relpath(out_root, ROOT).replace("\\", "/"))
    print("    python tools/convert/intake.py --from %s" % os.path.relpath(os.path.join(out_root, "_제출"), ROOT).replace("\\", "/"))


if __name__ == "__main__":
    main()
