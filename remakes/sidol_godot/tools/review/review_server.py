"""LLM 납품 심사 서버 — 검증 배지·승인/반려·재요청 프롬프트 생성.

stdlib 전용(http.server + subprocess). 프로젝트 루트를 정적 서빙하고
아래 API로 심사 보드(review_board.html)와 통신한다.

  GET  /api/categories                     카테고리 목록·건수
  GET  /api/list?cat=portraits             납품 목록(+검증 결과·피드백 md·참조 경로)
  POST /api/review  {cat,file,action,feedback}  승인(20_processed 이동 + assets 설치)/반려(피드백 md)
  POST /api/batch   {cat,action,feedback}       전체 승인/전체 반려
  GET  /api/fixer/contract?cat&file[&asset]    셀 편집기용 그리드 계약(셀 크기·행별 프레임)
  GET  /api/fixer/assets[?cat=monsters]        계약이 있는 에셋 목록(편집기 [계약] 드롭다운)
  GET  /api/fixer/files[?cat=monsters]         셀 편집기 파일 선택기 목록(대기·반려·승인본)
  GET  /api/fixer/webprompt?cat&file           웹 챗용 프롬프트(공통 + 시트 상세)
  POST /api/fixer/op   {op,params,png}         시트 픽셀 연산(정본: tools/convert/sheet_ops.py)
  POST /api/fixer/save {cat,file,png,mode}     편집 결과를 다음 버전으로 재납품

반려 시 10_submitted/_feedback/<cat>/<file>.md 에 재요청 패키지가 생성된다:
  원본 의뢰 prompt.md + 유저 반려 사항 + 자동 검증 결과 — 이 파일과 원본 첨부물을
  이미지 LLM에 재투입하면 v<n+1> 납품이 나온다.

실행: python tools/review/review_server.py  (기본 127.0.0.1:8643)
"""
from __future__ import annotations
import base64
import io
import json
import os
import re
import shutil
import subprocess
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
LLM = os.path.join(ROOT, "assets", "raw", "llm")
SUBMIT = os.path.join(LLM, "10_submitted")
PROCESSED = os.path.join(LLM, "20_processed")
FEEDBACK = os.path.join(LLM, "10_submitted", "_feedback")
REJECTED = os.path.join(LLM, "10_submitted", "_rejected")

# 카테고리 → (납품 하위폴더, 검증 방식, 원본 참조 파일명 패턴)
CATEGORIES = {
    "portraits": {"mode": "portrait", "validator": "submission"},
    "keyart": {"mode": "keyart", "validator": "submission"},
    # 몬스터는 신규 창작이라 리터치 검증기(주인공 시트 대조)를 쓰면 무조건 반려된다 —
    # 종별 그리드 계약만 보는 전용 검증기를 쓴다.
    "monsters": {"mode": None, "validator": "monster"},
    # NPC도 필드 캐릭터 시트라 몬스터와 같은 그리드 계약을 쓴다(스펙 파일만 다르다).
    "npcs": {"mode": None, "validator": "monster"},
    "sprites": {"mode": None, "validator": "retouch"},
    # 아이템 아이콘 — 96×96 단일 이미지. 시트 컷팅이 없으므로 submission 계열.
    "items": {"mode": "icon", "validator": "submission"},
    # 전투 이펙트 — 128 격자 시트. 정렬만 center라 검증기는 몬스터와 같은 것을 쓴다.
    "effects": {"mode": None, "validator": "monster"},
    # 전투 대형 컷 — 셀 512 시트. 계약은 battle_cut_specs.json이 준다.
    "battle_cuts": {"mode": None, "validator": "monster"},
    # 전투 전용 SD 시트 — 필드 시트와 같은 128 격자.
    "battle_actors": {"mode": None, "validator": "monster"},
}
VERSION_RE = re.compile(r"^(?P<id>.+)_v(?P<n>\d+)\.png$", re.IGNORECASE)
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8643


def safe_path(*parts: str) -> str:
    """경로 탈출 금지 — LLM 폴더 안으로 강제."""
    path = os.path.normpath(os.path.join(LLM, *parts))
    if not path.startswith(LLM):
        raise ValueError("경로 탈출")
    return path


_VALIDATION_CACHE: dict[str, tuple[float, dict]] = {}


