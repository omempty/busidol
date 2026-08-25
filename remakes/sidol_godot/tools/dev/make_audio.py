#!/usr/bin/env python3
"""칩튠 오디오 생성기 — assets/spec/audio/{bgm,sfx}.json 스펙의 음원을 프로그램 합성으로 생성.

스펙 요구: FM/PSG 칩튠(square/triangle/noise), 실악기 금지 → 파형 합성으로 충족.
출력: remakes/sidol_godot/assets/audio/{bgm,sfx}/<id>.wav (22050Hz mono 16bit)

사용: python tools/dev/make_audio.py [--only sfx|bgm]

구성:
- SFX: 레시피 함수(파형+피치 스윕+노이즈 믹스+엔벨로프) 21종
- BGM: 코드 진행+리듬 템플릿 기반 시드 랜덤워크 멜로디, 바 단위 정렬로 심리스 루프
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import wave
from pathlib import Path

import numpy as np
import soundfile as sf

SR = 22050
ROOT = Path(__file__).resolve().parents[3] / "sidol_godot"
OUT = ROOT / "assets" / "audio"

MAJ = [0, 2, 4, 5, 7, 9, 11]
MIN = [0, 2, 3, 5, 7, 8, 10]


def midi_hz(m: float) -> float:
    return 440.0 * 2 ** ((m - 69) / 12)


def osc(kind: str, phase: np.ndarray) -> np.ndarray:
    if kind == "square":
        return np.sign(np.sin(phase)) * 0.6
    if kind == "triangle":
        return 2 / np.pi * np.arcsin(np.sin(phase))
    if kind == "saw":
        return 2 * ((phase / (2 * np.pi)) % 1.0 - 0.5)
    return np.zeros_like(phase)


def envelope(n: int, attack: float = 0.004, release: float = 0.05) -> np.ndarray:
    a = max(int(SR * attack), 1)
    r = max(int(SR * release), 1)
    out = np.ones(n)
    out[:a] *= np.linspace(0, 1, a)
    out[n - r:] *= np.linspace(1, 0, min(r, n))
    return out


def add_tone(buf: np.ndarray, start: float, dur: float, freq: float,
             kind: str = "square", vol: float = 0.25,
             sweep: float = 0.0, vibrato: float = 0.0) -> None:
    """buf[start_sec : ]에 dur초 톤 가산. sweep>0이면 종료 주파수 배율(스윕)."""
    i0 = int(start * SR)
    n = int(dur * SR)
    if i0 >= len(buf):
        return
    n = min(n, len(buf) - i0)
    t = np.arange(n) / SR
    f = freq * (sweep ** (t / dur)) if sweep else freq
    if vibrato:
        f = f * (1 + vibrato * np.sin(2 * np.pi * 6 * t))
    phase = 2 * np.pi * np.cumsum(f) / SR
    sig = osc(kind, phase) * envelope(n) * vol
    buf[i0:i0 + n] += sig


def add_noise(buf: np.ndarray, start: float, dur: float, vol: float = 0.2,
              decay: float = 6.0, tone_mix: float = 0.0, tone_f: float = 800) -> None:
    i0 = int(start * SR)
    n = min(int(dur * SR), len(buf) - i0)
    if n <= 0:
        return
    rng = np.random.default_rng(hash((start, dur)) & 0xFFFF)
    noise = rng.uniform(-1, 1, n) * np.exp(-decay * np.arange(n) / SR)
    if tone_mix > 0:
        t = np.arange(n) / SR
        noise = noise * (1 - tone_mix) + tone_mix * np.sign(
            np.sin(2 * np.pi * tone_f * t)) * np.exp(-decay * np.arange(n) / SR)
    buf[i0:i0 + n] += noise * vol


# ---------------------------------------------------------------- SFX 레시피

def sfx_buffer(build) -> tuple[np.ndarray, float]:
    tmp = np.zeros(SR * 4)
    build(tmp)
    peak = float(np.max(np.abs(tmp))) or 1.0
    end = int(np.ceil((np.nonzero(np.abs(tmp) > 1e-4)[0][-1] + 1) / SR * 1000) / 1000 * SR)
    return tmp[:max(end, 1)], peak


SFX: dict[str, callable] = {
    "sfx_menu_move": lambda b: add_tone(b, 0, 0.05, 880, "square", 0.18),
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


# ---------------------------------------------------------------- BGM 엔진

def drum(buf: np.ndarray, beat_start: float, which: str) -> None:
    if which == "kick":
        add_tone(buf, beat_start, 0.12, 95, "triangle", 0.4, sweep=0.45)
    elif which == "snare":
        add_noise(buf, beat_start, 0.09, 0.22, 26)
    elif which == "hat":
        add_noise(buf, beat_start, 0.03, 0.10, 70)


def render_bgm(spec: dict, track_id: str, bpm: int, bars_total: int,
               key_root: int, scale: list[int],
               progression: list[int], mood: str) -> None:
    """바 단위 정렬 렌더 → 끝이 시작과 맞물리는 심리스 루프."""
    spb = 60.0 / bpm                      # 초/비트
    bar_len = 4 * spb
    total = int(bars_total * bar_len * SR)
    buf = np.zeros(total + SR)            # 여유분
    rng = np.random.default_rng(sum(ord(c) for c in track_id))
    dense = mood in ("battle", "boss")
    calm = mood in ("title", "emotional", "basement")

    for bar in range(bars_total):
        t0 = bar * bar_len
        chord_root = key_root + progression[bar % len(progression)]
        # 베이스 — battle/boss는 8분 펌핑, 나머지는 4분 루트
        step = 0.5 if dense else 1.0
        b = 0.0
        while b < 4.0:
            add_tone(buf, t0 + b * spb, step * spb * 0.92,
                     midi_hz(chord_root - 24), "triangle", 0.30)
            b += step
        # 드럼
        if not calm:
            drum(buf, t0, "kick")
            drum(buf, t0 + 2 * spb, "kick")
            drum(buf, t0 + 1 * spb, "snare")
            drum(buf, t0 + 3 * spb, "snare")
            for e in range(8):
                drum(buf, t0 + e * 0.5 * spb, "hat")
        elif mood != "emotional":
            drum(buf, t0, "hat")
            drum(buf, t0 + 2 * spb, "hat")
        # 리드 — 스케일 랜덤워크(강백은 코드톤), 마디 길이 정확히 소진
        pos = 0.0
        degree = rng.integers(0, 7)
        while pos < 4.0 - 1e-6:
            dur = rng.choice([0.5, 0.5, 1.0, 1.0, 2.0])
            if pos + dur > 4.0:
                dur = 4.0 - pos
            if rng.random() > (0.25 if calm else 0.10):   # 쉼표 확률
                strong = abs(pos - round(pos)) < 1e-6
                if strong:
                    offsets = [0, 2, 4]
                    degree = offsets[rng.integers(0, 3)]
                else:
                    degree = (degree + int(rng.choice([-2, -1, 1, 1, 2]))) % 7
                octave = 12 if rng.random() < 0.15 else 0
                note = chord_root + scale[degree] + 12 + octave
                kind = "triangle" if calm else "square"
                add_tone(buf, t0 + pos * spb, dur * spb * 0.95,
                         midi_hz(note), kind, 0.16)
            pos += dur

    buf = buf[:total]
    peak = float(np.max(np.abs(buf))) or 1.0
    write_ogg(OUT / "bgm" / f"{track_id}.ogg", buf / peak)


TRACKS = {
    # id: (bpm, bars, key_root_midi, scale, 진행(키 상대 반음), mood)
    "bgm_title":     (100, 32, 57, MIN, [0, -4, 3, -2], "title"),
    "bgm_field":     (124, 32, 60, MAJ, [0, 7, 9, 5], "field"),
    "bgm_battle":    (150, 24, 52, MIN, [0, -2, -4, 7], "battle"),
    "bgm_boss":      (160, 42, 57, MIN, [0, 0, 8, 7], "boss"),
    "bgm_basement":  (80, 24, 50, MIN, [0, -4, 3, -2], "basement"),
    "bgm_emotional": (75, 40, 53, MAJ, [0, -4, -7, 5], "emotional"),
}


def render_all_bgm() -> None:
    (OUT / "bgm").mkdir(parents=True, exist_ok=True)
    for tid, (bpm, bars, root, scale, prog, mood) in TRACKS.items():
        render_bgm({}, tid, bpm, bars, root, scale, prog, mood)
        print(f"[make_audio] {tid}.wav ({bars} bars @ {bpm}bpm)")


def write_wav(path: Path, samples: np.ndarray) -> None:
    pcm = np.clip(samples, -1.0, 1.0)
    pcm = (pcm * 32000).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"[make_audio] {path.name} ({len(pcm)/SR:.1f}s)")


def write_ogg(path: Path, samples: np.ndarray) -> None:
    """BGM용 손실 포맷 — WAV 대비 약 1/10 크기. AudioManager가 .ogg 우선 로드.
    인코더: imageio-ffmpeg 번들 ffmpeg(pip install imageio-ffmpeg).
    참고: soundfile(libsndfile)의 vorbis 인코더는 본 환경에서 크래시하므로 사용 금지."""
    import subprocess
    import tempfile

    ffmpeg = _ffmpeg_exe()
    wav_path = path.with_suffix(".tmp.wav")
    write_wav(wav_path, samples)
    try:
        subprocess.run(
            [ffmpeg, "-y", "-loglevel", "error", "-i", str(wav_path),
             "-c:a", "libvorbis", "-q:a", "4", str(path)],
            check=True)
    finally:
        wav_path.unlink()
    print(f"[make_audio] {path.name} "
          f"({path.stat().st_size/1024:.0f}KB)")


def _ffmpeg_exe() -> str:
    from imageio_ffmpeg import get_ffmpeg_exe
    return get_ffmpeg_exe()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", choices=["sfx", "bgm"], default=None)
    args = ap.parse_args()
    if args.only in (None, "sfx"):
        render_sfx()
    if args.only in (None, "bgm"):
        render_all_bgm()
    print("[make_audio] 완료")
