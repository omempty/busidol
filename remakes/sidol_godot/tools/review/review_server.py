"""LLM 납품 심사 서버 — 검증 배지·승인/반려·재요청 프롬프트 생성.

stdlib 전용(http.server + subprocess). 프로젝트 루트를 정적 서빙하고
아래 API로 심사 보드(review_board.html)와 통신한다.

  GET  /api/categories                     카테고리 목록·건수
  GET  /api/list?cat=portraits             납품 목록(+검증 결과·피드백 md·참조 경로)
  POST /api/review  {cat,file,action,feedback}  승인(20_processed 이동 + assets 설치)/반려(피드백 md)
  POST /api/batch   {cat,action,feedback}       전체 승인/전체 반려
  GET  /api/fixer/contract?cat&file            셀 편집기용 그리드 계약(셀 크기·행별 프레임)
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


def run_validator(cat: str, abs_path: str) -> dict:
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
        return {"pass": proc.returncode == 0, "lines": lines[-8:]}
    except Exception as exc:  # noqa: BLE001 — 검증기 크래시도 배지로 표시
        return {"pass": False, "lines": [f"검증기 오류: {exc}"]}


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
    cat_dir = safe_path("10_submitted", cat)
    if not os.path.isdir(cat_dir):
        return []
    items = []
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
            "validation": run_validator(cat, abs_path),
            "feedback": feedback,
            "prompt_md": read_prompt_md(cat, asset_id),
            "refs": reference_paths(cat, asset_id),
            "web": f"/assets/raw/llm/10_submitted/{cat}/{fname}",
        })
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
    if action not in ("approve", "reject"):
        raise ValueError(f"알 수 없는 액션: {action}")
    fname = os.path.basename(payload.get("file", ""))
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
            anims = sorted(sp["animations"].items(), key=lambda kv: int(kv[1].get("row", 0)))
            cols = max(int(a.get("frames", 1)) for _, a in anims)
            cell = int(sp.get("sheet_cell", 128))
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
    return {}


def fixer_contract(cat: str, fname: str) -> dict:
    asset_id = asset_id_of(fname)
    contract = sheet_contract(asset_id)
    if not contract and cat in FLAT_CONTRACTS:
        contract = dict(FLAT_CONTRACTS[cat])
        cell = int(contract.get("cell", 0))
        contract.setdefault("size", [cell * int(contract["cols"]), cell * int(contract["rows"])])
        contract["layout"] = [{"row": 0, "name": cat, "frames": int(contract["cols"])}]
    if not contract:
        contract = {"cell": 0, "cols": 1, "rows": 1, "size": [0, 0], "align": "none", "layout": []}
    m = VERSION_RE.match(fname)
    contract.update({
        "cat": cat,
        "file": fname,
        "asset_id": asset_id,
        "web": f"/assets/raw/llm/10_submitted/{cat}/{fname}",
        "next_file": f"{asset_id}_v{int(m.group('n')) + 1 if m else 2}.png",
        "prompt_md": read_prompt_md(cat, asset_id),
    })
    return contract


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
        elif parsed.path == "/api/fixer/contract":
            q = parse_qs(parsed.query)
            cat = q.get("cat", [""])[0]
            fname = os.path.basename(q.get("file", [""])[0])
            if cat not in CATEGORIES or not fname:
                self._json(400, {"error": "bad cat/file"})
                return
            self._json(200, fixer_contract(cat, fname))
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
        if urlparse(self.path).path not in ("/api/review", "/api/batch", "/api/fixer/save"):
            self._json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if urlparse(self.path).path == "/api/fixer/save":
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