def run_validator(cat: str, abs_path: str) -> dict:
    if not os.path.exists(abs_path):
        return {"pass": False, "lines": ["파일 없음"]}
    try:
        mtime = os.path.getmtime(abs_path)
    except OSError:
        mtime = 0.0
    cached = _VALIDATION_CACHE.get(abs_path)
    if cached and cached[0] == mtime:
        return cached[1]

    info = CATEGORIES[cat]
    if info["validator"] == "submission":
        script = os.path.join(ROOT, "tools", "convert", "validate_submission.py")
        args = [sys.executable, "-X", "utf8", script, info["mode"], abs_path]
    elif info["validator"] == "monster":
        script = os.path.join(ROOT, "tools", "convert", "validate_monster_sheet.py")
        args = [sys.executable, "-X", "utf8", script, abs_path]
    else:
        script = os.path.join(ROOT, "tools", "convert", "validate_retouch_sheet.py")
        args = [sys.executable, "-X", "utf8", script, abs_path]
    try:
        proc = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", timeout=60)
        lines = [l for l in (proc.stdout or "").strip().splitlines() if l.strip()]
        res = {"pass": proc.returncode == 0, "lines": lines[-8:]}
    except Exception as exc:  # noqa: BLE001 — 검증기 크래시도 배지로 표시
        res = {"pass": False, "lines": [f"검증기 오류: {exc}"]}
    _VALIDATION_CACHE[abs_path] = (mtime, res)
    return res


def asset_id_of(fname: str) -> str:
    m = VERSION_RE.match(fname)
    return m.group("id") if m else os.path.splitext(fname)[0]


def run_install(asset_id: str) -> str:
    """채택 직후 게임 에셋 자리로 설치한다.

    승인이 20_processed 이동에서 끝나던 탓에 채택본이 게임에 한 장도 안 들어가 있었다
    (2026-08-28: _remake.png가 _original.png와 바이트 동일, assets/portraits 부재).
    승인과 설치를 한 동작으로 묶어 그 간극을 없앤다.
    """
    script = os.path.join(ROOT, "tools", "convert", "install_delivery.py")
    try:
        proc = subprocess.run(
            [sys.executable, "-X", "utf8", script, asset_id],
            capture_output=True, text=True, encoding="utf-8", timeout=120,
        )
        return (proc.stdout or proc.stderr or "").strip()[-400:]
    except Exception as exc:  # noqa: BLE001 — 설치 실패도 심사 보드에 문자열로 보인다
        return f"설치 실패: {exc}"


def package_dir(cat: str, asset_id: str) -> tuple:
    """패키지 폴더의 (절대경로, 웹경로).

    sprites 패키지만 assets/gen/prompts/ 아래에 있다 — git 추적 대상이라
    gitignored인 raw/llm 밖에 두기 때문. 이 분기가 없으면 스프라이트 납품 카드에
    원본 의뢰문·참조 이미지가 붙지 않고, 반려 시 만들어지는 재요청 md에도
    원본 지시가 빠진다(계약 위반 상태로 재의뢰하게 된다).
    """
    if cat == "sprites":
        return os.path.join(ROOT, "assets", "gen", "prompts"), "/assets/gen/prompts"
    return os.path.join(LLM, cat, asset_id), f"/assets/raw/llm/{cat}/{asset_id}"


def read_prompt_md(cat: str, asset_id: str) -> str:
    pkg, _ = package_dir(cat, asset_id)
    for name in (
        "prompt.md",
        f"{asset_id}_prompt.md",
        "player_retouch_prompt.md",
        "player_gen_prompt.md",
    ):
        cand = os.path.join(pkg, name)
        if os.path.exists(cand):
            return io.open(cand, encoding="utf-8").read()
    return "(원본 의뢰문 없음)"


def reference_paths(cat: str, asset_id: str) -> dict:
    """보드 3열 비교용 — 참조/앵커 이미지의 웹 경로."""
    refs = {"reference": None, "anchor": None}
    pkg, base = package_dir(cat, asset_id)
    for name, key in (
        (f"{asset_id}_source.png", "reference"),
        ("player_sheet_original.png", "reference"),
        ("style_ref.png", "anchor"),
        ("tone_anchor.png", "anchor"),
        ("player_sheet_annotated.png", "anchor"),
    ):
        p = os.path.join(pkg, name)
        if os.path.exists(p) and refs[key] is None:
            refs[key] = f"{base}/{name}"
    return refs


