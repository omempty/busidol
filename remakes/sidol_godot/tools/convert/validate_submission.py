"""LLM 납품 자동 판정 게이트 — 포트레이트·키아트·아이템 아이콘.

스프라이트 시트는 validate_retouch_sheet.py / process_llm_sheet.py가 담당.
본 스크립트는 그 외 카테고리의 납품(10_submitted/)을 규격·키잉·AA·내용 충실
관점에서 자동 판정한다. FAIL은 20_processed로 넘어가지 않는다(LLM_WORKFLOW 규약).

판정 항목:
  portrait — 768×256(256셀 3개) 규격, 셀별 내용 존재, 배경 키잉 가능
             (투명 또는 마젠타), 반투명 AA 픽셀 비율, 팔레트 이탈(경고)
  keyart   — 1920×1080 규격(16:9 이탈은 경고), 무내용(단색) 판정,
             팔레트 이탈(경고)
  icon     — 96×96 규격(기존 아이콘 24종 실측치), 테두리 키잉, 내용 존재,
             팔레트 이탈(경고). 인벤토리·상점·슬롯바가 같은 크기로 쓴다
  공통     — delivery_checks: 격자 안내선 잔존(반려) · 고유색 수 · 순수 검정 ·
             반투명. 2026-08-28 실납품 9장이 위 항목만으로 전부 통과해 버려서 붙였다.

실행: python tools/convert/validate_submission.py portrait <png>
      python tools/convert/validate_submission.py keyart <png>
      python tools/convert/validate_submission.py icon <png>
종료코드: 0=PASS(경고 포함) / 1=FAIL
"""
from __future__ import annotations
import io
import json
import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import numpy as np
from PIL import Image

import delivery_checks as dc
from llm_package_common import scale6to8

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
PALETTE_JSON = os.path.join(ROOT, "assets", "palette_master.json")

MAGENTA = np.array([255, 0, 255])
MAGENTA_TOL = 90  # 마젠타 판정 거리 — 혼색 혐의는 AA/키잉 검사가 잡는다

PORTRAIT_SIZE = (768, 256)
PORTRAIT_CELL = 256
KEYART_SIZE = (1920, 1080)
## 아이템 아이콘 — 기존 assets/icons/*.png 24종이 전부 96×96이다(실측).
ICON_SIZE = (96, 96)

AA_FAIL_RATIO = 0.05   # 반투명 픽셀 >5% — AA 유입 판정
AA_WARN_RATIO = 0.01
BORDER_KEY_MIN = 0.95  # 셀 테두리 2px 중 키잉 가능 비율 하한
CONTENT_MIN_PIXELS = 100
PALETTE_WARN_DIST = 60.0  # 평균 최근접 팔레트 거리 — 이탈 경고


class Report:
    def __init__(self) -> None:
        self.lines: list[str] = []
        self.failed = False

    def fail(self, msg: str) -> None:
        self.failed = True
        self.lines.append(f"FAIL {msg}")

    def warn(self, msg: str) -> None:
        self.lines.append(f"WARN {msg}")

    def ok(self, msg: str) -> None:
        self.lines.append(f"ok   {msg}")


def load_rgba(path: str) -> Image.Image:
    im = Image.open(path)
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    return im


