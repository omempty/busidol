#!/usr/bin/env python3
"""OBJ.SPR(173프레임) → 32px 셀 오브젝트 아틀라스 + 메타 생성 (게임 에셋).

각 오브젝트를 종횡비 유지 스케일로 32x32 셀 중앙 배치.
산출: assets/sprites/obj_original_32.png + .json

**알파의 유일한 근거는 팔레트 인덱스 0이다**(parse_spr가 그것만 alpha 0으로 방출).
구운 뒤에 RGB로 다시 키잉하지 말 것 — 원작 팔레트에는 RGB(0,0,0)인 인덱스가 9개라
(투명 키 0 + 외곽선·그림자 224~231) RGB만으로는 구별할 수 없다.
2026-09-07 실측: 사후 키잉된 구판 아틀라스는 **불투명 순검정 12,153px를 잃어**
176셀 중 39셀(상자·소품)에 내부 구멍이 뚫려 있었다(재생성 후 구멍 셀 15개 = 원작 그대로).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHARED_SRC = ROOT.parent.parent / "_shared" / "src"
sys.path.insert(0, str(SHARED_SRC))

from spr_extract import parse_spr  # noqa: E402
from dosport.formats.png_write import fill_rect, write_png  # noqa: E402

ORIGINALS = ROOT.parent.parent / "originals" / "1995_sidol_bsd_dos"
CELL = 32

# 맵이 참조하지만 원작에도 그림이 없는 오브젝트 슬롯 — MapRenderer가 이 목록을 읽어
# 조용히 건너뛴다(src/map/map_renderer.gd:161). **메타를 다시 쓸 때 반드시 함께 낸다** —
# 2026-09-07 재생성에서 이 두 키를 떨어뜨려 층마다 경고가 되살아날 뻔했다.
# 상자 리터치 대상 — OBJ.SPR 프레임 번호 == 오브젝트 id.
# 닫힘 151·152(뚜껑 상반) / 155·156(몸통 하반) · 열림 153·154(원작 OBJ[x]=153·154 그대로).
CHEST_LID = (151, 152)
CHEST_BODY = (155, 156)
CHEST_OPEN = (153, 154)


def _retouch_chest(buf: bytearray, w: int, _h: int, cols: int) -> None:
    """상자 6셀 음영 폴리시 — 형태는 그대로, 명암만 손본다(2026-09-10).

    원작 상자는 노랑 한 톤이라 밋밋하다. 픽셀을 옮기거나 더하지 않고(어설픈
    재그림 금지) 불투명 픽셀의 값만 바꾼다: 뚜껑 윗부분 하이라이트 ·
    몸통 수직 그라데이션 · 열린 상자 내부 심화 + 앞 가장자리 엣지라이트.
    이 함수가 빌더 안에 있으므로 spr_alpha_check의 진실값도 같이 바뀌어
    관문이 깨지지 않는다(바깥에서 PNG를 직접 만지면 색 불일치로 FAIL).
    """
    import numpy as np

    a = np.frombuffer(buf, dtype=np.uint8).reshape(-1, w, 4).copy()
    rgb = a[:, :, :3].astype(np.float32)
    alpha = a[:, :, 3]

    def opaque(obj_id: int):
        gx, gy = (obj_id % cols) * CELL, (obj_id // cols) * CELL
        m = alpha[gy:gy + CELL, gx:gx + CELL] > 0
        yy, xx = np.nonzero(m)
        return gx, gy, yy, xx

    # 뚜껑 — 윗 8줄을 따뜻한 금빛으로 스크린 45% (원색 55% 유지).
    for obj_id in CHEST_LID:
        gx, gy, yy, xx = opaque(obj_id)
        if yy.size == 0:
            continue
        top = yy < 8
        c = rgb[gy + yy[top], gx + xx[top]]
        gold = np.array([255.0, 224.0, 130.0], dtype=np.float32)
        screen = 255.0 - (255.0 - c) * (255.0 - gold) / 255.0
        rgb[gy + yy[top], gx + xx[top]] = c * 0.55 + screen * 0.45

    # 몸통 — 위 1.03 → 아래 0.80 수직 그라데이션으로 부피감.
    for obj_id in CHEST_BODY:
        gx, gy, yy, xx = opaque(obj_id)
        if yy.size == 0:
            continue
        ramp = 1.03 - 0.23 * (yy.astype(np.float32) / max(CELL - 1, 1))
        rgb[gy + yy, gx + xx] *= ramp[:, None]

    # 열린 상자 — 내부는 어둡게(어두운 회색만), 앞 가장자리 윗줄은 엣지라이트.
    for obj_id in CHEST_OPEN:
        gx, gy, yy, xx = opaque(obj_id)
        if yy.size == 0:
            continue
        c = rgb[gy + yy, gx + xx]
        lum = c.mean(axis=1)
        dark = lum < 95.0
        rgb[gy + yy[dark], gx + xx[dark]] *= 0.72
        top_y = yy.min()
        rim = yy == top_y
        rgb[gy + yy[rim], gx + xx[rim]] = np.minimum(
            rgb[gy + yy[rim], gx + xx[rim]] * 1.3 + 12.0, 255.0)

    a[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    buf[:] = a.tobytes()
# 2026-09-07 재생성에서 이 두 키를 떨어뜨려 층마다 경고가 되살아날 뻔했다.
KNOWN_EMPTY = [173]
KNOWN_EMPTY_COMMENT = (
    "원작에서도 비어 있는 오브젝트 슬롯. OBJ.SPR은 173프레임(0~172)인데 GOODITEM.H의"
    " MAX_OBJ는 174라, 맵이 91칸에서 참조하는 obj 173은 원작에서도 그릴 그림이 없다"
    "(2026-08-28 원본 대조로 확정, docs/03_plan/05_polish_roadmap.md §7). 렌더러는 이"
    " 목록에 있는 id를 조용히 건너뛴다 — 층을 갈 때마다 경고가 뜨면 진짜 경고가 그 속에 묻힌다."
)


def build_atlas() -> tuple[int, int, bytes, dict]:
    """아틀라스를 메모리로만 굽는다 — 관문(tools/dev/spr_alpha_check.py)이 이걸 쓴다.

    굽기와 저장을 나눠 두어야 "게임에 들어 있는 파일 == 지금 원작 SPR로 구운 것"을
    관문이 바이트로 비교할 수 있다(레시피를 관문에 베끼면 소스가 둘로 갈라진다).
    """
    _, frames = parse_spr((ORIGINALS / "OBJ.SPR").read_bytes())
    n = len(frames)
    cols = 16
    rows = (n + cols - 1) // cols
    W, H = cols * CELL, rows * CELL
    buf = bytearray(W * H * 4)
    meta: dict[str, dict] = {}
    for i, (w, h, rgba) in enumerate(frames):
        scale = min(CELL / w, CELL / h)
        sw, sh = max(1, int(w * scale)), max(1, int(h * scale))
        ox = (CELL - sw) // 2
        oy = (CELL - sh) // 2
        gx, gy = (i % cols) * CELL, (i // cols) * CELL
        # 중앙 배치 + nearest 재샘플
        for y in range(sh):
            sy = min(h - 1, int(y / scale))
            for x in range(sw):
                sx = min(w - 1, int(x / scale))
                si = (sy * w + sx) * 4
                if rgba[si + 3] == 0:
                    continue
                di = ((gy + oy + y) * W + gx + ox + x) * 4
                buf[di:di + 4] = rgba[si:si + 4]
        meta[str(i)] = {"col": i % cols, "row": i // cols}

    _retouch_chest(buf, W, H, cols)

    return W, H, bytes(buf), {
        "schema_version": 1,
        "cell": CELL,
        "cols": cols,
        "objects": meta,
        "known_empty": KNOWN_EMPTY,
        "_known_empty_comment": KNOWN_EMPTY_COMMENT,
    }


def main() -> int:
    W, H, buf, meta_payload = build_atlas()
    out_png = ROOT / "assets" / "sprites" / "obj_original_32.png"
    write_png(out_png, W, H, buf)
    (ROOT / "assets" / "sprites" / "obj_original_32.json").write_text(
        json.dumps(meta_payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"obj atlas: {len(meta_payload['objects'])} objects -> {out_png.name} ({W}x{H})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
