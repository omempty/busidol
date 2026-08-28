#!/usr/bin/env python3
"""의뢰 패키지 무결성 검사 — 프롬프트가 가리키는 첨부가 실제로 있는가.

## 왜 (2026-08-29)

`의뢰생성.bat monsters` 한 번에 리마스터 8종의 `subpalette.png`가 통째로 사라졌다.
공용 참조 정리(`dedupe_package_dirs`)가 **이름만 보고** 지웠는데, 리마스터 패키지는
같은 이름의 파일을 그 몬스터 자신의 색으로 직접 만들어 쓰고 있었다.

첨부가 하나 빠진 의뢰문은 조용히 나쁜 결과를 만든다 — LLM은 없는 파일을 찾지 않고
그냥 문장만 따르며, 그 결과 색 정체성·크기 기준이 통째로 흔들린다. 게이트는 납품물을
보지 의뢰문을 보지 않으므로 **이 층을 보는 눈이 없었다.**

이 도구는 `prompt.md`의 "입력 (첨부)" 절에 적힌 경로만 검사한다(본문 산문 언급은 제외).
그 절이 첨부의 단일 근거라는 규약(LLM_WORKFLOW §2)과 같은 기준이다.

실행: python tools/dev/package_check.py
종료코드: 0=이상 없음 / 1=누락 있음
"""
from __future__ import annotations

import io
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
LLM = os.path.join(ROOT, "assets", "raw", "llm")
## 백틱 안의 png 경로(`../foo.png` 포함). 첨부 목록은 전부 이 형식으로 적힌다.
PATH_RE = re.compile(r"`((?:\.\./)*[A-Za-z0-9_\-/]+\.png)`")
ATTACH_RE = re.compile(r"^## 입력 \(첨부\).*?(?=^## )", re.S | re.M)
## 스테이지 폴더는 패키지가 아니다.
SKIP_PREFIX = ("_", "00_", "10_", "20_", "30_")


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if not os.path.isdir(LLM):
        print("[package_check] assets/raw/llm 없음 — 의뢰생성.bat 으로 패키지를 만들어라")
        return

    pkgs = refs = 0
    missing: list = []
    no_list: list = []
    for cat in sorted(os.listdir(LLM)):
        cat_dir = os.path.join(LLM, cat)
        if not os.path.isdir(cat_dir) or cat.startswith(SKIP_PREFIX):
            continue
        for pkg in sorted(os.listdir(cat_dir)):
            pkg_dir = os.path.join(cat_dir, pkg)
            prompt = os.path.join(pkg_dir, "prompt.md")
            if not os.path.isfile(prompt):
                continue
            pkgs += 1
            text = io.open(prompt, encoding="utf-8").read()
            section = ATTACH_RE.search(text)
            if not section:
                no_list.append(f"{cat}/{pkg}")
                continue
            for ref in sorted(set(PATH_RE.findall(section.group(0)))):
                refs += 1
                if not os.path.exists(os.path.normpath(os.path.join(pkg_dir, ref))):
                    missing.append((cat, pkg, ref))

    print("[package_check] 패키지 %d개 · 첨부 참조 %d개" % (pkgs, refs))
    for cat, pkg, ref in missing:
        print("  FAIL %s/%s → %s 없음" % (cat, pkg, ref))
    for p in no_list:
        print("  warn %s: '입력 (첨부)' 절이 없다" % p)
    if missing:
        print("  ─ 누락 %d건. 해당 카테고리 생성기를 다시 돌려라(의뢰생성.bat <카테고리>)" % len(missing))
        sys.exit(1)
    print("  ─ 이상 없음")


if __name__ == "__main__":
    main()
