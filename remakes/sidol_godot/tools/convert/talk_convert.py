#!/usr/bin/env python3
"""TALK.TXT(조합형/Johab) → data/dialogue.json 변환기.

스펙: docs/02_design/03_data_migration.md §3
규칙:
  - 키는 "@t<인덱스>" — 원문 불변 영역(재작성 문장은 @c로 별도 발급)
  - 주석(#...)의 장면명을 _meta[@tN].scene 으로 보존
사용:
  python tools/convert/talk_convert.py            # data/dialogue.json 생성
  python tools/convert/talk_convert.py --check    # 연속성·공백 항목 리포트만
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHARED_SRC = ROOT.parent.parent / "_shared" / "src"
sys.path.insert(0, str(SHARED_SRC))

from dosport.encodings.johab_kr import contaminated_lines, decode  # noqa: E402

SOURCE_PATH = ROOT.parent.parent / "originals" / "1995_sidol_bsd_dos" / "TALK.TXT"
OUTPUT_PATH = ROOT / "data" / "dialogue.json"

ENTRY_RE = re.compile(r'^/\*\s*(\d+)\s*\*/\s*"([^"]*)"\s*,?\s*(?:/\*.*?\*/)?\s*$')
COMMENT_RE = re.compile(r"^/\*(.+?)\*/\s*$")


def parse(text: str) -> tuple[dict[str, str], dict[str, dict[str, str]], list[str]]:
    """반환: (entries, meta, warnings)"""
    entries: dict[str, str] = {}
    meta: dict[str, dict[str, str]] = {}
    warnings: list[str] = []
    scene = ""

    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("char *message"):
            continue
        # 주의: 엔트리 매칭이 주석 매칭보다 선행해야 한다.
        # '/*N*/"...", /* 메모 */' 형태가 주석으로 오탈되는 것을 방지.
        entry = ENTRY_RE.match(line)
        if entry:
            idx, body = int(entry.group(1)), entry.group(2)
            key = f"@t{idx}"
            if key in entries:
                warnings.append(f"L{lineno}: 중복 인덱스 {key}")
                continue
            entries[key] = body
            if scene:
                meta[key] = {"scene": scene}
            continue
        comment = COMMENT_RE.match(line)
        if comment:
            inner = comment.group(1).strip()
            if inner.startswith("#"):
                scene = inner.lstrip("#").strip()
            continue
        if '"' in line:
            warnings.append(f"L{lineno}: 파싱 실패 행 보존 -> {line[:50]}")

    return entries, meta, warnings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="파일 미생성, 리포트만")
    args = parser.parse_args()

    text = decode(SOURCE_PATH.read_bytes())
    entries, meta, warnings = parse(text)

    indices = sorted(int(k[2:]) for k in entries)
    gaps = [str(i) for i in range(indices[-1] + 1) if i not in set(indices)] if indices else []
    empty_count = sum(1 for v in entries.values() if v == "")
    bad_lines = contaminated_lines(text)

    print(f"source={SOURCE_PATH.name} entries={len(entries)} max_index={indices[-1] if indices else '-'}")
    print(f"gaps={gaps if gaps else 'none'} empty={empty_count} contaminated_lines={bad_lines or 'none'}")
    for w in warnings[:10]:
        print(f"WARN {w}")

    if args.check:
        return 0

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload = {"schema_version": 1, "source": "TALK.TXT", "encoding": "johab", **entries}
    if meta:
        payload["_meta"] = meta
    OUTPUT_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"wrote {OUTPUT_PATH.relative_to(ROOT)} ({len(entries)} entries)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