def list_items(cat: str) -> list:
    items = []
    seen_ids = set()

    # 1. 10_submitted (납품 대기)
    cat_dir = safe_path("10_submitted", cat)
    if os.path.isdir(cat_dir):
        for fname in sorted(os.listdir(cat_dir)):
            if not fname.lower().endswith(".png"):
                continue
            m = VERSION_RE.match(fname)
            asset_id = m.group("id") if m else os.path.splitext(fname)[0]
            abs_path = os.path.join(cat_dir, fname)
            fb_path = safe_path("10_submitted", "_feedback", cat, fname + ".md")
            feedback = None
            if os.path.exists(fb_path):
                feedback = io.open(fb_path, encoding="utf-8").read()
            items.append({
                "file": fname,
                "asset_id": asset_id,
                "status": "submitted",
                "validation": run_validator(cat, abs_path),
                "feedback": feedback,
                "prompt_md": read_prompt_md(cat, asset_id),
                "refs": reference_paths(cat, asset_id),
                "web": f"/assets/raw/llm/10_submitted/{cat}/{fname}",
            })
            seen_ids.add(asset_id)

    # 2. 20_processed (승인 완료 / 게임 설치됨)
    proc_dir = safe_path("20_processed", cat)
    if os.path.isdir(proc_dir):
        for entry in sorted(os.listdir(proc_dir)):
            abs_entry = os.path.join(proc_dir, entry)
            if entry.lower().endswith(".png") and os.path.isfile(abs_entry):
                fname = entry
                m = VERSION_RE.match(fname)
                asset_id = m.group("id") if m else os.path.splitext(fname)[0]
                if asset_id not in seen_ids:
                    items.append({
                        "file": fname,
                        "asset_id": asset_id,
                        "status": "approved",
                        "validation": {"pass": True, "lines": ["승인 완료 (게임 에셋 설치됨)"]},
                        "feedback": None,
                        "prompt_md": read_prompt_md(cat, asset_id),
                        "refs": reference_paths(cat, asset_id),
                        "web": f"/assets/raw/llm/20_processed/{cat}/{fname}",
                    })
                    seen_ids.add(asset_id)
            elif os.path.isdir(abs_entry):
                asset_id = entry
                sheet_p = os.path.join(abs_entry, f"{asset_id}_sheet.png")
                web_p = f"/assets/raw/llm/20_processed/{cat}/{asset_id}/{asset_id}_sheet.png" if os.path.exists(sheet_p) else f"/assets/sprites/{asset_id}_remake.png"
                if asset_id not in seen_ids:
                    items.append({
                        "file": f"{asset_id}_approved.png",
                        "asset_id": asset_id,
                        "status": "approved",
                        "validation": {"pass": True, "lines": ["승인 완료 (스프라이트 분할 및 설치 완료)"]},
                        "feedback": None,
                        "prompt_md": read_prompt_md(cat, asset_id),
                        "refs": reference_paths(cat, asset_id),
                        "web": web_p,
                    })
                    seen_ids.add(asset_id)

    # 3. 10_submitted/_rejected (반려됨)
    rej_dir = safe_path("10_submitted", "_rejected", cat)
    if os.path.isdir(rej_dir):
        for fname in sorted(os.listdir(rej_dir)):
            if not fname.lower().endswith(".png"):
                continue
            m = VERSION_RE.match(fname)
            asset_id = m.group("id") if m else os.path.splitext(fname)[0]
            if asset_id not in seen_ids:
                abs_path = os.path.join(rej_dir, fname)
                fb_path = safe_path("10_submitted", "_feedback", cat, fname + ".md")
                feedback = None
                if os.path.exists(fb_path):
                    feedback = io.open(fb_path, encoding="utf-8").read()
                items.append({
                    "file": fname,
                    "asset_id": asset_id,
                    "status": "rejected",
                    "validation": {"pass": False, "lines": ["사용자 반려됨 (수정 대기)"]},
                    "feedback": feedback,
                    "prompt_md": read_prompt_md(cat, asset_id),
                    "refs": reference_paths(cat, asset_id),
                    "web": f"/assets/raw/llm/10_submitted/_rejected/{cat}/{fname}",
                })
                seen_ids.add(asset_id)

    # 4. Pending Targets (미납품 대기 항목)
    batch_base = safe_path("_batch")
    if os.path.isdir(batch_base):
        for b_name in sorted(os.listdir(batch_base), reverse=True):
            b_path = os.path.join(batch_base, b_name)
            if not os.path.isdir(b_path):
                continue
            prefix = f"{cat}__"
            for d in os.listdir(b_path):
                if d.startswith(prefix):
                    asset_id = d[len(prefix):]
                    if asset_id not in seen_ids:
                        d_path = os.path.join(b_path, d)
                        src_img = None
                        for s_name in (f"{asset_id}_source.png", "orig_frame_001.png", "orig_enemy_1.png", "style_ref.png", "grid_template.png"):
                            if os.path.exists(os.path.join(d_path, s_name)):
                                src_img = f"/assets/raw/llm/_batch/{b_name}/{d}/{s_name}"
                                break
                        items.append({
                            "file": f"{asset_id} (미납품)",
                            "asset_id": asset_id,
                            "status": "pending",
                            "validation": {"pass": False, "lines": ["미납품 (생성 및 작업 대기 중)"]},
                            "feedback": None,
                            "prompt_md": read_prompt_md(cat, asset_id),
                            "refs": reference_paths(cat, asset_id),
                            "web": src_img or "/assets/portraits/_fallback.png",
                        })
                        seen_ids.add(asset_id)

    return items


