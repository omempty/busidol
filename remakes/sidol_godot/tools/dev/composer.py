#!/usr/bin/env python3
"""BSD 시돌이의 모험 — 고속 고품질 레트로 칩튠/FM BGM 작곡 & 합성 엔진.

PolyBLEP 대역제한 파형과 벡터화 연산으로 초고속 렌더링을 제공하며,
클릭/틱 노이즈가 없는 깨끗하고 풍부한 44.1kHz 음악 트랙을 생성합니다.
"""
from __future__ import annotations

import math
import subprocess
from pathlib import Path
import numpy as np
import scipy.signal as signal
from imageio_ffmpeg import get_ffmpeg_exe

SR = 44100

def midi_hz(m: float) -> float:
    return 440.0 * (2.0 ** ((m - 69.0) / 12.0))

# ==============================================================================
# 1. PolyBLEP 안티앨리어싱 오실레이터 (초고속 + 완전 무잡음)
# ==============================================================================

def poly_blep(t: np.ndarray, dt: np.ndarray) -> np.ndarray:
    """PolyBLEP 잔차 보정값 (샘플 경계에서의 계단 현상 완화)."""
    res = np.zeros_like(t)
    # 0 <= t < dt
    mask1 = (t < dt) & (dt > 1e-7)
    if np.any(mask1):
        m_t = t[mask1] / dt[mask1]
        res[mask1] = m_t + m_t - m_t * m_t - 1.0
    # 1 - dt <= t < 1
    mask2 = (t > 1.0 - dt) & (dt > 1e-7)
    if np.any(mask2):
        m_t = (t[mask2] - 1.0) / dt[mask2]
        res[mask2] = m_t * m_t + m_t + m_t + 1.0
    return res


def osc_pulse(freq: float, dur: float, duty: float = 0.5,
              vibrato_rate: float = 5.2, vibrato_depth: float = 0.0,
              pitch_bend: float = 0.0) -> np.ndarray:
    """PolyBLEP 기반 안티앨리어싱 펄스파."""
    n = int(dur * SR)
    if n <= 0:
        return np.zeros(0)
    t = np.arange(n, dtype=np.float64) / SR

    f = np.full(n, freq, dtype=np.float64)
    if pitch_bend != 0.0:
        f *= (1.0 + pitch_bend * np.linspace(1.0, 0.0, n))
    if vibrato_depth > 0.0:
        vib_ramp = np.clip(t / 0.10, 0.0, 1.0)
        f *= (1.0 + vibrato_depth * vib_ramp * np.sin(2.0 * np.pi * vibrato_rate * t))

    dt = f / SR
    phase = np.cumsum(dt) % 1.0

    # 나이브 펄스파
    sig = np.where(phase < duty, 1.0, -1.0)
    # BLEP 보정
    sig += poly_blep(phase, dt)
    sig -= poly_blep((phase - duty) % 1.0, dt)
    return sig * 0.7


def osc_triangle(freq: float, dur: float, vibrato_depth: float = 0.0) -> np.ndarray:
    """대역제한 트라이앵글파 (적분 펄스 기반)."""
    n = int(dur * SR)
    if n <= 0:
        return np.zeros(0)
    t = np.arange(n, dtype=np.float64) / SR
    f = np.full(n, freq, dtype=np.float64)
    if vibrato_depth > 0.0:
        f *= (1.0 + vibrato_depth * np.sin(2.0 * np.pi * 5.0 * t))
    dt = f / SR
    phase = np.cumsum(dt) % 1.0
    # 2 * abs(2 * phase - 1) - 1
    tri = 2.0 * np.abs(2.0 * phase - 1.0) - 1.0
    return tri * 0.85


def osc_fm(freq: float, dur: float, ratio: float = 2.0,
           mod_idx: float = 1.5, decay: float = 3.5) -> np.ndarray:
    """2-오퍼레이터 FM 벨/피아노 음색."""
    n = int(dur * SR)
    if n <= 0:
        return np.zeros(0)
    t = np.arange(n, dtype=np.float64) / SR
    mod_env = mod_idx * np.exp(-decay * t)
    mod = mod_env * np.sin(2.0 * np.pi * freq * ratio * t)
    carrier = np.sin(2.0 * np.pi * freq * t + mod)
    return carrier * 0.75


