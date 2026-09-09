# 주인공 리터칭 의뢰서 — **이 문서는 대체되었다**

> 이 파일은 손으로 쓴 것이 아니라 `tools/convert/export_player_sheet.py`가 굽던 산출물이고,
> **정본과 다른 계약을 선언하고 있었다**(2열 × 5행 · 128×320 또는 256×640).
>
> 정본은 `assets/spec/sprites/player_sidol.json` 하나다 — **셀 128 · 4열 × 8행 = 512×1024**
> (walk 4방향 × 4프레임 + idle 4방향 × 2프레임). 저 낡은 규격으로 그려 온 납품은 크기
> 위반으로 자동 반려된다.
>
> 굽던 생성기 둘은 2026-09-09에 정리했다:
> - `export_player_gen_package.py` — **실행하면 죽었다**(`int(spec["cell"])`에 딕셔너리를 넣었다)
> - `export_player_sheet.py` — 돌긴 했지만 위 틀린 계약을 찍어 냈다

## 지금 쓸 것

```
python tools/convert/export_player_remaster_package.py
  -> assets/raw/llm/sprites/player_sidol/
       prompt.md            리터칭 의뢰문 (정본 계약 512×1024)
       player_original.png  지금 게임에 들어가 있는 원작 이관 시트
       orig_frame_*.png     원작 I.SPR 프레임 8장(24px 도트를 8배 확대)
       grid_template.png    정확한 캔버스 크기의 빈 격자
       grid_guide.png       행 이름·프레임 수 설명 그림(참고용)
       subpalette.png       주인공 자신의 색 16개
       palette_swatch.png   마스터 팔레트 전체
```

이 패키지는 **신규 창작이 아니라 리터칭** 계약이다 — 바꾸지 않는 것(신원·실루엣·색 정체성) /
격상하는 것(해상도·명암·질감) / 새로 그리는 것(원작에 대응 그림이 없는 행)을 갈라 준다.
화풍 규칙 블록은 몬스터·인물 리마스터와 **같은 것**을 쓴다(`llm_package_common`) — 카테고리마다
화풍이 갈라지지 않게 하려는 것이다.

`python tools/review/prompt_audit.py` 가 이 패키지의 선언 숫자를 정본 스펙과 대조한다.
