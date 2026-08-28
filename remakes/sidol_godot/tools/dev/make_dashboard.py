#!/usr/bin/env python3
"""현황판 생성 — 프로젝트 루트에 `현황판.html` 한 장을 굽는다.

## 왜

에셋 파이프라인이 여러 갈래(의뢰 생성 · 묶음 포장 · 웹 붙여넣기 · 납품 처리 · 심사 보드 ·
셀 편집기 · 설치)로 늘어나면서 "지금 무엇이 어디까지 왔나"를 한눈에 보는 자리가 없어졌다.
`asset_status.py`는 숫자를 주지만 **거기서 바로 갈 수가 없다**(프롬프트 열기·폴더 열기).

이 문서는 서버 없이 file:// 로 열린다. 링크는 전부 **상대 경로**라 저장소를 어디에 두든 돈다.
수치는 `asset_status.collect()`를 그대로 쓴다 — 두 곳에서 따로 세면 반드시 갈라진다.

실행: python tools/dev/make_dashboard.py   (또는 현황판.bat)
"""
from __future__ import annotations

import html
import io
import os
import sys
from datetime import datetime

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "dev"))

import asset_status  # noqa: E402

LLM = os.path.join(ROOT, "assets", "raw", "llm")
OUT = os.path.join(ROOT, "현황판.html")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

## 카테고리 → 의뢰 생성기 인자. 현황판이 명령까지 알려 준다(문서를 뒤지지 않게).
CAT_CMD = {
    "monsters": "의뢰생성.bat monsters",
    "npcs": "의뢰생성.bat npcs",
    "items": "의뢰생성.bat items",
    "portraits": "의뢰생성.bat portraits",
    "keyart": "의뢰생성.bat keyart",
    "effects": "의뢰생성.bat effects",
    "battle_cuts": "의뢰생성.bat battle_cuts",
    "battle_actors": "의뢰생성.bat battle_actors",
}
COMMANDS = [
    ("의뢰 패키지 만들기", "의뢰생성.bat", "카테고리 선택 메뉴. 뒤에 카테고리·id를 붙이면 그것만"),
    ("묶음 포장(폴더 통째로 LLM에)", "python tools/dev/pack_request.py --pick 3 --name 시범",
     "자기완결 폴더 + 작업지시.md + 웹붙여넣기.md 생성"),
    ("납품 받기(GUI 없이)", "python tools/convert/intake.py --from assets/raw/llm/_batch/시범/_제출",
     "검증 → 채택 → 설치까지 한 번에. 반려는 사유 md 생성"),
    ("심사 보드 / 셀 편집기", "심사실행.bat", "눈으로 비교하고 셀 단위로 고칠 때"),
    ("현황 숫자만", "python tools/dev/asset_status.py", "이 문서의 수치와 같은 소스"),
    ("검증 관문 전체", "검증실행.bat", "17종 관문(스모크·감사·내보내기 규칙)"),
]


def rel(path: str) -> str:
    return os.path.relpath(path, ROOT).replace("\\", "/")


def asset_state(cat: str, asset_id: str, installed: bool) -> tuple:
    """(상태 라벨, 클래스) — 설치됨 > 채택 > 납품 대기 > 의뢰 준비 > 패키지 없음."""
    if installed:
        return "설치됨", "s-done"
    processed = os.path.join(LLM, "20_processed", asset_id)
    processed_flat = os.path.join(LLM, "20_processed", cat)
    if os.path.isdir(processed) or (
        os.path.isdir(processed_flat)
        and any(f.startswith(asset_id + "_v") for f in os.listdir(processed_flat))
    ):
        return "채택(미설치)", "s-adopted"
    submit_dir = os.path.join(LLM, "10_submitted", cat)
    if os.path.isdir(submit_dir) and any(
        f.startswith(asset_id + "_v") for f in os.listdir(submit_dir)
    ):
        return "납품 대기", "s-submitted"
    if os.path.exists(os.path.join(LLM, cat, asset_id, "prompt.md")):
        return "의뢰 준비됨", "s-ready"
    return "패키지 없음", "s-none"


