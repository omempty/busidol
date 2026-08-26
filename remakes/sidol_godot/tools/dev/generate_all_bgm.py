#!/usr/bin/env python3
"""BSD 시돌이의 모험 — 고품질 BGM 6곡 작곡 및 렌더러.

원작 및 리메이크 마스터 시나리오 톤에 완벽하게 일치하는 6곡을
노이즈/클릭 없이 정교하게 작곡하여 44.1kHz 심리스 루프 OGG 파일로 출력합니다.
"""
from __future__ import annotations

import math
import subprocess
import wave
from pathlib import Path
import numpy as np
from imageio_ffmpeg import get_ffmpeg_exe

from composer import (
    SR, NoteSeq, render_track_buffer
)

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "audio" / "bgm"


# ==============================================================================
# 트랙 1: bgm_title — "1995년 부싯돌의 아침" (D minor, 102 BPM, 32마디)
# ==============================================================================
def compose_title() -> np.ndarray:
    bpm = 102.0
    total_bars = 32
    seq = NoteSeq(bpm)
    drums: list[tuple[float, str, float]] = []

    # 1) 화음 진행 (마디별)
    # 0..7 (Intro): Dm9 -> Bbmaj7 -> Gm9 -> Asus4 -> Dm9 -> Bbmaj7 -> Em7b5 -> A7
    # 8..23 (A): Dm -> Bb -> C -> F -> Gm -> Dm -> Bb -> A7 (x2)
    # 24..31 (B): F -> C -> Dm -> Bb -> Gm -> Dm -> Bb -> A7
    chords_intro = [
        [62, 65, 69, 72],  # Dm9
        [58, 62, 65, 69],  # Bbmaj7
        [55, 58, 62, 65],  # Gm7
        [57, 62, 64, 69],  # Asus4
        [62, 65, 69, 72],  # Dm9
        [58, 62, 65, 69],  # Bbmaj7
        [52, 55, 58, 62],  # Em7b5
        [57, 61, 64, 69],  # A7
    ]
    chords_a = [
        [50, 57, 62, 65],  # Dm
        [46, 53, 58, 62],  # Bb
        [48, 55, 60, 64],  # C
        [53, 57, 60, 65],  # F
        [43, 50, 55, 58],  # Gm
        [50, 57, 62, 65],  # Dm
        [46, 53, 58, 62],  # Bb
        [45, 52, 57, 61],  # A7
    ] * 2
    chords_b = [
        [53, 57, 60, 65],  # F
        [48, 55, 60, 64],  # C
        [50, 57, 62, 65],  # Dm
        [46, 53, 58, 62],  # Bb
        [43, 50, 55, 58],  # Gm
        [50, 57, 62, 65],  # Dm
        [46, 53, 58, 62],  # Bb
        [45, 52, 57, 61],  # A7
    ]

    all_chords = chords_intro + chords_a + chords_b

    # 패드 & 아르페지오 렌더
    for bar_idx, ch in enumerate(all_chords):
        b0 = bar_idx * 4.0
        # 부드러운 패드
        seq.chord(b0, 4.0, ch, "pad_warm", vol=0.18)
        # FM 벨/플럭 아르페지오 (16분음표 롤링)
        seq.arp(b0, 4.0, [n + 12 for n in ch] + [ch[-1] + 19], 0.25, "fm_epiano", vol=0.12)

    # 2) 베이스라인
    bass_roots = [
        50, 46, 43, 45, 50, 46, 40, 45,  # Intro
        50, 46, 48, 53, 43, 50, 46, 45,  # A1
        50, 46, 48, 53, 43, 50, 46, 45,  # A2
        53, 48, 50, 46, 43, 50, 46, 45,  # B
    ]
    for bar_idx, root in enumerate(bass_roots):
        b0 = bar_idx * 4.0
        if bar_idx < 8:
            seq.add(b0, 3.8, root - 12, "bass_tri", vol=0.28)
        else:
            # 워킹/싱코페이션 베이스
            seq.add(b0, 1.4, root - 12, "bass_tri", vol=0.30)
            seq.add(b0 + 1.5, 0.9, root - 12, "bass_tri", vol=0.22)
            seq.add(b0 + 2.5, 1.3, root - 5, "bass_tri", vol=0.24)

    # 3) 멜로디 (Section A & B)
    # A1 (bars 8..15)
    m_a1 = [
        # bar 8 (Dm)
        (8.0, 1.5, 69), (9.5, 0.5, 72), (10.0, 1.0, 74), (11.0, 1.0, 72),
        # bar 9 (Bb)
        (12.0, 2.0, 69), (14.0, 1.0, 65), (15.0, 1.0, 67),
        # bar 10 (C)
        (16.0, 1.5, 67), (17.5, 0.5, 69), (18.0, 1.0, 72), (19.0, 1.0, 69),
        # bar 11 (F)
        (20.0, 3.0, 65), (23.0, 1.0, 67),
        # bar 12 (Gm)
        (24.0, 1.5, 67), (25.5, 0.5, 69), (26.0, 1.0, 70), (27.0, 1.0, 72),
        # bar 13 (Dm)
        (28.0, 2.0, 69), (30.0, 1.0, 65), (31.0, 1.0, 62),
        # bar 14 (Bb)
        (32.0, 2.0, 65), (34.0, 2.0, 64),
        # bar 15 (A7)
        (36.0, 4.0, 61),
    ]
    # A2 (bars 16..23) - 옥타브 고음 & 변주
    m_a2 = [
        (40.0, 1.5, 81), (41.5, 0.5, 84), (42.0, 1.0, 86), (43.0, 1.0, 84),
        (44.0, 2.0, 81), (46.0, 1.0, 77), (47.0, 1.0, 79),
        (48.0, 1.5, 79), (49.5, 0.5, 81), (50.0, 1.0, 84), (51.0, 1.0, 81),
        (52.0, 3.0, 77), (55.0, 1.0, 79),
        (56.0, 1.5, 79), (57.5, 0.5, 81), (58.0, 1.0, 82), (59.0, 1.0, 84),
        (60.0, 2.0, 81), (62.0, 1.0, 77), (63.0, 1.0, 74),
        (64.0, 2.0, 76), (66.0, 2.0, 73),
        (68.0, 4.0, 74),
    ]
    # B (bars 24..31) - 서정적 클라이맥스
    m_b = [
        (96.0, 1.5, 77), (97.5, 0.5, 79), (98.0, 1.5, 81), (99.5, 0.5, 84),
        (100.0, 2.0, 84), (102.0, 1.0, 81), (103.0, 1.0, 79),
        (104.0, 1.5, 81), (105.5, 0.5, 86), (106.0, 2.0, 86),
        (108.0, 2.0, 82), (110.0, 1.0, 81), (111.0, 1.0, 79),
        (112.0, 1.5, 79), (113.5, 0.5, 81), (114.0, 1.0, 82), (115.0, 1.0, 84),
        (116.0, 2.0, 81), (118.0, 1.0, 77), (119.0, 1.0, 74),
        (120.0, 2.0, 77), (122.0, 2.0, 76),
        (124.0, 4.0, 74),
    ]

    for b_start, dur, note in m_a1 + m_a2 + m_b:
        seq.add(b_start, dur * 0.95, note, "lead_pulse", vol=0.26)
        # 3도 하모니 라인 (은은하게)
        seq.add(b_start, dur * 0.95, note - 4, "fm_bell", vol=0.08)

    # 4) 드럼 (부드럽고 절제된 레트로 비트)
    for bar_idx in range(8, total_bars):
        b0 = bar_idx * 4.0
        drums.append((b0, "kick", 0.42))
        drums.append((b0 + 2.0, "kick", 0.38))
        drums.append((b0 + 1.0, "snare", 0.28))
        drums.append((b0 + 3.0, "snare", 0.28))
        for step in range(8):
            drums.append((b0 + step * 0.5, "hat", 0.12))

    return render_track_buffer(total_bars, 4, bpm, seq, drums, echo_delay_beats=0.75)