def build_revise_md(cat: str, fname: str, feedback: str, validation: dict) -> str:
    m = VERSION_RE.match(fname)
    asset_id = m.group("id") if m else os.path.splitext(fname)[0]
    parts = [read_prompt_md(cat, asset_id), "", "---", "", f"## 반려 사항 (유저) — {fname}", ""]
    parts.append(feedback.strip() or "(사유 미기재)")
    parts.append("")
    parts.append("## 자동 검증 결과")
    parts.extend(validation.get("lines", []))
    parts.append("")
    parts.append("---")
    parts.append(f"위 사항을 반영해 **{asset_id}_v{int(m.group('n')) + 1 if m else 2}.png** 로 재납품하라.")
    return "\n".join(parts)


def do_review(payload: dict) -> dict:
    cat = payload.get("cat", "")
    action = payload.get("action", "")
    if cat not in CATEGORIES:
        raise ValueError(f"알 수 없는 카테고리: {cat}")
    if action not in ("approve", "reject", "reset"):
        raise ValueError(f"알 수 없는 액션: {action}")
    fname = os.path.basename(payload.get("file", ""))
    
    if action == "reset":
        asset_id = asset_id_of(fname)
        sub_dir = safe_path("10_submitted", cat)
        os.makedirs(sub_dir, exist_ok=True)
        clean_name = fname if (fname.endswith(".png") and not "approved" in fname and not "미납품" in fname) else f"{asset_id}_v1.png"
        dst = os.path.join(sub_dir, clean_name)
        
        proc_f = safe_path("20_processed", cat, fname)
        rej_f = safe_path("10_submitted", "_rejected", cat, fname)
        proc_dir = safe_path("20_processed", cat, asset_id)
        
        if os.path.isfile(proc_f):
            shutil.copy2(proc_f, dst)
        elif os.path.isfile(rej_f):
            shutil.move(rej_f, dst)
        elif os.path.isdir(proc_dir):
            sheet = os.path.join(proc_dir, f"{asset_id}_sheet.png")
            if os.path.exists(sheet):
                shutil.copy2(sheet, dst)
            else:
                shutil.copy2(os.path.join(ROOT, "assets", "sprites", f"{asset_id}_remake.png"), dst)
        else:
            raise FileNotFoundError(f"복구 대상 파일 없음: {fname}")
            
        return {"ok": True, "detail": f"10_submitted/{cat}/{os.path.basename(dst)} (재심사 상태로 복구 완료)"}

    src = safe_path("10_submitted", cat, fname)
    if not os.path.exists(src):
        raise FileNotFoundError(fname)
    validation = run_validator(cat, src)

    if action == "approve":
        if CATEGORIES[cat]["validator"] in ("retouch", "monster"):
            # 스프라이트 계열은 그리드 컷팅까지 한 번에(process_llm_sheet가 20_processed에 출력)
            script = os.path.join(ROOT, "tools", "convert", "process_llm_sheet.py")
            proc = subprocess.run(
                [sys.executable, "-X", "utf8", script, src],
                capture_output=True, text=True, encoding="utf-8", timeout=120,
            )
            os.remove(src)
            detail = (proc.stdout or proc.stderr)[-400:]
            return {"ok": True, "detail": detail + chr(10) + run_install(asset_id_of(fname))}
        dst_dir = safe_path("20_processed", cat)
        os.makedirs(dst_dir, exist_ok=True)
        shutil.move(src, os.path.join(dst_dir, fname))
        return {
            "ok": True,
            "detail": f"20_processed/{cat}/{fname}" + chr(10) + run_install(asset_id_of(fname)),
        }

    # 반려 — 피드백 md(재요청 패키지) 생성 후 _rejected 이동
    md = build_revise_md(cat, fname, payload.get("feedback", ""), validation)
    fb_dir = safe_path("10_submitted", "_feedback", cat)
    rej_dir = safe_path("10_submitted", "_rejected", cat)
    os.makedirs(fb_dir, exist_ok=True)
    os.makedirs(rej_dir, exist_ok=True)
    io.open(os.path.join(fb_dir, fname + ".md"), "w", encoding="utf-8").write(md)
    shutil.move(src, os.path.join(rej_dir, fname))
    return {"ok": True, "detail": f"_rejected/{cat}/{fname} + 피드백 md 생성", "revise_md": md}


