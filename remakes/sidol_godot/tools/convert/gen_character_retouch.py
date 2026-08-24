"""캐릭터 스프라이트 시트 시범 리터칭 + character_bible.html 비교 섹션 주입.

- assets/sprites/player_original.png(I.SPR 원작 도트)를 애니 행별로 잘라
  sprite_retouch 파이프라인(팔레트 잠금/명암 밴딩/남보라 그림자/남색 아웃라인) 적용
- 원본 스트립 vs 리터치 스트립 쌍을 samples/player_* 로 저장
- 기존 뷰어 character_bible.html 에 <!-- RETOUCH:PLAYER --> 마커 블록으로 주입
  (기존 기능을 건드리지 않고 섹션만 교체 - 재실행 안전)

사용: python tools/convert/gen_character_retouch.py
"""
from __future__ import annotations
import base64
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sprite_retouch as sr  # noqa: E402
from PIL import Image  # noqa: E402

ROOT = sr.ROOT
ATLAS = os.path.join(ROOT, "assets", "sprites", "player_original.png")
META = os.path.join(ROOT, "assets", "sprites", "player_original.json")
BIBLE = os.path.join(ROOT, "assets", "gen", "viewers", "character_bible.html")
MARK_BEGIN = "<!-- RETOUCH:PLAYER BEGIN -->"
MARK_END = "<!-- RETOUCH:PLAYER END -->"

ANIMS = ["walk_down", "walk_up", "walk_left", "walk_right", "idle_down"]


def b64(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def main() -> None:
    atlas = Image.open(ATLAS).convert("RGBA")
    meta = json.load(io.open(META, encoding="utf-8"))
    cell = int(meta["cell"])
    cols = int(meta["cols"])
    blocks = []
    for anim in ANIMS:
        info = meta.get("animations", {}).get(anim)
        if not info:
            continue
        row = int(info["row"])
        frames = []
        for f in range(int(info["frames"])):
            c = atlas.crop((f * cell, row * cell, (f + 1) * cell,
                            (row + 1) * cell))
            orig = sr.remove_background(c)
            orig = sr.crop_content(orig)
            # 프레임 단위 파이프라인(공통 함수 재사용)
            tmp = sr.remove_background(c)
            tmp = sr.crop_content(tmp)
            tmp = sr.snap_palette(tmp)
            tmp = sr.shade_jrpg(tmp)
            tmp = sr.add_outline(tmp)
            tmp = tmp.resize((tmp.width * sr.SCALE, tmp.height * sr.SCALE),
                             Image.NEAREST)
            frames.append((orig, tmp))
        if not frames:
            continue
        h_orig = max(o.height for o, _ in frames)
        w_orig = sum(o.width for o, _ in frames) + 8 * (len(frames) - 1)
        h_ret = max(t.height for _, t in frames)
        w_ret = sum(t.width for _, t in frames) + 8 * (len(frames) - 1)
        strip_o = Image.new("RGBA", (w_orig, h_orig), (0, 0, 0, 0))
        strip_r = Image.new("RGBA", (w_ret, h_ret), (0, 0, 0, 0))
        x1 = x2 = 0
        for o, t in frames:
            strip_o.paste(o, (x1, 0), o)
            strip_r.paste(t, (x2, 0), t)
            x1 += o.width + 8
            x2 += t.width + 8
        po = os.path.join(sr.OUT, f"player_{anim}_original.png")
        pr = os.path.join(sr.OUT, f"player_{anim}_retouched.png")
        strip_o.save(po)
        strip_r.save(pr)
        blocks.append((anim, b64(strip_o), b64(strip_r)))
        print("ok:", anim)

    section = [MARK_BEGIN,
               '<div style="border-top:2px solid #2a3550;margin-top:24px;'
               'padding:16px">',
               '<h3 style="color:#ffb74d;font-size:15px;margin-bottom:10px">'
               '스프라이트 리터치 시범 - I.SPR 원작 도트 '
               '(팔레트 잠금 / 5단 명암 / 남보라 색조 그림자)</h3>']
    for anim, o, r in blocks:
        section.append(
            f'<div style="margin-bottom:18px">'
            f'<div style="font-family:monospace;color:#81c784;margin-bottom:6px">'
            f'{anim}</div>'
            f'<div style="display:flex;gap:24px;flex-wrap:wrap">'
            f'<figure><figcaption style="font-size:11px;color:#90a4ae">'
            f'ORIGINAL</figcaption>'
            f'<img src="{o}" style="image-rendering:pixelated;background:'
            f'repeating-conic-gradient(#20242f 0% 25%,#171a23 0% 50%) 50%/12px 12px"></figure>'
            f'<figure><figcaption style="font-size:11px;color:#ffd54f">'
            f'RETOUCHED</figcaption>'
            f'<img src="{r}" style="image-rendering:pixelated;background:'
            f'repeating-conic-gradient(#20242f 0% 25%,#171a23 0% 50%) 50%/12px 12px"></figure>'
            f'</div></div>')
    section.append("</div>")
    section.append(MARK_END)
    new_block = "\n".join(section)

    with open(BIBLE, encoding="utf-8") as fh:
        html = fh.read()
    if MARK_BEGIN in html and MARK_END in html:
        pre = html.split(MARK_BEGIN)[0]
        post = html.split(MARK_END)[1]
        html = pre + new_block + post
    else:
        html = html.replace("</body>", new_block + "\n</body>")
    with open(BIBLE, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(html)
    print("injected ->", BIBLE)


if __name__ == "__main__":
    main()
