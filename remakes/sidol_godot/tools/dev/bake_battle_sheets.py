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
| 4·5 | **피격 반응** | `:235 EnemyAvoid()` — `Snum=6`으로 0~5를 로드하고 `random(3)==0 ? 4 : 5` |

> **정정(2026-09-07).** 처음엔 "4·5는 원작이 로드조차 안 한다"고 적었다. **틀렸다.**
> `LoadSprites`(`:678`)와 `EnemyAttackAni`(`:559`)만 보고 내린 판정이었는데, 세 번째
> 로드 지점인 `EnemyAvoid()`가 여섯 장을 전부 읽는다. 그 함수는 **주인공이 때렸을 때
> 적이 보이는 반응**이고(`MyAttackAni` → `:411 EnemyAvoid()`), 4와 5 중 하나를 무작위로
> 골라 x=100 → −50으로 밀며 `AttackEffect(100,60)`으로 히트 스파크를 얹는다.
> 그래서 4·5는 사문화가 아니라 **피격 반응**이고, 이 도구도 `hurt` 두 프레임으로 굽는다.

## 원작 공격은 돌진에서 끝나지 않는다 — 섬광과 에너지파가 붙는다

`EnemyAttackAni`(`:590~625`)의 전체 순서:

1. 프레임 3을 x=100 → −50으로 8단계 슬라이드
2. **발사 종에 한해**(`SprNum` 0·1·2·3·6·7 — Iron-Vic(4)·HellCop(5)은 제외):
   `fire.spr[0]` 섬광을 (0,0)에 얹고 `Delay(300)` →
   **`fire.spr[1]`을 x=−100 → 200으로 15단계 날린다**(화면을 가로지르는 에너지파)
3. `MyAvoid()` — 주인공 피격 반응

`EnemyAvoid`의 Iron-Vic은 `e5-1.spr`을 `(i,i)` 대각선으로 함께 끌고 온다.
이펙트 원본 크기: `fire.spr` 320×200 ×3 · `effect.spr` 121×101 · `e5-1.spr` 101×71.

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
    # 원작 `EnemyAvoid()`가 4·5 중 하나를 무작위로 고른다 — 두 장을 이어 붙여 굽는다.
    ("hurt", [4, 5], 8, False),
    ("death", [2, 2], 4, False),
]
# 특수 공격은 **원작에 없는 개념**이라 전용 그림이 없다. 돌진(프레임 3)을 그대로 쓰고
# 리메이크 이펙트(속성색)로 가른다 — 없는 그림을 지어내기보다 있는 그림을 재배치한다.
ALIAS = {"special": ("attack", 1, 5, False)}

# 원작 전투 이펙트 — 화면 좌표계(RPut_Spr 좌상단 기준)로 그대로 얹는다.
# (파일명, SPR, 프레임, 설명)
FX = [
    ("origin_muzzle", "fire", 0, "적 돌진 끝의 충돌 섬광 — WARMODE.C:607 RPut_Spr(0,0,&Fire[0],0)"),
    ("origin_bolt", "fire", 1, "에너지파 — :613 x=-100 → 200으로 15단계 가로지름"),
    ("origin_spark", "effect", 0, "히트 스파크 — AttackEffect(x,y) (:220)"),
    ("origin_bolt_ironvoc", "e5-1", 0, "Iron-Vic 전용 투사체 — :280 RPut_Spr(i,i,&Eff[0],0)"),
]
# 에너지파를 쏘는 종 — 원작 `EnemyAttackAni` :601 `case 0:1:2:3:6:7`.
# Iron-Vic(4) · HellCop(5)은 근접만 한다. 이 구분이 종을 가르는 원작의 장치다.
FIRES_BOLT = ["mad_eye", "vulgar", "dworm", "ozzy", "o_ray"]

# ── 발사 종의 빔 기준점 (`shot` 메타) ────────────────────────────────────
# `origin_muzzle`(섬광)과 `origin_bolt`(혜성)를 **적의 어디에 맞춰 띄울지**다.
# 원작은 섬광을 화면 (0,0) 고정에 얹었는데(`WARMODE.C:607`), 그러면 노즐이 프레임
# 어디에 있든 빔이 그 자리에서 나가야 해서 종마다 어긋난다(2026-09-11 유저 지적
# "DWORM 입에서 나오는 빔이 안 맞는다"). 그래서 노즐 좌표를 메타에 굽는다.
#
# `flip`: 공격 자세를 좌우 반전할지. 원작 공격 프레임은 오른쪽을 향해 저장돼 있는데
#   플레이어는 화면 **왼쪽**에 있다(`BackW` :1127·1129). 반전하지 않으면 적이 등을 돌리고
#   쏘고, 노즐도 반대를 향한다. 마드아이는 눈이 이미 왼쪽을 봐서 유지한다.
# `muzzle`[x,y]: 셀(320×200) 안에서 빔이 나갈 자리. **반전 전** 좌표로 적는다 —
#   런타임이 flip이면 x를 `320-x`로 옮긴다. 지정이 없으면 공격 프레임(3) 내용 bbox 중심.
SHOT_FLIP = {
    "mad_eye": False,
    "vulgar": True,
    "dworm": True,
    "ozzy": True,
    "o_ray": True,
}
# 뚜렷한 노즐이 있는 종은 그 자리를 직접 잡는다(빨간 링 중심 — 공격 프레임 3 실측).
SHOT_MUZZLE = {"dworm": [148, 62]}


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
    shot = _shot_meta(species, frames)
    if shot is not None:
        doc["shot"] = shot
    meta.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"  {species:14s} {set_id} hue{degrees:+4d}°  {sheet.width}x{sheet.height} 저장")
    return True