# --- 셀 편집기(sprite_fixer.html) 지원 -------------------------------------
# 생성물이 규약을 못 맞출 때 사람이 **통짜 시트를 셀 단위로 고쳐** 규격에 맞추는 경로.
# 재생성이 늘 더 싼 것은 아니다(잔선 한 줄·라벨 바 하나 때문에 전체를 다시 그리는 것은
# 낭비다). 계약을 서버가 알려 주고, 편집 결과는 다음 버전 번호로 다시 납품 폴더에 들어가
# 기존 심사 흐름(검증 → 승인 → 설치)을 그대로 탄다.
SHEET_SPEC_FILES = (
    "monster_anim_specs.json",
    "npc_anim_specs.json",
    "effect_specs.json",
    "battle_cut_specs.json",
    "battle_actor_specs.json",
)
## 스펙 파일이 어느 카테고리의 계약을 담고 있는가 — 계약 목록 API가 쓴다.
SPEC_FILE_CAT = {
    "monster_anim_specs.json": "monsters",
    "npc_anim_specs.json": "npcs",
    "effect_specs.json": "effects",
    "battle_cut_specs.json": "battle_cuts",
    "battle_actor_specs.json": "battle_actors",
}
## 평면 카테고리의 고정 규격 — 검증기(validate_submission.py)와 같은 수를 쓴다.
FLAT_CONTRACTS = {
    "portraits": {"cell": 256, "cols": 3, "rows": 1, "align": "none"},
    "items": {"cell": 96, "cols": 1, "rows": 1, "align": "none"},
    "keyart": {"cell": 0, "cols": 1, "rows": 1, "align": "none", "size": [1920, 1080]},
}


def sheet_contract(asset_id: str) -> dict:
    """*_anim_specs.json / effect_specs.json에서 그리드 계약을 뽑는다."""
    for name in SHEET_SPEC_FILES:
        path = os.path.join(ROOT, "data", name)
        if not os.path.exists(path):
            continue
        for sp in json.load(io.open(path, encoding="utf-8")).get("species", []):
            if sp.get("id") != asset_id:
                continue
            # animations 없는 항목은 시트가 아니다(battle_cut_specs의 origin_player 같은
            # 참조 전용 항목). sp["animations"]로 바로 들어가면 KeyError가 나고 편집기의
            # 계약 API가 통째로 죽어 **기본 계약(셀 128·2열 5행)으로 조용히 대체**된다 —
            # 격자와 정렬 판정이 전부 엉뚱해지므로 여기서 걸러 낸다.
            if not isinstance(sp.get("animations"), dict) or not sp["animations"]:
                continue
            anims = sorted(sp["animations"].items(), key=lambda kv: int(kv[1].get("row", 0)))
            cols = max(int(a.get("frames", 1)) for _, a in anims)
            # sheet_cell = 납품 시트의 셀(그리는 크기). sp["cell"]은 게임 내 프레임
            # 크기({w,h})라 서로 다른 값이다 — 섞으면 안 된다.
            cell = int(sp.get("sheet_cell") or 128)
            return {
                "cell": cell,
                "cols": cols,
                "rows": len(anims),
                "size": [cols * cell, len(anims) * cell],
                "align": str(sp.get("align", "bottom_center")),
                "layout": [
                    {"row": int(a.get("row", 0)), "name": n, "frames": int(a.get("frames", 1))}
                    for n, a in anims
                ],
            }
    # 시트 스펙에 없으면 타일셋 스펙(assets/spec/sprites/*.json, kind=tileset)을 본다.
    tc = _tileset_module()
    if tc:
        con = tc.contract(asset_id)
        if con:
            return con
    return {}


def _tileset_module():
    """타일셋 계약 정본(`tools/convert/tileset_contract.py`)을 지연 임포트한다.

    계약 도출을 여기서 다시 구현하지 않는다 — 의뢰문·검증기·편집기가 같은 배치를 봐야
    하고, 두 벌이 되는 순간 한쪽만 고쳐져 좌표가 갈라진다(이 저장소가 반복해 물린 결함).
    순수 stdlib이라 서버 기동을 막지 않는다.
    """
    try:
        sys.path.insert(0, os.path.join(ROOT, "tools", "convert"))
        import tileset_contract  # noqa: PLC0415 — 지연 임포트(위 주석)
        return tileset_contract
    except Exception:  # noqa: BLE001 — 계약 하나가 없다고 심사 보드가 죽으면 안 된다
        return None


def next_version_name(cat: str, asset_id: str) -> str:
    """`<asset>_v<n+1>.png` — n은 **디스크에 실제로 있는** 최대 버전.

    예전에는 열어 둔 파일명에서 뽑았다. 그래서 v2를 열어 고치면 v3로 저장되는데 이미 v3가
    있으면 조용히 덮어썼다. 계약을 직접 고르는 경로(웹에서 받은 임의 파일명)에서는 더 나빠서
    v2로 떨어져 v4를 밀어낼 수 있었다. 세 스테이지를 전부 훑어 가장 큰 번호 다음을 쓴다.
    """
    best = 0
    for parts in (("10_submitted", cat), ("10_submitted", "_rejected", cat),
                  ("20_processed", cat)):
        d = safe_path(*parts)
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            m = VERSION_RE.match(f)
            if m and m.group("id") == asset_id:
                best = max(best, int(m.group("n")))
    return f"{asset_id}_v{best + 1}.png"


