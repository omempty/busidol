#!/usr/bin/env python3
"""외부 무료팩 스탠드인 굽기 — 보스 본체 2종 + 탄막 탄 2종.

왜: 보스 2종은 스프라이트 공백이라 전투 대치 턴에 색 사각형이 뜬다(HANDOFF §3.23 —
탄막 페이즈 자체는 그림 없이 돌지만 바깥 턴은 그림이 없다). LLM 납품이 오기 전까지
무료팩을 스탠드인으로 세운다.

교체 가능성(핵심): 출력명은 <id>_external.png + .json 이고, 로더(SpriteSets)는
REMAKE 모드에서 remake → external → legacy 순으로 고른다. LLM _remake.png가
설치되는 순간 코드·데이터 수정 없이 외부팩이 밀려난다. 역도 성립(지우면 원상복구).

팩:
  craftpix_bosses — OGA-BY 3.0, CraftPix.net, 보스 3종(72px 셀 스트립) + 탄
  ruok_projectiles — CC0, RUOK, 16px 링 탄 10색 스트립
출처 단일 기록: data/external_sources.json + credits.json staff_roll.

사용: python tools/dev/bake_external_bosses.py [--no-download]
"""
from __future__ import annotations

import colorsys
import io
import json
import os
import sys
import urllib.request
import zipfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW_EXT = os.path.join(ROOT, "assets", "raw", "external")
SPR_DIR = os.path.join(ROOT, "assets", "sprites")
FX_DIR = os.path.join(ROOT, "assets", "effects")

PACKS = [
    {
        "id": "craftpix_bosses",
        "author": "CraftPix.net",
        "license": "OGA-BY 3.0",
        "page": "https://opengameart.org/content/bosses-pixel-art-sprite-sheet",
        "file_url": "https://opengameart.org/sites/default/files/bosses-pixel-art-sprite-sheet-pack.zip",
        "bytes": 54246,
        "credit": "Boss stand-ins: CraftPix Bosses Pack (OGA-BY 3.0)",
    },
    {
        "id": "ruok_projectiles",
        "author": "RUOK",
        "license": "CC0",
        "page": "https://opengameart.org/content/bright-projectiles-missiles-and-bullets",
        "file_url": "https://opengameart.org/sites/default/files/ruokprojectilepack.zip",
        "bytes": 791530,
        "credit": "Danmaku bullets: RUOK Projectiles (CC0)",
    },
]

CELL = 72
BOSSES = [
    {"game_id": "sys_builder", "pack_no": "2", "note": "최종보스 — 가장 큰 체구 + 탄 보유"},
    {"game_id": "professor_monster", "pack_no": "3", "note": "4층 제압전 보스(D14: 탄막 없음, 본체만)"},
]
ROWS = [  # (시트 행 이름, 팩 파일, fps, loop)
    ("idle", "Idle", 4, True),
    ("walk_right", "Walk", 6, True),
    ("walk_left", "Walk", 6, True),
    ("attack", "Attack1", 10, False),
    ("special", "Attack2", 10, False),
    ("hurt", "Hurt", 8, False),
    ("death", "Death", 6, False),
]
MAGENTA = (255, 0, 255)


def fetch(pack: dict, no_download: bool) -> str:
    os.makedirs(RAW_EXT, exist_ok=True)
    zp = os.path.join(RAW_EXT, pack["id"] + ".zip")
    if os.path.exists(zp) and os.path.getsize(zp) == pack["bytes"]:
        print("  [%s] zip 있음(크기 일치) — 재사용" % pack["id"])
    elif no_download:
        sys.exit("zip 없음: %s (--no-download 해제하고 받으라)" % zp)
    else:
        print("  [%s] 다운로드 중..." % pack["id"])
        urllib.request.urlretrieve(pack["file_url"], zp)
        got = os.path.getsize(zp)
        print("  [%s] %d bytes (기록 %d)" % (pack["id"], got, pack["bytes"]))
    out = os.path.join(RAW_EXT, pack["id"])
    with zipfile.ZipFile(zp) as z:
        z.extractall(out)
    with io.open(os.path.join(out, "CREDITS.txt"), "w", encoding="utf-8") as fh:
        fh.write("%s\n%s\n%s\n%s\n" % (
            pack["credit"], "Author: " + pack["author"],
            "License: " + pack["license"], "Page: " + pack["page"]))
    return out