# ==============================================================================
# 트랙 2: bgm_field — "동아리방과 복도" (G major, 124 BPM, 32마디)
# ==============================================================================
def compose_field() -> np.ndarray:
    bpm = 124.0
    total_bars = 32
    seq = NoteSeq(bpm)
    drums: list[tuple[float, str, float]] = []

    # 화성 진행
    # A (bars 0..15): G -> D/F# -> Em -> Bm -> C -> G/B -> Am7 -> D7 (x2)
    # B (bars 16..27): Em -> C -> D -> G -> Em -> Am -> B7 -> B7 -> Em -> C -> Am7 -> D7
    # Outro (bars 28..31): G -> C -> G -> D7
    chords_a_unit = [
        [55, 59, 62, 67],  # G
        [54, 57, 62, 66],  # D/F#
        [52, 55, 59, 64],  # Em
        [47, 54, 59, 62],  # Bm
        [48, 55, 60, 64],  # C
        [47, 55, 59, 62],  # G/B
        [45, 52, 57, 60],  # Am7
        [50, 57, 60, 64],  # D7
    ]
    chords_b = [
        [52, 55, 59, 64],  # Em
        [48, 55, 60, 64],  # C
        [50, 57, 62, 66],  # D
        [55, 59, 62, 67],  # G
        [52, 55, 59, 64],  # Em
        [45, 52, 57, 60],  # Am
        [47, 54, 59, 63],  # B7
        [47, 54, 59, 63],  # B7
        [52, 55, 59, 64],  # Em
        [48, 55, 60, 64],  # C
        [45, 52, 57, 60],  # Am7
        [50, 57, 60, 64],  # D7
    ]
    chords_outro = [
        [55, 59, 62, 67],  # G
        [48, 55, 60, 64],  # C
        [55, 59, 62, 67],  # G
        [50, 57, 60, 64],  # D7
    ]

    all_chords = chords_a_unit + chords_a_unit + chords_b + chords_outro

    for bar_idx, ch in enumerate(all_chords):
        b0 = bar_idx * 4.0
        # 경쾌한 오프비트 스타카토 코드
        seq.chord(b0 + 0.5, 0.4, ch, "harp_pluck", vol=0.15)
        seq.chord(b0 + 1.5, 0.4, ch, "harp_pluck", vol=0.15)
        seq.chord(b0 + 2.5, 0.4, ch, "harp_pluck", vol=0.15)
        seq.chord(b0 + 3.5, 0.4, ch, "harp_pluck", vol=0.15)
        # 패드
        seq.chord(b0, 4.0, ch, "pad_warm", vol=0.12)

    # 베이스라인 (통통 튀는 펑키 레트로 베이스)
    bass_roots = [
        55, 54, 52, 47, 48, 47, 45, 50,  # A1
        55, 54, 52, 47, 48, 47, 45, 50,  # A2
        52, 48, 50, 55, 52, 45, 47, 47,  # B
        52, 48, 45, 50, 55, 48, 55, 50   # B tail & outro
    ]
    for bar_idx, r in enumerate(bass_roots):
        b0 = bar_idx * 4.0
        seq.add(b0, 0.8, r - 12, "bass_pulse", vol=0.28)
        seq.add(b0 + 1.0, 0.4, r - 12, "bass_pulse", vol=0.22)
        seq.add(b0 + 1.5, 0.4, r - 12, "bass_pulse", vol=0.22)
        seq.add(b0 + 2.0, 0.8, r - 5, "bass_pulse", vol=0.26)
        seq.add(b0 + 3.0, 0.8, r - 12, "bass_pulse", vol=0.24)

    # 경쾌한 메인 멜로디 (Square Lead)
    # A1 (bars 0..7)
    m_a1 = [
        (0.0, 0.75, 71), (0.75, 0.25, 74), (1.0, 1.0, 79), (2.0, 1.0, 78), (3.0, 1.0, 76),
        (4.0, 2.0, 74), (6.0, 1.0, 71), (7.0, 1.0, 74),
        (8.0, 0.75, 76), (8.75, 0.25, 74), (9.0, 1.0, 72), (10.0, 1.0, 71),
        (12.0, 2.0, 69), (14.0, 2.0, 71),
        (16.0, 0.75, 72), (16.75, 0.25, 74), (17.0, 1.0, 76), (18.0, 1.0, 74),
        (20.0, 2.0, 71), (22.0, 1.0, 74), (23.0, 1.0, 71),
        (24.0, 1.5, 69), (25.5, 0.5, 71), (26.0, 1.0, 72), (27.0, 1.0, 74),
        (28.0, 3.0, 71), (31.0, 1.0, 74),
    ]
    # A2 (bars 8..15) - 옥타브 도약
    m_a2 = [
        (32.0, 0.75, 83), (32.75, 0.25, 86), (33.0, 1.0, 91), (34.0, 1.0, 90), (35.0, 1.0, 88),
        (36.0, 2.0, 86), (38.0, 1.0, 83), (39.0, 1.0, 86),
        (40.0, 0.75, 88), (40.75, 0.25, 86), (41.0, 1.0, 84), (42.0, 1.0, 83),
        (44.0, 2.0, 81), (46.0, 2.0, 83),
        (48.0, 0.75, 84), (48.75, 0.25, 86), (49.0, 1.0, 88), (50.0, 1.0, 86),
        (52.0, 2.0, 83), (54.0, 1.0, 86), (55.0, 1.0, 83),
        (56.0, 1.5, 81), (57.5, 0.5, 83), (58.0, 1.0, 84), (59.0, 1.0, 86),
        (60.0, 4.0, 83),
    ]
    # B (bars 16..27)
    m_b = [
        (64.0, 1.5, 76), (65.5, 0.5, 79), (66.0, 1.0, 83), (67.0, 1.0, 81),
        (68.0, 2.0, 79), (70.0, 1.0, 76), (71.0, 1.0, 79),
        (72.0, 1.5, 81), (73.5, 0.5, 83), (74.0, 1.0, 86), (75.0, 1.0, 83),
        (76.0, 4.0, 79),
        (80.0, 1.5, 76), (81.5, 0.5, 79), (82.0, 1.0, 81), (83.0, 1.0, 83),
        (84.0, 2.0, 81), (86.0, 1.0, 77), (87.0, 1.0, 76),
        (88.0, 4.0, 75),
        (92.0, 4.0, 76),
        (96.0, 1.5, 76), (97.5, 0.5, 79), (98.0, 1.0, 83), (99.0, 1.0, 81),
        (100.0, 2.0, 79), (102.0, 1.0, 84), (103.0, 1.0, 83),
        (104.0, 2.0, 81), (106.0, 2.0, 86),
        (108.0, 4.0, 83),
    ]

    for b_start, dur, note in m_a1 + m_a2 + m_b:
        seq.add(b_start, dur * 0.92, note, "lead_square", vol=0.26)
        seq.add(b_start, dur * 0.92, note - 12, "lead_pulse", vol=0.12)

    # 드럼 비트 (경쾌한 16비트 햇과 스네어 롤)
    for bar_idx in range(total_bars):
        b0 = bar_idx * 4.0
        drums.append((b0, "kick", 0.45))
        drums.append((b0 + 2.0, "kick", 0.40))
        drums.append((b0 + 1.0, "snare", 0.32))
        drums.append((b0 + 3.0, "snare", 0.32))
        for step in range(8):
            drums.append((b0 + step * 0.5, "hat", 0.14))
        # 오프비트 오픈 하이햇
        drums.append((b0 + 1.5, "hat_open", 0.18))
        drums.append((b0 + 3.5, "hat_open", 0.18))

    return render_track_buffer(total_bars, 4, bpm, seq, drums, echo_delay_beats=0.5)


