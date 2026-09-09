#!/usr/bin/env python3
"""납품 자동 판정 공통 부품 — 게이트를 통과해 버린 결함들을 잡는 층.

## 왜 생겼나 (2026-08-28 수동 검증)

납품 9장이 `validate_monster_sheet.py`·`validate_submission.py`를 **전부 통과**했는데
눈으로 보니 5건이 반려급이었다. 게이트가 못 본 것:

1. **격자 템플릿 잔선** — `make_grid_template`이 안내선을 반투명(alpha 110)으로 깔았고,
   그림 LLM이 그 위에 그린 뒤 배경을 합성해 **불투명 반감광 마젠타(#850080 대)**로 구워 왔다.
   정확한 `#FF00FF`가 아니라서 ① 마젠타 키잉이 안 지우고 ② near-magenta(R>195) 판정도 비껴갔다.
   납품물이 리샘플링돼 오면 좌표도 밀리므로 **좌표 대조가 아니라 직선 런**으로 잡는다.
2. **라벨 글자 바** — 템플릿에 행 이름을 글자로 찍어 놨더니(`d.text`) 납품물이 그걸 따라 그렸다.
   `null_pointer_v3`는 "Idle / Attack Seg / Fault Claws / Hurt / Death…" 바가 6칸에 박혀 왔다.
3. **고유색 수 폭증** — 계약은 24~48색인데 실납품은 16,772~50,666색(원작 도트는 18~34색).
   팔레트 평균 거리 검사는 "가까운 색이 있는가"만 보므로 부드러운 그라데이션을 못 잡는다.

각 검사는 (통과여부, 메시지, 수치) 튜플이 아니라 **Finding 리스트**를 돌려주고,
어떤 등급(FAIL/WARN)으로 쓸지는 호출자가 정한다 — 카테고리마다 허용치가 다르다.
"""
from __future__ import annotations

import numpy as np
from PIL import Image

## 안내선 색 — make_grid_template이 쓰는 두 색. 반투명으로 깔렸다가 합성되면
## 밝기만 떨어지고 색상(hue)은 유지되므로, 밝기와 무관하게 색상으로 판정한다.
MAGENTA_HUE = "magenta"
CYAN_HUE = "cyan"
## 직선 런 판정 — 셀 변 길이의 이 비율 이상이 한 줄로 이어지면 그림이 아니라 선이다.
LINE_RUN_RATIO = 0.5
## 셀 안 한 줄에서 안내선 색이 이 비율 이상이면 선으로 본다(가려져 끊긴 선 대응).
LINE_DENSITY = 0.3
## 안내선은 단색이다 — 한 줄의 채널별 색 폭이 이보다 넓으면 그림의 음영으로 본다.
LINE_COLOR_SPREAD = 40
## 안내선은 얇다 — 연속으로 이만큼 넘게 뭉치면 선이 아니라 채색 면이다.
LINE_MAX_THICKNESS = 3
## 액자 판정 — 내용이 있는 셀 중 이 비율 이상에서 같은 좌표·같은 색 직선이 나오면 액자다.
BORDER_REPEAT_RATIO = 0.6
## 반쪽 잘림 판정 — 두 덩어리가 이만큼 비슷하고, 이만큼 벌어져 있고, 각자 충분히 크면.
SPLIT_SIZE_RATIO = 0.6
SPLIT_MIN_GAP = 4
SPLIT_MIN_PIXELS = 300
## 고유색 계약 — 프롬프트가 박는 값(24~48)의 상한. 넘으면 그라데이션 유입.
##
## ## 48이 어디서 온 숫자인가 (2026-09-09, 원작 실측)
##
## "48색이면 너무 적은 것 아닌가"는 원작을 재 보면 답이 나온다. 대상 하나짜리
## 에셋은 원작이 그보다 훨씬 적게 쓴다 — 48은 오히려 두 배 이상 여유다.
##
##   캐릭터 시트(*_original.png, 20종)  9 ~ 37색 (중앙값 19)
##     null_pointer 9 · flying_thesis 12 · c_bug 18 · mad_eye 25 · guard_idle 37
##   원작 얼굴(originals_ref/face*.png) 27 ~ 35색
##   아이콘(설치본 64종)                 4 ~ 20색 (중앙값 6)
##   이펙트(originals_ref/effect.png)    9색
##
## 반면 **여러 대상이 한 장에 든** 에셋은 원작이 훨씬 많이 쓴다. 그런 카테고리가
## 생기면 이 값을 그대로 쓰면 안 된다(근거로 쓰라고 수치를 남긴다):
##
##   소품·오브젝트 모음(obj_original_32.png)      131색
##   타일셋·필드(remastered/tile_32, i_field_64)  132 ~ 138색
##   원작 화면 UI(hp.png, store.png)               76 ~ 138색
##
## 지금은 소품·타일셋 납품 경로가 없어(CATEGORIES에도 스펙 파일에도 없다) 카테고리별
## 표를 두지 않는다 — 쓰지 않는 표는 이 저장소가 반복해 물린 '사문화 데이터'가 된다.
## 키아트·초상은 이미 validate_submission이 allow_rich_colors로 완화해 받는다.
COLOR_BUDGET = 48
## 후처리 양자화로도 살리기 어려운 수준 — 이 위는 사실상 리샘플된 풀컬러 이미지다.
COLOR_HARD_CAP = 4096
## 순수 검정 금지(외곽선은 짙은 남색) — 이 비율을 넘으면 경고.
PURE_BLACK_WARN = 0.005
## 플레이스홀더 판정 — 이만큼 큰 그림에 이보다 색이 적으면 그림이 아니다.
PLACEHOLDER_MIN_PIXELS = 20000
PLACEHOLDER_MIN_COLORS = 12