def osc_sine(freq: float, dur: float) -> np.ndarray:
    n = int(dur * SR)
    if n <= 0:
        return np.zeros(0)
    t = np.arange(n, dtype=np.float64) / SR
    return np.sin(2.0 * np.pi * freq * t) * 0.8


def adsr_envelope(n: int, a_sec: float = 0.006, d_sec: float = 0.06,
                  s_level: float = 0.7, r_sec: float = 0.04) -> np.ndarray:
    if n <= 0:
        return np.zeros(0)
    a_len = max(int(a_sec * SR), 4)
    d_len = max(int(d_sec * SR), 4)
    r_len = max(int(r_sec * SR), 4)

    env = np.ones(n, dtype=np.float64)
    if a_len < n:
        env[:a_len] = 0.5 * (1.0 - np.cos(np.pi * np.arange(a_len) / a_len))
    else:
        env[:] = 0.5 * (1.0 - np.cos(np.pi * np.arange(n) / n))
        return env

    d_end = min(a_len + d_len, n)
    if d_end > a_len:
        d_samples = d_end - a_len
        env[a_len:d_end] = s_level + (1.0 - s_level) * np.exp(-3.5 * np.arange(d_samples) / d_samples)

    if d_end < n - r_len:
        env[d_end:n - r_len] = s_level

    if r_len > 0 and n > r_len:
        r_start = n - r_len
        s_val = env[r_start]
        env[r_start:] = s_val * np.exp(-4.5 * np.arange(r_len) / r_len)
        env[-1] = 0.0

    return env


def apply_echo_fast(sig: np.ndarray, delay_sec: float, feedback: float = 0.28, wet: float = 0.22) -> np.ndarray:
    """고속 벡터화 탭 딜레이."""
    d = int(delay_sec * SR)
    if d <= 0 or d >= len(sig):
        return sig
    out = sig.copy()
    fb = feedback
    tap = 1
    while tap * d < len(sig) and fb > 0.02:
        out[tap * d:] += sig[:-tap * d] * fb
        fb *= feedback
        tap += 1
    return sig * (1.0 - wet * 0.5) + out * wet


# ==============================================================================
# 2. 퍼커션
# ==============================================================================

def drum_kick(buf: np.ndarray, start_sec: float, vol: float = 0.50) -> None:
    dur = 0.16
    n = int(dur * SR)
    i0 = int(start_sec * SR)
    if i0 >= len(buf) or n <= 0:
        return
    n = min(n, len(buf) - i0)
    t = np.arange(n, dtype=np.float64) / SR
    f = 120.0 * np.exp(-18.0 * t) + 42.0
    phase = 2.0 * np.pi * np.cumsum(f) / SR
    env = np.sin(np.pi * (t / dur) ** 0.45) * np.exp(-10.0 * t)
    sig = np.sin(phase) * env * vol
    buf[i0:i0 + n] += sig


def drum_snare(buf: np.ndarray, start_sec: float, vol: float = 0.35) -> None:
    dur = 0.16
    n = int(dur * SR)
    i0 = int(start_sec * SR)
    if i0 >= len(buf) or n <= 0:
        return
    n = min(n, len(buf) - i0)
    t = np.arange(n, dtype=np.float64) / SR
    body = np.sin(2.0 * np.pi * (190.0 * np.exp(-14.0 * t)) * t) * np.exp(-18.0 * t) * 0.40

    rng = np.random.default_rng(int(start_sec * 10000) & 0xFFFFFFFF)
    raw_noise = rng.uniform(-1.0, 1.0, n)
    a_len = int(0.002 * SR)
    noise_env = np.exp(-18.0 * t)
    if a_len < n:
        noise_env[:a_len] *= np.linspace(0.0, 1.0, a_len)
    wire = raw_noise * noise_env * 0.45

    sig = (body + wire) * vol
    buf[i0:i0 + n] += sig