# ==============================================================================
# 트랙 3: bgm_battle — "조우! 격돌" (E minor, 150 BPM, 28마디)
# ==============================================================================
def compose_battle() -> np.ndarray:
    bpm = 150.0
    total_bars = 28
    seq = NoteSeq(bpm)
    drums: list[tuple[float, str, float]] = []

    # 화성 진행
    # 0..3 (Intro): Em -> Em -> Em -> B7
    # 4..19 (A): Em -> C -> D -> Bm -> Em -> C -> D -> B7 (x2)
    # 20..27 (B): C -> D -> Em -> G -> C -> D -> B7 -> B7
    chords_intro = [
        [52, 55, 59, 64], [52, 55, 59, 64], [52, 55, 59, 64], [47, 54, 59, 63]
    ]
    chords_a = [
        [52, 55, 59, 64], [48, 55, 60, 64], [50, 57, 62, 66], [47, 54, 59, 62],
        [52, 55, 59, 64], [48, 55, 60, 64], [50, 57, 62, 66], [47, 54, 59, 63],
    ] * 2
    chords_b = [
        [48, 55, 60, 64], [50, 57, 62, 66], [52, 55, 59, 64], [55, 59, 62, 67],
        [48, 55, 60, 64], [50, 57, 62, 66], [47, 54, 59, 63], [47, 54, 59, 63],
    ]
    all_chords = chords_intro + chords_a + chords_b

    # 고속 16분음표 아르페지오 (전투 드라이브감)
    for bar_idx, ch in enumerate(all_chords):
        b0 = bar_idx * 4.0
        seq.arp(b0, 4.0, [n + 12 for n in ch] + [ch[-1] + 19, ch[1] + 12], 0.25, "harp_pluck", vol=0.15)
        seq.chord(b0, 4.0, ch, "pad_warm", vol=0.10)

    # 갤로핑 전투 베이스라인 (E-E-E-E E-E-E-E...)
    bass_roots = [
        52, 52, 52, 47,
        52, 48, 50, 47, 52, 48, 50, 47,
        52, 48, 50, 47, 52, 48, 50, 47,
        48, 50, 52, 55, 48, 50, 47, 47
    ]
    for bar_idx, r in enumerate(bass_roots):
        b0 = bar_idx * 4.0
        for step in range(8):
            note = (r - 12) if step % 2 == 0 else (r - 0)
            seq.add(b0 + step * 0.5, 0.42, note, "bass_pulse", vol=0.30)

    # 긴박하고 영웅적인 배틀 리드 멜로디
    m_battle = [
        # Intro (bars 0..3)
        (0.0, 0.5, 64), (0.5, 0.5, 67), (1.0, 0.5, 71), (1.5, 0.5, 76),
        (2.0, 1.0, 79), (3.0, 1.0, 78),
        (4.0, 0.5, 64), (4.5, 0.5, 67), (5.0, 0.5, 71), (5.5, 0.5, 76),
        (6.0, 1.0, 79), (7.0, 1.0, 83),
        (8.0, 0.5, 83), (8.5, 0.5, 81), (9.0, 0.5, 79), (9.5, 0.5, 78),
        (10.0, 0.5, 76), (10.5, 0.5, 74), (11.0, 0.5, 72), (11.5, 0.5, 71),
        (12.0, 4.0, 71),

        # Section A (bars 4..11)
        (16.0, 1.0, 76), (17.0, 1.0, 79), (18.0, 1.5, 83), (19.5, 0.5, 81),
        (20.0, 2.0, 79), (22.0, 1.0, 76), (23.0, 1.0, 79),
        (24.0, 1.0, 81), (25.0, 1.0, 83), (26.0, 1.5, 86), (27.5, 0.5, 84),
        (28.0, 4.0, 83),
        (32.0, 1.0, 88), (33.0, 1.0, 86), (34.0, 1.0, 84), (35.0, 1.0, 83),
        (36.0, 2.0, 84), (38.0, 1.0, 81), (39.0, 1.0, 79),
        (40.0, 1.5, 78), (41.5, 0.5, 79), (42.0, 1.0, 81), (43.0, 1.0, 79),
        (44.0, 4.0, 76),

        # Section B (bars 20..27)
        (80.0, 1.5, 84), (81.5, 0.5, 86), (82.0, 1.0, 88), (83.0, 1.0, 91),
        (84.0, 2.0, 86), (86.0, 1.0, 83), (87.0, 1.0, 86),
        (88.0, 2.0, 88), (90.0, 2.0, 91),
        (92.0, 4.0, 95),
        (96.0, 1.5, 84), (97.5, 0.5, 86), (98.0, 1.0, 88), (99.0, 1.0, 86),
        (100.0, 2.0, 83), (102.0, 2.0, 81),
        (104.0, 4.0, 83),
        (108.0, 4.0, 76),
    ]

    for b_start, dur, note in m_battle:
        seq.add(b_start, dur * 0.90, note, "lead_pulse", vol=0.28)
        seq.add(b_start, dur * 0.90, note - 12, "lead_square", vol=0.18)

    # 드럼 (고속 포온더플로어 + 펀치 스네어)
    for bar_idx in range(total_bars):
        b0 = bar_idx * 4.0
        drums.append((b0, "kick", 0.48))
        drums.append((b0 + 1.0, "kick", 0.42))
        drums.append((b0 + 2.0, "kick", 0.48))
        drums.append((b0 + 3.0, "kick", 0.42))
        drums.append((b0 + 1.0, "snare", 0.35))
        drums.append((b0 + 3.0, "snare", 0.35))
        for step in range(8):
            drums.append((b0 + step * 0.5, "hat", 0.15))
        drums.append((b0 + 3.5, "hat_open", 0.20))

    return render_track_buffer(total_bars, 4, bpm, seq, drums, echo_delay_beats=0.375)