def batches() -> list:
    base = os.path.join(LLM, "_batch")
    if not os.path.isdir(base):
        return []
    out = []
    for name in sorted(os.listdir(base), reverse=True):
        d = os.path.join(base, name)
        if not os.path.isdir(d):
            continue
        items = [x for x in sorted(os.listdir(d)) if os.path.isdir(os.path.join(d, x)) and "__" in x]
        pend = os.path.join(d, "_제출")
        pending = [f for f in sorted(os.listdir(pend))] if os.path.isdir(pend) else []
        out.append({"name": name, "dir": d, "items": items, "pending": pending})
    return out


def build_html() -> str:
    rows = asset_status.collect()
    total_ids = sum(len(r["ids"]) for r in rows)
    total_have = sum(len(r["have"]) for r in rows)
    parts = []

    for r in rows:
        cat = r["cat"]
        have = set(r["have"])
        pct = int(100 * len(have) / max(len(r["ids"]), 1))
        cmd = CAT_CMD.get(cat, "")
        cat_dir = os.path.join(LLM, cat)
        cat_link = (
            f'<a href="{rel(cat_dir)}/">패키지 폴더</a>' if os.path.isdir(cat_dir) else
            '<span class="dim">패키지 없음</span>'
        )
        cells = []
        for aid in r["ids"]:
            label, cls = asset_state(cat, aid, aid in have)
            prompt = os.path.join(LLM, cat, aid, "prompt.md")
            web = os.path.join(LLM, cat, aid, "웹붙여넣기.md")
            links = []
            if os.path.exists(prompt):
                links.append(f'<a href="{rel(prompt)}">prompt</a>')
            if os.path.exists(web):
                links.append(f'<a href="{rel(web)}">web</a>')
            link_html = (" · ".join(links)) if links else '<span class="dim">-</span>'
            cells.append(
                f'<tr><td class="id">{html.escape(aid)}</td>'
                f'<td><span class="chip {cls}">{label}</span></td>'
                f'<td class="links">{link_html}</td></tr>'
            )
        parts.append(f"""
<section class="cat">
  <h2>{html.escape(r['label'])}
    <span class="meta">{len(have)} / {len(r['ids'])}</span>
    <span class="bar"><i style="width:{pct}%"></i></span>
  </h2>
  <div class="sub">{html.escape(r['note'])} · {cat_link}
    {'· <code>' + html.escape(cmd) + '</code>' if cmd else ''}</div>
  <table>{''.join(cells)}</table>
</section>""")

    batch_html = []
    for b in batches():
        pend = (
            f'<b>{len(b["pending"])}장 납품 대기</b> — <code>python tools/convert/intake.py '
            f'--from {rel(os.path.join(b["dir"], "_제출"))}</code>'
            if b["pending"] else '<span class="dim">아직 납품 없음</span>'
        )
        item_links = " · ".join(
            f'<a href="{rel(os.path.join(b["dir"], it))}/웹붙여넣기.md">{html.escape(it)}</a>'
            for it in b["items"]
        )
        batch_html.append(
            f'<div class="batch"><b><a href="{rel(b["dir"])}/작업지시.md">{html.escape(b["name"])}</a></b> '
            f'— {len(b["items"])}건 · {pend}<div class="sub">{item_links}</div></div>'
        )
    if not batch_html:
        batch_html.append('<div class="dim">아직 묶음이 없다 — <code>python tools/dev/pack_request.py --pick 3</code></div>')

    cmd_html = "".join(
        f'<tr><td>{html.escape(t)}</td><td><code>{html.escape(c)}</code></td>'
        f'<td class="dim">{html.escape(d)}</td></tr>'
        for t, c, d in COMMANDS
    )

    return f"""<!doctype html>
<meta charset="utf-8">
<title>BSD 시돌이 리메이크 — 에셋 현황판</title>
<!-- 자동 생성: python tools/dev/make_dashboard.py · 손으로 고치지 마라(다시 구우면 덮인다) -->
<style>
 :root{{--bg:#14141b;--panel:#1c1c26;--line:#2e2e3d;--fg:#e8e6f2;--dim:#9a94b8;--acc:#8b7cff;
       --done:#57d78a;--adopted:#68c8ff;--submitted:#ffc861;--ready:#b0a8e0;--none:#6b6880}}
 *{{box-sizing:border-box}}
 body{{margin:0;padding:20px 24px 60px;background:var(--bg);color:var(--fg);
      font:13px/1.6 "Segoe UI",system-ui,sans-serif;max-width:1180px}}
 h1{{font-size:19px;margin:0 0 4px}}
 h2{{font-size:14px;color:#cfc7ff;margin:0 0 4px;display:flex;align-items:center;gap:10px}}
 .meta,.dim{{color:var(--dim);font-size:12px;font-weight:400}}
 .sub{{color:var(--dim);font-size:12px;margin-bottom:8px}}
 a{{color:#a99cff}} a:hover{{color:#fff}}
 code{{background:#101018;border:1px solid var(--line);border-radius:5px;padding:1px 5px;font-size:12px}}
 .grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:14px;margin-top:14px}}
 section.cat{{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px}}
 table{{width:100%;border-collapse:collapse}}
 td{{padding:2px 4px;border-bottom:1px solid #24242f;vertical-align:top}}
 td.id{{font-size:12px}} td.links{{text-align:right;white-space:nowrap;font-size:12px}}
 .bar{{flex:1;height:6px;background:#101018;border-radius:3px;overflow:hidden}}
 .bar i{{display:block;height:100%;background:var(--acc)}}
 .chip{{font-size:11px;border-radius:999px;padding:1px 8px;white-space:nowrap}}
 .s-done{{background:#1d3b2a;color:var(--done)}} .s-adopted{{background:#14313f;color:var(--adopted)}}
 .s-submitted{{background:#3d3320;color:var(--submitted)}} .s-ready{{background:#2a2740;color:var(--ready)}}
 .s-none{{background:#24242f;color:var(--none)}}
 .panel{{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px;margin-top:14px}}
 .batch{{padding:6px 0;border-bottom:1px solid #24242f}}
 .top{{display:flex;gap:18px;align-items:baseline;flex-wrap:wrap}}
</style>

<h1>에셋 현황판 <span class="meta">{total_have} / {total_ids} 완료 · 공백 {total_ids - total_have}종</span></h1>
<div class="sub">생성 {datetime.now().strftime('%Y-%m-%d %H:%M')} ·
 <a href="assets/gen/prompts/PROMPTING_QUICKGUIDE.md">퀵가이드</a> ·
 <a href="assets/gen/prompts/LLM_WORKFLOW.md">워크플로우 계약</a> ·
 <a href="tools/review/review_board.html">심사 보드</a>(서버 필요) ·
 다시 굽기 <code>python tools/dev/make_dashboard.py</code></div>

<div class="panel">
 <h2>지금 할 일</h2>
 <table>{cmd_html}</table>
</div>

<div class="panel">
 <h2>의뢰 묶음</h2>
 {''.join(batch_html)}
</div>

<div class="grid">{''.join(parts)}</div>

<div class="panel">
 <h2>상태 표기</h2>
 <div class="sub">
  <span class="chip s-done">설치됨</span> 게임이 실제로 읽는다 ·
  <span class="chip s-adopted">채택(미설치)</span> 20_processed에 있으나 assets로 안 갔다 ·
  <span class="chip s-submitted">납품 대기</span> 10_submitted에 있고 심사 전 ·
  <span class="chip s-ready">의뢰 준비됨</span> prompt.md는 있고 납품이 없다 ·
  <span class="chip s-none">패키지 없음</span> 의뢰 패키지부터 만들어야 한다
 </div>
</div>
"""


def main() -> None:
    io.open(OUT, "w", encoding="utf-8").write(build_html())
    print("현황판: %s" % rel(OUT))
    print("  브라우저로 그냥 열면 된다(서버 불필요). 링크는 전부 상대 경로다.")


if __name__ == "__main__":
    main()
