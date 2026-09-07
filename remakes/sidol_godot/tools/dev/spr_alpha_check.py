"""원작 SPR 파생 에셋 알파 관문 — "게임에 든 파일 == 지금 원작 SPR로 구운 것"인가.

## 왜 이 관문이 있는가 (2026-09-07, 유저 신고 "멍청조교·상자 스프라이트가 깨진다")

원작 팔레트에는 **RGB(0,0,0)인 인덱스가 9개**다 — 투명 키인 인덱스 0과, 캐릭터
외곽선·그림자로 쓰이는 224~231. `spr_extract.parse_spr`는 인덱스 0만 alpha 0으로
방출하므로 옳다. 문제는 **그 뒤에 RGB만 보고 투명을 다시 정한 도구들**이었다:

- `tools/dev/key_color0_transparent.py` — RGBA PNG 위에서 순검정을 전부 투명화.
  `obj_original_32.png`가 불투명 순검정 12,153px를 잃어 176셀 중 39셀에 구멍.
- `tools/convert/migrate_original_sheets.py` (구판) — 알파 없는 `bmp_spr/*.bmp`를
  테두리 flood-fill로 지워 캐릭터 시트 14종이 외곽선 150,326px를 잃고
  둘러싸인 배경 4,404px가 검게 남았다.
- `tools/convert/migrate_item_icons.py` (구판) — 같은 flood-fill. 아이콘 35종에서
  외곽선 36,939px 손실 · 잔여 배경 9,465px.

세 건 다 **팔레트 인덱스를 잃은 뒤 RGB만 보고 투명을 정했다**는 하나의 결함이다.
그래서 이 관문은 "구멍 개수 기준선" 같은 간접 지표가 아니라 **원본에서 다시 구워
바이트로 비교**한다. 굽는 레시피는 각 빌더 안에 그대로 두고(단일 소스) 여기서는
호출만 한다 — 레시피를 여기에 베끼면 관문 자신이 갈라진다.

원본(`../../originals/1995_sidol_bsd_dos`)은 저장소에 없다(gitignored).
없으면 SKIP — CI를 빨간불로 만들지 않는다(originals_check.py와 같은 규약).

사용:
  python tools/dev/spr_alpha_check.py            # 관문(불일치 있으면 exit 1)
  python tools/dev/spr_alpha_check.py --report   # 시트별 내부 구멍·순검정 실측표
"""

import io
import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ORIGINALS = os.path.normpath(os.path.join(ROOT, "..", "..", "originals", "1995_sidol_bsd_dos"))
SPRITES = os.path.join(ROOT, "assets", "sprites")
ICONS = os.path.join(ROOT, "assets", "icons")

sys.path.insert(0, os.path.join(ROOT, "tools", "dev"))
sys.path.insert(0, os.path.join(ROOT, "tools", "convert"))
sys.path.insert(0, os.path.normpath(os.path.join(ROOT, "..", "..", "_shared", "src")))


def _rgba(path):
    from PIL import Image
    return Image.open(path).convert("RGBA")


def _mask_diff(cur, tru):
    """(잃은 불투명px, 남은 배경px, 색 불일치px). cur·tru는 PIL RGBA."""
    import numpy as np
    a = np.asarray(cur)
    b = np.asarray(tru)
    if a.shape != b.shape:
        return None
    lost = int(((a[:, :, 3] == 0) & (b[:, :, 3] > 0)).sum())
    extra = int(((a[:, :, 3] > 0) & (b[:, :, 3] == 0)).sum())
    both = (a[:, :, 3] > 0) & (b[:, :, 3] > 0)
    color = int((both & (a[:, :, :3] != b[:, :, :3]).any(axis=2)).sum())
    return lost, extra, color


# 빌더가 함께 내는 메타 JSON — _truths()가 채운다. 픽셀만 보면 놓치는 것이 있어서 같이 본다:
# 2026-09-07 재생성에서 obj 메타의 known_empty(원작에도 그림이 없는 슬롯 173, MapRenderer가
# 읽어 조용히 건너뛴다)가 통째로 날아갈 뻔했다. 빌더가 손으로 넣은 값을 덮는 사고는
# 파이프라인 재생성의 단골이다.
_META_EXPECT: dict = {}


def _truths():
    """(표시이름, 게임 파일 경로, 진실값 PIL RGBA) 목록 — 빌더를 그대로 호출한다."""
    from PIL import Image
    out = []

    import migrate_original_sheets as mos
    for sid in mos.SOURCES:
        out.append((f"{sid}_original.png",
                    os.path.join(SPRITES, f"{sid}_original.png"),
                    mos.build_sheet_image(sid)))

    import migrate_item_icons as mic
    for item_id, frame_idx in mic.icon_targets().items():
        out.append((f"icons/{item_id}.png",
                    os.path.join(ICONS, f"{item_id}.png"),
                    mic.build_icon_image(frame_idx)))

    import remaster_obj_atlas as roa
    w, h, buf, meta = roa.build_atlas()
    out.append(("obj_original_32.png",
                os.path.join(SPRITES, "obj_original_32.png"),
                Image.frombytes("RGBA", (w, h), buf)))
    _META_EXPECT["obj_original_32.json"] = (os.path.join(SPRITES, "obj_original_32.json"), meta)

    import make_player_original_sheet as mps
    out.append(("player_original.png",
                os.path.join(SPRITES, "player_original.png"),
                Image.frombytes("RGBA", (mps.W, mps.H), mps.build_sheet_bytes())))

    return out


