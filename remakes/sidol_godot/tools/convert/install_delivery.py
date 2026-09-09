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
import sheet_ops as so

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROCESSED = os.path.join(ROOT, "assets", "raw", "llm", "20_processed")
SPRITES = os.path.join(ROOT, "assets", "sprites")
CELL = 128
## 스펙이 게임 프레임 크기를 안 적어 둔 시트(대형 컷 등)의 기본 배율.
## 원래 이 값이 **모든 종에 그대로** 쓰였다 — 아래 sheet_scale()의 주석 참조.
SHEET_SCALE = 0.6667
## 화면 배율은 이 사다리 위의 값만 쓴다. 도트를 비정수 배율로 그리면 칸마다 픽셀이
## 한 줄씩 먹히거나 겹쳐 보인다(0.6667이 정확히 그 값이었다). 동률이면 큰 쪽을 고른다.
SCALE_LADDER = (0.25, 0.5, 1.0, 2.0)
## 화면에 그려지는 최소 배율. 스펙의 잡몹 game cell 64는 사다리에서 0.5(=화면 64px)로
## 떨어지는데, **유저 신고: "필드 몬스터가 너무 작아졌다"**. 이 차등이 들어오기 전에는
## 전 종이 0.6667(=85px)이었고 그 크기가 기준이었다. 보스 차등(1.0=128px)은 그대로
## 두고 아래쪽만 옛 크기로 되돌린다 — 작아진 쪽만 원복하는 것이 신고의 내용이다.
SCALE_MIN = 0.6667
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


## 픽셀 규칙(양자화·안내선 정리)은 sheet_ops.py가 정본이다 — 검증기·편집기와 같은 함수를
## 써야 "편집기에서 통과시킨 시트가 설치에서 어긋나는" 갈라짐이 안 생긴다.
quantize = so.quantize
clean_guides = so.clean_guides


def sheet_scale(sp: dict, cell: int) -> tuple:
    """설치 메타의 `scale` — **스펙이 적어 둔 게임 프레임 크기에서 뽑는다.**

    ## 왜 바꿨나 (2026-09-09, 실측)

    예전에는 종을 가리지 않고 `SHEET_SCALE`(0.6667) 하나였다. 시트 셀도 전 종 128이라
    설치된 11종이 **화면에서 전부 똑같은 85px**였다:

        c_bug 85px · dworm 85px · sewer_king 85px · hall_mother 85px · crt_overseer 85px

    뒤 셋은 보스다. 스펙은 잡몹 64 · 보스 128 · sys_builder 192로 **크기 차등을 적어
    두었는데 게임이 그 값을 아예 읽지 않았다**(읽는 곳은 절차적 플레이스홀더 생성기
    하나뿐). 이 저장소의 지배적 결함(선언은 있는데 읽는 코드가 없다)이 몬스터 크기에서
    난 자리다. 게임은 설치 메타의 `cell_w × scale`만 보므로, 그 차등을 **여기서** 메타에
    실어야 산다.

    배율 = 스펙 게임 cell ÷ 시트 셀. 비정수가 나오면 SCALE_LADDER로 당긴다 —
    도트를 1.5배나 0.375배로 그리면 픽셀 줄이 먹힌다.

    돌려주는 값: (배율, 그 근거 문장). 문장은 설치 로그에 그대로 실어 조용히 안 바뀌게 한다.
    """
    game = sp.get("cell")
    base = int(cell or CELL)
    if not isinstance(game, dict) or not int(game.get("w", 0)):
        return SHEET_SCALE, f"스펙에 게임 cell이 없어 기본 배율 {SHEET_SCALE}"
    ratio = float(int(game["w"])) / float(base)
    snapped = min(SCALE_LADDER, key=lambda k: (abs(k - ratio), -k))
    note = f"게임 cell {int(game['w'])} ÷ 시트 셀 {base} = {ratio:.3f} → 배율 {snapped}"
    if snapped < SCALE_MIN:
        # 사다리 아래쪽(0.5=64px)은 화면에서 너무 작다는 신고가 있었다. 차등을 없애지 않고
        # 바닥만 옛 기준(0.6667=85px)으로 올린다 — 보스의 1.0은 그대로다.
        note += f" → 최소 배율 {SCALE_MIN}로 올림(화면 {base * SCALE_MIN:.0f}px, 너무 작다는 신고)"
        return SCALE_MIN, note
    if abs(snapped - ratio) > 1e-6:
        note += f" (사다리로 당김 · 화면 {base * snapped:.0f}px)"
    else:
        note += f" (화면 {base * snapped:.0f}px)"
    return snapped, note


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
        "scale": sheet_scale(sp, cell)[0],
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
    return (True, f"{asset_id}: {rel} {want[0]}x{want[1]} · 색 {before}->{after}{note} "
                  f"· 애니 {rows}행 · {sheet_scale(sp, cell)[1]}")


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


## 평면 카테고리의 셀 크기 — 안내선 판정은 셀 단위로 훑으므로 값이 있어야 한다.
## (검증기·편집기의 FLAT_CONTRACTS와 같은 수. keyart는 격자가 없어 이미지 자체가 한 칸이다.)
FLAT_CELL = {"portraits": 256, "items": 96, "effects": 128, "battle_cuts": 512}


def install_flat(cat: str, asset_id: str, fname: str, colors: int, dry: bool) -> tuple:
    src = os.path.join(PROCESSED, cat, fname)
    dst_dir = FLAT_TARGETS[cat]
    im = Image.open(src).convert("RGBA")
    before = unique_colors(im)
    # cell을 안 넘겨 NameError로 죽던 자리 — 평면 카테고리 설치가 통째로 예외였다.
    # 이펙트·전투컷은 스펙의 sheet_cell이 정본이고, 나머지는 고정 규격을 쓴다.
    sp_flat, _ = load_spec(asset_id)
    cell = int(sp_flat.get("sheet_cell") or 0) or FLAT_CELL.get(cat) or min(im.width, im.height)
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