def _shot_meta(species: str, frames: list[Image.Image]) -> dict | None:
    """발사 종의 빔 기준점 — 없으면 None(빔을 안 쏘는 종)."""
    if species not in FIRES_BOLT:
        return None
    muzzle = SHOT_MUZZLE.get(species)
    if muzzle is None:
        bb = frames[3].getbbox() if len(frames) > 3 else None
        if bb is not None:
            muzzle = [(bb[0] + bb[2]) // 2, (bb[1] + bb[3]) // 2]
    if muzzle is None:
        return None
    return {"dir": -1, "flip": SHOT_FLIP.get(species, False), "muzzle": [int(muzzle[0]), int(muzzle[1])]}


# ── 주인공 전투 시트 ────────────────────────────────────────────────────────
# 원작은 주인공도 320×200 대형이었다. `lth.spr`이 대치/빈사 포즈이고(`:1129`
# `RPut_Spr(0,20,&Back[MELoss],0)` — MELoss는 HP로 갈린다), 공격·회피는 별도 SPR이다.
#
# | 행 | 원작 | 무엇 | 움직임(원작 루프) |
# |---|---|---|---|
# | 0 `pose`    | lth 1·2      | 대치 · 빈사        | 고정 (0,20) |
# | 1 `rise`    | a5 0         | 승룡권 패러디      | `:301` y 200 → 0, 9단계 |
# | 2 `swing`   | a1 0~3       | 기본 타격 4종      | `:322` x −50 → 150, 8단계 |
# | 3 `flurry`  | a3 0·1·2     | 백열 장수 패러디   | `:347` 1·2를 20회 교대, 점점 빨라짐 |
# | 4 `avoid_a` | d3 0~2       | 회피 3종           | `:424` x 0 → 40, 9단계 + 스파크 |
# | 5 `avoid_b` | d2 0·1       | 회피 1종           | `:444` x 0 → 50, 3단계 + 마무리 포즈 |
# | 6 `avoid_c` | d1 0~4       | 회피 2종           | `:471` 0·1을 1초씩 → 2+3 겹쳐 x −20 → 60 |
#
# 선택 확률도 원작 그대로다 — 공격 `random(6)`: 5→rise · 0~3→swing[select] · 4→flurry,
# 회피 `random(6)`: 0~2→avoid_a[n] · 3→avoid_b · 4·5→avoid_c (`:390`·`:516`).
#
# 실측 프레임 수: lth 3 · a5 **1** · a1 4 · a3 3 · d3 **3** · d2 2 · d1 5.
# a5와 d3은 원작이 `Load_Spr(0,1,…)`·`Load_Spr(0,3,…)`로 **한 칸씩 더 요청**하는데
# 파일에 없다 — [[originals-confirm-map-and-obj-quirks]]에 적힌 그 습관이다
# (OBJ.SPR 173 vs MAX_OBJ 174 · ITEM.SPR 35 vs NUM_ITEM 37). 실제 사용분만 굽는다.
PLAYER_ROWS = [
    ("pose", "lth", [1, 2], 2, True),
    ("rise", "a5", [0], 6, False),
    ("swing", "a1", [0, 1, 2, 3], 8, False),
    ("flurry", "a3", [0, 1, 2], 12, False),
    ("avoid_a", "d3", [0, 1, 2], 8, False),
    ("avoid_b", "d2", [0, 1], 6, False),
    ("avoid_c", "d1", [0, 1, 2, 3, 4], 6, False),
]
## 원작 주인공 대치 포즈 그리기 오프셋 — `:1129` `RPut_Spr(0,20,&Back[MELoss],0)`.
PLAYER_POSE_OFFSET = [0, 20]


def bake_player(check: bool) -> bool:
    # **적과 달리 상시 대형이 아니다.** 원작 주인공 동작은 공격 3종·회피 3종뿐이라
    # 매 턴 터지면 금방 물린다(유저 판단 2026-09-07). 그래서 상시 표현이 아니라
    # **임팩트 순간에만 끊고 들어오는 컷**으로 쓴다 — 저장소에 이미 그 용도로 만들어 둔
    # `assets/battle_cuts/` + `BattlePresenter.play_cut` 계열의 자리다.
    # 평소 주인공은 지금처럼 96px 도트로 남는다(하이브리드).
    out = ROOT / "assets" / "battle_cuts"
    out.mkdir(parents=True, exist_ok=True)
    png = out / "origin_player.png"
    meta_path = out / "origin_player.json"
    if check:
        print("  %-14s %s" % ("origin_player", "있음" if png.exists() else "**없음**"))
        return png.exists()

    cols = max(len(idx) for _, _, idx, _, _ in PLAYER_ROWS)
    sheet = Image.new("RGBA", (cols * CELL_W, len(PLAYER_ROWS) * CELL_H), (0, 0, 0, 0))
    anims: dict[str, dict] = {}
    for row, (name, spr_id, idx, fps, loop) in enumerate(PLAYER_ROWS):
        frames = load_frames(spr_id)
        if len(frames) <= max(idx):
            print(f"  {'origin_player':14s} SKIP — {spr_id} 프레임 부족({len(frames)})")
            return False
        for col, frame_no in enumerate(idx):
            sheet.paste(frames[frame_no], (col * CELL_W, row * CELL_H))
        anims[name] = {"row": row, "frames": len(idx), "fps": fps, "loop": loop}
    sheet.save(png)
    meta_path.write_text(
        json.dumps(
            {
                "schema_version": 3,
                "kind": "battle",
                "actor": "player",
                "source": "originals lth/a5/a1/a3/d3/d2/d1.SPR — WARMODE.C:295-536 · :1129",
                "generator": "tools/dev/bake_battle_sheets.py",
                "cell": CELL_W,
                "cell_w": CELL_W,
                "cell_h": CELL_H,
                "cols": cols,
                "scale": 1.0,
                "origin_screen": [CELL_W, CELL_H],
                "draw_offset": PLAYER_POSE_OFFSET,
                "animations": anims,
            },
            ensure_ascii=False,
            indent=1,
        )
        + chr(10),
        encoding="utf-8",
    )
    print(f"  {'origin_player':14s} lth+a5+a1+a3+d3+d2+d1  {sheet.width}x{sheet.height} 저장")
    return True


def bake_fx(check: bool) -> int:
    """원작 전투 이펙트 — 화면 좌표계 그대로 낱장으로 굽는다.

    적 시트와 달리 셀 격자에 넣지 않는다. 원작이 `RPut_Spr(x, y, spr)`로 **좌상단 기준**
    자유 좌표에 얹었고(에너지파는 x가 −100에서 200까지 움직인다), 크기도 제각각이라
    (320×200 · 121×101 · 101×71) 한 격자에 억지로 맞추면 그 좌표 규약이 깨진다.
    """
    out = ROOT / "assets" / "effects"
    out.mkdir(parents=True, exist_ok=True)
    ok = 0
    for name, spr_id, frame_no, desc in FX:
        png = out / f"{name}.png"
        if check:
            print("  %-22s %s" % (name, "있음" if png.exists() else "**없음**"))
            ok += 1 if png.exists() else 0
            continue
        spr = ORIGINALS / f"{spr_id.upper()}.SPR"
        if not spr.exists():
            print(f"  {name:22s} SKIP — {spr.name} 없음")
            continue
        _palette, raw = parse_spr(spr.read_bytes())
        if frame_no >= len(raw):
            print(f"  {name:22s} SKIP — 프레임 {frame_no} 없음(총 {len(raw)})")
            continue
        w, h, rgba = raw[frame_no]
        Image.frombytes("RGBA", (w, h), bytes(rgba)).save(png)
        (out / f"{name}.json").write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "kind": "origin_fx",
                    "source": f"originals {spr_id.upper()}.SPR frame {frame_no} — {desc}",
                    "generator": "tools/dev/bake_battle_sheets.py",
                    "size": [w, h],
                    "origin_screen": [CELL_W, CELL_H],
                },
                ensure_ascii=False,
                indent=1,
            )
            + chr(10),
            encoding="utf-8",
        )
        print(f"  {name:22s} {spr_id}[{frame_no}]  {w}x{h} 저장")
        ok += 1
    return ok


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
    print("[bake_battle] 주인공 전투 시트")
    player_ok = bake_player(check)
    print("[bake_battle] 원작 전투 이펙트")
    fx_ok = bake_fx(check)
    print(
        "[bake_battle] 적 %d/%d종 · 주인공 %s · 이펙트 %d/%d"
        % (ok, len(SPECIES), "ok" if player_ok else "실패", fx_ok, len(FX))
    )
    return 0 if (ok == len(SPECIES) and player_ok and fx_ok == len(FX)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
