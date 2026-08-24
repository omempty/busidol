#!/usr/bin/env python3
"""뷰어 HTML의 인라인 base64 PNG를 수정본으로 재주입."""
from __future__ import annotations

import base64
import re
from pathlib import Path

VIEWERS = Path(r"D:\Project\Etc\Old\부싯돌시절\remakes\sidol_godot\assets\gen\viewers")
RAW = Path(r"D:\Project\Etc\Old\부싯돌시절\remakes\sidol_godot\assets\raw\sprites")

PAIRS = [
    (VIEWERS / "tile_viewer.html", RAW / "tileset_campus" / "tileset_v1.png"),
    (VIEWERS / "character_bible.html", RAW / "player_sidol" / "sheet_v1.png"),
]


def main() -> int:
    pattern = re.compile(r'data:image/png;base64,[A-Za-z0-9+/=]+')
    for html_path, png_path in PAIRS:
        html = html_path.read_text(encoding="utf-8")
        b64 = base64.b64encode(png_path.read_bytes()).decode("ascii")
        new_uri = f"data:image/png;base64,{b64}"
        count = len(pattern.findall(html))
        if count == 0:
            print(f"skip(마커 없음): {html_path.name}")
            continue
        html = pattern.sub(new_uri, html)
        html_path.write_text(html, encoding="utf-8")
        print(f"reembedded {count} image(s) -> {html_path.name} ({len(b64)//1024}KB b64)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
