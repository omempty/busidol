#!/usr/bin/env python3
"""BSD 시돌이의 모험 — 칩튠 오디오 생성기.

합성 엔진·인코더는 공유 라이브러리(D:\\Game\\_godot_shared\\audio\\chipwave.py,
다른 Godot 프로젝트와 공용)에 있고, 이 파일은 프로젝트 스펙만 정의한다:
  - SFX: assets/spec/audio/sfx.json의 21종 ID별 파형 레시피
  - BGM: assets/spec/audio/bgm.json 트랙별 BPM/코드진행/분위기

출력: assets/audio/{sfx}/*.wav, assets/audio/{bgm}/*.ogg
사용: python tools/dev/make_audio.py [--only sfx|bgm]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

# 공유 라이브러리 탐색 — 상위 경로에서 D:\Game\_godot_shared\audio 를 찾는다.
_SHARED = next((_p / "_godot_shared" / "audio"
                for _p in Path(__file__).resolve().parents
                if (_p / "_godot_shared" / "audio").is_dir()), None)
if _SHARED is None:
    raise FileNotFoundError("_godot_shared/audio 를 상위 경로에서 찾지 못함")
sys.path.insert(0, str(_SHARED))

from chipwave import (MAJ, MIN, add_noise, add_tone, midi_hz,  # noqa: E402
                      render_bgm, sfx_buffer, write_ogg, write_wav)

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "audio"


SFX = {
    "sfx_menu_move": lambda b: add_tone(b, 0, 0.05, 880, "square", 0.18),
    "sfx_chest_open": lambda b: (add_tone(b, 0, 0.22, 150, "triangle", 0.22, sweep=0.5),
                                 add_noise(b, 0.20, 0.06, 0.25, 18),
                                 add_tone(b, 0.26, 0.16, 330, "square", 0.2, sweep=1.6)),
    "sfx_coin": lambda b: [add_tone(b, 0.07 * i, 0.09 if i == 0 else 0.30, f, "square", 0.2)
                           for i, f in enumerate([988, 1319])],
    "sfx_drink": lambda b: [add_tone(b, 0.09 * i, 0.08, f, "triangle", 0.25)
                            for i, f in enumerate([660, 520, 390])],
    "sfx_cure": lambda b: [add_tone(b, 0.08 * i, 0.10, f, "triangle", 0.22)
                           for i, f in enumerate([523, 659, 784])],
    "sfx_buff": lambda b: add_tone(b, 0, 0.35, 220, "square", 0.2, sweep=3.0),
    "sfx_menu_cancel": lambda b: add_tone(b, 0, 0.08, 440, "square", 0.2, sweep=0.5),
    "sfx_item_get": lambda b: [add_tone(b, 0.09 * i, 0.10, midi_hz(m), "square", 0.22)
                               for i, m in enumerate([72, 76, 79, 84])],
    "sfx_encounter": lambda b: [add_tone(b, 0.15 * i, 0.14, f, "square", 0.25)
                                for i, f in enumerate([740, 554])],
    "sfx_hit_player": lambda b: (add_noise(b, 0, 0.18, 0.3, 14, 0.5, 160),
                                 add_tone(b, 0, 0.15, 180, "triangle", 0.3, sweep=0.5)),
    "sfx_hit_enemy": lambda b: (add_noise(b, 0, 0.10, 0.2, 20),
                                add_tone(b, 0, 0.09, 420, "square", 0.22, sweep=0.6)),
    "sfx_door_open": lambda b: (add_noise(b, 0, 0.35, 0.12, 5),
                                add_tone(b, 0, 0.35, 140, "triangle", 0.15, sweep=1.8)),
    "sfx_explosion": lambda b: (add_noise(b, 0, 0.9, 0.42, 5),
                                add_tone(b, 0, 0.5, 90, "triangle", 0.35, sweep=0.4)),
    "sfx_thunder_arc": lambda b: [add_noise(b, 0.06 * i, 0.05, 0.28, 26)
                                  for i in range(6)],
    "voice_dead": lambda b: [add_tone(b, 0.22 * i, 0.24, midi_hz(m), "triangle", 0.3)
                             for i, m in enumerate([69, 65, 62, 57])],
    "voice_win": lambda b: [add_tone(b, 0.13 * i, 0.15, midi_hz(m), "square", 0.22)
                            for i, m in enumerate([72, 72, 74, 76, 79])],
    "voice_domang": lambda b: add_tone(b, 0, 0.4, 300, "square", 0.2,
                                       sweep=2.2, vibrato=0.05),
    "atk_swish": lambda b: add_noise(b, 0, 0.16, 0.25, 16, 0.3, 900),
    "impact_light": lambda b: (add_noise(b, 0, 0.08, 0.2, 24),
                               add_tone(b, 0, 0.08, 260, "square", 0.18, sweep=0.5)),
    "impact_heavy": lambda b: (add_noise(b, 0, 0.22, 0.32, 12, 0.4, 120),
                               add_tone(b, 0, 0.2, 130, "triangle", 0.32, sweep=0.4)),
    "cast_fire": lambda b: (add_noise(b, 0, 0.6, 0.2, 3.5),
                            add_tone(b, 0, 0.55, 110, "square", 0.18, sweep=3.0)),
    "cast_shield": lambda b: add_tone(b, 0, 0.5, 520, "triangle", 0.22, vibrato=0.02),
    "charge_volt": lambda b: add_tone(b, 0, 0.7, 200, "square", 0.2,
                                      sweep=4.0, vibrato=0.12),
    "impact_volt": lambda b: (add_noise(b, 0, 0.14, 0.34, 22),
                              add_tone(b, 0, 0.12, 900, "square", 0.24, sweep=0.25)),
    "finisher_charge": lambda b: (add_tone(b, 0, 1.1, 100, "square", 0.2, sweep=8.0),
                                  add_noise(b, 0.7, 0.4, 0.18, 8)),
    "rain_ambience": lambda b: add_noise(b, 0, 2.6, 0.11, 1.2),
    "alarm_system": lambda b: [add_tone(b, 0.2 * i, 0.18, 660 if i % 2 == 0 else 495,
                                        "square", 0.22) for i in range(5)],
}


def render_sfx() -> None:
    out_dir = OUT / "sfx"
    out_dir.mkdir(parents=True, exist_ok=True)
    for sid, recipe in SFX.items():
        buf, peak = sfx_buffer(recipe)
        write_wav(out_dir / f"{sid}.wav", buf / peak)
        print(f"[make_audio] {sid}.wav")


# ---------------------------------------------------------------- BGM 트랙 렌더

def render_all_bgm() -> None:
    try:
        from generate_all_bgm import render_all
        render_all()
    except Exception as e:
        print(f"[make_audio] 고급 BGM 렌더러 실패({e}), 기본 폴백 실행...")
        (OUT / "bgm").mkdir(parents=True, exist_ok=True)
        for tid, (bpm, bars, root, scale, prog, mood) in TRACKS.items():
            buf = render_bgm(tid, bpm, bars, root, scale, prog, mood)
            write_ogg(OUT / "bgm" / f"{tid}.ogg", buf)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", choices=["sfx", "bgm"], default=None)
    args = ap.parse_args()
    if args.only in (None, "sfx"):
        render_sfx()
    if args.only in (None, "bgm"):
        render_all_bgm()
    print("[make_audio] 완료")