def split_strip(path: str) -> list:
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    assert h == CELL and w % CELL == 0, "셀 규격 아님: %s %s" % (path, im.size)
    return [im.crop((x * CELL, 0, (x + 1) * CELL, CELL)) for x in range(w // CELL)]


def despeckle(im: Image.Image) -> int:
    """테두리 1px 고립점 제거(Bullet.png 모서리 검은점 같은 것). 몸통은 안 건든다."""
    px = im.load()
    w, h = im.size
    n = 0
    for x, y in [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] \
            + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]:
        if px[x, y][3] == 0:
            continue
        inside = [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                  if 0 <= x + dx < w and 0 <= y + dy < h and (dx or dy)]
        if all(px[ix, iy][3] == 0 for ix, iy in inside):
            px[x, y] = (0, 0, 0, 0)
            n += 1
    return n


def bake_boss(pack_dir: str, game_id: str, no: str) -> dict:
    frames: dict[str, list] = {}
    for _row, name, _fps, _loop in ROWS:
        if name not in frames:
            frames[name] = split_strip(os.path.join(pack_dir, no, name + ".png"))
    cols = max(len(v) for v in frames.values())
    sheet = Image.new("RGBA", (cols * CELL, len(ROWS) * CELL), (0, 0, 0, 0))
    anims = {}
    for r, (row, name, fps, loop) in enumerate(ROWS):
        for i, fr in enumerate(frames[name]):
            sheet.paste(fr, (i * CELL, r * CELL))
        anims[row] = {"row": r, "frames": len(frames[name]), "fps": fps, "loop": loop}
    n = despeckle(sheet)
    px = sheet.load()
    bad = sum(1 for y in range(sheet.height) for x in range(sheet.width)
              if px[x, y][:3] == MAGENTA and px[x, y][3] > 0)
    assert bad == 0, "마젠타 잔류 %dpx" % bad
    png = os.path.join(SPR_DIR, game_id + "_external.png")
    sheet.save(png)
    meta = {"schema_version": 2,
            "source": "external:craftpix_bosses#%s (OGA-BY 3.0)" % no,
            "cell": CELL, "cell_w": CELL, "cell_h": CELL,
            "cols": cols, "scale": 1.0, "animations": anims}
    with io.open(os.path.join(SPR_DIR, game_id + "_external.json"),
                 "w", encoding="utf-8", newline="\n") as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=2)
    print("  %s: %dx%d %d행 (고립점 %d 제거)" % (game_id, *sheet.size, len(ROWS), n))
    return {"game_id": game_id, "pack_no": no, "size": list(sheet.size)}


def pick_ring(pack_dir: str) -> dict:
    """OpenCircleBullets(16px 링 10색)에서 난색·한색을 골라 탄 2종으로 굽는다."""
    strip = Image.open(os.path.join(pack_dir, "OpenCircleBullets.png")).convert("RGBA")
    cells = [strip.crop((17 * i, 0, 17 * i + 16, 16)) for i in range(10)]
    def hue(cell: Image.Image) -> float:
        # 링 중앙은 비어 있다 — 불투명 픽셀들의 평균 색조를 쓴다.
        px = list(cell.getdata())
        op = [(r, g, b) for r, g, b, a in px if a > 8]
        if not op:
            return -1.0
        n = len(op)
        sr = sum(r for r, _g, _b in op) / n / 255
        sg = sum(g for _r, g, _b in op) / n / 255
        sb = sum(b for _r, _g, b in op) / n / 255
        h, _s, _v = colorsys.rgb_to_hsv(sr, sg, sb)
        return h * 360
    warm = min(range(10), key=lambda i: min(abs(hue(cells[i]) - 20), 360 - abs(hue(cells[i]) - 20)))
    cool = min(range(10), key=lambda i: min(abs(hue(cells[i]) - 210), 360 - abs(hue(cells[i]) - 210)))
    out = {}
    for name, i in (("ext_bullet_warm", warm), ("ext_bullet_cool", cool)):
        p = os.path.join(FX_DIR, name + ".png")
        cells[i].save(p)
        out[name] = {"cell": i, "hue": round(hue(cells[i]))}
        print("  %s: 링 %d번(색상 %d도)" % (name, i, out[name]["hue"]))
    return out


def main() -> None:
    no_dl = "--no-download" in sys.argv
    print("[bake_external_bosses] 외부 스탠드인 굽기")
    pack_dir = {p["id"]: fetch(p, no_dl) for p in PACKS}
    baked = [bake_boss(pack_dir["craftpix_bosses"], b["game_id"], b["pack_no"]) for b in BOSSES]
    rings = pick_ring(pack_dir["ruok_projectiles"])
    manifest = {"_comment": "외부 스탠드인 출처 단일 기록. _remake 설치 시 자동 교체(코드 수정 불필요).",
                "packs": PACKS, "baked_bosses": baked, "baked_bullets": rings}
    with io.open(os.path.join(ROOT, "data", "external_sources.json"),
                 "w", encoding="utf-8", newline="\n") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)
    cp = os.path.join(ROOT, "data", "credits.json")
    cr = json.load(io.open(cp, encoding="utf-8"))
    for line in [p["credit"] for p in PACKS]:
        if line not in cr["staff_roll"]:
            cr["staff_roll"].append(line)
    with io.open(cp, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(cr, fh, ensure_ascii=False, indent=2)
    print("[bake_external_bosses] 완료 — data/external_sources.json + credits 갱신")


if __name__ == "__main__":
    main()