def fixer_assets(cat: str = "") -> list:
    """계약이 있는 에셋 전부 — 셀 편집기의 [계약] 드롭다운이 쓴다.

    왜 필요한가: 편집기는 **파일명에서** asset_id를 뽑아 계약을 찾는다
    (`flying_thesis_v4.png` → `flying_thesis`). 그래서 웹 챗에서 받아
    `ChatGPT Image ....png` 같은 이름으로 내려받은 그림을 열면 계약이 하나도 안 잡히고
    **크기 자동 조절도 격자도 통째로 죽는다** — "제일 기본이 안 된다"의 정체다.
    이 목록으로 사람이 대상 에셋을 직접 고를 수 있게 한다.
    """
    out = []
    for name in SHEET_SPEC_FILES:
        c = SPEC_FILE_CAT.get(name, "")
        if cat and c != cat:
            continue
        path = os.path.join(ROOT, "data", name)
        if not os.path.exists(path):
            continue
        for sp in json.load(io.open(path, encoding="utf-8")).get("species", []):
            aid = str(sp.get("id") or "")
            con = sheet_contract(aid) if aid else {}
            if not con:
                continue
            out.append({"cat": c, "asset_id": aid,
                        "name": str(sp.get("name_ko") or aid),
                        "cell": con["cell"], "rows": con["rows"], "cols": con["cols"],
                        "size": con["size"]})
    tc = _tileset_module()
    if tc and (not cat or cat == "sprites"):
        for aid in tc.tileset_ids():
            con = tc.contract(aid)
            if not con:
                continue
            out.append({"cat": "sprites", "asset_id": aid,
                        "name": f"{aid} (타일셋 {len(con['groups'])}묶음)",
                        "cell": con["cell"], "rows": con["rows"], "cols": con["cols"],
                        "size": con["size"]})
    for c, flat in FLAT_CONTRACTS.items():
        if cat and c != cat:
            continue
        cell = int(flat.get("cell", 0))
        size = flat.get("size") or [cell * int(flat["cols"]), cell * int(flat["rows"])]
        out.append({"cat": c, "asset_id": f"__flat__{c}", "name": f"{c} 공통 규격",
                    "cell": cell, "rows": int(flat["rows"]), "cols": int(flat["cols"]),
                    "size": size})
    out.sort(key=lambda a: (a["cat"], a["name"]))
    return out


def fixer_contract(cat: str, fname: str, asset: str = "") -> dict:
    """asset을 명시하면 파일명 대신 그것으로 계약을 찾는다(웹에서 받은 임의 파일명 대응)."""
    asset_id = asset or asset_id_of(fname)
    if asset_id.startswith("__flat__"):
        # 카테고리 공통 규격을 고른 경우 — 계약은 FLAT_CONTRACTS가 주고,
        # 이름(저장 파일명)은 원래대로 파일명에서 뽑는다.
        contract = {}
        asset_id = asset_id_of(fname)
    else:
        contract = sheet_contract(asset_id)
    if not contract and cat in FLAT_CONTRACTS:
        contract = dict(FLAT_CONTRACTS[cat])
        cell = int(contract.get("cell", 0))
        contract.setdefault("size", [cell * int(contract["cols"]), cell * int(contract["rows"])])
        contract["layout"] = [{"row": 0, "name": cat, "frames": int(contract["cols"])}]
    if not contract:
        contract = {"cell": 0, "cols": 1, "rows": 1, "size": [0, 0], "align": "none", "layout": []}
    # 실제 파일이 위치한 경로를 역추적하여 올바른 웹 서빙 경로 부여
    web = f"/assets/raw/llm/10_submitted/{cat}/{fname}"
    if not os.path.exists(safe_path("10_submitted", cat, fname)):
        if os.path.exists(safe_path("10_submitted", "_rejected", cat, fname)):
            web = f"/assets/raw/llm/10_submitted/_rejected/{cat}/{fname}"
        elif os.path.exists(safe_path("20_processed", cat, fname)):
            web = f"/assets/raw/llm/20_processed/{cat}/{fname}"
        elif os.path.exists(os.path.join(ROOT, "assets", "portraits", fname)):
            web = f"/assets/portraits/{fname}"
        elif os.path.exists(os.path.join(ROOT, "assets", "sprites", fname)):
            web = f"/assets/sprites/{fname}"

    contract.update({
        "cat": cat,
        "file": fname,
        "asset_id": asset_id,
        "web": web,
        "next_file": next_version_name(cat, asset_id),
        "prompt_md": read_prompt_md(cat, asset_id),
    })
    return contract