def _cell_size(png_path):
    import json
    j = os.path.splitext(png_path)[0] + ".json"
    if not os.path.exists(j):
        return None
    try:
        m = json.load(io.open(j, encoding="utf-8"))
    except (ValueError, OSError):
        return None
    cw = m.get("cell_w") or m.get("cell")
    ch = m.get("cell_h") or m.get("cell")
    return (cw, ch) if isinstance(cw, int) and isinstance(ch, int) and cw > 0 else None


def _holes(alpha):
    """각 행에서 첫/마지막 불투명 픽셀 사이의 alpha 0 픽셀 수(= 내부 구멍)."""
    import numpy as np
    total = 0
    for row in alpha > 0:
        idx = np.flatnonzero(row)
        if idx.size >= 2:
            total += int((~row[idx[0]:idx[-1] + 1]).sum())
    return total


def _holes_by_cell(img, png_path):
    """셀 격자를 알면 셀 단위로 센다 — 아틀라스는 셀 사이 여백이 구멍으로 잡히므로."""
    import numpy as np
    a = np.asarray(img)
    cs = _cell_size(png_path)
    if not cs:
        return _holes(a[:, :, 3]), 0
    cw, ch = cs
    tot, cells = 0, 0
    for gy in range(0, a.shape[0] - ch + 1, ch):
        for gx in range(0, a.shape[1] - cw + 1, cw):
            n = _holes(a[gy:gy + ch, gx:gx + cw, 3])
            if n:
                tot += n
                cells += 1
    return tot, cells


def report():
    import numpy as np
    print("%-34s %8s %8s %8s %8s %8s" % (
        "파일", "구멍", "구멍셀", "잃음", "잔여배경", "순검정"))
    for name, path, tru in _truths():
        if not os.path.exists(path):
            print("%-34s  파일 없음" % name)
            continue
        cur = _rgba(path)
        d = _mask_diff(cur, tru)
        a = np.asarray(cur)
        holes, cells = _holes_by_cell(cur, path)
        blk = int(((a[:, :, 3] > 0) & (a[:, :, :3].sum(axis=2) == 0)).sum())
        lost, extra = ("크기", "불일치") if d is None else (d[0], d[1])
        print("%-34s %8d %8d %8s %8s %8d" % (name, holes, cells, lost, extra, blk))


def main():
    if not os.path.isdir(ORIGINALS):
        print("[spr_alpha_check] SKIP — 원본 없음(%s)" % ORIGINALS)
        return 0
    try:
        import numpy  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError as e:
        print("[spr_alpha_check] SKIP — 의존성 없음(%s)" % e)
        return 0

    if "--report" in sys.argv:
        report()
        return 0

    import json

    fails = []
    checked = 0
    truths = _truths()
    for name, (path, expect) in sorted(_META_EXPECT.items()):
        if not os.path.exists(path):
            fails.append("%s — 메타 파일 없음" % name)
            continue
        got = json.load(io.open(path, encoding="utf-8"))
        missing = [k for k in expect if k not in got or got[k] != expect[k]]
        if missing:
            fails.append("%s — 빌더 산출과 다른 키: %s" % (name, ", ".join(missing)))
        else:
            checked += 1
    for name, path, tru in truths:
        if not os.path.exists(path):
            fails.append("%s — 파일 없음(빌더를 돌려 굽지 않았다)" % name)
            continue
        d = _mask_diff(_rgba(path), tru)
        if d is None:
            fails.append("%s — 크기가 원작 빌더 산출과 다르다" % name)
            continue
        lost, extra, color = d
        if lost or extra or color:
            fails.append(
                "%s — 원작 대비 잃은 불투명 %dpx · 남은 배경 %dpx · 색 불일치 %dpx"
                % (name, lost, extra, color))
        checked += 1

    for f in fails:
        print("[spr_alpha_check] FAIL — %s" % f)
    if fails:
        print("[spr_alpha_check] 복구: python tools/convert/migrate_original_sheets.py"
              " · python tools/convert/migrate_item_icons.py"
              " · python tools/dev/remaster_obj_atlas.py"
              " · python tools/dev/make_player_original_sheet.py")
        print("[spr_alpha_check] 구운 뒤 RGB 기준 사후 키잉을 절대 걸지 말 것"
              " — 원작 팔레트의 검정 인덱스는 0 하나가 아니라 9개다(0 · 224~231).")
        return 1
    print("[spr_alpha_check] ok — SPR 파생 에셋 %d개(픽셀 + 메타)가 원작 빌더 산출과 일치" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