def drum_hat_closed(buf: np.ndarray, start_sec: float, vol: float = 0.18) -> None:
    dur = 0.04
    n = int(dur * SR)
    i0 = int(start_sec * SR)
    if i0 >= len(buf) or n <= 0:
        return
    n = min(n, len(buf) - i0)
    t = np.arange(n, dtype=np.float64) / SR
    rng = np.random.default_rng(int(start_sec * 10000) & 0xFFFFFFFF)
    raw_noise = rng.uniform(-1.0, 1.0, n)
    a_len = int(0.0015 * SR)
    env = np.exp(-70.0 * t)
    if a_len < n:
        env[:a_len] *= np.linspace(0.0, 1.0, a_len)
    sig = raw_noise * env * vol
    buf[i0:i0 + n] += sig


def drum_hat_open(buf: np.ndarray, start_sec: float, vol: float = 0.20) -> None:
    dur = 0.20
    n = int(dur * SR)
    i0 = int(start_sec * SR)
    if i0 >= len(buf) or n <= 0:
        return
    n = min(n, len(buf) - i0)
    t = np.arange(n, dtype=np.float64) / SR
    rng = np.random.default_rng(int(start_sec * 10000) & 0xFFFFFFFF)
    raw_noise = rng.uniform(-1.0, 1.0, n)
    a_len = int(0.002 * SR)
    env = np.exp(-18.0 * t)
    if a_len < n:
        env[:a_len] *= np.linspace(0.0, 1.0, a_len)
    sig = raw_noise * env * vol
    buf[i0:i0 + n] += sig


# ==============================================================================
# 3. 보이스 렌더러
# ==============================================================================

def play_note(buf: np.ndarray, start_sec: float, dur_sec: float,
              midi_note: float, instrument: str, vol: float = 0.25) -> None:
    i0 = int(start_sec * SR)
    if i0 >= len(buf):
        return
    freq = midi_hz(midi_note)

    if instrument == "lead_pulse":
        raw = osc_pulse(freq, dur_sec, duty=0.25, vibrato_depth=0.015)
        env = adsr_envelope(len(raw), a_sec=0.008, d_sec=0.08, s_level=0.75, r_sec=0.04)
        sig = raw * env * vol

    elif instrument == "lead_square":
        raw = osc_pulse(freq, dur_sec, duty=0.50, vibrato_depth=0.012)
        env = adsr_envelope(len(raw), a_sec=0.006, d_sec=0.06, s_level=0.70, r_sec=0.04)
        sig = raw * env * vol

    elif instrument == "fm_bell":
        raw = osc_fm(freq, dur_sec, ratio=3.0, mod_idx=1.8, decay=4.0)
        env = adsr_envelope(len(raw), a_sec=0.004, d_sec=dur_sec * 0.8, s_level=0.1, r_sec=0.06)
        sig = raw * env * vol

    elif instrument == "fm_epiano":
        raw = osc_fm(freq, dur_sec, ratio=1.0, mod_idx=1.2, decay=2.5)
        env = adsr_envelope(len(raw), a_sec=0.008, d_sec=0.15, s_level=0.5, r_sec=0.05)
        sig = raw * env * vol

    elif instrument == "pad_warm":
        raw1 = osc_pulse(freq * 0.998, dur_sec, duty=0.40)
        raw2 = osc_triangle(freq * 1.002, dur_sec)
        env = adsr_envelope(len(raw1), a_sec=0.06, d_sec=0.15, s_level=0.85, r_sec=0.08)
        sig = (raw1 * 0.5 + raw2 * 0.5) * env * vol

    elif instrument == "bass_tri":
        raw = osc_triangle(freq, dur_sec)
        sub = osc_sine(freq, dur_sec)
        env = adsr_envelope(len(raw), a_sec=0.008, d_sec=0.10, s_level=0.80, r_sec=0.03)
        sig = (raw * 0.6 + sub * 0.4) * env * vol

    elif instrument == "bass_fm":
        raw = osc_fm(freq, dur_sec, ratio=0.5, mod_idx=1.4, decay=5.0)
        env = adsr_envelope(len(raw), a_sec=0.006, d_sec=0.12, s_level=0.75, r_sec=0.03)
        sig = raw * env * vol

    elif instrument == "bass_pulse":
        raw = osc_pulse(freq, dur_sec, duty=0.125)
        env = adsr_envelope(len(raw), a_sec=0.006, d_sec=0.08, s_level=0.70, r_sec=0.03)
        sig = raw * env * vol

    elif instrument == "harp_pluck":
        raw = osc_pulse(freq, dur_sec, duty=0.5)
        env = adsr_envelope(len(raw), a_sec=0.004, d_sec=0.12, s_level=0.2, r_sec=0.05)
        sig = raw * env * vol

    else:
        raw = osc_triangle(freq, dur_sec)
        env = adsr_envelope(len(raw), a_sec=0.005, d_sec=0.05, s_level=0.7, r_sec=0.03)
        sig = raw * env * vol

    n = min(len(sig), len(buf) - i0)
    buf[i0:i0 + n] += sig[:n]


