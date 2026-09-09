# -*- coding: utf-8 -*-
"""셀 편집기(sprite_fixer.html) 정적 검사 — 브라우저 없이 잴 수 있는 것만 전부 잰다.

왜 있나: 이 파일은 마크업과 스크립트가 한 파일에 있고, 손으로 헤더를 재배치하거나
버튼을 늘리다 배선이 조용히 끊기는 사고가 나기 쉽다. 실제로 [크기 자동 조절] 버튼은
`data-op`만 달린 채 처리기가 없어 **눌러도 아무 일이 없었다**(이 저장소의 지배적 결함
유형인 '선언은 있는데 읽는 코드가 없다'가 UI에서 난 모양이다). 브라우저가 없는
환경에서도 그런 것만큼은 기계가 잡게 한다.

  py tools/review/fixer_check.py          # 실패하면 종료코드 1

실조작(드래그로 실제 지워지는가)은 여기서 못 본다 — 그건 fixer_probe.py가 본다.

검사 항목
  1) 태그 균형: 열고 닫는 짝이 맞는가(void 요소 제외).
  2) id 배선: JS가 $("#x")로 찾는 id가 마크업에 다 있는가. 반대로 아무도 안 쓰는 id도 알린다.
  3) 버튼 배선: data-op를 단 버튼마다 OPS 처리기가 있는가(없으면 눌러도 아무 일이 없다),
     serverOp을 부르는 연산이 SERVER_OPS에 들어 있는가(빠지면 되돌리기가 두 번 쌓인다).
  4) 아이콘: <use>가 가리키는 <symbol>이 있는가, 안 쓰는 symbol은 없는가.
  5) 헤더 묶음: 헤더 줄마다 어떤 조작이 들어갔는지 표로 뽑는다(눈으로 대조용).
  6) 스크립트 문법: node가 있으면 `node --check`로 확인한다.
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from html.parser import HTMLParser
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    # 콘솔이 cp949로 잡히면 '—' 하나에 UnicodeEncodeError로 죽는다(이 저장소가 반복해 물린 함정).
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HTML = Path(__file__).resolve().parent / "sprite_fixer.html"
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link",
        "meta", "param", "source", "track", "wbr", "use", "path", "circle",
        "rect", "line", "polygon", "polyline", "ellipse", "stop"}
# 닫는 태그를 생략해도 되는 것들 — 이 파일이 실제로 그렇게 쓴다(<title> 뒤 <style> 등).
OPTIONAL_CLOSE = {"html", "head", "body", "p", "li", "option", "tr", "td", "th"}


class Balance(HTMLParser):
    """태그 균형과 마크업 id·클래스를 함께 걷는다."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[tuple[str, int]] = []
        self.errors: list[str] = []
        self.ids: dict[str, str] = {}        # id -> 태그이름
        self.dup_ids: list[str] = []
        self.symbols: set[str] = set()
        self.uses: list[str] = []
        self.hbars: list[list[str]] = []     # .hbar 줄마다 담긴 조작 요약
        self._hbar_depth: int | None = None
        self._group: str | None = None

    # -- 태그 --------------------------------------------------------------
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            if a["id"] in self.ids:
                self.dup_ids.append(a["id"])
            self.ids[a["id"]] = tag
        if tag == "symbol" and "id" in a:
            self.symbols.add(a["id"])
        if tag == "use":
            href = a.get("href") or a.get("xlink:href") or ""
            if href.startswith("#"):
                self.uses.append(href[1:])

        cls = (a.get("class") or "").split()
        if "hbar" in cls:
            self.hbars.append([])
            self._hbar_depth = len(self.stack)
            self._group = None
        if self._hbar_depth is not None:
            self._note(tag, a, cls)

        if tag not in VOID:
            self.stack.append((tag, self.getpos()[0]))

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        while self.stack:
            top, line = self.stack.pop()
            if top == tag:
                if (self._hbar_depth is not None
                        and len(self.stack) <= self._hbar_depth):
                    self._hbar_depth = None
                return
            if top not in OPTIONAL_CLOSE:
                self.errors.append(
                    f"{line}행 <{top}> 이(가) </{tag}> 로 닫혔다 (짝이 어긋남)")
                return
        self.errors.append(f"짝 없는 </{tag}> (여는 태그가 없다)")

    # -- 헤더 요약 ---------------------------------------------------------
    def _note(self, tag, a, cls):
        row = self.hbars[-1]
        if "gl" in cls:
            self._group = "…"          # 라벨 글자는 handle_data에서 채운다
            row.append("[")
            return
        if tag == "button":
            row.append(f"button#{a.get('id', '?')}")
        elif tag == "select":
            row.append(f"select#{a.get('id', '?')}")
        elif tag == "input":
            row.append(f"input[{a.get('type', 'text')}]#{a.get('id', '?')}")
        elif tag == "div" and "sep" in cls:
            row.append("|")

    def handle_data(self, data):
        if self._group == "…" and data.strip():
            self.hbars[-1][-1] = f"[{data.strip()}"
            self._group = None


