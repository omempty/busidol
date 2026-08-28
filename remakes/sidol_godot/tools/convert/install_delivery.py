#!/usr/bin/env python3
"""채택본 설치 — 20_processed → assets/ (게임이 실제로 읽는 자리).

## 왜 필요했나 (2026-08-28)

심사 보드가 승인하면 납품물은 `20_processed/`로 옮겨질 뿐이고, 거기서 게임 에셋
디렉터리로 **넘어가는 단계가 파이프라인에 없었다**. 실측:

  assets/sprites/c_bug_original.png  b15f476f0ff1a96a48dcdd4998542300
  assets/sprites/c_bug_remake.png    b15f476f0ff1a96a48dcdd4998542300   <- 바이트 동일

`_remake`는 `_original`의 복사본 그대로였고 `assets/portraits/`는 디렉터리조차 없었다.
그래서 몬스터 4종을 채택하고도 `asset_status.py`의 공백은 73종에서 1도 줄지 않았다.
이 저장소의 지배적 결함(데이터는 있는데 코드가 안 읽는다)이 에셋에서 재현된 자리다.

## 무엇을 하나

  20_processed/<id>/processed_sheet.png -> assets/sprites/<id>_remake.png + <id>_remake.json
      (몬스터·NPC 시트. 메타 JSON은 *_anim_specs.json의 계약에서 생성 —
       손으로 쓰면 스펙과 갈라진다)
  20_processed/portraits/<id>_v<n>.png  -> assets/portraits/<id>.png
  20_processed/keyart/<id>_v<n>.png     -> assets/keyart/<id>.png
  20_processed/items/<ID>_v<n>.png      -> assets/icons/<ID>.png
  20_processed/effects/<id>_v<n>.png    -> assets/effects/<id>.png + <id>.json

## 색 양자화 — 크기를 후처리로 강제하듯 색도 강제한다

실납품의 고유색은 16,772~50,666개였다(계약 24~48, 원작 도트 18~34). 생성 모델이
리샘플·부드러운 음영을 넣어 오기 때문이고, 문장 지시로는 계속 안 고쳐졌다.
`normalize_icon.py`가 크기를 규격으로 되돌리는 것과 같은 자리에서 색을 되돌린다:
불투명 픽셀만 median-cut으로 N색(기본 48)에 몰고 알파는 0/255로 이진화한다.
`--no-quantize`로 끌 수 있다(이미 도트로 그려 온 납품).

실행:
  python tools/convert/install_delivery.py                 # 채택본 전부
  python tools/convert/install_delivery.py c_bug npc_girl  # 지정 id만
  python tools/convert/install_delivery.py --dry-run --colors 32
종료코드: 0=설치(또는 설치할 것 없음) / 1=오류
"""
from __future__ import annotations

import io
import json
import os
import re
import sys

import numpy as np
from PIL import Image

import delivery_checks as dc

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROCESSED = os.path.join(ROOT, "assets", "raw", "llm", "20_processed")
SPRITES = os.path.join(ROOT, "assets", "sprites")
CELL = 128
## 시트 메타 규약 — 실효 96px×2/3 = 64px = 타일 2배(player_original 규약, migrate_original_sheets.py).
SHEET_SCALE = 0.6667
DEFAULT_COLORS = 48
VERSION_RE = re.compile(r"^(?P<id>.+)_v(?P<n>\d+)\.png$", re.IGNORECASE)

