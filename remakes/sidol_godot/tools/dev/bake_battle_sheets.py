#!/usr/bin/env python3
"""원작 전투 프레임(E*.SPR) → 리메이크 전투 대형 시트 베이커.

## 왜 필요했나

원작 전투는 **320×200 전체 화면 프레임 시퀀스**였다(격투게임 패러디).
그 프레임 82장이 `assets/originals_ref/bmp_spr/`에 이미 추출돼 있었는데
**게임 코드가 로드하는 곳이 0곳**이었고, 그 자리를 필드 보행 도트(I.SPR 24~26px를
4배 확대한 것)로 대신 쓰고 있었다. 적이 화면 높이의 13~21%밖에 안 되어
원작(52~73%)의 압박감이 통째로 사라져 있었다. [[dead-data-is-dominant-defect]]

## 원작이 프레임에 부여한 의미 — 소스로 확정 (추측 아님)

`originals/1995_sidol_bsd_dos/WARMODE.C`

| 프레임 | 원작 용도 | 근거 |
|---|---|---|
| 0 | 평상시 | `:1116` `if (EN.Hp > 15) ENLoss = 0` → `:1127` `RPut_Spr(30,10,&Enemy[ENLoss],0)` |
| 1 | **빈사**(HP 1~15) | `:1117` `else if (EN.Hp > 0 && EN.Hp <= 15) ENLoss = 1` |
| 2 | **사망** | `:1119` `if (EN.Life == 0) ENLoss = 2` |
| 3 | **공격** | `:537 EnemyAttackAni()` — `S[Snum-1]`(=S[3])을 x=100 → -50으로 슬라이드 |
| 4·5 | **원작이 로드조차 안 한다** | `:678 Load_Spr(0,2,...)` · `:559 Load_Spr(0,Snum-1=3,...)` |

프레임 4·5는 파일에 있는데 원작이 한 번도 안 쓴 사문화 에셋이다. 리메이크는
**특수 공격(상태이상)**에 배정한다 — 원작에 없던 전투룰이니 원작이 안 쓴 그림을 준다.

## 종 ↔ SPR 매핑 — 이것도 소스로 확정

`WARMODE.C:17` `char *EName[]={"Mad Eye","Vilgur","DWorm","Ozzy","Iron-Vic","HellCop","O-Rey","FireMan"}`
와 `:251-262`의 로드 스위치가 SprNum으로 1:1 대응한다.

**e2·e4·e7·e8은 바이트 동일하다**(프레임0 md5 `d7467a3a`) — 원작이 네 종에 같은 그림을
돌려 썼다. 리메이크는 그 셋을 **색상 변주**로 가른다(유저 결정 2026-09-07). 색은 굽는
단계에서 HSV 색상환 회전으로 넣는다 — 런타임 modulate(곱셈)는 노란 불꽃을 탁하게 만든다.

## 투명 키 — **BMP가 아니라 SPR을 직접 읽는다**

`assets/originals_ref/bmp_spr/*.bmp`는 알파가 없는 RGB 중간물이라 **쓰면 안 된다.**
이 팔레트에는 순검정 RGB(0,0,0)이 **아홉 개** 있다 — 투명 키인 인덱스 0과, 외곽선·그림자로
쓰이는 **인덱스 224~231**. RGB만 보고 순검정을 키잉하면 후자까지 날아가 스프라이트에
구멍이 뚫린다. 실측(2026-09-07): `E6.SPR` 프레임0의 불투명 순검정이 **4,173px**다.

그래서 `spr_extract.parse_spr`로 원본 SPR을 직접 읽는다 — 그쪽은 **팔레트 인덱스 0만**
투명으로 내보내므로 224~231은 검은 픽셀로 살아남는다.

같은 함정이 `obj_original_32.png`에서 실제로 터졌다(유저 신고 2026-09-07): 사후 키잉
도구가 RGB 순검정을 전부 지워 176셀 중 **39셀(22%)** 에 구멍이 났다. 백로그에 기록.

## 사용

    python tools/dev/bake_battle_sheets.py            # 굽는다
    python tools/dev/bake_battle_sheets.py --check    # 굽지 않고 현황만
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from spr_extract import parse_spr  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ORIGINALS = ROOT.parent.parent / "originals" / "1995_sidol_bsd_dos"
OUT_DIR = ROOT / "assets" / "sprites"

CELL_W, CELL_H = 320, 200  # 원작 화면 = 셀. 구도를 그대로 보존한다.

# 원작 메인 전투 화면의 적 그리기 오프셋 — WARMODE.C:1127 `RPut_Spr(30,10,...)`
DRAW_OFFSET = [30, 10]
# 원작 공격 슬라이드 폭 — WARMODE.C:590 `for(i=100;i>=-50;i-=20)`
ATTACK_SLIDE = [100, -50]

# 행 배치. (애니 이름, [프레임 번호...], fps, loop)
# 정지 행도 2칸을 채운다 — BattlePresenter._apply_anim_frame이 idle 행의 0·1칸을
# 번갈아 짚으므로, 1칸만 채우면 반 박자마다 빈 칸이 보인다.
ROWS = [
    ("idle", [0, 0], 2, True),
    ("wounded", [1, 1], 2, True),
    ("attack", [3, 3], 6, False),
    ("special", [5, 3], 5, False),
    ("death", [2, 2], 4, False),
]
# 빈사 행을 피격 순간에도 재사용한다(별도 행을 굽지 않는다).
ALIAS = {"hurt": ("wounded", 1, 6, False)}

# 리메이크 종 → (원작 SPR 세트, 색상환 회전°, 설명)
SPECIES = {
    "mad_eye": ("e1", 0, "Mad Eye — 원작 SprNum 0"),
    "vulgar": ("e2", 0, "Vilgur — 원작 SprNum 1"),
    "dworm": ("e3", 0, "DWorm — 원작 SprNum 2"),
    "ozzy": ("e4", 100, "Ozzy — 원작 SprNum 3. e2와 바이트 동일 → 폐시약 녹색으로 변주"),
    "iron_voc": ("e5", 0, "Iron-Vic — 원작 SprNum 4"),
    "hellcop": ("e6", 0, "HellCop — 원작 SprNum 5"),
    "o_ray": ("e7", 160, "O-Rey — 원작 SprNum 6. e2와 바이트 동일 → 광선 청백으로 변주"),
}
# FireMan(SprNum 7 · e8)은 리메이크에 대응 종이 없다 — 굽지 않는다.


def load_frames(set_id: str) -> list[Image.Image]:
    """한 세트의 320×200 프레임을 RGBA로 돌려준다.

    투명 판정은 `parse_spr`에 맡긴다 — 팔레트 인덱스 0만 알파 0으로 나온다.
    여기서 RGB를 보고 다시 키잉하면 인덱스 224~231(정당한 검정)까지 지워진다.
    """
    spr = ORIGINALS / f"{set_id.upper()}.SPR"
    if not spr.exists():
        return []
    _palette, raw = parse_spr(spr.read_bytes())
    frames: list[Image.Image] = []
    for w, h, rgba in raw:
        if (w, h) != (CELL_W, CELL_H):
            # E5.SPR에 딸린 101×71은 e5-1(투사체 이펙트) — 시트에 넣지 않는다.
            continue
        frames.append(Image.frombytes("RGBA", (w, h), bytes(rgba)))
    return frames


def hue_rotate(img: Image.Image, degrees: int) -> Image.Image:
    """색상환 회전 — 알파는 보존한다. 곱셈 틴트와 달리 명도를 잃지 않는다."""
    if degrees % 360 == 0:
        return img
    alpha = img.getchannel("A")
    hsv = img.convert("RGB").convert("HSV")
    h, s, v = hsv.split()
    shift = int(round(degrees * 255 / 360))
    h = h.point(lambda p, d=shift: (p + d) % 256)
    out = Image.merge("HSV", (h, s, v)).convert("RGBA")
    out.putalpha(alpha)
    return out


def bake(species: str, set_id: str, degrees: int, desc: str, check: bool) -> bool:
    frames = load_frames(set_id)
    need = max(max(idx) for _, idx, _, _ in ROWS) + 1
    if len(frames) < need:
        print(f"  {species:14s} SKIP — {set_id} 프레임 {len(frames)}장(필요 {need})")
        return False

    cols = max(len(idx) for _, idx, _, _ in ROWS)
    sheet = Image.new("RGBA", (cols * CELL_W, len(ROWS) * CELL_H), (0, 0, 0, 0))
    anims: dict[str, dict] = {}
    for row, (name, idx, fps, loop) in enumerate(ROWS):
        for col, frame_no in enumerate(idx):
            sheet.paste(frames[frame_no], (col * CELL_W, row * CELL_H))
        anims[name] = {"row": row, "frames": len(idx), "fps": fps, "loop": loop}
    for name, (base, count, fps, loop) in ALIAS.items():
        anims[name] = {"row": anims[base]["row"], "frames": count, "fps": fps, "loop": loop}

    sheet = hue_rotate(sheet, degrees)

    png = OUT_DIR / f"{species}_battle.png"
    meta = OUT_DIR / f"{species}_battle.json"
    if check:
        mark = "있음" if png.exists() else "**없음**"
        print(f"  {species:14s} {set_id} hue{degrees:+4d}°  {mark}")
        return png.exists()

    sheet.save(png)
    doc = {
        "schema_version": 3,
        "kind": "battle",
        "source": f"originals E*.SPR — {desc}",
        "generator": "tools/dev/bake_battle_sheets.py",
        "cell": CELL_W,
        "cell_w": CELL_W,
        "cell_h": CELL_H,
        "cols": cols,
        "scale": 1.0,
        "origin_screen": [CELL_W, CELL_H],
        "draw_offset": DRAW_OFFSET,
        "attack_slide": ATTACK_SLIDE,
        "hue_shift": degrees,
        "animations": anims,
    }
    meta.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"  {species:14s} {set_id} hue{degrees:+4d}°  {sheet.width}x{sheet.height} 저장")
    return True


def main() -> int:
    check = "--check" in sys.argv
    if not ORIGINALS.exists():
        print(f"[bake_battle] 원작 소스 없음: {ORIGINALS}")
        return 1
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"[bake_battle] {'현황' if check else '베이크'} — 원작 전투 프레임 → 전투 대형 시트")
    ok = 0
    for species, (set_id, degrees, desc) in SPECIES.items():
        if bake(species, set_id, degrees, desc, check):
            ok += 1
    print(f"[bake_battle] {ok}/{len(SPECIES)}종")
    return 0 if ok == len(SPECIES) else 1


if __name__ == "__main__":
    raise SystemExit(main())