def main() -> int:
    src = HTML.read_text(encoding="utf-8")
    p = Balance()
    p.feed(src)
    fails: list[str] = []
    notes: list[str] = []

    # 1) 태그 균형 ---------------------------------------------------------
    leftover = [f"<{t}>({ln}행)" for t, ln in p.stack if t not in OPTIONAL_CLOSE]
    if p.errors or leftover:
        fails += [f"태그 균형: {e}" for e in p.errors]
        if leftover:
            fails.append("태그 균형: 닫히지 않은 태그 " + ", ".join(leftover))
    if p.dup_ids:
        fails.append("중복 id: " + ", ".join(sorted(set(p.dup_ids))))

    # 2) id 배선 -----------------------------------------------------------
    script = "\n".join(re.findall(r"<script>(.*?)</script>", src, re.S))
    want = set(re.findall(r"""\$\(\s*["']#([A-Za-z0-9_-]+)["']""", script))
    want |= set(re.findall(r"""getElementById\(\s*["']([A-Za-z0-9_-]+)["']""", script))
    # 문자열 조립("#tool-" + k)은 정규식이 못 본다 — 접두사만 뽑아 따로 확인한다.
    prefixed = set(re.findall(r"""\$\(\s*["']#([A-Za-z0-9_-]+?)["']\s*\+""", script))
    # 조립 선택자의 접두사('tool-')는 그 자체로 존재하는 id가 아니다 — 아래에서 따로 본다.
    missing = sorted(w for w in want if w not in p.ids and w not in prefixed)
    if missing:
        fails.append("JS가 찾는데 마크업에 없는 id: " + ", ".join(missing))
    for pre in sorted(prefixed):
        hit = [i for i in p.ids if i.startswith(pre)]
        if not hit:
            fails.append(f"조립 선택자 '#{pre}…' 에 맞는 id가 하나도 없다")
        else:
            notes.append(f"조립 선택자 '#{pre}…' → {len(hit)}개: " + ", ".join(sorted(hit)))

    css = "\n".join(re.findall(r"<style>(.*?)</style>", src, re.S))
    css_ids = set(re.findall(r"#([A-Za-z0-9_-]+)", css))
    dead = sorted(i for i in p.ids
                  if i not in want and i not in css_ids
                  and not any(i.startswith(x) for x in prefixed)
                  and not i.startswith("i-"))
    if dead:
        notes.append("JS·CSS 어디서도 안 쓰는 id(사문화 후보): " + ", ".join(dead))

    # 3) 버튼 배선 ---------------------------------------------------------
    declared = set(re.findall(r'data-op="([A-Za-z0-9_-]+)"', src))
    ops_body = re.search(r"const OPS = \{(.*?)\n\};", script, re.S)
    body = ops_body.group(1) if ops_body else ""
    handled = set(re.findall(r"^\s{2}([A-Za-z0-9_]+)\s*:", body, re.M))
    orphan = sorted(declared - handled)
    if orphan:
        fails.append("버튼에 data-op만 있고 OPS에 처리기가 없다(눌러도 아무 일 없음): "
                     + ", ".join(orphan))
    if handled - declared:
        notes.append("OPS에만 있고 버튼이 없는 연산: " + ", ".join(sorted(handled - declared)))

    srv = re.search(r"const SERVER_OPS = new Set\(\[(.*?)\]\);", script, re.S)
    srv_set = set(re.findall(r'"([A-Za-z0-9_-]+)"', srv.group(1))) if srv else set()
    calls_server = set()
    for name, chunk in re.findall(
            r"^\s{2}([A-Za-z0-9_]+)\s*:(.*?)(?=^\s{2}[A-Za-z0-9_]+\s*:|\Z)", body, re.S | re.M):
        if "serverOp(" in chunk:
            calls_server.add(name)
    double_undo = sorted(calls_server - srv_set)
    if double_undo:
        fails.append("serverOp을 부르는데 SERVER_OPS에 없다(되돌리기가 두 번 쌓인다): "
                     + ", ".join(double_undo))

    # 4) 아이콘 ------------------------------------------------------------
    ghost = sorted(set(u for u in p.uses if u not in p.symbols))
    if ghost:
        fails.append("<use>가 가리키는 symbol이 없다: " + ", ".join(ghost))
    if p.symbols - set(p.uses):
        notes.append("안 쓰는 아이콘 symbol: " + ", ".join(sorted(p.symbols - set(p.uses))))

    # 5) 헤더 묶음 ---------------------------------------------------------
    print(f"[셀 편집기 검사] {HTML.name}")
    print(f"  마크업 id {len(p.ids)}개 · JS가 찾는 id {len(want)}개 · 아이콘 symbol {len(p.symbols)}개"
          f" · data-op 버튼 {len(declared)}개 · OPS 처리기 {len(handled)}개"
          f" · 서버 연산 {len(srv_set)}개")
    for n, row in enumerate(p.hbars, 1):
        print(f"  헤더 {n}줄: " + " ".join(row))

    # 6) 스크립트 문법 ------------------------------------------------------
    node = shutil.which("node")
    if node:
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False,
                                         encoding="utf-8") as f:
            f.write(script)
            tmp = f.name
        r = subprocess.run([node, "--check", tmp], capture_output=True, text=True)
        Path(tmp).unlink(missing_ok=True)
        if r.returncode != 0:
            fails.append("스크립트 문법 오류:\n" + (r.stderr or r.stdout).strip())
        else:
            print(f"  스크립트 문법: OK ({len(script.splitlines())}행, node --check)")
    else:
        notes.append("node가 없어 스크립트 문법은 확인하지 못했다")

    for n in notes:
        print("  · " + n)
    if fails:
        print("\n실패:")
        for f_ in fails:
            print("  X " + f_)
        return 1
    print("\n통과 — 정적으로 잴 수 있는 항목은 모두 맞다(실조작은 fixer_probe.py가 본다).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