## 평면 카테고리(시트 컷팅 없이 한 장 그대로 설치) -> 설치 폴더
FLAT_TARGETS = {
    "portraits": os.path.join(ROOT, "assets", "portraits"),
    "keyart": os.path.join(ROOT, "assets", "keyart"),
    "items": os.path.join(ROOT, "assets", "icons"),
    "effects": os.path.join(ROOT, "assets", "effects"),
    "battle_cuts": os.path.join(ROOT, "assets", "battle_cuts"),
}
SPEC_FILES = (
    os.path.join(ROOT, "data", "monster_anim_specs.json"),
    os.path.join(ROOT, "data", "npc_anim_specs.json"),
    os.path.join(ROOT, "data", "effect_specs.json"),
    os.path.join(ROOT, "data", "battle_cut_specs.json"),
    os.path.join(ROOT, "data", "battle_actor_specs.json"),
)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def load_spec(asset_id: str) -> tuple:
    """(스펙, 출처 파일명). 출처로 설치 위치가 갈린다 — 이펙트는 sprites가 아니다."""
    for path in SPEC_FILES:
        if not os.path.exists(path):
            continue
        for sp in json.load(io.open(path, encoding="utf-8")).get("species", []):
            if sp.get("id") == asset_id:
                return sp, os.path.basename(path)
    return {}, ""


def unique_colors(im: Image.Image) -> int:
    a = np.asarray(im.convert("RGBA"))
    mask = a[:, :, 3] > 8
    if mask.sum() == 0:
        return 0
    return len({tuple(c) for c in a[:, :, :3][mask]})


def quantize(im: Image.Image, colors: int) -> Image.Image:
    """불투명 픽셀만 N색으로 몰고 알파는 0/255로 이진화한다.

    알파를 함께 median-cut에 넣으면 반투명 경계색이 팔레트 한 칸을 먹고
    투명 배경이 색으로 굳는다 — RGB만 양자화하고 알파는 따로 씌운다.

    **안내선 색(마젠타·청록) 픽셀은 팔레트 계산에서 뺀다.** 남은 잔선이 어두운 외곽선과
    한 상자에 묶이면 평균이 자주색이 되어 스프라이트에 분홍 테두리가 생긴다(실측).
    뺀 픽셀은 양자화 뒤 최근접 색으로 흡수돼 구멍이 나지 않는다.
    """
    src = im.convert("RGBA")
    a = np.asarray(src).astype(np.uint8).copy()
    alpha = (a[:, :, 3] > 127).astype(np.uint8) * 255
    rgb = a[:, :, :3].astype(int)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    tainted = (
        ((np.abs(r - b) < 40) & (g + 40 < np.minimum(r, b)) & (np.maximum(r, b) > 40))
        | ((np.abs(g - b) < 40) & (r + 40 < np.minimum(g, b)) & (np.maximum(g, b) > 40))
    ) & (alpha > 0)
    clean = a[:, :, :3].copy()
    if tainted.any() and (~tainted & (alpha > 0)).any():
        # 팔레트 산출용 이미지에서 오염 픽셀을 흔한 그림색으로 임시 치환한다.
        fill = clean[(~tainted) & (alpha > 0)].mean(axis=0).astype(np.uint8)
        clean[tainted] = fill
    q = Image.fromarray(clean, "RGB").quantize(
        colors=colors, method=Image.MEDIANCUT, dither=Image.NONE
    ).convert("RGB")
    out = np.dstack([np.asarray(q), alpha]).astype(np.uint8)
    out[alpha == 0] = 0  # 투명 픽셀의 RGB를 0으로 — 키잉 잔색 방지
    return Image.fromarray(out, "RGBA")


