#!/usr/bin/env python3
"""[폐기 · 실행 거부] RGB 순검정 일괄 투명 키잉 — 이 도구가 스프라이트를 깨뜨렸다.

## 무엇을 했었나

원작 엔진 blit은 팔레트 인덱스 0을 스킵한다(= 투명). 구판 아틀라스에 검은 사각
배경이 남아 있던 시절, **원본 SPR이 없는 환경에서도 되돌릴 수 있게** RGBA PNG 위에서
순검정(0,0,0)을 전부 alpha 0으로 바꾸는 사후 키잉을 했다.

## 왜 틀렸나 (2026-09-07 실측, 유저 신고 "멍청조교·상자 스프라이트가 깨진다")

옛 docstring은 "원작 도트의 어두운 외곽선은 (32,32,32) 등 별도 인덱스라 안전하다"고
적었다. **거짓이다.** 원작 팔레트에는 RGB(0,0,0)인 인덱스가 **9개** 있다:

    인덱스 0        — 투명 키 (엔진이 스킵)
    인덱스 224~231  — 캐릭터·오브젝트의 외곽선과 그림자 (불투명해야 한다)

`OBJ.SPR` · `EVENTER.SPR` 팔레트에서 직접 확인한 값이다. 즉 **팔레트 인덱스를 잃은
RGBA PNG 위에서는 "지워야 할 검정"과 "그려야 할 검정"을 원리적으로 구별할 수 없다.**
이 도구는 둘을 같이 지웠고, `assets/sprites/obj_original_32.png`는 불투명 순검정
12,153px를 잃어 176셀 중 39셀(상자·소품)에 내부 구멍이 뚫린 채로 게임에 들어가 있었다.

같은 결함이 flood-fill 방식(`extract_sprites.remove_bg_np`)을 쓰던
`migrate_original_sheets.py`(캐릭터 시트 15종, 외곽선 155,840px 손실)와
`migrate_item_icons.py`(아이콘 35종, 36,939px 손실)에도 있었다. 셋 다 같은 하나의
규칙 위반이다 — **팔레트 인덱스를 잃은 뒤 RGB만 보고 투명을 정했다.**

## 대신 무엇을 쓰나

알파의 근거는 언제나 원작 SPR의 팔레트 인덱스 0뿐이다(`spr_extract.parse_spr`).
파일이 상했으면 사후 보정이 아니라 **원본에서 다시 굽는다**:

    python tools/convert/migrate_original_sheets.py   # <id>_original.png 15종
    python tools/convert/migrate_item_icons.py        # assets/icons/*.png
    python tools/dev/remaster_obj_atlas.py            # obj_original_32.png
    python tools/dev/make_player_original_sheet.py    # player_original.png

그리고 관문이 상시 감시한다(run_gates.ps1 마지막 단계):

    python tools/dev/spr_alpha_check.py            # 게임 파일 == 원작 재굽기?
    python tools/dev/spr_alpha_check.py --report   # 시트별 실측표

## 왜 파일을 지우지 않고 남겼나

지우면 교훈도 같이 사라지고, 몇 달 뒤 "검은 배경이 남았다"를 본 사람이 같은 도구를
다시 짠다. 이 저장소가 반복해 겪은 결함이 그 모양이다. 그래서 **실행은 거부하고
근거만 남기는 묘비**로 둔다. 지우려면 이 docstring을
`docs/03_plan/03_content_backlog.md`의 해당 항목으로 먼저 옮길 것.
"""
from __future__ import annotations

import sys


def main(argv: list[str]) -> int:
    print(__doc__)
    print("[key_color0_transparent] 실행 거부 — 위 근거를 읽고 원본에서 다시 구울 것.")
    if argv:
        print("[key_color0_transparent] 무시한 인자: %s" % " ".join(argv))
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
