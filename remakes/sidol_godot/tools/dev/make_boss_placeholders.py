#!/usr/bin/env python3
"""보스 플레이스홀더 절차적 생성기 — 원작 없는 보스 6종의 임시 비주얼.
각 보스의 컨셉을 기하 패턴 + 색으로 표현. AI 정식 아트로 교체 전까지 사용."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHARED_SRC = ROOT.parent.parent / "_shared" / "src"
sys.path.insert(0, str(SHARED_SRC))
from dosport.formats.png_write import fill_rect, write_png  # noqa: E402


def make_boss_placeholder(spec: dict, out_png: Path) -> None:
    cw = spec["cell"]["w"]
    ch = spec["cell"]["h"]
    buf = bytearray(cw * ch * 4)
    is_final = spec.get("is_final_boss", False)

    # 배경 (완전 투명)
    base_color = {
        "sewer_king":   ((60, 50, 30),  "먼지 갈색"),
        "hall_mother":  ((90, 40, 60),  "생체 자주"),
        "crt_overseer": ((20, 60, 40),  "녹색 CRT"),
        "flask_titan":  ((30, 70, 80),  "화학 청록"),
        "volt_wyrm":    ((40, 40, 90),  "고전앵 남색"),
        "sys_builder":  ((0, 60, 0),    "녹색 CRT 와이어프레임"),
    }.get(spec["id"], ((80, 80, 80), "?"))
    body = base_color[0]

    # 실루엣: 중앙 큰 타원형
    cx, cy = cw // 2, ch // 2
    rx, ry = cw // 3, ch // 3
    for y in range(ch):
        for x in range(cw):
            dx = (x - cx) / max(rx, 1)
            dy = (y - cy) / max(ry, 1)
            if dx * dx + dy * dy <= 1.0:
                i = (y * cw + x) * 4
                shade = 0.7 if (x // 8 + y // 8) % 2 == 0 else 1.0
                if is_final:
                    # CRT 스캔라인
                    shade *= 0.85 if y % 4 < 2 else 0.6
                buf[i]     = int(body[0] * shade)
                buf[i + 1] = int(body[1] * shade)
                buf[i + 2] = int(body[2] * shade)
                buf[i + 3] = 255
    # 외곽선
    for y in range(ch):
        for x in range(cw):
            dx = (x - cx) / max(rx, 1)
            dy = (y - cy) / max(ry, 1)
            dist = dx * dx + dy * dy
            if 0.9 <= dist <= 1.15:
                i = (y * cw + x) * 4
                buf[i:i+4] = bytes((20, 10, 30, 255))

    write_png(out_png, cw, ch, bytes(buf))


def main() -> int:
    specs_path = ROOT / "data" / "monster_anim_specs.json"
    specs = json.loads(Path(specs_path).read_text(encoding="utf-8"))

    out_dir = ROOT / "assets" / "raw" / "sprites" / "boss_placeholders"
    out_dir.mkdir(parents=True, exist_ok=True)

    count = 0
    for s in specs["species"]:
        if s.get("source") != "placeholder_procedural":
            continue
        sid = s["id"]
        cell_w = s["cell"]["w"]
        cell_h = s["cell"]["h"]
        frames = s.get("animations", {}).get("idle", {}).get("frames", 2)

        # idle 애니 프레임 수만큼 생성 (미세 변형)
        for f in range(frames):
            out = out_dir / sid / f"frame_{f:03d}.bmp"
            out.parent.mkdir(parents=True, exist_ok=True)
            make_boss_placeholder(s, out)
            count += 1

        print(f"{sid}: {frames} idle frames ({cell_w}x{cell_h}) -> {out_dir / sid}")

    print(f"\ntotal placeholders: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