# ==============================================================================
# 트랙 4: bgm_boss — "시스템 빌더의 미궁" (D minor / Phrygian, 160 BPM, 32마디)
# ==============================================================================
def compose_boss() -> np.ndarray:
    bpm = 160.0
    total_bars = 32
    seq = NoteSeq(bpm)
    drums: list[tuple[float, str, float]] = []

    # 불길하고 기계적인 오스티나토 화성
    # 0..7 (Intro): Dm -> D#dim -> Dm -> D#dim -> Dm -> Gm -> Edim -> A7
    # 8..23 (A): Dm -> Dm -> Gm -> A7 -> Dm -> Bb -> Edim -> A7 (x2)
    # 24..31 (B): Dm -> F -> Gm -> A7 -> Bb -> C -> Dm -> A7
    chords_intro = [
        [50, 53, 57, 62], [51, 54, 57, 63], [50, 53, 57, 62], [51, 54, 57, 63],
        [50, 53, 57, 62], [43, 50, 55, 58], [40, 46, 52, 55], [45, 52, 57, 61],
    ]
    chords_a = [
        [50, 53, 57, 62], [50, 53, 57, 62], [43, 50, 55, 58], [45, 52, 57, 61],
        [50, 53, 57, 62], [46, 53, 58, 62], [40, 46, 52, 55], [45, 52, 57, 61],
    ] * 2
    chords_b = [
        [50, 53, 57, 62], [53, 57, 60, 65], [43, 50, 55, 58], [45, 52, 57, 61],
        [46, 53, 58, 62], [48, 55, 60, 64], [50, 53, 57, 62], [45, 52, 57, 61],
    ]
    all_chords = chords_intro + chords_a + chords_b

    # 기계적 인더스트리얼 신스 펄스
    for bar_idx, ch in enumerate(all_chords):
        b0 = bar_idx * 4.0
        seq.arp(b0, 4.0, [n + 12 for n in ch] + [ch[0] + 24, ch[2] + 12], 0.25, "fm_bell", vol=0.15)
        seq.chord(b0, 4.0, ch, "pad_warm", vol=0.12)

    # 헤비 인더스트리얼 베이스
    bass_roots = [
        50, 51, 50, 51, 50, 43, 40, 45,
        50, 50, 43, 45, 50, 46, 40, 45,
        50, 50, 43, 45, 50, 46, 40, 45,
        50, 53, 43, 45, 46, 48, 50, 45
    ]
    for bar_idx, r in enumerate(bass_roots):
        b0 = bar_idx * 4.0
        for step in range(8):
            seq.add(b0 + step * 0.5, 0.40, r - 12, "bass_fm", vol=0.32)

    # 보스전 위압적 리드 테마
    m_boss = [
        # Intro (bars 0..7)
        (0.0, 0.75, 62), (0.75, 0.25, 63), (1.0, 1.0, 62), (2.0, 1.0, 65), (3.0, 1.0, 63),
        (4.0, 0.75, 62), (4.75, 0.25, 63), (5.0, 1.0, 62), (6.0, 2.0, 68),
        (8.0, 0.75, 62), (8.75, 0.25, 63), (9.0, 1.0, 62), (10.0, 1.0, 65), (11.0, 1.0, 63),
        (12.0, 2.0, 62), (14.0, 2.0, 61),

        # Section A (bars 8..15)
        (32.0, 1.5, 74), (33.5, 0.5, 75), (34.0, 1.0, 74), (35.0, 1.0, 77),
        (36.0, 2.0, 75), (38.0, 1.0, 74), (39.0, 1.0, 72),
        (40.0, 1.5, 70), (41.5, 0.5, 72), (42.0, 1.0, 74), (43.0, 1.0, 75),
        (44.0, 4.0, 73),
        (48.0, 1.5, 74), (49.5, 0.5, 77), (50.0, 1.0, 81), (51.0, 1.0, 79),
        (52.0, 2.0, 77), (54.0, 1.0, 75), (55.0, 1.0, 74),
        (56.0, 2.0, 72), (58.0, 2.0, 73),
        (60.0, 4.0, 74),

        # Section B (bars 24..31)
        (96.0, 1.0, 86), (97.0, 1.0, 84), (98.0, 1.0, 86), (99.0, 1.0, 89),
        (100.0, 2.0, 86), (102.0, 2.0, 84),
        (104.0, 1.5, 82), (105.5, 0.5, 84), (106.0, 1.0, 86), (107.0, 1.0, 84),
        (108.0, 4.0, 81),
        (112.0, 1.5, 82), (113.5, 0.5, 84), (114.0, 1.0, 86), (115.0, 1.0, 89),
        (116.0, 2.0, 88), (118.0, 2.0, 86),
        (120.0, 4.0, 86),
        (124.0, 4.0, 73),
    ]

    for b_start, dur, note in m_boss:
        seq.add(b_start, dur * 0.90, note, "lead_pulse", vol=0.30)
        seq.add(b_start, dur * 0.90, note - 12, "lead_square", vol=0.20)

    # 드럼 (헤비 킥 & 스네어)
    for bar_idx in range(total_bars):
        b0 = bar_idx * 4.0
        drums.append((b0, "kick", 0.50))
        drums.append((b0 + 1.5, "kick", 0.44))
        drums.append((b0 + 2.0, "kick", 0.48))
        drums.append((b0 + 1.0, "snare", 0.36))
        drums.append((b0 + 3.0, "snare", 0.36))
        for step in range(8):
            drums.append((b0 + step * 0.5, "hat", 0.15))

    return render_track_buffer(total_bars, 4, bpm, seq, drums, echo_delay_beats=0.375)


