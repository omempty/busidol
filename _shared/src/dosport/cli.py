"""dosport CLI — 공용 포맷 유틸 엔트리."""
from __future__ import annotations

import argparse
from pathlib import Path

from .encodings.johab_kr import contaminated_lines, decode


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="dosport", description="공용 DOS 에셋 유틸")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_johab = sub.add_parser("johab-report", help="조합형 텍스트 오염 행(U+FFFD) 리포트")
    p_johab.add_argument("path")

    args = parser.parse_args(argv)
    if args.cmd == "johab-report":
        text = decode(Path(args.path).read_bytes())
        lines = text.splitlines()
        bad = contaminated_lines(text)
        print(f"file={args.path} lines={len(lines)} contaminated={len(bad)}")
        for n in bad[:20]:
            print(f"  L{n}")
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
