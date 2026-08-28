#!/usr/bin/env python3
"""납품 일괄 처리 — 검증 → 채택 → 설치를 한 명령으로. 심사 보드(GUI) 없이 돈다.

## 왜 필요했나 (2026-08-28)

심사 흐름이 웹 보드(review_server.py) 하나뿐이었다. 그런데 실제 발주는
**몇 건만 시범 생성**하는 일이 잦고(이미지 토큰이 비싸다), 그럴 때 서버를 띄우고
브라우저를 열어 카드를 누르는 것은 과하다. 여기서는 폴더에 받은 PNG를 그대로 던지면
검증·컷팅·설치까지 끝난다. 보드는 눈으로 비교하고 싶을 때만 쓴다.

카테고리는 **파일 이름에서 자동 판별**한다(`<id>_v<n>.png`의 id를 스펙·패키지에서 찾는다).
사람이 카테고리를 외울 필요가 없어야 폴더 드롭이 편해진다.

## 사용

  python tools/convert/intake.py                       10_submitted 전부 처리
  python tools/convert/intake.py --from <폴더>          그 폴더의 PNG를 받아 처리(묶음 _제출/)
  python tools/convert/intake.py --dry-run             검증 결과만 보고(파일 이동 없음)
  python tools/convert/intake.py --force               검증 FAIL도 설치(사람이 판단한 경우)

종료코드: 0=전건 처리 / 1=반려나 오류가 하나라도 있음
"""
from __future__ import annotations

import io
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
LLM = os.path.join(ROOT, "assets", "raw", "llm")
SUBMIT = os.path.join(LLM, "10_submitted")
PROCESSED = os.path.join(LLM, "20_processed")
FEEDBACK = os.path.join(SUBMIT, "_feedback")
VERSION_RE = re.compile(r"^(?P<id>.+)_v(?P<n>\d+)\.png$", re.IGNORECASE)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

## 스펙 파일 → 카테고리. 시트 계열은 그리드 컷팅(process_llm_sheet)을 거친다.
SPEC_CATEGORY = {
    "monster_anim_specs.json": "monsters",
    "npc_anim_specs.json": "npcs",
    "effect_specs.json": "effects",
    "battle_cut_specs.json": "battle_cuts",
    "battle_actor_specs.json": "battle_actors",
}
SHEET_CATEGORIES = set(SPEC_CATEGORY.values())
## 검증 방식 — 시트 계열은 그리드 계약, 나머지는 규격 검사.
SUBMISSION_MODE = {"portraits": "portrait", "keyart": "keyart", "items": "icon"}


def detect_category(asset_id: str) -> str:
    """에셋 id → 카테고리. 스펙·패키지 폴더를 훑어 자동 판별한다."""
    for name, cat in SPEC_CATEGORY.items():
        path = os.path.join(ROOT, "data", name)
        if not os.path.exists(path):
            continue
        for sp in json.load(io.open(path, encoding="utf-8")).get("species", []):
            if sp.get("id") == asset_id:
                return cat
    for cat, spec_dir in (("portraits", "portraits"), ("keyart", "keyart")):
        if os.path.exists(os.path.join(ROOT, "assets", "spec", spec_dir, f"{asset_id}.json")):
            return cat
    items = json.load(io.open(os.path.join(ROOT, "data", "items.json"), encoding="utf-8"))
    if any(str(i.get("id")) == asset_id for i in items.get("items", [])):
        return "items"
    # 마지막 수단 — 의뢰 패키지 폴더가 있는 카테고리
    for cat in sorted(os.listdir(LLM)) if os.path.isdir(LLM) else []:
        if os.path.isdir(os.path.join(LLM, cat, asset_id)):
            return cat
    return ""


def run(args: list, timeout: int = 180) -> tuple:
    proc = subprocess.run(
        [sys.executable, "-X", "utf8"] + args,
        capture_output=True, text=True, encoding="utf-8", timeout=timeout,
    )
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def validate(cat: str, path: str) -> tuple:
    if cat in SHEET_CATEGORIES:
        script = os.path.join(ROOT, "tools", "convert", "validate_monster_sheet.py")
        return run([script, path])
    mode = SUBMISSION_MODE.get(cat, "portrait")
    script = os.path.join(ROOT, "tools", "convert", "validate_submission.py")
    return run([script, mode, path])


def write_feedback(cat: str, fname: str, report: str) -> str:
    """반려 사유 md — 재의뢰 때 이 파일 하나만 다시 던지면 된다."""
    asset_id = VERSION_RE.match(fname).group("id") if VERSION_RE.match(fname) else fname[:-4]
    nxt = int(VERSION_RE.match(fname).group("n")) + 1 if VERSION_RE.match(fname) else 2
    prompt_path = os.path.join(LLM, cat, asset_id, "prompt.md")
    prompt = io.open(prompt_path, encoding="utf-8").read() if os.path.exists(prompt_path) else "(원본 의뢰문 없음)"
    body = [
        prompt, "", "---", "", f"## 자동 검증 결과 — {fname}", "", "```", report.strip(), "```", "",
        f"위 사항을 고쳐 **{asset_id}_v{nxt}.png** 로 재납품하라.",
        "부분 수정으로 될 것 같으면 셀 편집기로 고칠 수도 있다:",
        f"  심사실행.bat → [셀 편집]  또는  tools/review/sprite_fixer.html?cat={cat}&file={fname}",
    ]
    os.makedirs(os.path.join(FEEDBACK, cat), exist_ok=True)
    out = os.path.join(FEEDBACK, cat, fname + ".md")
    io.open(out, "w", encoding="utf-8").write("\n".join(body) + "\n")
    return out