# ==============================================================================
# 트랙 5: bgm_basement — "먼지 쌓인 80년대 서고" (C minor, 80 BPM, 24마디)
# ==============================================================================
def compose_basement() -> np.ndarray:
    bpm = 80.0
    total_bars = 24
    seq = NoteSeq(bpm)
    drums: list[tuple[float, str, float]] = []

    # 신비롭고 어두운 화성 (Cm9, Abmaj7, Fm9, G7b9)
    chords = [
        [48, 51, 55, 58, 62],  # Cm9
        [44, 48, 51, 55, 58],  # Abmaj7
        [41, 44, 48, 51, 55],  # Fm9
        [43, 47, 50, 53, 56],  # G7b9
    ] * 6

    for bar_idx, ch in enumerate(chords):
        b0 = bar_idx * 4.0
        # 깊은 패드
        seq.chord(b0, 4.0, ch, "pad_warm", vol=0.18)
        # 유리종 같은 맑은 FM 벨 아르페지오 (느긋하게)
        seq.arp(b0, 4.0, [n + 12 for n in ch], 0.5, "fm_bell", vol=0.14)

    # 서브 트라이앵글 베이스
    bass_roots = [48, 44, 41, 43] * 6
    for bar_idx, r in enumerate(bass_roots):
        b0 = bar_idx * 4.0
        seq.add(b0, 3.8, r - 12, "bass_tri", vol=0.32)

    # 고요하고 쓸쓸한 오보에/플루트 풍 리드 선율
    m_basement = [
        (8.0, 2.0, 72), (10.0, 1.0, 74), (11.0, 1.0, 75),
        (12.0, 3.0, 70), (15.0, 1.0, 68),
        (16.0, 2.0, 67), (18.0, 1.0, 65), (19.0, 1.0, 67),
        (20.0, 4.0, 67),

        (24.0, 2.0, 75), (26.0, 1.0, 77), (27.0, 1.0, 79),
        (28.0, 3.0, 82), (31.0, 1.0, 80),
        (32.0, 2.0, 79), (34.0, 2.0, 74),
        (36.0, 4.0, 72),

        (64.0, 2.0, 84), (66.0, 2.0, 82),
        (68.0, 3.0, 80), (71.0, 1.0, 79),
        (72.0, 2.0, 77), (74.0, 2.0, 75),
        (76.0, 4.0, 74),
    ]

    for b_start, dur, note in m_basement:
        seq.add(b_start, dur * 0.95, note, "lead_pulse", vol=0.22)
        seq.add(b_start, dur * 0.95, note - 12, "fm_epiano", vol=0.10)

    # 아주 은은한 심장박동 킥 & 소프트 셰이커
    for bar_idx in range(4, total_bars):
        b0 = bar_idx * 4.0
        drums.append((b0, "kick", 0.30))
        drums.append((b0 + 2.0, "kick", 0.25))
        drums.append((b0 + 1.0, "hat", 0.08))
        drums.append((b0 + 3.0, "hat", 0.08))

    return render_track_buffer(total_bars, 4, bpm, seq, drums, echo_delay_beats=1.5)