class Finding:
    """검사 결과 한 건. level은 호출자가 등급으로 해석한다."""

    def __init__(self, code: str, msg: str, value=None) -> None:
        self.code = code
        self.msg = msg
        self.value = value

    def __repr__(self) -> str:  # 디버그용
        return f"<{self.code}: {self.msg}>"


def _rgba(im: Image.Image) -> tuple:
    a = np.asarray(im.convert("RGBA")).astype(int)
    return a[:, :, :3], a[:, :, 3]


def opaque_mask(im: Image.Image) -> np.ndarray:
    """불투명(=그림) 픽셀. 정확한 마젠타 배경은 배경으로 친다."""
    rgb, alpha = _rgba(im)
    exact_magenta = (rgb[:, :, 0] == 255) & (rgb[:, :, 1] == 0) & (rgb[:, :, 2] == 255)
    return (alpha > 8) & ~exact_magenta


def guide_hue_mask(im: Image.Image) -> dict:
    """안내선 색상 마스크 — 밝기 무관.

    마젠타 계열: R≈B, G가 둘보다 확연히 낮다(그림의 보라 음영과 겹칠 수 있으므로
    직선 판정과 **함께** 써야 한다 — 이 마스크 단독으로는 반려 근거가 못 된다).
    시안 계열: G≈B, R이 확연히 낮다.
    """
    rgb, alpha = _rgba(im)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    vis = alpha > 8
    mag = (np.abs(r - b) < 40) & (g + 40 < np.minimum(r, b)) & (np.maximum(r, b) > 40) & vis
    cyan = (np.abs(g - b) < 40) & (r + 40 < np.minimum(g, b)) & (np.maximum(g, b) > 40) & vis
    return {MAGENTA_HUE: mag, CYAN_HUE: cyan}


def _runs(mask: np.ndarray, min_len: int) -> list:
    """마스크에서 가로·세로 직선 런을 찾는다. 반환 [(축, 좌표, 시작, 길이)]."""
    found = []
    h, w = mask.shape
    for y in range(h):
        row = mask[y]
        if row.sum() < min_len:
            continue
        start = None
        for x in range(w + 1):
            on = x < w and row[x]
            if on and start is None:
                start = x
            elif not on and start is not None:
                if x - start >= min_len:
                    found.append(("row", y, start, x - start))
                start = None
    for x in range(w):
        col = mask[:, x]
        if col.sum() < min_len:
            continue
        start = None
        for y in range(h + 1):
            on = y < h and col[y]
            if on and start is None:
                start = y
            elif not on and start is not None:
                if y - start >= min_len:
                    found.append(("col", x, start, y - start))
                start = None
    return found


