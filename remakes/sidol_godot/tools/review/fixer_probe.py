# -*- coding: utf-8 -*-
"""셀 편집기 실조작 시험 — 사람이 눌러 보는 대신 브라우저를 몰아 실제로 그려 본다.

왜 있나: 지우개·연필은 **마우스 이벤트 사이가 비면 자국이 점선처럼 끊긴다**. 그 결함은
코드를 읽어서는 안 보이고, 문법 검사(fixer_check.py)로도 안 잡힌다 — 빠르게 문지를 때만
난다. 예전 세션은 브라우저가 없어 "눌러 보지 못했다"로 끝냈고, 지우개가 시험 없이
커밋됐다. 여기서는 playwright(chromium)로 진짜 드래그를 만들어 캔버스 픽셀을 읽는다.

  py tools/review/fixer_probe.py            # 실패하면 종료코드 1
  py tools/review/fixer_probe.py --shots    # 시험 끝 화면을 옆에 남긴다

서버 없이 file:// 로 연다 — 로컬 파일 열기 경로(#localfile)로 시험용 시트를 밀어 넣고
계약은 fallbackContract가 만든 것을 쓴다. 서버가 하는 픽셀 연산(sheet_ops.py)은
여기서 안 본다. 여기서 보는 것은 **브라우저 안의 조작**뿐이다.
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PAGE = (HERE / "sprite_fixer.html").as_uri()
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def make_sheet(path: Path, w: int = 256, h: int = 256) -> None:
    """전면 불투명 시트 — 지운 자리가 alpha 0으로 또렷하게 보이도록."""
    from PIL import Image
    Image.new("RGBA", (w, h), (40, 60, 200, 255)).save(path)


def make_move_sheet(path: Path) -> None:
    """부동 이동 시험용 — 투명 배경에 덩어리 둘.

    · r1c0 덩어리는 **행 밴드 위로 18px 삐져나가** 있다(격자 밖으로 나간 캐릭터의 재현).
    · r0 덩어리는 그와 **떨어져** 있다 — 행1을 옮길 때 따라오면 안 된다.
    """
    from PIL import Image
    im = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    px = im.load()
    for y in range(110, 200):                 # 셀 경계(y=128) 위로 18px 삐져나감
        for x in range(40, 80):
            px[x, y] = (200, 70, 70, 255)
    for y in range(20, 60):                   # 행0의 별개 덩어리 — 붙어 있지 않다
        for x in range(150, 190):
            px[x, y] = (70, 200, 120, 255)
    im.save(path)


def bresenham(x0, y0, x1, y1):
    pts, dx, dy = [], abs(x1 - x0), abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx - dy
    while True:
        pts.append((x0, y0))
        if x0 == x1 and y0 == y1:
            return pts
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x0 += sx
        if e2 < dx:
            err += dx
            y0 += sy


class Probe:
    def __init__(self, pg):
        self.pg = pg
        self.fails: list[str] = []
        self.lines: list[str] = []

    def ok(self, name, cond, detail=""):
        self.lines.append(("  OK  " if cond else "  X   ") + name
                          + (f" — {detail}" if detail and not cond else ""))
        if not cond:
            self.fails.append(f"{name}: {detail}")

    def to_screen(self, x, y):
        r = self.pg.eval_on_selector("#view", "e=>{const b=e.getBoundingClientRect();return [b.x,b.y]}")
        z = self.pg.evaluate("zoomFactor()")
        return r[0] + x * z + z / 2, r[1] + y * z + z / 2

    def alphas(self, pts):
        """work 캔버스에서 여러 점의 alpha를 한 번에 읽는다."""
        return self.pg.evaluate(
            """pts=>{const d=wctx.getImageData(0,0,work.width,work.height).data;
                     return pts.map(p=>d[(p[1]*work.width+p[0])*4+3]);}""",
            [list(p) for p in pts])

    def rgbs(self, pts):
        """색을 본다. 배경이 불투명(alpha 255)이라 '그렸는가'는 alpha로 못 가른다 —
        연필·되돌리기 시험은 반드시 색으로 판정해야 한다."""
        return self.pg.evaluate(
            """pts=>{const d=wctx.getImageData(0,0,work.width,work.height).data;
                     return pts.map(p=>{const i=(p[1]*work.width+p[0])*4;
                       return [d[i],d[i+1],d[i+2],d[i+3]];});}""",
            [list(p) for p in pts])

    def sig(self):
        """캔버스 전체의 지문 — 불투명 픽셀 수와 위치·색을 함께 담는다.

        '왕복하면 원본 그대로'를 재려면 픽셀 수만으로는 모자란다(같은 수로 밀려 있어도
        통과해 버린다). 위치까지 섞은 해시를 쓴다.
        """
        return self.pg.evaluate(
            """()=>{const d=wctx.getImageData(0,0,work.width,work.height).data;
                    let n=0,h=0;
                    for(let i=0;i<d.length;i+=4) if(d[i+3]>8){
                      n++; h=(Math.imul(h,31)+(i>>2)+d[i]*7)|0; }
                    return [n,h];}""")

    def bbox(self, x0, y0, x1, y1):
        """구간 안 불투명 픽셀의 경계상자 — 없으면 None."""
        return self.pg.evaluate(
            """r=>{const w=work.width,d=wctx.getImageData(0,0,w,work.height).data;
                   let a=1e9,b=1e9,c=-1,e=-1;
                   for(let y=r[1];y<r[3];y++) for(let x=r[0];x<r[2];x++){
                     if(d[(y*w+x)*4+3]<=8) continue;
                     if(x<a)a=x; if(x>c)c=x; if(y<b)b=y; if(y>e)e=y; }
                   return c<0?null:[a,b,c,e];}""", [x0, y0, x1, y1])

    def drag(self, a, b, steps=1, button="left", modifiers=None):
        """steps=1이면 중간 이벤트가 없는 '순간이동' 드래그 — 보간이 없으면 여기서 끊긴다."""
        m = self.pg.mouse
        sx, sy = self.to_screen(*a)
        ex, ey = self.to_screen(*b)
        for k in (modifiers or []):
            self.pg.keyboard.down(k)
        m.move(sx, sy)
        m.down(button=button)
        m.move(ex, ey, steps=steps)
        m.up(button=button)
        for k in (modifiers or []):
            self.pg.keyboard.up(k)


def run(shots: bool) -> int:
    from playwright.sync_api import sync_playwright

    tmp = Path(tempfile.mkdtemp(prefix="fixer_probe_"))
    sheet = tmp / "probe_sheet_v1.png"
    make_sheet(sheet)

    with sync_playwright() as pw:
        br = pw.chromium.launch()
        pg = br.new_page(viewport={"width": 1500, "height": 900})
        errs: list[str] = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto(PAGE)
        pg.wait_for_timeout(400)
        pg.set_input_files("#localfile", str(sheet))
        pg.wait_for_function("typeof work!=='undefined' && work && work.width===256", timeout=5000)
        pg.eval_on_selector("#picker", "e=>e.hidden=true")
        pg.select_option("#zoom", "1")          # 1px = 화면 1px, 좌표 계산을 단순하게
        p = Probe(pg)

        # 1) 지우개 — 이벤트 하나로 건너뛰는 긴 대각 드래그. 보간이 없으면 점선이 된다.
        pg.click("#tool-erase")
        pg.select_option("#brushsize", "1")
        a, b = (20, 20), (200, 140)
        p.drag(a, b, steps=1)
        line = bresenham(a[0], a[1], b[0], b[1])
        av = p.alphas(line)
        left = [pt for pt, v in zip(line, av) if v != 0]
        p.ok("지우개 문지르기: 자국이 끊기지 않는다", not left,
             f"선 {len(line)}px 중 {len(left)}px가 안 지워짐 (예: {left[:5]})")

        # 2) 굵기 12px — 커서가 붓의 중앙인가(굵을 때 한쪽으로 밀리던 것).
        pg.select_option("#brushsize", "12")
        p.drag((128, 200), (128, 210), steps=1)
        probe = [(122, 205), (133, 205), (120, 205), (135, 205)]
        v = p.alphas(probe)
        p.ok("굵은 지우개가 커서를 중심에 둔다",
             v[0] == 0 and v[1] == 0 and v[2] != 0 and v[3] != 0,
             f"좌-6={v[0]} 우+5={v[1]} 좌-8={v[2]} 우+7={v[3]} (안쪽 0 · 바깥 0아님이어야)")

        # 3) 우클릭 지우개는 도구와 무관하게 동작한다(선택 도구 상태에서).
        pg.click("#tool-select")
        pg.select_option("#brushsize", "1")
        p.drag((30, 230), (90, 230), steps=1, button="right")
        seg = [(x, 230) for x in range(30, 91)]
        v = p.alphas(seg)
        p.ok("선택 도구에서도 우클릭 지우개가 이어진다", all(k == 0 for k in v),
             f"{sum(1 for k in v if k)}px 남음")

        # 4) Shift+드래그 사각 지우기 — 지우개 모드에서도 되는가.
        pg.click("#tool-erase")
        p.drag((150, 30), (180, 60), steps=3, modifiers=["Shift"])
        inside = [(160, 40), (170, 50), (150, 30), (180, 60)]
        outside = [(149, 40), (181, 50), (160, 29), (170, 61)]
        vi, vo = p.alphas(inside), p.alphas(outside)
        p.ok("Shift+드래그 사각 지우기(지우개 모드)",
             all(k == 0 for k in vi) and all(k != 0 for k in vo), f"안쪽 {vi} 바깥 {vo}")

        # 5) 지움 대상 = 마젠타. 투명으로 뚫지 않고 배경색으로 덮는가.
        pg.select_option("#erasemode", "magenta")
        p.drag((40, 100), (110, 100), steps=1)
        px = pg.evaluate("()=>{const d=wctx.getImageData(75,100,1,1).data;return [d[0],d[1],d[2],d[3]]}")
        p.ok("지움 → 마젠타가 배경색으로 덮는다", px == [255, 0, 255, 255], f"{px}")
        pg.select_option("#erasemode", "clear")

        # 6) 연필도 같은 보간을 쓰는가 — 1)에서 지운 대각선을 가로질러 그린다.
        pg.click("#tool-pencil")
        pg.evaluate("picked=null")
        pg.eval_on_selector("#brushcolor", "e=>{e.value='#ff2200'}")
        a2, b2 = (25, 25), (195, 135)
        p.drag(a2, b2, steps=1)
        line2 = bresenham(a2[0], a2[1], b2[0], b2[1])
        RED = [255, 34, 0, 255]
        v = p.rgbs(line2)
        p.ok("연필 자국도 끊기지 않는다", all(k == RED for k in v),
             f"{sum(1 for k in v if k != RED)}px가 안 칠해짐 (예: {[k for k in v if k != RED][:3]})")

        # 7) 되돌리기가 스트로크 단위인가 — 한 번 누르면 방금 연필선이 통째로 사라진다.
        pg.click("#undo")
        pg.wait_for_timeout(150)
        v = p.rgbs(line2)
        still = sum(1 for k in v if k == RED)
        p.ok("되돌리기 한 번이 스트로크 하나를 되돌린다", still == 0,
             f"{still}/{len(v)}px가 아직 붉게 남아 있다")

        # 8) 도구 단축키 배선
        bad = []
        for k, want in {"v": "select", "b": "pencil", "g": "fill", "e": "erase"}.items():
            pg.keyboard.press(k)
            got = pg.evaluate("tool")
            if got != want:
                bad.append(f"{k}→{got}(기대 {want})")
        p.ok("도구 단축키 V·B·G·E", not bad, ", ".join(bad))

        # 9) 헤더가 눌린 도구를 하나만 표시하는가(아이콘 정리 뒤 배선 확인)
        pg.keyboard.press("e")
        pressed = pg.eval_on_selector_all(
            ".toolbtn", "es=>es.filter(e=>e.getAttribute('aria-pressed')==='true').map(e=>e.id)")
        p.ok("눌린 도구가 헤더에 하나만 표시된다", pressed == ["tool-erase"], f"{pressed}")

        # 10) 부동 이동 — 격자 밖으로 삐져나간 그림이 잘리지 않는가.
        #     여기서 재는 것은 예전 결함 그대로다: 밴드에서 집어 밴드로 잘라 붙이면
        #     ① 삐져나온 부분은 안 따라오고 ② 밴드를 벗어난 픽셀은 그 자리에서 소멸했다.
        move_sheet = tmp / "probe_move_v1.png"
        make_move_sheet(move_sheet)
        # confirmDiscard()의 confirm()은 playwright가 자동으로 '아니오'로 답한다 —
        # 앞 시험이 남긴 dirty를 내려놓지 않으면 파일이 조용히 안 바뀐다.
        pg.evaluate("dirty=false")
        pg.set_input_files("#localfile", str(move_sheet))
        pg.wait_for_function("work && LOCAL==='probe_move_v1.png' && !floating", timeout=5000)
        pg.select_option("#zoom", "1")
        pg.click("#tool-select")
        base = p.sig()
        # 이웃 덩어리만 보는 구간이어야 한다 — 행0 밴드 전체를 재면 r1 덩어리의
        # 삐져나온 부분(y110~127)까지 들어와 '안 움직였는가'를 못 가린다.
        row0_before = p.bbox(140, 0, 256, 128)
        p.ok("이동 시험 시트: 삐져나온 덩어리와 떨어진 덩어리가 있다",
             base[0] == 90 * 40 + 40 * 40, f"불투명 {base[0]}px (기대 {90*40+40*40})")

        # 행1의 셀을 고르고 행 전체를 8px 아래로.
        sx, sy = p.to_screen(60, 160)
        pg.mouse.click(sx, sy)
        pg.click("[data-op='rowdown']", modifiers=["Shift"])
        pg.eval_on_selector("[data-op='rowdown']", "e=>e.blur()")
        held = pg.evaluate("floating && [floating.kind, floating.dx, floating.dy, floating.px]")
        p.ok("행 이동은 확정 전까지 띄운 채로 있다", held == ["row", 0, 8, 90 * 40],
             f"{held} (기대 ['row',0,8,{90*40}])")
        pg.keyboard.press("Enter")
        pg.wait_for_timeout(150)

        after = p.sig()
        p.ok("행을 옮겨도 불투명 픽셀이 한 개도 안 없어진다", after[0] == base[0],
             f"{base[0]}px → {after[0]}px ({base[0] - after[0]}px 사라짐)")
        moved = p.bbox(0, 100, 140, 256)
        p.ok("격자 위로 삐져나온 부분까지 함께 내려간다", moved == [40, 118, 79, 207],
             f"{moved} (기대 [40,118,79,207] — 예전에는 y0가 110에 남았다)")
        row0_after = p.bbox(140, 0, 256, 128)
        p.ok("떨어져 있는 이웃 행 그림은 안 따라온다", row0_after == row0_before,
             f"{row0_before} → {row0_after}")

        # 11) 왕복 무손실 — ↓8 뒤 ↑8이면 원본 그대로여야 한다(예전엔 잘려 안 돌아왔다).
        pg.click("[data-op='rowup']", modifiers=["Shift"])
        pg.eval_on_selector("[data-op='rowup']", "e=>e.blur()")
        pg.keyboard.press("Enter")
        pg.wait_for_timeout(150)
        back = p.sig()
        p.ok("↓8 뒤 ↑8은 원본과 픽셀까지 같다", back == base, f"{base} → {back}")

        # 12) Esc — 확정 안 한 이동은 통째로 없던 일이 된다.
        for _ in range(3):
            pg.click("[data-op='rowright']")
        pg.eval_on_selector("[data-op='rowright']", "e=>e.blur()")
        pg.keyboard.press("Escape")
        pg.wait_for_timeout(150)
        p.ok("Esc로 이동을 취소하면 원본 그대로", p.sig() == base and not pg.evaluate("!!floating"),
             f"{p.sig()} · floating={pg.evaluate('!!floating')}")

        # 13) 되돌리기가 **제스처 단위**인가 — 5번 눌러도 Ctrl+Z 한 번이면 원상.
        undo_before = pg.evaluate("undoStack.length")
        for _ in range(5):
            pg.click("[data-op='rowdown']")
        pg.eval_on_selector("[data-op='rowdown']", "e=>e.blur()")
        pg.keyboard.press("Enter")
        pg.wait_for_timeout(150)
        grew = pg.evaluate("undoStack.length") - undo_before
        p.ok("1px씩 5번 눌러도 되돌리기는 하나만 쌓인다", grew == 1, f"{grew}개 쌓임(기대 1)")
        pg.keyboard.press("Control+z")
        pg.wait_for_timeout(150)
        p.ok("되돌리기 한 번이 이동 제스처 하나를 되돌린다", p.sig() == base, f"{p.sig()} vs {base}")

        # 14) 셀 방향키 이동도 같은 규칙 — 칸 밖으로 삐져나온 부분이 안 잘린다.
        sx, sy = p.to_screen(60, 160)
        pg.mouse.click(sx, sy)
        for _ in range(6):
            pg.keyboard.press("ArrowDown")
        pg.keyboard.press("Enter")
        pg.wait_for_timeout(150)
        cell_after = p.sig()
        p.ok("셀 방향키 이동도 픽셀을 잃지 않는다", cell_after[0] == base[0],
             f"{base[0]}px → {cell_after[0]}px")
        for _ in range(6):
            pg.keyboard.press("ArrowUp")
        pg.keyboard.press("Enter")
        pg.wait_for_timeout(150)
        p.ok("셀 이동도 왕복하면 원본 그대로", p.sig() == base, f"{p.sig()} vs {base}")

        # 15) 잘리는 경우에는 **수치로 말한다** — 캔버스 밖으로 크게 밀어 본다.
        pg.evaluate("$('#log').innerHTML=''")
        for _ in range(30):
            pg.click("[data-op='rowdown']", modifiers=["Shift"])
        pg.eval_on_selector("[data-op='rowdown']", "e=>e.blur()")
        pg.keyboard.press("Enter")
        pg.wait_for_timeout(200)
        txt = pg.eval_on_selector("#log", "e=>e.textContent")
        p.ok("캔버스 밖으로 나가 잘리면 그 수를 세어 알린다", "잘린" in txt and "px" in txt,
             (txt or "")[-160:].replace(chr(10), " / "))
        pg.keyboard.press("Control+z")
        pg.wait_for_timeout(150)

        if shots:
            out = HERE / "_probe_shot.png"
            pg.screenshot(path=str(out))
            p.lines.append(f"  ·   화면: {out}")

        # 13) 영역으로 집어 옮기기 — 행도 셀도 아닌 덩어리를 사람이 사각형으로 집는다.
        #     행 단위 이동으로는 격자를 벗어난 그림을 못 맞춘다는 실사용 지적에서 나왔다.
        pg.evaluate("dirty=false")
        pg.set_input_files("#localfile", str(move_sheet))
        pg.wait_for_function("work && LOCAL==='probe_move_v1.png' && !floating", timeout=5000)
        pg.select_option("#zoom", "1")
        pg.click("#tool-select")
        base2 = p.sig()

        # (a) 선택 도구 맨드래그로 r0 덩어리(150~189, 20~59)만 감싸 집는다.
        p.drag((145, 15), (195, 65), steps=3)
        held = pg.evaluate("floating && [floating.kind, floating.px, floating.w, floating.h]")
        p.ok("선택 도구 드래그가 영역을 집는다",
             held and held[0] == "rect" and held[1] == 40 * 40,
             f"{held} (기대 rect · 1600px)")

        # 집은 자리는 캔버스에서 비어 있어야 한다 — 들고 있는 동안은 work에서 빠진다.
        hole = p.bbox(140, 0, 256, 128)
        p.ok("집는 동안 원래 자리는 비어 있다", hole is None, f"{hole}")

        # (b) 든 영역을 마우스로 끌어 옮긴다(방향키가 아니라 실제 드래그).
        p.drag((170, 40), (170, 100), steps=4)
        moved_dy = pg.evaluate("floating && floating.dy")
        p.ok("든 영역을 마우스로 끌어 옮긴다", moved_dy == 60, f"dy={moved_dy} (기대 60)")

        # (c) Esc — 원본 그대로. 사람이 정한 범위가 날아가도 픽셀은 살아야 한다.
        pg.keyboard.press("Escape")
        p.ok("Esc로 영역 이동을 취소하면 원본 그대로",
             p.sig() == base2 and not pg.evaluate("!!floating"),
             f"{p.sig()} vs {base2}")

        # (d) 다시 집어 Enter로 확정 — 픽셀 총량이 보존되고 실제로 옮겨져 있어야 한다.
        p.drag((145, 15), (195, 65), steps=3)
        p.drag((170, 40), (170, 100), steps=4)
        pg.keyboard.press("Enter")
        after2 = p.sig()
        box = p.bbox(140, 0, 256, 256)
        p.ok("영역 이동을 확정해도 불투명 픽셀이 안 없어진다", after2[0] == base2[0],
             f"{base2[0]} → {after2[0]}")
        p.ok("확정한 영역이 실제로 60px 내려가 있다", box == [150, 80, 189, 119],
             f"{box} (기대 [150, 80, 189, 119])")

        # (e) [선택 칸에 앉히기] — 계약 정렬 자리(가로 중앙·바닥 여백 4%)로 간다.
        #     "격자를 벗어난 객체를 셀 안으로"가 이 기능의 목적이라 여기서 좌표로 잰다.
        pg.evaluate("dirty=false")
        pg.set_input_files("#localfile", str(move_sheet))
        pg.wait_for_function("work && LOCAL==='probe_move_v1.png' && !floating", timeout=5000)
        pg.select_option("#zoom", "1")
        pg.click("#tool-select")
        cell = pg.evaluate("contract.cell")
        p.drag((145, 15), (195, 65), steps=3)          # r0 덩어리를 집고
        sx, sy = p.to_screen(30, 160)                  # r1c0 칸을 선택 대상으로
        pg.evaluate("sel={r:1,c:0}")
        pg.click("[data-op='fitcell']")
        pg.keyboard.press("Enter")
        # 측정 구간을 y205 아래로 잡는다 — 이 시트에는 r1c0에 원래 덩어리(y110~199)가
        # 있어서 칸 전체를 재면 그것과 합쳐진 경계상자가 나온다(실제로 그렇게 헛짚었다).
        fit = p.bbox(0, 205, 128, 256)
        want_cx = cell / 2
        got_cx = None if not fit else (fit[0] + fit[2]) / 2
        margin = None if not fit else (2 * cell - 1 - fit[3])
        p.ok("[선택 칸에 앉히기]가 칸 가로 중앙에 맞춘다",
             fit is not None and abs(got_cx - want_cx) <= 1,
             f"중심 x={got_cx} (기대 {want_cx}) · fit={fit} · cell={cell}")
        p.ok("[선택 칸에 앉히기]가 칸 바닥에 접지시킨다",
             margin == round(cell * 0.04),
             f"바닥 여백 {margin}px (기대 {round(cell * 0.04) if cell else '?'})")

        # (f) 부정 시험 — 짧은 클릭은 영역을 집지 않는다(예전 셀 선택이 살아 있어야 한다).
        pg.evaluate("dirty=false")
        pg.set_input_files("#localfile", str(move_sheet))
        pg.wait_for_function("work && LOCAL==='probe_move_v1.png' && !floating", timeout=5000)
        pg.select_option("#zoom", "1")
        pg.click("#tool-select")
        cx2, cy2 = p.to_screen(60, 160)
        pg.mouse.click(cx2, cy2)
        p.ok("부정 시험 - 짧은 클릭은 영역을 집지 않는다",
             not pg.evaluate("!!floating") and pg.evaluate("sel && [sel.r, sel.c]") == [1, 0],
             f"floating={pg.evaluate('!!floating')} sel={pg.evaluate('sel && [sel.r,sel.c]')}")

        p.ok("페이지 예외 없음", not errs, " / ".join(errs[:3]))
        br.close()

    print("[셀 편집기 실조작 시험] file:// · chromium · 256×256 시트")
    for ln in p.lines:
        print(ln)
    if p.fails:
        print(f"\n실패 {len(p.fails)}건")
        return 1
    print("\n통과 — 그리기·지우기·되돌리기·단축키가 실제 드래그에서 동작한다.")
    return 0


def run_server_mode() -> int:
    """서버를 실제로 띄우고 **크기·배경 자동 보정과 픽셀풍**이 왕복해서 도는지 본다.

    file:// 모드로는 못 보는 층이다 — 픽셀 규칙은 전부 파이썬(sheet_ops.py)에 있고
    편집기는 /api/fixer/op 로 왕복한다. 그 왕복이 끊기면(서버가 옛 버전이거나 연산 이름이
    어긋나면) 편집기는 조용히 아무 일도 안 하는 상태가 된다.
    """
    import socket
    import subprocess
    from playwright.sync_api import sync_playwright
    from PIL import Image

    root = HERE.parent.parent
    with socket.socket() as sk:                    # 빈 포트를 잡아 기존 서버와 안 부딪히게
        sk.bind(("127.0.0.1", 0))
        port = sk.getsockname()[1]

    tmp = Path(tempfile.mkdtemp(prefix="fixer_probe_srv_"))
    # 웹 LLM 납품의 전형: 계약과 다른 크기 + 흰 배경 + 그림 안쪽에도 흰 점.
    bad = Image.new("RGBA", (300, 150), (255, 255, 255, 255))
    for y in range(40, 110):
        for x in range(60, 240):
            bad.putpixel((x, y), (70, 110, 190, 255))
    for y in range(60, 70):
        for x in range(90, 100):
            bad.putpixel((x, y), (255, 255, 255, 255))   # 그림 안쪽 흰 점
    sheet = tmp / "probe_web_v1.png"
    bad.save(sheet)

    proc = subprocess.Popen([sys.executable, str(HERE / "review_server.py"), str(port)],
                            cwd=str(root), stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    lines, fails = [], []

    def ok(name, cond, detail=""):
        lines.append(("  OK  " if cond else "  X   ") + name
                     + (f" — {detail}" if detail and not cond else f" — {detail}" if detail else ""))
        if not cond:
            fails.append(name)

    try:
        for _ in range(60):                        # 서버가 뜰 때까지
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.3):
                    break
            except OSError:
                pass
        with sync_playwright() as pw:
            br = pw.chromium.launch()
            pg = br.new_page(viewport={"width": 1500, "height": 900})
            errs = []
            pg.on("pageerror", lambda e: errs.append(str(e)))
            # portraits는 서버가 계약을 아는 카테고리다(256셀 3열 1행 = 768x256).
            # 로컬 파일의 계약은 헤더 카테고리 드롭다운에서 온다 — URL 인자가 아니라 그쪽을 맞춘다.
            pg.goto(f"http://127.0.0.1:{port}/tools/review/sprite_fixer.html?cat=portraits")
            pg.wait_for_timeout(1200)
            pg.eval_on_selector("#picker", "e=>e.hidden=true")
            pg.select_option("#pickcat", "portraits")
            pg.set_input_files("#localfile", str(sheet))
            # 자동 보정은 서버 왕복이라 시간이 걸린다 — 계약 크기가 될 때까지 기다린다.
            pg.wait_for_function(
                "typeof work!=='undefined' && work && work.width===contract.size[0]"
                " && work.height===contract.size[1]", timeout=20000)
            size = pg.evaluate("[work.width, work.height, contract.size]")
            ok("열자마자 캔버스가 계약 크기로 맞는다", size[0] == size[2][0] and size[1] == size[2][1],
               f"{size[0]}x{size[1]} · 계약 {size[2]}")

            corner = pg.evaluate("()=>{const d=wctx.getImageData(0,0,1,1).data;return [d[0],d[1],d[2],d[3]]}")
            ok("열자마자 흰 배경이 투명으로 빠진다", corner[3] == 0, f"좌상단 {corner}")

            inner = pg.evaluate("""()=>{const d=wctx.getImageData(0,0,work.width,work.height).data;
                let white=0; for(let i=0;i<d.length;i+=4)
                  if(d[i+3]>8 && d[i]>240 && d[i+1]>240 && d[i+2]>240) white++;
                return white;}""")
            ok("그림 안쪽의 흰 점은 살아남는다", inner > 0, f"불투명한 흰 픽셀 {inner}px")

            before = pg.evaluate("""()=>{const d=wctx.getImageData(0,0,work.width,work.height).data;
                const s=new Set(); for(let i=0;i<d.length;i+=4) if(d[i+3]>8) s.add((d[i]<<16)|(d[i+1]<<8)|d[i+2]);
                return s.size;}""")
            pg.select_option("#pixlevel", "8")
            pg.click("[data-op='pixelize']")
            pg.wait_for_function("!document.querySelector('#autofix').disabled", timeout=20000)
            pg.wait_for_timeout(300)
            blocky = pg.evaluate("""()=>{const w=work.width,h=work.height,
                d=wctx.getImageData(0,0,w,h).data; let bad=0;
                for(let by=0;by<h;by+=8) for(let bx=0;bx<w;bx+=8){
                  const i0=(by*w+bx)*4; const k0=[d[i0],d[i0+1],d[i0+2],d[i0+3]].join();
                  for(let y=by;y<by+8;y++) for(let x=bx;x<bx+8;x++){
                    const i=(y*w+x)*4;
                    if([d[i],d[i+1],d[i+2],d[i+3]].join()!==k0) bad++;
                  }}
                return bad;}""")
            ok("픽셀풍 버튼이 8px 블록으로 뭉갠다", blocky == 0,
               f"블록 안에서 어긋난 픽셀 {blocky}px")
            after = pg.evaluate("""()=>{const d=wctx.getImageData(0,0,work.width,work.height).data;
                const s=new Set(); for(let i=0;i<d.length;i+=4) if(d[i+3]>8) s.add((d[i]<<16)|(d[i+1]<<8)|d[i+2]);
                return s.size;}""")
            ok("픽셀풍이 고유색을 늘리지 않는다", after <= before, f"{before}색 → {after}색")

            # 계약 종류별 크기 자동 조절 — 격자 있는 계약(portraits·items)과
            # **격자 없이 size만 있는 계약(keyart)** 둘 다. 뒤쪽이 통째로 건너뛰어지던
            # 결함이 있었다: 2048x1152로 온 keyart가 그대로 남고 계측도 초록이었다.
            for cat, w, h, why in [("portraits", 1024, 1024, "정사각(비율 다름)"),
                                   ("portraits", 1536, 512, "배수로 큼"),
                                   ("items", 512, 512, "아이콘이 크게 옴"),
                                   ("keyart", 2048, 1152, "격자 없는 계약")]:
                shot = tmp / f"sz_{cat}_{w}x{h}_v1.png"
                Image.new("RGBA", (w, h), (255, 255, 255, 255)).save(shot)
                p2 = br.new_page(viewport={"width": 1400, "height": 900})
                p2.goto(f"http://127.0.0.1:{port}/tools/review/sprite_fixer.html?cat={cat}")
                p2.wait_for_timeout(900)
                p2.eval_on_selector("#picker", "e=>e.hidden=true")
                p2.select_option("#pickcat", cat)
                p2.set_input_files("#localfile", str(shot))
                want = None
                try:
                    p2.wait_for_function(
                        "typeof work!=='undefined' && work && contract && contract.size[0]>0"
                        " && work.width===contract.size[0] && work.height===contract.size[1]",
                        timeout=20000)
                except Exception:
                    pass
                got = p2.evaluate("[work && work.width, work && work.height]")
                want = p2.evaluate("contract && contract.size")
                badge = p2.eval_on_selector("#badge", "e=>e.textContent")
                ok(f"{cat} {w}x{h} ({why}) → 계약 {want[0]}x{want[1]}",
                   got[0] == want[0] and got[1] == want[1], f"실제 {got[0]}x{got[1]} · 배지 {badge}")
                p2.close()

            # 웹 챗에서 받아 파일명이 제각각인 그림을 **기존 에셋의 계약에 붙이기**.
            # 이 길이 없어서 "크기도 격자도 안 되는" 상태가 났다(2026-09-08 실측).
            odd = tmp / "ChatGPT Image 2026년 9월 8일 오후 09_20_08.png"
            Image.new("RGBA", (1456, 1088), (0, 0, 0, 0)).save(odd)
            p3 = br.new_page(viewport={"width": 1400, "height": 900})
            p3.goto(f"http://127.0.0.1:{port}/tools/review/sprite_fixer.html?cat=monsters")
            p3.wait_for_timeout(1200)
            p3.eval_on_selector("#picker", "e=>e.hidden=true")
            p3.select_option("#pickcat", "monsters")
            p3.set_input_files("#localfile", str(odd))
            p3.wait_for_timeout(2000)
            before = p3.evaluate("[work.width, work.height, contract.cell, contract.size[0]]")
            ok("파일명으로 계약을 못 찾으면 자유 규격이 된다(재현)",
               before[2] == 0 and before[3] == 0, f"{before}")
            names = p3.eval_on_selector_all("#pickasset option", "es=>es.map(e=>e.value)")
            ok("[계약] 드롭다운이 기존 에셋을 싣는다", "flying_thesis" in names,
               f"{len(names)}개 · flying_thesis 없음")
            if "flying_thesis" in names:
                p3.select_option("#pickasset", "flying_thesis")
                try:
                    p3.wait_for_function(
                        "work && contract && work.width===contract.size[0]"
                        " && work.height===contract.size[1] && contract.cell>0", timeout=20000)
                except Exception:
                    pass
                after = p3.evaluate("[work.width, work.height, contract.cell, contract.rows,"
                                    " contract.cols, contract.next_file]")
                ok("계약을 고르면 크기·격자가 그 자리에서 맞는다",
                   after[:5] == [512, 384, 128, 3, 4], f"{after}")
                ok("저장 이름이 디스크의 다음 버전이다",
                   isinstance(after[5], str) and after[5].startswith("flying_thesis_v")
                   and after[5] != "flying_thesis_v2.png", f"{after[5]}")
            p3.close()

            # 행별 재배치의 **채움 비율**과 **선택한 행만** 배선.
            # 규칙 자체(축척·클립·행 보존)는 test_sheet_ops.py가 픽셀로 잰다. 여기서 보는 것은
            # 입력칸과 버튼이 그 인자를 서버까지 실제로 실어 보내는가다 — 이 저장소가
            # 반복해 물린 결함이 정확히 "선언은 있는데 읽는 코드가 없다"이다.
            fit = Image.new("RGBA", (512, 384), (0, 0, 0, 0))
            for r, n in enumerate([4, 3, 3]):          # 행마다 프레임 수가 다른 진짜 배치
                for c in range(n):
                    x0, x1 = round(c * 512 / n), round((c + 1) * 512 / n)
                    cx, hw = (x0 + x1) // 2, (x1 - x0) // 4
                    hh = 45 - r * 8
                    for y in range((r + 1) * 128 - 12 - hh * 2, (r + 1) * 128 - 12):
                        for x in range(cx - hw, cx + hw):
                            fit.putpixel((x, y), (80 + 40 * r, 90, 200, 255))
            fitsheet = tmp / "probe_fit_v1.png"
            fit.save(fitsheet)

            p5 = br.new_page(viewport={"width": 1400, "height": 900})
            p5.on("pageerror", lambda e: errs.append(str(e)))
            p5.goto(f"http://127.0.0.1:{port}/tools/review/sprite_fixer.html?cat=monsters")
            p5.wait_for_timeout(1200)
            p5.eval_on_selector("#picker", "e=>e.hidden=true")
            p5.select_option("#pickcat", "monsters")
            p5.set_input_files("#localfile", str(fitsheet))
            p5.wait_for_timeout(1500)
            p5.select_option("#pickasset", "flying_thesis")
            try:
                p5.wait_for_function("contract && contract.cell===128 && work.width===512", timeout=20000)
            except Exception:
                pass
            p5.evaluate("$('#log').innerHTML=''")
            p5.eval_on_selector("#refitfill", "e=>{e.value='60'}")
            p5.click("[data-op='refit']")
            try:
                p5.wait_for_function(
                    "document.querySelector('#log').textContent.includes('재배치')", timeout=20000)
            except Exception:
                pass
            p5.wait_for_timeout(300)
            t5 = p5.eval_on_selector("#log", "e=>e.textContent")
            ok("[칸 채움] 입력이 서버까지 실려 간다", "채움 0.60" in (t5 or ""),
               (t5 or "")[-200:].replace(chr(10), " / "))

            row0 = p5.evaluate("""()=>{const w=work.width,d=wctx.getImageData(0,0,w,128).data;
                let n=0,h=0; for(let i=0;i<d.length;i+=4) if(d[i+3]>8){n++;h=(Math.imul(h,31)+i+d[i])|0;}
                return [n,h];}""")
            p5.evaluate("$('#log').innerHTML=''")
            sx = p5.eval_on_selector("#view", "e=>{const b=e.getBoundingClientRect();return [b.x,b.y]}")
            zf = p5.evaluate("zoomFactor()")
            p5.mouse.click(sx[0] + 64 * zf, sx[1] + 192 * zf)     # 행1의 셀을 고른다
            selr = p5.evaluate("sel && sel.r")
            ok("캔버스 클릭이 행1을 고른다", selr == 1, f"sel.r={selr}")
            p5.click("[data-op='rowfit']")
            try:
                p5.wait_for_function(
                    "document.querySelector('#log').textContent.includes('재배치')", timeout=20000)
            except Exception:
                pass
            p5.wait_for_timeout(300)
            t6 = p5.eval_on_selector("#log", "e=>e.textContent")
            ok("[선택한 행만]이 그 행 번호를 실어 보낸다",
               "행 1만 재배치" in (t6 or "") and "축척" in (t6 or ""),
               (t6 or "")[-200:].replace(chr(10), " / "))
            row0b = p5.evaluate("""()=>{const w=work.width,d=wctx.getImageData(0,0,w,128).data;
                let n=0,h=0; for(let i=0;i<d.length;i+=4) if(d[i+3]>8){n++;h=(Math.imul(h,31)+i+d[i])|0;}
                return [n,h];}""")
            ok("한 행만 재배치하면 행0은 픽셀까지 그대로다", row0b == row0, f"{row0} → {row0b}")
            p5.close()

            # 타일셋 계약과 **묶음 편집**. 계약이 없어 통째로 사문화였던 층이라,
            # 여기서 보는 것은 "서버가 계약을 주는가"와 "묶음이 상자 하나로 움직이는가"다.
            tile = Image.new("RGBA", (256, 288), (0, 0, 0, 0))
            for y in range(0, 64):                       # 단일 타일 두 칸(0행)
                for x in range(0, 64):
                    tile.putpixel((x, y), (70, 110, 190, 255))
            for y in range(196, 252):                    # desk_pc 상자(r6c3 2×2)를 가로지르는 소품
                for x in range(100, 156):
                    tile.putpixel((x, y), (200, 160, 80, 255))
            tilesheet = tmp / "tileset_campus_v1.png"
            tile.save(tilesheet)

            p6 = br.new_page(viewport={"width": 1400, "height": 900})
            p6.on("pageerror", lambda e: errs.append(str(e)))
            p6.goto(f"http://127.0.0.1:{port}/tools/review/sprite_fixer.html?cat=sprites")
            p6.wait_for_timeout(1200)
            p6.eval_on_selector("#picker", "e=>e.hidden=true")
            p6.select_option("#pickcat", "sprites")
            p6.set_input_files("#localfile", str(tilesheet))
            try:
                p6.wait_for_function(
                    "contract && contract.cell===32 && contract.groups"
                    " && contract.groups.length===6", timeout=20000)
            except Exception:
                pass
            con = p6.evaluate("contract && [contract.cell, contract.rows, contract.cols,"
                              " contract.size, contract.align, (contract.groups||[]).length]")
            ok("타일셋 계약을 서버가 준다(파일명으로 자동)",
               con == [32, 9, 8, [256, 288], "none", 6], f"{con}")
            gsec = p6.eval_on_selector("#groupbox", "e=>e.hidden")
            ok("묶음이 있는 계약에서 [선택한 묶음] 칸이 열린다", gsec is False, f"hidden={gsec}")

            p6.select_option("#zoom", "1")
            rect = p6.eval_on_selector("#view", "e=>{const b=e.getBoundingClientRect();return [b.x,b.y]}")
            p6.mouse.click(rect[0] + 110, rect[1] + 210)      # r6c3 = desk_pc 안
            ginfo = p6.eval_on_selector("#groupinfo", "e=>e.textContent")
            ok("소품 칸을 고르면 어느 묶음인지 알려 준다", "desk_pc" in (ginfo or ""), f"{ginfo!r}")

            def box(pg, x0, y0, x1, y1):
                return pg.evaluate(
                    """r=>{const w=work.width,d=wctx.getImageData(0,0,w,work.height).data;
                           let a=1e9,b=1e9,c=-1,e=-1;
                           for(let y=r[1];y<r[3];y++) for(let x=r[0];x<r[2];x++){
                             if(d[(y*w+x)*4+3]<=8) continue;
                             if(x<a)a=x; if(x>c)c=x; if(y<b)b=y; if(y>e)e=y; }
                           return c<0?null:[a,b,c,e];}""", [x0, y0, x1, y1])

            b0 = box(p6, 90, 180, 170, 270)
            p6.click("[data-op='grpdown']", modifiers=["Shift"])
            p6.eval_on_selector("[data-op='grpdown']", "e=>e.blur()")
            held = p6.evaluate("floating && [floating.kind, floating.r, floating.c, floating.dy]")
            ok("묶음 이동은 앵커 기준으로 상자를 든다", held == ["group", 6, 3, 8], f"{held}")
            p6.keyboard.press("Enter")
            p6.wait_for_timeout(200)
            b1 = box(p6, 90, 180, 170, 270)
            ok("묶음이 상자 하나로 통째로 내려간다",
               b0 is not None and b1 is not None
               and b1[0] == b0[0] and b1[2] == b0[2]
               and b1[1] == b0[1] + 8 and b1[3] == b0[3] + 8,
               f"{b0} → {b1} (가로 그대로 · 세로 +8이어야)")

            # 계측이 칸 경계 가로지름을 결함으로 세지 않아야 한다.
            p6.evaluate("$('#log').innerHTML=''")
            p6.click("[data-op='measure']")
            try:
                p6.wait_for_function("serverStats && serverStats.cell_issues", timeout=20000)
            except Exception:
                pass
            issues = p6.evaluate("(serverStats && serverStats.cell_issues) || []")
            ok("계측이 소품의 칸 경계 가로지름을 결함으로 안 센다",
               not any("중앙 이탈" in i for i in issues),
               "; ".join(issues[:4]) or "이상 없음")

            # 정렬이 없는 계약에서 [정렬 스냅]을 눌러도 타일을 밀지 않는다.
            sig0 = p6.evaluate("""()=>{const d=wctx.getImageData(0,0,work.width,work.height).data;
                let n=0,h=0; for(let i=0;i<d.length;i+=4) if(d[i+3]>8){n++;h=(Math.imul(h,31)+i)|0;}
                return [n,h];}""")
            p6.evaluate("$('#log').innerHTML=''")
            p6.click("[data-op='snapall']")
            try:
                p6.wait_for_function(
                    "document.querySelector('#log').textContent.includes('align=none')", timeout=20000)
            except Exception:
                pass
            sig1 = p6.evaluate("""()=>{const d=wctx.getImageData(0,0,work.width,work.height).data;
                let n=0,h=0; for(let i=0;i<d.length;i+=4) if(d[i+3]>8){n++;h=(Math.imul(h,31)+i)|0;}
                return [n,h];}""")
            t7 = p6.eval_on_selector("#log", "e=>e.textContent")
            ok("align=none 계약에서 [전 셀 정렬]이 타일을 안 민다",
               sig1 == sig0 and "align=none" in (t7 or ""),
               f"{sig0} → {sig1} · {(t7 or '')[-90:]}")
            p6.close()


            # 저장 — 로컬에서 연 그림을 [계약]으로 기존 에셋에 붙인 뒤 다음 버전으로 저장.
            # 예전에는 LOCAL이면 무조건 막고 기록에만 한 줄 남겨 "아무 반응 없음"이었다.
            saved_dir = root / "assets" / "raw" / "llm" / "10_submitted" / "monsters"
            before_files = {f.name for f in saved_dir.glob("*.png")} if saved_dir.is_dir() else set()
            p4 = br.new_page(viewport={"width": 1400, "height": 900})
            p4.goto(f"http://127.0.0.1:{port}/tools/review/sprite_fixer.html?cat=monsters")
            p4.wait_for_timeout(1200)
            p4.eval_on_selector("#picker", "e=>e.hidden=true")
            p4.select_option("#pickcat", "monsters")
            p4.set_input_files("#localfile", str(odd))
            p4.wait_for_timeout(1500)
            p4.click("#save")                       # 계약을 안 고른 상태 — 막히되 눈에 보여야 한다
            p4.wait_for_timeout(400)
            vis = p4.eval_on_selector("#toast", "e=>e.hidden===false && e.textContent")
            ok("계약이 없으면 저장이 막히고 그 이유가 화면에 뜬다",
               bool(vis) and "계약" in str(vis), f"toast={vis!r}")
            p4.select_option("#pickasset", "flying_thesis")
            p4.wait_for_timeout(2500)
            want_name = p4.evaluate("contract.next_file")
            p4.click("#save")
            try:
                p4.wait_for_function(
                    "document.querySelector('#log').textContent.includes('저장:')", timeout=20000)
            except Exception:
                pass
            p4.wait_for_timeout(400)
            after_files = {f.name for f in saved_dir.glob("*.png")} if saved_dir.is_dir() else set()
            made = after_files - before_files
            ok("다음 버전으로 저장이 실제로 파일을 만든다", made == {want_name},
               f"기대 {want_name} · 실제 새 파일 {sorted(made)}")
            tt = p4.eval_on_selector("#toast", "e=>e.hidden===false && e.textContent")
            ok("저장 결과가 화면에 뜬다(저장 사실 + 검증을 한 알림에)",
               bool(tt) and "저장 완료" in str(tt) and ("검증" in str(tt)),
               f"toast={tt!r}")
            icon = p4.eval_on_selector("#save svg", "e=>!!e")
            ok("저장 뒤에도 버튼 아이콘이 남는다", icon is True, f"svg={icon}")
            for f in made:                          # 시험이 만든 파일은 치운다
                (saved_dir / f).unlink(missing_ok=True)
            p4.close()

            logtxt = pg.eval_on_selector("#log", "e=>e.textContent")
            ok("배경 판정 근거가 기록에 남는다", "배경" in logtxt and "허용오차" in logtxt,
               (logtxt or "")[-160:].replace(chr(10), " / "))
            ok("페이지 예외 없음", not errs, " / ".join(errs[:3]))
            br.close()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()

    print("[셀 편집기 서버 왕복 시험] review_server + chromium")
    for ln in lines:
        print(ln)
    if fails:
        print(f"{chr(10)}실패 {len(fails)}건")
        return 1
    print(f"{chr(10)}통과 — 크기·배경 자동 보정과 픽셀풍이 서버 왕복으로 실제 동작한다.")
    return 0


if __name__ == "__main__":
    rc = run("--shots" in sys.argv)
    if "--server" in sys.argv:
        print()
        rc |= run_server_mode()
    sys.exit(rc)