def clean_guides(im: Image.Image, cell: int) -> tuple:
    """안내선 잔선을 지우고 **그 주변 2px의 오염 픽셀만** 이웃 그림색으로 메운다.

    범위를 안 좁히면 그림을 먹는다 — 전 마젠타/청록 픽셀을 오염으로 보면 청록 유령
    `null_pointer`는 불투명 83,786px 중 45,959px이 대상이 됐다(실측). 오염은 안내선이
    지나간 자리에만 생기므로 마스크를 팽창시킨 띠 안으로 한정한다.
    반환: (이미지, 지운 잔선 px, 메운 오염 px).
    """
    a = np.asarray(im.convert("RGBA")).astype(np.uint8).copy()
    line = dc.guide_line_mask(im, cell, cell)
    removed = int(line.sum())
    if not removed:
        return im, 0, 0
    a[line] = 0
    h, w = line.shape
    band = np.zeros_like(line)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            band |= np.roll(np.roll(line, dy, axis=0), dx, axis=1)
    vis = a[:, :, 3] > 8
    rgb = a[:, :, :3].astype(int)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    hue = (
        ((np.abs(r - b) < 40) & (g + 40 < np.minimum(r, b)) & (np.maximum(r, b) > 40))
        | ((np.abs(g - b) < 40) & (r + 40 < np.minimum(g, b)) & (np.maximum(g, b) > 40))
    )
    bad = hue & vis & band
    filled_total = int(bad.sum())
    for _ in range(2):
        ys, xs = np.nonzero(bad)
        if ys.size == 0:
            break
        moved = 0
        for y, x in zip(ys, xs):
            cand = []
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if (dy or dx) and 0 <= ny < h and 0 <= nx < w and vis[ny, nx] and not bad[ny, nx]:
                        cand.append(tuple(a[ny, nx, :3]))
            if not cand:
                continue
            a[y, x, :3] = max(set(cand), key=cand.count)
            bad[y, x] = False
            moved += 1
        if not moved:
            break
    return Image.fromarray(a, "RGBA"), removed, filled_total


def sheet_meta(sp: dict, cols: int, source: str, cell: int = CELL) -> dict:
    anims = {}
    for name, a in sorted(sp.get("animations", {}).items(), key=lambda kv: int(kv[1].get("row", 0))):
        anims[name] = {
            "row": int(a.get("row", 0)),
            "frames": int(a.get("frames", 1)),
            "fps": int(a.get("fps", 6)),
            "loop": bool(a.get("loop", True)),
        }
    return {
        "schema_version": 2,
        "source": source,
        "cell": cell,
        "cell_w": cell,
        "cell_h": cell,
        "cols": cols,
        "scale": SHEET_SCALE,
        "animations": anims,
    }


def install_sheet(asset_id: str, colors: int, dry: bool) -> tuple:
    """20_processed/<id>/processed_sheet.png -> assets/sprites/<id>_remake.{png,json}"""
    src = os.path.join(PROCESSED, asset_id, "processed_sheet.png")
    if not os.path.exists(src):
        return (False, f"{asset_id}: processed_sheet.png 없음")
    sp, spec_file = load_spec(asset_id)
    if not sp:
        return (False, f"{asset_id}: 스펙 없음 — *_anim_specs.json / effect_specs.json에 등록돼야 메타를 만든다")
    # 이펙트·대형 컷은 캐릭터 시트가 아니다 — 각자의 폴더로 간다(프리젠터가 그 경로를 읽는다).
    flat_by_spec = {"effect_specs.json": "effects", "battle_cut_specs.json": "battle_cuts"}
    flat_kind = flat_by_spec.get(spec_file, "")
    is_flat = bool(flat_kind)
    out_dir = FLAT_TARGETS[flat_kind] if is_flat else SPRITES
    cell = int(sp.get("sheet_cell", CELL))
    anims = sp["animations"]
    rows = len(anims)
    cols = max(int(a.get("frames", 1)) for a in anims.values())
    im = Image.open(src).convert("RGBA")
    want = (cols * cell, rows * cell)
    if im.size != want:
        return (False, f"{asset_id}: 크기 {im.size} != 계약 {want} — 편집기로 재격자화하라")
    before = unique_colors(im)
    im, lines, tainted = clean_guides(im, cell)
    if colors:
        im = quantize(im, colors)
    after = unique_colors(im)
    stem = asset_id if is_flat else f"{asset_id}_remake"
    png = os.path.join(out_dir, f"{stem}.png")
    meta = os.path.join(out_dir, f"{stem}.json")
    if not dry:
        os.makedirs(out_dir, exist_ok=True)
        im.save(png)
        source = f"20_processed/{asset_id}/processed_sheet.png ({want[0]}x{want[1]}, {cell} cell)"
        io.open(meta, "w", encoding="utf-8").write(
            json.dumps(sheet_meta(sp, cols, source, cell), ensure_ascii=False, indent=1)
        )
    rel = os.path.relpath(png, ROOT).replace("\\", "/")
    note = f" · 잔선 {lines}px 제거+오염 {tainted}px 정리" if lines else ""
    return (True, f"{asset_id}: {rel} {want[0]}x{want[1]} · 색 {before}->{after}{note} · 애니 {rows}행")


