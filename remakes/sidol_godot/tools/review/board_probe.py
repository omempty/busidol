#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""심사보드 실조작 시험 — 서버를 띄우고 브라우저로 실제로 눌러 본다.

## 왜 (2026-09-09)

보드에 🗑️ 삭제를 붙였는데 "제대로 안 된다"는 신고가 왔다. 코드를 읽어서는 멀쩡했고,
실제로 눌러 보니 **동작했다**. 안 되는 것처럼 보인 이유는 둘이었다:

- 삭제 뒤 목록을 서버에서 다시 읽는 데 **3.9초**가 걸린다(파일마다 검증기를 하위
  프로세스로 돌린다). 그 동안 카드가 남아 있어 반응이 없는 것처럼 보였다.
- 삭제는 서버 코드다. 심사 서버를 켜 둔 채 코드만 바꾸면 옛 프로세스가 돌아
  "알 수 없는 액션: delete"가 돌아온다.

둘 다 고쳤지만, 고친 것을 지키는 것은 이 시험이다. 브라우저 없이 짐작으로 판단하다
두 번 헛짚었다(카테고리가 안 바뀐 줄 모르고 "목록에 없다"고 결론 내렸다).

버릴 납품(dworm_v99.png)을 만들어 지우고 원상복구하므로 실제 납품은 건드리지 않는다.

  py tools/review/board_probe.py
종료코드: 0=통과 / 1=실패
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PORT = int(os.environ.get("BOARD_PROBE_PORT", "8699"))
URL = f"http://127.0.0.1:{PORT}/tools/review/review_board.html"
SUB = os.path.join(ROOT, "assets", "raw", "llm", "10_submitted", "monsters")
PROBE = os.path.join(SUB, "dworm_v99.png")
FEED = os.path.join(ROOT, "assets", "raw", "llm", "10_submitted", "_feedback",
                    "monsters", "dworm_v99.png.md")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

_pass = _fail = 0


def check(name: str, cond: bool, detail: str = "") -> None:
    global _pass, _fail
    if cond:
        _pass += 1
        print(f"  OK  {name}" + (f" - {detail}" if detail else ""))
    else:
        _fail += 1
        print(f"  X   {name}" + (f" - {detail}" if detail else ""))


def pick_source() -> str:
    for f in sorted(os.listdir(SUB)) if os.path.isdir(SUB) else []:
        if f.lower().endswith(".png"):
            return os.path.join(SUB, f)
    return ""


def main() -> int:
    src = pick_source()
    if not src:
        print("[심사보드 시험] 10_submitted/monsters에 납품이 없어 건너뛴다")
        return 0
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("[심사보드 시험] playwright가 없어 건너뛴다 (pip install playwright)")
        return 0

    shutil.copyfile(src, PROBE)
    os.makedirs(os.path.dirname(FEED), exist_ok=True)
    with open(FEED, "w", encoding="utf-8") as f:
        f.write("# 시험용 피드백(자동 생성 · 자동 삭제)\n")
    print(f"[심사보드 시험] 버릴 납품 {os.path.basename(PROBE)} 준비 · 서버 :{PORT}")

    srv = subprocess.Popen(
        [sys.executable, "-X", "utf8", os.path.join(ROOT, "tools", "review", "review_server.py"), str(PORT)],
        cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    time.sleep(2.0)
    try:
        with sync_playwright() as pw:
            br = pw.chromium.launch()
            pg = br.new_page()
            errs: list[str] = []
            pg.on("pageerror", lambda e: errs.append(str(e)))
            pg.on("dialog", lambda d: d.accept())          # confirm() 자동 승인
            pg.goto(URL)
            pg.wait_for_selector(".card", timeout=20000)
            pg.click("#cats button[data-cat='monsters']")
            # 보드는 파일마다 검증기를 돌려 느리다 — 목록이 실제로 갈릴 때까지 기다린다.
            # 성급하면 이전 카테고리를 읽고 "목록에 없다"고 잘못 판단한다(실제로 두 번 그랬다).
            pg.wait_for_function(
                "() => PENDING_ITEMS.some(i => i.file === 'dworm_v99.png')", timeout=120000)
            check("보드가 그 납품을 보여 준다", True,
                  f"{pg.evaluate('() => PENDING_ITEMS.length')}개")

            btn = pg.query_selector("button[onclick*=\"deleteItem('dworm_v99.png')\"]")
            check("삭제 버튼이 카드에 있다", btn is not None)
            if btn:
                btn.click()
                pg.wait_for_function(
                    "() => !PENDING_ITEMS.some(i => i.file === 'dworm_v99.png')", timeout=120000)

            after = pg.evaluate("() => PENDING_ITEMS.map(i => i.file)")
            check("삭제 뒤 그 버전이 목록에서 사라진다", "dworm_v99.png" not in after)
            check("납품 png가 실제로 지워졌다", not os.path.exists(PROBE))
            check("피드백 md도 함께 지워졌다", not os.path.exists(FEED))
            toast = pg.evaluate("() => ($('#toast')||{}).textContent || ''")
            check("무엇을 지웠는지 알린다", "dworm_v99" in toast, toast[:70])
            check("페이지 예외 없음", not errs, " / ".join(errs[:2]))
            br.close()
    finally:
        srv.terminate()
        for p in (PROBE, FEED):
            if os.path.exists(p):
                os.remove(p)

    print(f"\n[심사보드 시험] 통과 {_pass} · 실패 {_fail}")
    return 1 if _fail else 0


if __name__ == "__main__":
    sys.exit(main())