def adopt(cat: str, asset_id: str, path: str) -> tuple:
    """채택 — 시트는 컷팅 후, 평면은 이동 후 설치까지."""
    log = []
    if cat in SHEET_CATEGORIES:
        code, out = run([os.path.join(ROOT, "tools", "convert", "process_llm_sheet.py"), path])
        log.append(out.strip().splitlines()[-1] if out.strip() else "")
        if code != 0:
            return False, "\n".join(log)
        os.remove(path)
    else:
        dst_dir = os.path.join(PROCESSED, cat)
        os.makedirs(dst_dir, exist_ok=True)
        shutil.move(path, os.path.join(dst_dir, os.path.basename(path)))
    code, out = run([os.path.join(ROOT, "tools", "convert", "install_delivery.py"), asset_id])
    for line in out.strip().splitlines():
        if line.strip().startswith(("ok", "FAIL")):
            log.append(line.strip())
    return code == 0, "\n".join(log)


def gather(from_dir: str) -> list:
    """처리 대상 (카테고리, 파일경로) 목록. --from이면 10_submitted로 먼저 옮긴다."""
    out = []
    if from_dir:
        src = from_dir if os.path.isabs(from_dir) else os.path.join(ROOT, from_dir)
        if not os.path.isdir(src):
            print(f"폴더가 없다: {src}")
            sys.exit(1)
        for f in sorted(os.listdir(src)):
            if not f.lower().endswith(".png"):
                continue
            m = VERSION_RE.match(f)
            asset_id = m.group("id") if m else f[:-4]
            cat = detect_category(asset_id)
            if not cat:
                print(f"  ?? {f}: 카테고리를 못 찾았다(id '{asset_id}'가 스펙·패키지에 없음)")
                continue
            dst_dir = os.path.join(SUBMIT, cat)
            os.makedirs(dst_dir, exist_ok=True)
            dst = os.path.join(dst_dir, f)
            shutil.move(os.path.join(src, f), dst)
            print(f"  받음 {f} -> 10_submitted/{cat}/")
            out.append((cat, dst))
        return out
    if not os.path.isdir(SUBMIT):
        return out
    for cat in sorted(os.listdir(SUBMIT)):
        cat_dir = os.path.join(SUBMIT, cat)
        if not os.path.isdir(cat_dir) or cat.startswith("_"):
            continue
        for f in sorted(os.listdir(cat_dir)):
            if f.lower().endswith(".png"):
                out.append((cat, os.path.join(cat_dir, f)))
    return out


def main() -> None:
    args = list(sys.argv[1:])
    dry = "--dry-run" in args
    force = "--force" in args
    from_dir = ""
    if "--from" in args:
        i = args.index("--from")
        from_dir = args[i + 1]
        del args[i:i + 2]
    for flag in ("--dry-run", "--force"):
        if flag in args:
            args.remove(flag)

    targets = gather(from_dir)
    if not targets:
        print("[intake] 처리할 납품이 없다")
        return

    print("[intake] 납품 %d건%s" % (len(targets), " (모의 실행)" if dry else ""))
    ok_n = fail_n = 0
    for cat, path in targets:
        fname = os.path.basename(path)
        m = VERSION_RE.match(fname)
        asset_id = m.group("id") if m else fname[:-4]
        code, report = validate(cat, path)
        passed = code == 0
        head = "PASS" if passed else "FAIL"
        print(f"\n── {cat}/{fname} — 검증 {head}")
        for line in report.strip().splitlines():
            if line.strip().startswith(("ok", "FAIL", "WARN", "[ERR", "[warn")):
                print("   " + line.strip())
        if dry:
            ok_n += 1 if passed else 0
            fail_n += 0 if passed else 1
            continue
        if passed or force:
            done, log = adopt(cat, asset_id, path)
            for line in log.splitlines():
                if line.strip():
                    print("   " + line.strip())
            if done:
                ok_n += 1
                print("   → 설치 완료" + (" (검증 FAIL이지만 --force)" if not passed else ""))
            else:
                fail_n += 1
                print("   → 설치 실패")
        else:
            fb = write_feedback(cat, fname, report)
            fail_n += 1
            print("   → 반려. 재요청 문서: %s" % os.path.relpath(fb, ROOT).replace("\\", "/"))

    print("\n[intake] 설치 %d건 · 반려/실패 %d건" % (ok_n, fail_n))
    if ok_n:
        print("  게임 현황 확인: python tools/dev/asset_status.py")
    sys.exit(1 if fail_n else 0)


if __name__ == "__main__":
    main()