def fixer_files(cat: str = "") -> list:
    """셀 편집기 파일 선택기용 목록 — 납품 대기·반려·승인본을 한데 모은다.

    보드를 거치지 않고 편집기를 단독으로 띄우는 경로(셀편집기.bat) 때문에 필요하다.
    편집 대상은 10_submitted에만 있는 게 아니다: 반려본을 되살려 고치는 경우와
    승인본을 손보는 경우가 실제로 있어 세 스테이지를 모두 싣는다.
    """
    cats = [cat] if cat in CATEGORIES else list(CATEGORIES)
    out = []
    stages = (
        ("submitted", lambda c: safe_path("10_submitted", c), "/assets/raw/llm/10_submitted/{c}/{f}"),
        ("rejected", lambda c: safe_path("10_submitted", "_rejected", c), "/assets/raw/llm/10_submitted/_rejected/{c}/{f}"),
        ("processed", lambda c: safe_path("20_processed", c), "/assets/raw/llm/20_processed/{c}/{f}"),
    )
    for c in cats:
        for status, dir_of, web_fmt in stages:
            d = dir_of(c)
            if not os.path.isdir(d):
                continue
            for fname in sorted(os.listdir(d)):
                if not fname.lower().endswith(".png"):
                    continue
                p = os.path.join(d, fname)
                out.append({
                    "cat": c,
                    "file": fname,
                    "asset_id": asset_id_of(fname),
                    "status": status,
                    "web": web_fmt.format(c=c, f=fname),
                    "size": os.path.getsize(p),
                    "mtime": int(os.path.getmtime(p)),
                })
    return out


def fixer_op(payload: dict) -> dict:
    """셀 편집기의 시트 연산 — 규칙은 sheet_ops.py 하나에만 있다.

    편집기(자바스크립트)가 같은 판정을 다시 구현하고 있었다. 그러면 한쪽만 튜닝됐을 때
    "편집기에서는 깨끗한데 검증기는 반려하는" 상태가 조용히 생긴다 — 이 저장소가 반복해
    물린 중복 로직 결함이다. 그래서 픽셀을 만지는 일은 전부 서버(=파이썬 정본)가 한다.

    PIL/numpy는 여기서만 **지연 임포트**한다: 서버 자체는 stdlib으로 뜨고, 픽셀 연산을
    처음 누를 때 비로소 필요해진다(설치되지 않은 환경에서도 심사 보드는 그대로 돈다).
    """
    sys.path.insert(0, os.path.join(ROOT, "tools", "convert"))
    from PIL import Image  # noqa: PLC0415 — 지연 임포트(위 주석)
    import sheet_ops  # noqa: PLC0415

    data_url = str(payload.get("png", ""))
    if "," not in data_url:
        raise ValueError("png 데이터가 없다")
    raw = base64.b64decode(data_url.split(",", 1)[1])
    im = Image.open(io.BytesIO(raw)).convert("RGBA")
    params = payload.get("params") or {}
    op = str(payload.get("op", ""))
    if op == "measure":
        log = ""
    else:
        im, log = sheet_ops.apply_op(im, op, params)
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    stats = sheet_ops.measure(
        im,
        cell=int(params.get("cell") or 0),
        rows=int(params.get("rows") or 0),
        cols=int(params.get("cols") or 0),
        layout=params.get("layout") or [],
        align=str(params.get("align") or "bottom_center"),
        budget=int(params.get("budget") or 48),
        # 묶음을 안 넘기면 다중 타일 소품의 조각이 전부 "가로 중앙 이탈"로 잡힌다.
        groups=params.get("groups") or [],
    )
    return {
        "ok": True, "log": log, "stats": stats,
        "png": "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode(),
    }


def fixer_webprompt(cat: str, fname: str) -> dict:
    """첨부 없이 웹 챗에 붙여넣는 프롬프트 — 공통 규약 + 이 시트 상세.

    편집기에서 바로 복사하려고 있는 자리다. 텍스트는 `tools/convert/web_prompt.py`가
    스펙에서 굽는다(손으로 쓴 허브 문서가 규격과 어긋나 있던 전례가 있다).
    """
    sys.path.insert(0, os.path.join(ROOT, "tools", "convert"))
    import web_prompt  # noqa: PLC0415 — 지연 임포트(PIL 계열 의존)

    asset_id = asset_id_of(fname)
    return {
        "asset_id": asset_id,
        "common": web_prompt.common_prompt(),
        "sheet": web_prompt.sheet_prompt(cat, asset_id),
    }