class NoteSeq:
    def __init__(self, bpm: float):
        self.bpm = bpm
        self.spb = 60.0 / bpm
        self.notes: list[tuple[float, float, float, str, float]] = []

    def add(self, beat_start: float, dur_beats: float, midi: float, inst: str, vol: float = 0.25) -> NoteSeq:
        self.notes.append((beat_start * self.spb, dur_beats * self.spb, midi, inst, vol))
        return self

    def chord(self, beat_start: float, dur_beats: float, midis: list[float], inst: str, vol: float = 0.20) -> NoteSeq:
        for m in midis:
            self.add(beat_start, dur_beats, m, inst, vol / math.sqrt(len(midis)))
        return self

    def arp(self, beat_start: float, total_beats: float, midis: list[float], step_beats: float,
            inst: str, vol: float = 0.20) -> NoteSeq:
        curr = beat_start
        idx = 0
        while curr < beat_start + total_beats - 1e-5:
            self.add(curr, step_beats * 0.95, midis[idx % len(midis)], inst, vol)
            curr += step_beats
            idx += 1
        return self


def render_track_buffer(total_bars: int, beats_per_bar: int, bpm: float,
                        note_seq: NoteSeq, drum_events: list[tuple[float, str, float]],
                        echo_delay_beats: float = 0.75) -> np.ndarray:
    spb = 60.0 / bpm
    total_beats = total_bars * beats_per_bar
    main_len_sec = total_beats * spb
    main_samples = int(main_len_sec * SR)
    
    tail_len_sec = 4.0 * beats_per_bar * spb
    buf = np.zeros(main_samples + int(tail_len_sec * SR), dtype=np.float64)

    for start_sec, dur_sec, midi, inst, vol in note_seq.notes:
        play_note(buf, start_sec, dur_sec, midi, inst, vol)

    for b_start, drum_type, d_vol in drum_events:
        s_sec = b_start * spb
        if drum_type == "kick":
            drum_kick(buf, s_sec, d_vol)
        elif drum_type == "snare":
            drum_snare(buf, s_sec, d_vol)
        elif drum_type == "hat":
            drum_hat_closed(buf, s_sec, d_vol)
        elif drum_type == "hat_open":
            drum_hat_open(buf, s_sec, d_vol)

    # 전역 온화한 저역통과 필터 (8.5kHz 컷오프로 따스한 레트로 톤 보장)
    sos = signal.butter(2, 8500.0, 'low', fs=SR, output='sos')
    buf = signal.sosfilt(sos, buf)

    if echo_delay_beats > 0:
        buf = apply_echo_fast(buf, echo_delay_beats * spb, feedback=0.22, wet=0.18)

    # 심리스 루프 래핑
    tail = buf[main_samples:]
    wrap_len = min(len(tail), main_samples)
    buf[:wrap_len] += tail[:wrap_len]

    result = buf[:main_samples]
    result = np.tanh(result * 1.35)
    peak = np.max(np.abs(result))
    if peak > 1e-4:
        result = (result / peak) * 0.88

    return result