def is_keyable(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """투명 또는 마젠타 배경 판정 배열."""
    dist = np.abs(rgb.astype(int) - MAGENTA).sum(axis=2)
    return (alpha < 16) | (dist < MAGENTA_TOL)


def check_common(im: Image.Image, rep: Report, region: str, box: tuple[int, int, int, int]) -> None:
    """반투명 AA 비율 + 내용 존재 — 셀 또는 전체 영역 공통."""
    a = np.asarray(im.crop(box))
    alpha = a[:, :, 3]
    rgb = a[:, :, :3]
    semi = ((alpha > 16) & (alpha < 240)).mean()
    if semi > AA_FAIL_RATIO:
        rep.fail(f"{region}: 반투명 픽셀 {semi:.1%} — 안티에일리어싱 유입(금지)")
    elif semi > AA_WARN_RATIO:
        rep.warn(f"{region}: 반투명 픽셀 {semi:.1%} — 경계 확인 권장")
    opaque = alpha >= 240
    if int(opaque.sum()) < CONTENT_MIN_PIXELS:
        rep.fail(f"{region}: 불투명 내용 {int(opaque.sum())}px — 사실상 공셀")
    else:
        rep.ok(f"{region}: 내용 {int(opaque.sum())}px")


def check_border_keyable(im: Image.Image, rep: Report, box: tuple[int, int, int, int]) -> None:
    """셀 테두리가 키잉 가능(투명/마젠타)인지 — 체커보드·흰 배경 반려."""
    a = np.asarray(im.crop(box))
    alpha = a[:, :, 3]
    rgb = a[:, :, :3]
    ring = np.ones(alpha.shape, dtype=bool)
    ring[2:-2, 2:-2] = False
    key_ratio = is_keyable(rgb, alpha)[ring].mean()
    if key_ratio < BORDER_KEY_MIN:
        rep.fail(f"셀{box}: 테두리 키잉 비율 {key_ratio:.1%} — 배경이 투명/마젠타가 아님")


def palette_colors() -> np.ndarray:
    """palette_master.json hex 문자열 리스트 → (N,3) RGB 배열.

    colors는 6비트 DAC 원값이라 그대로 쓰면 팔레트 전체가 25% 밝기다.
    그 기준으로 거리를 재면 **정상 밝기 납품이 항상 "팔레트 이탈"로 경고**되고,
    반대로 어두운 납품이 통과한다. 스왑치와 같은 변환을 쓴다.
    """
    hexes = json.load(io.open(PALETTE_JSON, encoding="utf-8"))["colors"]
    return np.array([scale6to8(h) for h in hexes])


def check_palette(im: Image.Image, rep: Report, box: tuple[int, int, int, int]) -> None:
    """팔레트 이탈 평균 거리 — 경고만(스타일 가이드 수준)."""
    colors = palette_colors()
    rgb = np.asarray(im.crop(box))[:, :, :3].reshape(-1, 3)
    rgb = rgb[::7]
    if rgb.shape[0] == 0:
        return
    # 청크 순회로 최근접 거리(메모리 폭발 방지)
    d = np.empty(rgb.shape[0])
    for i in range(0, rgb.shape[0], 4096):
        chunk = rgb[i:i + 4096].astype(int)
        dists = np.abs(chunk[:, None, :] - colors[None, :, :].astype(int)).sum(axis=2)
        d[i:i + 4096] = dists.min(axis=1)
    mean_d = float(d.mean())
    if mean_d > PALETTE_WARN_DIST:
        rep.warn(f"팔레트 평균 거리 {mean_d:.0f} — 마스터 팔레트 이탈 의심(톤 점검)")
    else:
        rep.ok(f"팔레트 평균 거리 {mean_d:.0f}")


def apply_shared_checks(im: Image.Image, rep: Report, cell_w: int, cell_h: int) -> None:
    """delivery_checks 묶음 — 격자 잔선·색 수·순수 검정·반투명.

    등급 분기는 delivery_checks.is_fail 한 곳에서만 정한다(검증기 3종이 갈라지지 않게).
    """
    findings = dc.run_all(im, cell_w, cell_h)
    if not findings:
        rep.ok("잔선·색 수·검정·반투명 이상 없음")
        return
    for f in findings:
        (rep.fail if dc.is_fail(f) else rep.warn)(f.msg)


def validate_portrait(path: str, rep: Report) -> None:
    im = load_rgba(path)
    if im.size != PORTRAIT_SIZE:
        rep.fail(f"크기 {im.size[0]}x{im.size[1]} — 규격 {PORTRAIT_SIZE[0]}x{PORTRAIT_SIZE[1]}")
        return
    rep.ok(f"크기 {im.size[0]}x{im.size[1]}")
    apply_shared_checks(im, rep, PORTRAIT_CELL, PORTRAIT_CELL)
    for i in range(3):
        box = (i * PORTRAIT_CELL, 0, (i + 1) * PORTRAIT_CELL, PORTRAIT_CELL)
        check_border_keyable(im, rep, box)
        check_common(im, rep, f"셀{i + 1}", box)
        check_palette(im, rep, box)


def validate_keyart(path: str, rep: Report) -> None:
    im = load_rgba(path)
    if im.size != KEYART_SIZE:
        if im.size[0] * 9 == im.size[1] * 16:
            rep.warn(f"크기 {im.size[0]}x{im.size[1]} — 16:9이나 규격 {KEYART_SIZE[0]}x{KEYART_SIZE[1]} 아님(리스케일 필요)")
        else:
            rep.fail(f"크기 {im.size[0]}x{im.size[1]} — 16:9 규격 위반")
            return
    else:
        rep.ok(f"크기 {im.size[0]}x{im.size[1]}")
    arr = np.asarray(im.convert("RGB").convert("L")).astype(float)
    if arr.std() < 4.0:
        rep.fail(f"명도 표준편차 {arr.std():.1f} — 단색/무내용 이미지")
    else:
        rep.ok(f"명도 표준편차 {arr.std():.1f}")
    # 키아트는 한 장 그림이라 셀이 없다 — 셀 변 대신 화면 1/8을 직선 판정 기준으로 쓴다.
    apply_shared_checks(im, rep, im.width // 8, im.height // 8)
    check_palette(im, rep, (0, 0, im.width, im.height))


def validate_icon(path: str, rep: Report) -> None:
    im = load_rgba(path)
    if im.size != ICON_SIZE:
        rep.fail(f"크기 {im.size[0]}x{im.size[1]} — 규격 {ICON_SIZE[0]}x{ICON_SIZE[1]}")
        return
    rep.ok(f"크기 {im.size[0]}x{im.size[1]}")
    box = (0, 0, im.width, im.height)
    apply_shared_checks(im, rep, ICON_SIZE[0], ICON_SIZE[1])
    check_border_keyable(im, rep, box)
    check_common(im, rep, "아이콘", box)
    check_palette(im, rep, box)


MODES = {"portrait": validate_portrait, "keyart": validate_keyart, "icon": validate_icon}


def main() -> None:
    if len(sys.argv) != 3 or sys.argv[1] not in MODES:
        raise SystemExit(__doc__)
    mode, path = sys.argv[1], sys.argv[2]
    if not os.path.exists(path):
        raise SystemExit(f"파일 없음: {path}")
    rep = Report()
    MODES[mode](path, rep)
    for line in rep.lines:
        print(line)
    print(f"[{mode}] {'FAIL' if rep.failed else 'PASS'} — {path}")
    raise SystemExit(1 if rep.failed else 0)


if __name__ == "__main__":
    main()