# ==============================================================================
# 트랙 6: bgm_emotional — "30년의 불씨, 영원한 기억" (F major, 74 BPM, 32마디)
# ==============================================================================
def compose_emotional() -> np.ndarray:
    bpm = 74.0
    total_bars = 32
    seq = NoteSeq(bpm)
    drums: list[tuple[float, str, float]] = []

    # 눈물겨운 명작 RPG 감동 화성
    # 0..7 (Intro): F -> C/E -> Dm7 -> Am7 -> Bbmaj7 -> F/A -> Gm7 -> C7
    # 8..23 (A): F -> C/E -> Dm7 -> Am7 -> Bbmaj7 -> F/A -> Gm7 -> C7 (x2)
    # 24..31 (B Climax): Bbmaj7 -> C/Bb -> Am7 -> Dm7 -> Gm7 -> C7 -> Fsus4 -> F
    chords_unit = [
        [53, 57, 60, 65],  # F
        [52, 55, 60, 64],  # C/E
        [50, 53, 57, 60],  # Dm7
        [45, 52, 57, 60],  # Am7
        [46, 53, 57, 62],  # Bbmaj7
        [45, 53, 57, 60],  # F/A
        [43, 50, 55, 58],  # Gm7
        [48, 55, 58, 64],  # C7
    ]
    chords_climax = [
        [46, 53, 57, 62],  # Bbmaj7
        [46, 55, 58, 64],  # C/Bb
        [45, 52, 57, 60],  # Am7
        [50, 53, 57, 60],  # Dm7
        [43, 50, 55, 58],  # Gm7
        [48, 55, 58, 64],  # C7
        [53, 58, 60, 65],  # Fsus4
        [53, 57, 60, 65],  # F
    ]

    all_chords = chords_unit + chords_unit + chords_unit + chords_climax

    for bar_idx, ch in enumerate(all_chords):
        b0 = bar_idx * 4.0
        # 따스한 오르골/플럭 아르페지오
        seq.arp(b0, 4.0, [n + 12 for n in ch] + [ch[-1] + 19], 0.5, "harp_pluck", vol=0.14)
        # 현악기 풍 따뜻한 신스 패드
        seq.chord(b0, 4.0, ch, "pad_warm", vol=0.20)

    # 서정적 어쿠스틱 베이스
    bass_roots = [
        53, 52, 50, 45, 46, 45, 43, 48,
        53, 52, 50, 45, 46, 45, 43, 48,
        53, 52, 50, 45, 46, 45, 43, 48,
        46, 46, 45, 50, 43, 48, 53, 53
    ]
    for bar_idx, r in enumerate(bass_roots):
        b0 = bar_idx * 4.0
        seq.add(b0, 3.8, r - 12, "bass_tri", vol=0.28)

    # 감동적이고 아름다운 메인 멜로디 (Singing Square/Flute)
    m_emotional = [
        # A1 (bars 8..15)
        (32.0, 1.5, 69), (33.5, 0.5, 72), (34.0, 2.0, 72),
        (36.0, 1.5, 67), (37.5, 0.5, 69), (38.0, 2.0, 65),
        (40.0, 1.5, 65), (41.5, 0.5, 67), (42.0, 1.0, 69), (43.0, 1.0, 65),
        (44.0, 4.0, 64),
        (48.0, 1.5, 65), (49.5, 0.5, 67), (50.0, 1.0, 69), (51.0, 1.0, 72),
        (52.0, 2.0, 69), (54.0, 1.0, 65), (55.0, 1.0, 62),
        (56.0, 2.0, 65), (58.0, 2.0, 64),
        (60.0, 4.0, 65),

        # A2 (bars 16..23) - 옥타브 고음
        (64.0, 1.5, 81), (65.5, 0.5, 84), (66.0, 2.0, 84),
        (68.0, 1.5, 79), (69.5, 0.5, 81), (70.0, 2.0, 77),
        (72.0, 1.5, 77), (73.5, 0.5, 79), (74.0, 1.0, 81), (75.0, 1.0, 77),
        (76.0, 4.0, 76),
        (80.0, 1.5, 77), (81.5, 0.5, 79), (82.0, 1.0, 81), (83.0, 1.0, 84),
        (84.0, 2.0, 81), (86.0, 1.0, 77), (87.0, 1.0, 74),
        (88.0, 2.0, 77), (90.0, 2.0, 76),
        (92.0, 4.0, 77),

        # Climax (bars 24..31)
        (96.0, 1.5, 82), (97.5, 0.5, 84), (98.0, 2.0, 86),
        (100.0, 1.5, 84), (101.5, 0.5, 86), (102.0, 2.0, 88),
        (104.0, 1.5, 81), (105.5, 0.5, 84), (106.0, 2.0, 84),
        (108.0, 2.0, 81), (110.0, 2.0, 77),
        (112.0, 1.5, 79), (113.5, 0.5, 81), (114.0, 1.0, 82), (115.0, 1.0, 84),
        (116.0, 2.0, 84), (118.0, 2.0, 79),
        (120.0, 4.0, 82),
        (124.0, 4.0, 77),
    ]

    for b_start, dur, note in m_emotional:
        seq.add(b_start, dur * 0.95, note, "lead_pulse", vol=0.26)
        seq.add(b_start, dur * 0.95, note - 12, "fm_bell", vol=0.12)

    # 감미로운 소프트 브러시 드럼
    for bar_idx in range(12, total_bars):
        b0 = bar_idx * 4.0
        drums.append((b0, "kick", 0.32))
        drums.append((b0 + 2.0, "kick", 0.28))
        drums.append((b0 + 1.0, "snare", 0.20))
        drums.append((b0 + 3.0, "snare", 0.20))
        drums.append((b0 + 0.5, "hat", 0.10))
        drums.append((b0 + 1.5, "hat", 0.10))
        drums.append((b0 + 2.5, "hat", 0.10))
        drums.append((b0 + 3.5, "hat", 0.10))

    return render_track_buffer(total_bars, 4, bpm, seq, drums, echo_delay_beats=1.0)