def _dense_lines(rgb: np.ndarray, mask: np.ndarray, cell_w: int, cell_h: int) -> int:
    """셀 안의 **얇고 단색이며 밀도 높은** 행/열 수 = 가려져 끊긴 안내선.

    세 조건을 모두 걸어야 그림과 구분된다(실측으로 하나씩 붙였다):
      밀도  — 런 길이만 보면 스프라이트 뒤로 지나가며 토막 난 선을 놓친다(c_bug).
      단색  — 밀도만 보면 원작 도트의 음영이 잡힌다(c_bug_original 청록 13줄).
      두께  — 단색까지 걸어도 **평면 채색**이 잡힌다(null_pointer_original 23줄).
              안내선은 1~2px다. 연속으로 뭉친 줄(=면)은 세지 않는다.
    """
    h, w = mask.shape
    total = 0
    for r in range(max(1, h // cell_h)):
        for c in range(max(1, w // cell_w)):
            y0, x0 = r * cell_h, c * cell_w
            sub = mask[y0:y0 + cell_h, x0:x0 + cell_w]
            sub_rgb = rgb[y0:y0 + cell_h, x0:x0 + cell_w]
            if sub.size == 0:
                continue
            for axis in (1, 0):
                dens = sub.mean(axis=axis)
                flags = []
                for i in range(dens.shape[0]):
                    if dens[i] < LINE_DENSITY:
                        flags.append(False)
                        continue
                    line_mask = sub[i, :] if axis == 1 else sub[:, i]
                    sel = (sub_rgb[i, :] if axis == 1 else sub_rgb[:, i])[line_mask]
                    flags.append(
                        bool(sel.size)
                        and int((sel.max(axis=0) - sel.min(axis=0)).max()) <= LINE_COLOR_SPREAD
                    )
                # 연속 그룹으로 묶어 두께가 얇은 것만 선으로 센다.
                i = 0
                while i < len(flags):
                    if not flags[i]:
                        i += 1
                        continue
                    j = i
                    while j < len(flags) and flags[j]:
                        j += 1
                    if j - i <= LINE_MAX_THICKNESS:
                        total += j - i
                    i = j
    return total


def _thin_runs(runs: list) -> list:
    """직선 런 중 **얇은 것만** 남긴다.

    런 길이만 보면 채색 면이 걸린다 — 아이콘의 청록 액체가 48px짜리 가로 런을
    72줄 쌓아 만든다(실측: ITEM_FLASK_TRI_1). 안내선은 1~2px 두께다.
    같은 방향·겹치는 구간의 런이 수직 방향으로 몇 줄 연속되는지 세고, 두꺼우면 버린다.
    """
    by_axis = {}
    for ax, pos, start, length in runs:
        by_axis.setdefault(ax, []).append((pos, start, length))
    kept = []
    for ax, items in by_axis.items():
        items.sort()
        for pos, start, length in items:
            thickness = 1
            for step in (-1, 1):
                k = 1
                while k <= LINE_MAX_THICKNESS:
                    nb = [
                        it for it in items
                        if it[0] == pos + step * k
                        and it[1] < start + length and start < it[1] + it[2]
                    ]
                    if not nb:
                        break
                    thickness += 1
                    k += 1
            if thickness <= LINE_MAX_THICKNESS:
                kept.append((ax, pos, start, length))
    return kept


def check_guide_residue(im: Image.Image, cell_w: int, cell_h: int) -> list:
    """격자 템플릿 안내선·라벨 바 잔존 검사.

    두 신호를 함께 본다: ① 셀 변의 LINE_RUN_RATIO 이상 이어지는 직선 런,
    ② 셀 안에서 안내선 색 밀도가 LINE_DENSITY 이상인 행/열(가려져 끊긴 선).
    도트 그림에 이런 줄이 생기는 일은 사실상 없다(있어도 셀 경계와 나란하지 않다).
    """
    findings = []
    masks = guide_hue_mask(im)
    rgb, _alpha = _rgba(im)
    min_len = int(min(cell_w, cell_h) * LINE_RUN_RATIO)
    for hue, mask in masks.items():
        runs = _thin_runs(_runs(mask, min_len))
        dense = _dense_lines(rgb, mask, cell_w, cell_h)
        if not runs and dense:
            findings.append(
                Finding(
                    "guide_residue",
                    "격자 안내선 잔존 의심 — %s 계열 고밀도 줄 %d개(그림에 가려 끊긴 선)" % (hue, dense),
                    dense,
                )
            )
        if not runs:
            continue
        sample = runs[:4]
        where = ", ".join(
            "%s%d(%d~%dpx)" % (ax, pos, start, start + length) for ax, pos, start, length in sample
        )
        findings.append(
            Finding(
                "guide_residue",
                "격자 안내선 잔존 의심 — %s 계열 직선 %d줄: %s%s"
                % (hue, len(runs), where, " …" if len(runs) > 4 else ""),
                len(runs),
            )
        )
    return findings


def _repeated_lines(op: np.ndarray, cell_w: int, cell_h: int) -> tuple:
    """셀마다 **같은 좌표**에 나타나는 긴 직선을 센다. 반환 (내용 셀 수, {(축, 좌표): 셀 수}).

    색은 보지 않는다 — "선을 지우라"는 지시를 색만 바꿔 피해 갈 수 있기 때문이다.
    """
    from collections import Counter

    h, w = op.shape
    tally: Counter = Counter()
    cells = 0
    for r in range(max(1, h // cell_h)):
        for c in range(max(1, w // cell_w)):
            sub = op[r * cell_h:(r + 1) * cell_h, c * cell_w:(c + 1) * cell_w]
            if not sub.any():
                continue
            cells += 1
            rows_n, cols_n = sub.shape
            for x in np.nonzero(sub.sum(axis=0) >= rows_n * LINE_RUN_RATIO)[0]:
                tally[("col", int(x))] += 1
            for y in np.nonzero(sub.sum(axis=1) >= cols_n * LINE_RUN_RATIO)[0]:
                tally[("row", int(y))] += 1
    return cells, tally


def _thin_groups(coords: list) -> list:
    """연속 좌표를 묶어 **얇은 그룹만** 남긴다.

    이 조건이 액자와 그림을 가른다(실측):
      액자   — 셀마다 같은 자리에 **1~3px 단독 선**(mad_eye 리마스터: col21 · row26)
      그림   — 반복되는 것은 몸통이라 **수십 px 덩어리**(guard_idle_original: col48~79 = 32px)
    """
    if not coords:
        return []
    coords = sorted(coords)
    out, run = [], [coords[0]]
    for v in coords[1:]:
        if v == run[-1] + 1:
            run.append(v)
        else:
            out.append(run)
            run = [v]
    out.append(run)
    return [g for g in out if len(g) <= LINE_MAX_THICKNESS]


def check_frame_border(im: Image.Image, cell_w: int, cell_h: int) -> list:
    """셀마다 같은 자리에 반복되는 **얇은** 직선 = 액자·안내선을 색만 바꿔 그린 것.

    안내선 검사(check_guide_residue)는 마젠타·청록 **색상**만 본다. 실납품에서
    "선을 전부 지우라"는 지시를 **색만 바꿔 그대로 그리는** 회피가 나왔다
    (mad_eye 리마스터: 셀마다 x=21에 짙은 적색 세로선, y=26에 남보라 가로선).
    그래서 이 검사는 색을 보지 않고 **반복 + 얇음**만 본다 —
    그림의 직선은 프레임마다 흔들리고, 반복되는 것은 얇지 않다.

    **경고에 머문다(반려가 아니다).** 기계적으로는 "액자"와 "곧은 모서리가 프레임마다
    같은 자리에 오는 그림"을 완전히 가를 수 없다(c_bug·flying_thesis 리메이크가 걸린다).
    사람이 그림을 보고 판단할 자리이므로 신호만 올린다 — 액자가 맞으면 셀 편집기의
    스포이드(Alt+클릭) → "이 색 전역 삭제"로 지우면 된다.
    """
    op = opaque_mask(im)
    cells, tally = _repeated_lines(op, cell_w, cell_h)
    if cells < 3:
        return []
    threshold = max(2, int(cells * BORDER_REPEAT_RATIO))
    hits = []
    for axis in ("col", "row"):
        coords = [pos for (ax, pos), n in tally.items() if ax == axis and n >= threshold]
        for group in _thin_groups(coords):
            hits.append((axis, group))
    if not hits:
        return []
    where = ", ".join(
        "%s%s" % (ax, g[0] if len(g) == 1 else "%d~%d" % (g[0], g[-1])) for ax, g in hits[:4]
    )
    return [
        Finding(
            "frame_border",
            "셀 %d개 중 %d개 이상에서 같은 자리에 반복되는 얇은 직선 %d줄 — 액자·안내선으로 보인다(%s)"
            % (cells, threshold, len(hits), where),
            len(hits),
        )
    ]


## 본체가 셀 내용에서 차지해야 할 최소 비율 — 미만이면 '본체가 없다'고 본다.
## 검증기·계측·정렬 스냅이 **같은 값**을 써야 한다(아래 align_anchor 주석 참고).
MAIN_BLOB_MIN = 0.5


def align_anchor(mask: np.ndarray, min_ratio: float = MAIN_BLOB_MIN) -> tuple:
    """정렬을 무엇에 맞출지 한 곳에서 정한다 — (bbox, 흩어짐?, 본체비율).

    ## 왜 한 곳인가 (2026-09-09)

    같은 그림을 검증기는 **본체 덩어리**로, 편집기 계측·정렬 스냅은 **셀 전체 bbox**로
    재고 있었다. 그래서 flying_thesis death r2c2에서 이런 일이 났다(실측):

      - 소멸 프레임이 30조각으로 흩어져 본체가 내용의 15%뿐
      - 검증기는 그 15%짜리 종잇조각을 본체로 골라 중심 x=38 · 바닥 66px → [ERR] 2건
      - 같은 파일에 편집기 계측은 cell_issues 없음 (전체 bbox로 재면 x=63 · 바닥 5px)
      - [정렬 스냅]을 눌러도 전체 bbox 기준으로 1px 옮길 뿐이라 판정은 그대로 [ERR]
        → 자동보정을 눌러도 FAIL이 안 없어지는 무한루프

    잣대가 둘이면 자동보정이 수렴하지 않는다. 그래서 판정·계측·보정이 모두 이 함수를 쓴다.

    ## 무엇을 고르나

    - 본체가 min_ratio 이상 → **본체 bbox**. 잔선·파편·액자가 경계를 부풀려 어긋난 배치가
      되레 '정상'으로 보이던 것을 막는다(mad_eye·sparker 리마스터 첫 납품이 그렇게 통과했다).
    - 본체가 min_ratio 미만 → **내용 전체 bbox**. 소멸·폭발 프레임은 본체가 없는 것이
      정상이고, 이때 최대 조각은 본체가 아니라 파편 하나라 그걸 기준 삼으면 틀린다.
    """
    total = int(mask.sum())
    if not total:
        return None, False, 0.0
    parts = blobs(mask)
    if not parts:
        return None, False, 0.0
    main = parts[0]
    ratio = main["n"] / float(total)
    if ratio >= min_ratio:
        return main, False, ratio
    ys, xs = np.where(mask)
    whole = {"n": total, "x0": int(xs.min()), "x1": int(xs.max()),
             "y0": int(ys.min()), "y1": int(ys.max())}
    return whole, True, ratio


def blobs(mask: np.ndarray) -> list:
    """8방향 연결 덩어리 목록(큰 것부터). 각 항목 {n, x0, x1, y0, y1}.

    셀 안의 '내용'을 하나로 뭉뚱그려 bbox를 재면 잔선·파편·액자가 경계를 부풀려
    정렬 검사가 통째로 무의미해진다(실납품에서 실제로 그렇게 통과했다).
    본체를 골라내려면 덩어리를 나눠 봐야 한다.
    """
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    for sy in range(h):
        for sx in range(w):
            if not mask[sy, sx] or seen[sy, sx]:
                continue
            stack = [(sy, sx)]
            seen[sy, sx] = True
            xs, ys = [], []
            while stack:
                y, x = stack.pop()
                xs.append(x)
                ys.append(y)
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            stack.append((ny, nx))
            out.append(
                {"n": len(xs), "x0": min(xs), "x1": max(xs), "y0": min(ys), "y1": max(ys)}
            )
    return sorted(out, key=lambda b: -b["n"])


def _split_cell(cell: np.ndarray, cell_w: int) -> str:
    """한 셀이 '반쪽 두 개'인지 — 비슷한 크기 · 가로로 벌어짐 · 좌우 반쪽에 하나씩."""
    bs = blobs(cell)
    if len(bs) < 2:
        return ""
    a, b = bs[0], bs[1]
    if b["n"] < a["n"] * SPLIT_SIZE_RATIO or min(a["n"], b["n"]) < SPLIT_MIN_PIXELS:
        return ""
    left, right = (a, b) if a["x0"] < b["x0"] else (b, a)
    gap = right["x0"] - left["x1"]
    if gap < SPLIT_MIN_GAP:
        return ""
    if not (left["x1"] < cell_w * 0.55 and right["x0"] > cell_w * 0.45):
        return ""
    return "%dpx+%dpx(간격 %dpx)" % (a["n"], b["n"], gap)


def check_split_cells(im: Image.Image, cell_w: int, cell_h: int) -> list:
    """셀 하나에 **두 포즈의 반쪽**이 들어온 경우 — 납품물의 자체 격자가 계약과 어긋난 것.

    mad_eye·sparker 리마스터 첫 납품에서 나왔다(셀 5칸). 기존 검사는 통과시켰다 —
    잘린 두 조각이 합쳐져 bbox가 셀을 거의 채우니 중앙·하단 정렬이 되레 '정상'으로 보였다.
    파편이 흩어지는 사망 프레임과 구분하려고 **비슷한 크기 + 좌우 분리**를 함께 건다
    (원작·기존 시트 27장에서 오탐 0 확인).
    """
    op = opaque_mask(im)
    h, w = op.shape
    hits = []
    for r in range(max(1, h // cell_h)):
        for c in range(max(1, w // cell_w)):
            cell = op[r * cell_h:(r + 1) * cell_h, c * cell_w:(c + 1) * cell_w]
            if cell.sum() < 50:
                continue
            note = _split_cell(cell, cell_w)
            if note:
                hits.append("r%dc%d %s" % (r, c, note))
    if not hits:
        return []
    return [
        Finding(
            "split_cell",
            "셀 %d칸이 반쪽 두 개다 — 납품물의 격자가 계약과 어긋났다(셀 단위 재배치 필요): %s%s"
            % (len(hits), ", ".join(hits[:3]), " …" if len(hits) > 3 else ""),
            len(hits),
        )
    ]


def check_color_budget(im: Image.Image, budget: int = COLOR_BUDGET) -> list:
    """고유색 수 — 계약(24~48색) 대비.

    수치만 돌려준다. 반려로 볼지 후처리(양자화)로 흡수할지는 호출자 판단:
    설치 단계(install_delivery.py)가 마스터 팔레트로 양자화하므로 통상은 경고다.
    """
    rgb, _ = _rgba(im)
    mask = opaque_mask(im)
    if mask.sum() == 0:
        return []
    n = len({tuple(c) for c in rgb[mask]})
    if n <= budget:
        return []
    code = "color_hard" if n > COLOR_HARD_CAP else "color_budget"
    return [
        Finding(
            code,
            "고유색 %d개 — 계약 %d색 이하(원작 도트 18~34색). %s"
            % (
                n,
                budget,
                "리샘플된 풀컬러 이미지로 보인다 — 도트로 다시 그리거나 편집기에서 양자화하라"
                if n > COLOR_HARD_CAP
                else "설치 시 팔레트 양자화로 정리된다",
            ),
            n,
        )
    ]


def check_pure_black(im: Image.Image) -> list:
    """순수 검정(#000000) 사용 — 프롬프트가 외곽선·그림자에 금지한 색."""
    rgb, _ = _rgba(im)
    mask = opaque_mask(im)
    if mask.sum() == 0:
        return []
    px = rgb[mask]
    ratio = float(((px[:, 0] == 0) & (px[:, 1] == 0) & (px[:, 2] == 0)).mean())
    if ratio <= PURE_BLACK_WARN:
        return []
    return [Finding("pure_black", "순수 검정 %.1f%% — 외곽선·그림자는 짙은 남색 계열" % (ratio * 100), ratio)]


def check_flat_placeholder(im: Image.Image) -> list:
    """색이 거의 없는 큰 그림 = 플레이스홀더(그림이 아니다).

    저장소의 자동 생성 플레이스홀더(`generate_all_portraits.py`)는 768×256을 7~9색으로
    채운다. 규격·키잉·정렬을 모두 통과하므로 색 수 상한만으로는 안 걸리고, 그대로 설치되면
    **"대화 초상 16종 완료"로 표시되면서 실제 공백이 감춰진다**. 큰 캔버스일수록 색이
    적다는 사실 자체가 신호다(원작 도트도 18~34색이다).
    """
    rgb, _alpha = _rgba(im)
    mask = opaque_mask(im)
    opaque = int(mask.sum())
    if opaque < PLACEHOLDER_MIN_PIXELS:
        return []
    n = len({tuple(c) for c in rgb[mask]})
    if n >= PLACEHOLDER_MIN_COLORS:
        return []
    return [
        Finding(
            "flat_placeholder",
            "불투명 %d px에 고유색 %d개 — 플레이스홀더로 보인다(그림이라면 최소 %d색)"
            % (opaque, n, PLACEHOLDER_MIN_COLORS),
            n,
        )
    ]


## 내용 대비 반투명 비율이 이 값을 넘으면 AA가 아니라 **그림 자체가 소프트 알파**다.
## 그런 시트를 이진화하면 가장자리 정리가 아니라 형태가 바뀐다(아래 실측 참고).
SEMI_SOFT_ART = 0.5


def check_semi_alpha(im: Image.Image) -> list:
    """반투명 픽셀 — 계약은 0%(픽셀은 켜지거나 꺼진다).

    ## 왜 두 코드로 가르나 (2026-09-09)

    캔버스 전체 대비 비율만 재면 두 가지가 한 코드로 뭉뚱그려진다:

      1. **AA 유입** — 도트 그림의 가장자리에만 반투명이 낀 것. 이진화가 정답이다.
      2. **소프트 알파 그림** — 렌더링된 그림이 통째로 반투명인 것. 이진화하면
         가장자리 정리가 아니라 **그림이 깎인다**.

    flying_thesis_v8 실측: attack r1c0의 내용 6177px 중 반투명이 6169px(99.9%).
    이진화하니 내용이 5439px로 줄고(-12%) 본체가 92%→66%로 쪼개졌으며 중심이
    74.0→82.5로 밀려, **없던 [ERR] 2건이 생겼다**. 자동보정이 그림을 망친 셈이다.

    그래서 내용(alpha>8) 대비 비율로 갈라 코드를 다르게 낸다. `semi_alpha`만
    편집기의 자동보정 표에 있고, `semi_alpha_soft`는 사람 몫으로 남는다.
    """
    _, alpha = _rgba(im)
    semi = (alpha > 0) & (alpha < 255)
    ratio = float(semi.mean())
    if ratio <= 0.001:
        return []
    # 내용(alpha>8) 안에서의 반투명 비율. semi 전체를 내용으로 나누면 alpha 1~8인
    # 픽셀이 분자에만 들어가 100%를 넘는다(실측에서 143%가 찍혔다).
    content_mask = alpha > 8
    content = int(content_mask.sum())
    share = float((semi & content_mask).sum()) / content if content else 0.0
    if share > SEMI_SOFT_ART:
        return [Finding(
            "semi_alpha_soft",
            "반투명 픽셀 %.2f%% — 내용의 %.0f%%가 반투명이다. AA가 아니라 그림 자체가 "
            "소프트 알파라, 이진화하면 형태가 깎인다 — 도트로 다시 받아야 한다"
            % (ratio * 100, share * 100),
            ratio,
        )]
    return [Finding("semi_alpha", "반투명 픽셀 %.2f%% — 계약 0%%(AA 유입)" % (ratio * 100), ratio)]


def run_all(im: Image.Image, cell_w: int, cell_h: int, budget: int = COLOR_BUDGET) -> list:
    """표준 묶음 — 잔선 · 색 수 · 순수 검정 · 반투명."""
    out = []
    out += check_guide_residue(im, cell_w, cell_h)
    out += check_frame_border(im, cell_w, cell_h)
    out += check_split_cells(im, cell_w, cell_h)
    out += check_flat_placeholder(im)
    out += check_color_budget(im, budget)
    out += check_pure_black(im)
    out += check_semi_alpha(im)
    return out


def guide_line_mask(im: Image.Image, cell_w: int, cell_h: int) -> np.ndarray:
    """안내선으로 판정된 **픽셀 마스크** — 검사(세기)와 제거(지우기)의 단일 근거.

    설치 단계(install_delivery.py)와 편집기가 같은 판정을 써야 한다. 판정이 갈라지면
    "검사는 잡는데 도구는 못 지우는" 상태가 되고, 반대로 도구가 그림을 지운다.
    """
    masks = guide_hue_mask(im)
    rgb, _alpha = _rgba(im)
    out = np.zeros(rgb.shape[:2], dtype=bool)
    min_len = int(min(cell_w, cell_h) * LINE_RUN_RATIO)
    for _hue, mask in masks.items():
        for ax, pos, start, length in _thin_runs(_runs(mask, min_len)):
            if ax == "row":
                out[pos, start:start + length] |= mask[pos, start:start + length]
            else:
                out[start:start + length, pos] |= mask[start:start + length, pos]
        out |= _dense_line_mask(rgb, mask, cell_w, cell_h)
    return out


def _dense_line_mask(rgb: np.ndarray, mask: np.ndarray, cell_w: int, cell_h: int) -> np.ndarray:
    """_dense_lines와 같은 판정의 마스크판(세는 대신 위치를 돌려준다)."""
    h, w = mask.shape
    out = np.zeros_like(mask)
    for r in range(max(1, h // cell_h)):
        for c in range(max(1, w // cell_w)):
            y0, x0 = r * cell_h, c * cell_w
            sub = mask[y0:y0 + cell_h, x0:x0 + cell_w]
            sub_rgb = rgb[y0:y0 + cell_h, x0:x0 + cell_w]
            if sub.size == 0:
                continue
            for axis in (1, 0):
                dens = sub.mean(axis=axis)
                flags = []
                for i in range(dens.shape[0]):
                    if dens[i] < LINE_DENSITY:
                        flags.append(False)
                        continue
                    line_mask = sub[i, :] if axis == 1 else sub[:, i]
                    sel = (sub_rgb[i, :] if axis == 1 else sub_rgb[:, i])[line_mask]
                    flags.append(
                        bool(sel.size)
                        and int((sel.max(axis=0) - sel.min(axis=0)).max()) <= LINE_COLOR_SPREAD
                    )
                i = 0
                while i < len(flags):
                    if not flags[i]:
                        i += 1
                        continue
                    j = i
                    while j < len(flags) and flags[j]:
                        j += 1
                    if j - i <= LINE_MAX_THICKNESS:
                        for k in range(i, j):
                            if axis == 1:
                                out[y0 + k, x0:x0 + sub.shape[1]] |= sub[k, :]
                            else:
                                out[y0:y0 + sub.shape[0], x0 + k] |= sub[:, k]
                    i = j
    return out


## 어떤 코드가 반려(FAIL)이고 어떤 게 경고(WARN)인가 — 검증기가 공유하는 단일 기준.
FAIL_CODES = {"guide_residue", "color_hard", "flat_placeholder", "split_cell"}


def is_fail(f: Finding) -> bool:
    return f.code in FAIL_CODES
