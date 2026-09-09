#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""초상 배선 관문 — 설치된 초상이 **화자 이름과 이어져 있는가**.

## 왜 (2026-09-09, 유저 신고 "멍청조교 초상이 대화 중 안 나옴")

`PortraitLibrary`는 스펙의 `name`으로만 화자를 찾았다. 그런데 대사의 화자는 배치명·
별명으로 적힌다:

    대사 화자        "멍청 조교"        (data/dialogue_sequences.json)
    초상 스펙 name   "화공과 조교"       (assets/spec/portraits/npc_tutor_dumb.json)
    초상 파일        npc_tutor_dumb.png (설치됨)

`resolve()`가 빈 문자열을 돌려주고 **조용히** 초상을 건너뛴다. 납품·검증·설치를 다
통과하고도 화면에는 안 나오는, 이 저장소의 지배적 결함(선언은 있는데 안 읽힌다)이다.

## 무엇을 재나

NPC 배치(data/maps/npcs_*.json · walkers_*.json)의 id에 해당하는 초상이 **설치돼
있으면**, 그 NPC의 대사 화자가 반드시 초상으로 이어져야 한다. 이어지지 않으면 실패다
— 고치는 법은 그 초상 스펙에 `speaker_aliases`를 한 줄 추가하는 것이다.

초상이 아예 없는 화자는 실패로 보지 않는다(아직 안 그린 것뿐이다). 다만 몇 종인지는
세어서 알린다 — 그 수가 줄어드는 것이 초상 작업의 진척이다.

실행: python tools/dev/portrait_speakers_check.py
종료코드: 0=통과 / 1=이어지지 않은 초상 있음
"""
from __future__ import annotations

import glob
import io
import json
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PORTRAITS = os.path.join(ROOT, "assets", "portraits")
SPECS = os.path.join(ROOT, "assets", "spec", "portraits")
MAPS = os.path.join(ROOT, "data", "maps")
SEQ = os.path.join(ROOT, "data", "dialogue_sequences.json")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def load_json(path: str):
    try:
        with io.open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def build_index() -> tuple:
    """PortraitLibrary.resolve와 **같은 규칙**으로 색인을 만든다."""
    installed = {os.path.basename(p)[:-4] for p in glob.glob(os.path.join(PORTRAITS, "*.png"))}
    name_to_id: dict[str, str] = {}
    for p in glob.glob(os.path.join(SPECS, "*.json")):
        spec = load_json(p) or {}
        asset_id = str(spec.get("asset_id", os.path.basename(p)[:-5]))
        display = str(spec.get("name", ""))
        if display:
            name_to_id[display] = asset_id
        for alias in spec.get("speaker_aliases", []):
            if str(alias):
                name_to_id[str(alias)] = asset_id
    return installed, name_to_id


def resolve(speaker: str, installed: set, name_to_id: dict) -> str:
    for cand in ([name_to_id[speaker]] if speaker in name_to_id else []) + [speaker]:
        if cand and cand in installed:
            return cand
    return ""


def sequences() -> dict:
    data = load_json(SEQ) or {}
    return data.get("sequences", data)


def speakers_of(seq_id: str, seqs: dict) -> set:
    seq = seqs.get(seq_id)
    if seq is None:
        return set()
    steps = seq.get("steps", []) if isinstance(seq, dict) else seq
    return {str(st["speaker"]) for st in steps
            if isinstance(st, dict) and str(st.get("speaker", ""))}


def npc_entries() -> list:
    """배치 파일의 NPC·워커 — (id, 표시 이름, 이 NPC가 쓰는 시퀀스 id들)."""
    out = []
    for path in sorted(glob.glob(os.path.join(MAPS, "npcs_*.json"))
                       + glob.glob(os.path.join(MAPS, "walkers_*.json"))):
        data = load_json(path)
        rows = data if isinstance(data, list) else (data or {}).get("npcs", [])
        if not rows and isinstance(data, dict):
            for v in data.values():
                if isinstance(v, list):
                    rows = v
                    break
        for row in rows or []:
            if not isinstance(row, dict):
                continue
            nid = str(row.get("id", row.get("sprite", "")))
            if not nid:
                continue
            seq_ids = set()
            for key in ("sequence_id", "repeat_sequence_id"):
                if row.get(key):
                    seq_ids.add(str(row[key]))
            for var in row.get("sequence_variants", []):
                if isinstance(var, dict):
                    for key in ("sequence_id", "repeat_sequence_id"):
                        if var.get(key):
                            seq_ids.add(str(var[key]))
            out.append((nid, str(row.get("name", "")), seq_ids, os.path.basename(path)))
    return out


def main() -> int:
    installed, name_to_id = build_index()
    seqs = sequences()
    fails: list[str] = []
    checked = 0

    print(f"[초상 배선 관문] 설치된 초상 {len(installed)}개 · 배치 NPC를 훑는다")
    for nid, disp, seq_ids, src in npc_entries():
        # 이 NPC에 해당하는 초상이 설치돼 있는가(npc_<id> 또는 <id>).
        asset = next((a for a in (f"npc_{nid}", nid) if a in installed), "")
        if not asset:
            continue
        spoken = set()
        for sid in seq_ids:
            spoken |= speakers_of(sid, seqs)
        if not spoken:
            continue
        # 한 시퀀스에는 여러 화자가 섞인다(NPC + 주인공 + 지문). 이 NPC **자신의**
        # 대사만 본다 — 배치 이름이 그대로 화자로 쓰이는 것이 이 데이터의 규칙이다
        # (예: npcs_f1.json의 name '멍청 조교' = dialogue_sequences의 speaker).
        if not disp or disp not in spoken:
            continue
        checked += 1
        if resolve(disp, installed, name_to_id) != asset:
            fails.append(
                f"{src}: NPC '{nid}'({disp})의 초상 {asset}.png가 설치돼 있는데 "
                f"화자 '{disp}'가 이어지지 않는다 "
                f"— assets/spec/portraits/{asset}.json 의 speaker_aliases에 '{disp}'를 추가하라"
            )

    # 초상이 아예 없는 화자는 실패가 아니다 — 아직 안 그린 것뿐이다.
    all_speakers = set()
    for seq in seqs.values():
        steps = seq.get("steps", []) if isinstance(seq, dict) else seq
        for st in steps:
            if isinstance(st, dict) and str(st.get("speaker", "")):
                all_speakers.add(str(st["speaker"]))
    without = sorted(sp for sp in all_speakers if not resolve(sp, installed, name_to_id))

    print(f"  초상이 설치된 NPC {checked}종을 확인했다 · 대사 화자 {len(all_speakers)}종 중 "
          f"초상이 뜨는 화자 {len(all_speakers) - len(without)}종")
    if without:
        print(f"  · 아직 초상이 없는 화자 {len(without)}종(실패 아님): "
              + ", ".join(without[:8]) + (" …" if len(without) > 8 else ""))
    if fails:
        print("\n실패 — 설치된 초상이 화자와 안 이어진다:")
        for f in fails:
            print("  [ERR ] " + f)
        return 1
    print("\n통과 — 설치된 초상은 모두 그 NPC의 화자와 이어져 있다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