# ==============================================================================
# 파일 출력 및 인코딩
# ==============================================================================

def write_wav(path: Path, samples: np.ndarray) -> None:
    pcm = np.clip(samples, -1.0, 1.0)
    pcm = (pcm * 32000.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def write_ogg(path: Path, samples: np.ndarray) -> None:
    wav_path = path.with_suffix(".tmp.wav")
    write_wav(wav_path, samples)
    try:
        subprocess.run(
            [get_ffmpeg_exe(), "-y", "-loglevel", "error", "-i", str(wav_path),
             "-c:a", "libvorbis", "-q:a", "5", str(path)],
            check=True
        )
    finally:
        if wav_path.exists():
            wav_path.unlink()
    print(f"[composer] 생성 완료: {path.name} ({path.stat().st_size / 1024:.1f} KB, 샘플레이트: {SR}Hz)")


def render_all() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tracks = {
        "bgm_title": compose_title,
        "bgm_field": compose_field,
        "bgm_battle": compose_battle,
        "bgm_boss": compose_boss,
        "bgm_basement": compose_basement,
        "bgm_emotional": compose_emotional,
    }

    print("=== BSD 시돌이의 모험 BGM 6곡 생성 시작 ===")
    for tid, func in tracks.items():
        print(f"[composer] 트랙 합성 중: {tid}...")
        buf = func()
        write_ogg(OUT_DIR / f"{tid}.ogg", buf)
    print("=== BGM 6곡 생성 완료 ===")


if __name__ == "__main__":
    render_all()