def latest_versions(cat_dir: str) -> dict:
    """<id>_v<n>.png 중 id별 최신 n만 — 여러 버전이 채택돼 있으면 마지막 것이 정본."""
    best = {}
    for f in sorted(os.listdir(cat_dir)):
        if not f.lower().endswith(".png"):
            continue
        m = VERSION_RE.match(f)
        asset_id = m.group("id") if m else os.path.splitext(f)[0]
        n = int(m.group("n")) if m else 0
        if asset_id not in best or n >= best[asset_id][0]:
            best[asset_id] = (n, f)
    return {k: v[1] for k, v in best.items()}


def install_flat(cat: str, asset_id: str, fname: str, colors: int, dry: bool) -> tuple:
    src = os.path.join(PROCESSED, cat, fname)
    dst_dir = FLAT_TARGETS[cat]
    im = Image.open(src).convert("RGBA")
    before = unique_colors(im)
    im, lines, tainted = clean_guides(im, cell)
    if colors:
        im = quantize(im, colors)
    after = unique_colors(im)
    dst = os.path.join(dst_dir, f"{asset_id}.png")
    if not dry:
        os.makedirs(dst_dir, exist_ok=True)
        im.save(dst)
        if cat in ("effects", "battle_cuts"):
            sp, _src = load_spec(asset_id)
            if sp:
                cols = max(int(a.get("frames", 1)) for a in sp["animations"].values())
                io.open(os.path.join(dst_dir, f"{asset_id}.json"), "w", encoding="utf-8").write(
                    json.dumps(
                        sheet_meta(
                            sp, cols, f"20_processed/{cat}/{fname}", int(sp.get("sheet_cell", CELL))
                        ),
                        ensure_ascii=False,
                        indent=1,
                    )
                )
    rel = os.path.relpath(dst, ROOT).replace("\\", "/")
    note = f" · 잔선 {lines}px 제거+오염 {tainted}px 정리" if lines else ""
    return (True, f"{asset_id}: {rel} {im.size[0]}x{im.size[1]} · 색 {before}->{after}{note}")


def main() -> None:
    args = list(sys.argv[1:])
    dry = "--dry-run" in args
    colors = DEFAULT_COLORS
    if "--no-quantize" in args:
        colors = 0
        args.remove("--no-quantize")
    if "--colors" in args:
        i = args.index("--colors")
        colors = int(args[i + 1])
        del args[i:i + 2]
    if dry:
        args.remove("--dry-run")
    targets = set(args)

    if not os.path.isdir(PROCESSED):
        print("[install] 20_processed 없음 — 채택된 납품이 없다")
        return
    done, failed = [], []
    for entry in sorted(os.listdir(PROCESSED)):
        path = os.path.join(PROCESSED, entry)
        if not os.path.isdir(path) or entry.startswith("_"):
            continue
        if entry in FLAT_TARGETS:
            for asset_id, fname in latest_versions(path).items():
                if targets and asset_id not in targets:
                    continue
                ok, msg = install_flat(entry, asset_id, fname, colors, dry)
                (done if ok else failed).append(msg)
            continue
        if targets and entry not in targets:
            continue
        ok, msg = install_sheet(entry, colors, dry)
        (done if ok else failed).append(msg)

    print("[install] %s채택본 -> assets 설치" % ("(모의 실행) " if dry else ""))
    for m in done:
        print("  ok   " + m)
    for m in failed:
        print("  FAIL " + m)
    if not done and not failed:
        print("  (설치할 채택본 없음)")
    print(
        "  ─ 설치 %d건 · 실패 %d건%s"
        % (len(done), len(failed), (" · 양자화 %d색" % colors) if colors else " · 양자화 없음")
    )
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