def fixer_save(payload: dict) -> dict:
    cat = payload.get("cat", "")
    if cat not in CATEGORIES:
        raise ValueError(f"알 수 없는 카테고리: {cat}")
    data_url = str(payload.get("png", ""))
    if "," not in data_url:
        raise ValueError("png 데이터가 없다")
    raw = base64.b64decode(data_url.split(",", 1)[1])
    src_name = os.path.basename(payload.get("file", ""))
    out_name = os.path.basename(payload.get("out", "")) or src_name
    if not out_name.lower().endswith(".png"):
        raise ValueError("파일명이 .png가 아니다")
    dst = safe_path("10_submitted", cat, out_name)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    # 있는 파일을 조용히 덮지 않는다 — 심사 대기 중인 납품을 지우는 사고가 난다.
    # 원본을 그 자리에서 고쳐 넣는 경우(같은 파일을 열어 저장)만 예외로 허용한다.
    if os.path.exists(dst) and out_name != src_name:
        bumped = next_version_name(cat, asset_id_of(out_name))
        dst = safe_path("10_submitted", cat, bumped)
        out_name = bumped
    io.open(dst, "wb").write(raw)
    # 편집 직후 같은 검증기를 돌려 결과를 그대로 돌려준다 — 고쳤는지 그 자리에서 안다.
    return {"ok": True, "saved": f"10_submitted/{cat}/{out_name}",
            "validation": run_validator(cat, dst)}


class Handler(SimpleHTTPRequestHandler):
    def _json(self, code: int, obj: dict) -> None:
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/api/categories":
            cats = {}
            for cat in CATEGORIES:
                cat_dir = safe_path("10_submitted", cat)
                n = (
                    len([f for f in os.listdir(cat_dir) if f.lower().endswith(".png")])
                    if os.path.isdir(cat_dir)
                    else 0
                )
                cats[cat] = n
            self._json(200, {"categories": cats})
        elif parsed.path == "/api/fixer/assets":
            q = parse_qs(parsed.query)
            self._json(200, {"assets": fixer_assets(q.get("cat", [""])[0])})
        elif parsed.path == "/api/fixer/contract":
            q = parse_qs(parsed.query)
            cat = q.get("cat", [""])[0]
            fname = os.path.basename(q.get("file", [""])[0])
            if cat not in CATEGORIES or not fname:
                self._json(400, {"error": "bad cat/file"})
                return
            self._json(200, fixer_contract(cat, fname, q.get("asset", [""])[0]))
        elif parsed.path == "/api/fixer/webprompt":
            q = parse_qs(parsed.query)
            cat = q.get("cat", [""])[0]
            fname = os.path.basename(q.get("file", [""])[0])
            if cat not in CATEGORIES or not fname:
                self._json(400, {"error": "bad cat/file"})
                return
            self._json(200, fixer_webprompt(cat, fname))
        elif parsed.path == "/api/fixer/files":
            q = parse_qs(parsed.query)
            self._json(200, {"files": fixer_files(q.get("cat", [""])[0]),
                             "categories": list(CATEGORIES)})
        elif parsed.path == "/api/list":
            cat = parse_qs(parsed.query).get("cat", [""])[0]
            if cat not in CATEGORIES:
                self._json(400, {"error": "bad cat"})
                return
            self._json(200, {"items": list_items(cat)})
        else:
            # 정적 서빙(보드·이미지) — 기본 핸들러가 프로젝트 루트 기준으로 처리
            super().do_GET()

    def do_POST(self) -> None:  # noqa: N802
        if urlparse(self.path).path not in ("/api/review", "/api/batch", "/api/fixer/save", "/api/fixer/op"):
            self._json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if urlparse(self.path).path == "/api/fixer/op":
                self._json(200, fixer_op(payload))
            elif urlparse(self.path).path == "/api/fixer/save":
                self._json(200, fixer_save(payload))
            elif urlparse(self.path).path == "/api/batch":
                results = []
                for item in list_items(payload.get("cat", "")):
                    results.append(do_review({
                        "cat": payload["cat"], "file": item["file"],
                        "action": payload.get("action", ""), "feedback": payload.get("feedback", ""),
                    }))
                self._json(200, {"ok": True, "count": len(results)})
            else:
                self._json(200, do_review(payload))
        except Exception as exc:  # noqa: BLE001 — API 오류는 JSON으로 반환
            self._json(400, {"error": str(exc)})

    def log_message(self, fmt: str, *args) -> None:  # noqa: N802 — 콘솔 소음 억제
        pass


def main() -> None:
    os.chdir(ROOT)  # 정적 서빙 루트 = 프로젝트 (viewer.html 패턴과 동일)
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"심사 서버: http://127.0.0.1:{PORT}/tools/review/review_board.html")
    print("중지: Ctrl+C")
    server.serve_forever()


if __name__ == "__main__":
    main()
