# 컷신 키아트

채택된 키아트를 `<scene_id>.png`로 넣는다. 스펙은 `assets/spec/keyart/<scene_id>.json`,
컷신은 `illustration` op으로 이 폴더를 본다(`CutscenePlayer.KEYART_DIR`).

```
assets/keyart/scene_02_hp_room.png     ← 이 이름으로
```

현재 6종이 컷신에 이미 배선돼 있다(opening · hp_room_visit · f0_disk · f4_sacrifice ·
boss_sys_builder · epilogue). **그림이 없으면 컷신은 그 단계를 건너뛴다** — 대사·연출은
정상 진행되므로 납품 전에도 게임이 멈추지 않는다.

미납품 현황은 `검증실행.bat`의 validate 단계가 매번 한 줄로 보고한다:

```
[validate] 경고 — 컷신이 쓰는데 아직 납품되지 않은 키아트 6종: ...
```

규격은 스펙 JSON이 소유한다(1920×1080, 16:9). 의뢰·심사 절차는
`assets/gen/prompts/PROMPTING_QUICKGUIDE.md`.
