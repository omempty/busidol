"""내보내기 포함 규칙 관문 — 프리셋으로 .pck를 뽑아 "무엇이 들어갔는가"를 실측한다.

이 프로젝트는 콘텐츠 전량이 data/**.json 이라, 프리셋 필터가 한 줄만 어긋나도
"부팅은 되는데 대사·아이템이 비어 있는" 빌드가 나온다. 개발 실행에서는 res://가
프로젝트 폴더라 절대 재현되지 않는 결함이므로, 관문이 .pck 목록으로 직접 확인한다.

사용: python tools/dev/export_check.py [godot 실행파일]
"""

import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_GODOT = os.path.join(
    ROOT, "..", "..", "_shared", "tools", "godot", "Godot_v4.7.2-stable_win64_console.exe"
)
PRESET = "Windows Desktop"
# 들어가면 안 되는 것 — 문서·개발 도구·테스트는 배포물에 실릴 이유가 없다.
FORBIDDEN = ("res://docs/", "res://tools/", "res://tests/", "res://assets/raw/")


def data_json_count() -> int:
    n = 0
    for base, _dirs, files in os.walk(os.path.join(ROOT, "data")):
        n += sum(1 for f in files if f.endswith(".json"))
    return n


def main() -> int:
    godot = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_GODOT
    if not os.path.exists(godot):
        print("[export_check] godot 실행파일 없음: %s" % godot)
        return 1
    out_pck = os.path.join(tempfile.gettempdir(), "sidol_export_check.pck")
    proc = subprocess.run(
        [godot, "--headless", "--path", ROOT, "--export-pack", PRESET, out_pck],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    log = (proc.stdout or "") + (proc.stderr or "")
    # Godot 콘솔 빌드는 진행률에 ANSI 색코드를 붙인다 — 경로 뒤에 붙어 매칭을 깬다.
    log = re.sub("\x1b\\[[0-9;]*m", "", log)
    packed = set(re.findall(r"res://[^\s]+", log))
    if not packed:
        print("[export_check] FAIL — 내보내기 실패\n%s" % log[-2000:])
        return 1

    expected = data_json_count()
    got = len([p for p in packed if p.startswith("res://data/") and p.endswith(".json")])
    fails = []
    if got < expected:
        fails.append("data/**.json %d개 중 %d개만 포함 — 프리셋 필터 확인" % (expected, got))
    for bad in FORBIDDEN:
        leaked = [p for p in packed if p.startswith(bad)]
        if leaked:
            fails.append("배포 제외 대상 유출 %s ×%d (예: %s)" % (bad, len(leaked), leaked[0]))
    if not os.path.exists(out_pck):
        fails.append(".pck 파일이 생성되지 않음")

    for f in fails:
        print("[export_check] FAIL — %s" % f)
    if fails:
        return 1
    print(
        "[export_check] ok — %s 프리셋: 항목 %d개 · data/**.json %d/%d · 제외 규칙 준수"
        % (PRESET, len(packed), got, expected)
    )
    if os.path.exists(out_pck):
        os.remove(out_pck)
    return 0


if __name__ == "__main__":
    sys.exit(main())
