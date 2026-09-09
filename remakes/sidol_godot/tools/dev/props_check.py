#!/usr/bin/env python3
"""소품 덧층 무결성 관문 — data/maps/props_f*.json이 **스키마와 참조**에서 성한가.

## 왜 (기존 관문이 못 보는 층)

- `originals_check.py`는 맵 3평면이 원본과 바이트 일치인지만 본다. 소품은 원본에 쓰지
  않는 **덧층**이라 그 관문의 눈 밖이다 — 덧층이 통째로 틀려도 초록불이다.
- `validate.gd`·`world_audit`는 **런타임 조립 결과**를 본다. 그러려면 Godot이 있어야 하고,
  JSON 오타 한 줄이면 그 앞에서 먼저 죽는다.
- 그 사이에 아무도 안 보는 층이 있다: **소품 파일이 가리키는 것들이 실재하는가.**
  스프라이트 id는 `assets/spec/sprites/tileset_campus.json`의 `multi_tile_objects`가 정본이고,
  칸은 `data/maps/f<N>.json`의 attr 평면이 정본이다. 둘 중 하나만 바뀌어도 소품은
  "벽 속에 박힌 책상"이나 "없는 그림"이 된다 — 그런데 게임은 조용히 돌아간다.

  FAIL  반드시 어긋난다(스키마 위반·없는 id·크기 불일치·맵 밖·벽 위·겹침·문 막음)
  WARN  틀렸다고 단정할 수 없지만 사람이 봐야 한다(원본 그림과 겹침·벽면 행·근거 주석 없음)

## 여기서 하지 않는 것 — 통로 차단(도달 가능성) 판정

"이 소품이 길을 끊는가"는 `src/map/placement.gd`의 `CHOKE_RADIUS`·`blocks_passage()`가
GDScript로 이미 갖고 있는 규칙이다. 파이썬으로 옮겨 오면 같은 규칙이 두 벌이 되고,
이 저장소가 반복해 물린 결함이 정확히 그것이다(한쪽만 고쳐진다). **그 판정은 GDScript
쪽 관문이 본다** — 2026-09-09에 `PropsProbe.check_choke`(world_audit)가 붙었고,
`Placement.blocks_cells()`로 소품이 **실제로 막는 칸**만 놓고 묻는다. 여기서는 스키마와
참조만 본다.

사용:
  python tools/dev/props_check.py                    data/maps/props_f*.json 전부
  python tools/dev/props_check.py <경로> [<경로>…]   지정 파일만(부정 시험용)
종료코드: 0=FAIL 없음 / 1=FAIL 있음
"""

from __future__ import annotations

import glob
import io
import json
import os
import re
import sys

# 콘솔 코드페이지가 cp949여도 한글·em대시가 깨지지 않게 한다(bash·cmd 양쪽).
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAPS = os.path.join(ROOT, "data", "maps")
TILESET = os.path.join(ROOT, "assets", "spec", "sprites", "tileset_campus.json")

SCHEMA_VERSION = 1
FILE_RE = re.compile(r"^props_f(\d+)\.json$")

## src/map/map_runtime.gd 통행 규칙과 같은 수 — 0(PASSABLE)·2(OVERHEAD)만 통과.
PASSABLE_ATTR = (0, 2)
## 소품이 덧씌울 수 있는 ATT. 그 밖의 값은 원본에서 NPC·상자·방 ID로 쓰는 자리라
## 소품이 흉내 내면 안 된다(같은 숫자를 두 뜻으로 쓰게 된다).
ALLOWED_OVERRIDE = (0, 1, 2)
BLOCKING_ATTR = 1
## src/map/placement.gd DOOR_ATTR / find_spot(door_margin=2)와 같은 수.
DOOR_ATTR = 9
DOOR_MARGIN = 2

PROP_KEYS = {"id", "sprite", "name_ko", "footprint", "state", "inspect"}
FOOTPRINT_KEYS = {"anchor", "size", "attr_grid"}


class Report:
    def __init__(self) -> None:
        self.fails: list[str] = []
        self.warns: list[str] = []

    def fail(self, msg: str) -> None:
        self.fails.append(msg)

    def warn(self, msg: str) -> None:
        self.warns.append(msg)


def load_json(path: str, rep: Report, what: str):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        rep.fail("%s 없음: %s" % (what, path))
    except ValueError as exc:
        rep.fail("%s JSON 파싱 실패: %s (%s)" % (what, path, exc))
    return None


def load_spec(rep: Report) -> dict:
    """소품 정본 — tileset_campus.json multi_tile_objects. id → (w, h)."""
    raw = load_json(TILESET, rep, "타일셋 스펙")
    out = {}
    if not isinstance(raw, dict):
        return out
    for obj in raw.get("multi_tile_objects", []):
        if isinstance(obj, dict) and "id" in obj:
            out[str(obj["id"])] = (int(obj.get("w", 0)), int(obj.get("h", 0)))
    if not out:
        rep.fail("타일셋 스펙에 multi_tile_objects가 비어 있다: %s" % TILESET)
    return out


def load_map(floor: int, rep: Report) -> dict:
    """f<N>.json의 attr/object/ground 평면 — 행 배열·평탄 배열 양쪽을 받는다."""
    path = os.path.join(MAPS, "f%d.json" % floor)
    raw = load_json(path, rep, "맵")
    if not isinstance(raw, dict):
        return {}
    w, h = int(raw.get("width", 0)), int(raw.get("height", 0))
    layers = raw.get("layers", {})
    out = {"width": w, "height": h}
    for name in ("attr", "object", "ground"):
        rows = layers.get(name)
        if not isinstance(rows, list) or not rows:
            rep.fail("맵 f%d에 %s 평면이 없다" % (floor, name))
            return {}
        if isinstance(rows[0], list):
            flat = [c for row in rows for c in row]
        else:
            flat = list(rows)
        if len(flat) != w * h:
            rep.fail("맵 f%d %s 셀 수 %d (기대 %d)" % (floor, name, len(flat), w * h))
            return {}
        out[name] = flat
    return out


def at(mp: dict, name: str, x: int, y: int) -> int:
    return mp[name][y * mp["width"] + x]


def door_cells(mp: dict) -> set:
    w = mp["width"]
    return set(
        (i % w, i // w) for i, v in enumerate(mp["attr"]) if v == DOOR_ATTR
    )


def check_footprint(tag: str, prop: dict, rep: Report):
    """스키마만 본다. 통과하면 (anchor, size, attr_grid), 아니면 None."""
    fp = prop.get("footprint")
    if not isinstance(fp, dict):
        rep.fail("%s footprint가 없다(칸 속성 층이 통째로 빠졌다)" % tag)
        return None
    for key in sorted(set(fp) - FOOTPRINT_KEYS):
        if not key.startswith("_"):
            rep.warn("%s footprint에 모르는 키 '%s'" % (tag, key))
    pair = {}
    for key in ("anchor", "size"):
        val = fp.get(key)
        ok = (
            isinstance(val, list)
            and len(val) == 2
            and all(isinstance(v, int) and not isinstance(v, bool) for v in val)
        )
        if not ok:
            rep.fail("%s footprint.%s는 정수 2개 배열이어야 한다: %r" % (tag, key, val))
            return None
        pair[key] = (val[0], val[1])
    w, h = pair["size"]
    if w < 1 or h < 1:
        rep.fail("%s footprint.size가 %d×%d — 1 이상이어야 한다" % (tag, w, h))
        return None
    grid = fp.get("attr_grid")
    if not isinstance(grid, list) or len(grid) != h:
        rep.fail("%s attr_grid는 size의 h(%d)행이어야 한다: %r" % (tag, h, grid))
        return None
    for r, row in enumerate(grid):
        if not isinstance(row, list) or len(row) != w:
            rep.fail("%s attr_grid[%d]은 size의 w(%d)열이어야 한다: %r" % (tag, r, w, row))
            return None
        for c, v in enumerate(row):
            if not isinstance(v, int) or isinstance(v, bool):
                rep.fail("%s attr_grid[%d][%d]이 정수가 아니다: %r" % (tag, r, c, v))
                return None
            if v not in ALLOWED_OVERRIDE:
                rep.fail(
                    "%s attr_grid[%d][%d]=%d — 소품이 덧씌울 수 있는 값은 %s뿐이다"
                    % (tag, r, c, v, "/".join(str(a) for a in ALLOWED_OVERRIDE))
                )
                return None
    if all(v == 0 for row in grid for v in row):
        rep.warn("%s attr_grid가 전부 0 — 칸 속성 층이 아무것도 하지 않는다" % tag)
    return pair["anchor"], pair["size"], grid


def collect_settable_flags() -> set:
    """이 게임에서 **누군가 실제로 세우는** 플래그 전부.

    소품의 `state.open_flag`·`inspect.requires_flag`는 그 플래그가 서야 뜻이 생긴다.
    아무도 안 세우는 이름(오타 포함)이면 그 소품은 **영영 열리지 않고 영영 조사되지
    않는다** — 데이터는 멀쩡해 보이고 게임도 조용히 돌아간다. validate.gd가 대화 마커에
    대해 같은 사슬 검사를 하고 있고(「요구만 하고 아무도 안 세우는 플래그」), 여기는
    소품판이다.

    출처(값이 곧 플래그 이름인 키들):
      triggers_f*.json  done_flag           트리거가 발동하면 선다
      cutscenes/*.json  set_flags.args 키   컷신 op가 세운다
                        flag / on_win_flag  craft 성공·전투 승리로 선다
      talk_targets.json sets_flag           원작 마커 대화가 세운다
      monsters.json     first_win_flag      첫 승리로 선다
    그리고 GDScript가 코드로 세우는 것(GameState.set_flag("X") / flags["X"] = true)도 훑는다.
    """
    flags: set = set()

    def walk(node) -> None:
        if isinstance(node, dict):
            if node.get("op") == "set_flags" and isinstance(node.get("args"), dict):
                flags.update(str(k) for k in node["args"])
            for key in ("done_flag", "flag", "on_win_flag", "sets_flag", "first_win_flag"):
                val = node.get(key)
                if isinstance(val, str) and val:
                    flags.add(val)
            for val in node.values():
                walk(val)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    for path in glob.glob(os.path.join(ROOT, "data", "**", "*.json"), recursive=True):
        try:
            with io.open(path, encoding="utf-8") as fh:
                walk(json.load(fh))
        except (OSError, ValueError):
            continue  # 다른 관문이 잡는다 — 여기서 파싱 실패로 죽지 않는다

    code_re = re.compile(r'(?:set_flag|has_flag)\(\s*"([A-Za-z0-9_]+)"|flags\["([A-Za-z0-9_]+)"\]')
    for path in glob.glob(os.path.join(ROOT, "src", "**", "*.gd"), recursive=True) + glob.glob(
        os.path.join(ROOT, "scenes", "**", "*.gd"), recursive=True
    ):
        try:
            with io.open(path, encoding="utf-8") as fh:
                for m in code_re.finditer(fh.read()):
                    flags.add(m.group(1) or m.group(2))
        except OSError:
            continue
    return flags


def check_flags(tag: str, prop: dict, settable: set, rep: Report) -> None:
    """소품이 기대는 플래그를 아무도 안 세우면 그 소품은 죽은 것이다."""
    pairs = [
        ("state.open_flag", (prop.get("state") or {}).get("open_flag")),
        ("inspect.requires_flag", (prop.get("inspect") or {}).get("requires_flag")),
    ]
    for key, val in pairs:
        if val is None:
            continue
        if not isinstance(val, str) or not val.strip():
            rep.fail("%s %s는 비지 않은 문자열이어야 한다: %r" % (tag, key, val))
            continue
        if val not in settable:
            rep.fail(
                "%s %s '%s'를 세우는 곳이 없다 — 그 소품은 영영 %s"
                % (tag, key, val, "열리지 않는다" if "open" in key else "조사되지 않는다")
            )


def check_inspect(tag: str, prop: dict, rep: Report) -> None:
    ins = prop.get("inspect")
    if ins is None:
        return
    if not isinstance(ins, dict):
        rep.fail("%s inspect는 객체여야 한다: %r" % (tag, ins))
        return
    unknown = set(ins) - {"lines", "requires_flag"}
    if unknown:
        rep.warn("%s inspect에 모르는 키: %s" % (tag, ", ".join(sorted(unknown))))
    lines = ins.get("lines")
    if not isinstance(lines, list) or not lines:
        rep.fail("%s inspect.lines는 비지 않은 배열이어야 한다: %r" % (tag, lines))
        return
    for i, line in enumerate(lines):
        if not isinstance(line, str) or not line.strip():
            rep.fail("%s inspect.lines[%d]가 빈 문자열이다" % (tag, i))


def check_state(tag: str, prop: dict, rep: Report) -> None:
    st = prop.get("state")
    if st is None:
        return
    if not isinstance(st, dict):
        rep.fail("%s state는 객체여야 한다: %r" % (tag, st))
        return
    default = st.get("default")
    if default not in ("open", "closed"):
        rep.fail("%s state.default는 'open'/'closed'여야 한다: %r" % (tag, default))


def check_file(path: str, spec: dict, settable: set, rep: Report) -> int:
    """한 파일을 검사하고 검사한 소품 수를 반환."""
    name = os.path.basename(path)
    m = FILE_RE.match(name)
    if not m:
        rep.fail("파일 이름이 props_f<층>.json 꼴이 아니다: %s" % name)
        return 0
    file_floor = int(m.group(1))
    raw = load_json(path, rep, "소품 덧층")
    if not isinstance(raw, dict):
        return 0

    ver = raw.get("schema_version")
    if not isinstance(ver, int) or isinstance(ver, bool):
        rep.fail("%s schema_version이 정수가 아니다: %r" % (name, ver))
    elif ver != SCHEMA_VERSION:
        rep.warn("%s schema_version=%d (이 관문이 아는 것은 %d)" % (name, ver, SCHEMA_VERSION))

    floor = raw.get("floor")
    if not isinstance(floor, int) or isinstance(floor, bool):
        rep.fail("%s floor가 정수가 아니다: %r" % (name, floor))
        return 0
    if floor != file_floor:
        rep.fail("%s floor=%d인데 파일 이름은 f%d다" % (name, floor, file_floor))
        return 0

    props = raw.get("props")
    if not isinstance(props, list):
        rep.fail("%s props가 배열이 아니다: %r" % (name, type(props).__name__))
        return 0

    mp = load_map(floor, rep)
    if not mp:
        return 0
    doors = door_cells(mp)

    seen_ids: set = set()
    owner: dict = {}  # (x, y) -> 소품 id
    checked = 0

    for idx, prop in enumerate(props):
        tag = "%s[%d]" % (name, idx)
        if not isinstance(prop, dict):
            rep.fail("%s 항목이 객체가 아니다" % tag)
            continue
        pid = prop.get("id")
        if not isinstance(pid, str) or not pid.strip():
            rep.fail("%s id가 비었다" % tag)
            continue
        tag = "%s %s" % (name, pid)
        if pid in seen_ids:
            rep.fail("%s id 중복" % tag)
        seen_ids.add(pid)
        for key in sorted(set(prop) - PROP_KEYS):
            if not key.startswith("_"):
                rep.warn("%s 모르는 키 '%s'" % (tag, key))
        if not str(prop.get("_comment", "")).strip():
            rep.warn("%s _comment가 없다 — 좌표 근거를 남기는 것이 이 저장소의 관례다" % tag)

        check_inspect(tag, prop, rep)
        check_state(tag, prop, rep)
        check_flags(tag, prop, settable, rep)

        sprite = prop.get("sprite")
        if not isinstance(sprite, str) or not sprite.strip():
            rep.fail("%s sprite가 비었다" % tag)
            continue

        parsed = check_footprint(tag, prop, rep)
        if parsed is None:
            continue
        (ax, ay), (w, h), grid = parsed

        # --- 스프라이트 정본 대조 -------------------------------------------------
        if sprite not in spec:
            rep.fail(
                "%s sprite '%s'가 tileset_campus.json multi_tile_objects에 없다 (있는 것: %s)"
                % (tag, sprite, ", ".join(sorted(spec)))
            )
            continue
        sw, sh = spec[sprite]
        if (w, h) != (sw, sh):
            rep.fail(
                "%s size %d×%d인데 '%s' 정본은 %d×%d다" % (tag, w, h, sprite, sw, sh)
            )
            continue

        # --- 맵 대조 -------------------------------------------------------------
        for dy in range(h):
            for dx in range(w):
                x, y = ax + dx, ay + dy
                cell = "(%d,%d)" % (x, y)
                if not (0 <= x < mp["width"] and 0 <= y < mp["height"]):
                    rep.fail("%s %s가 맵 밖이다 (맵 %d×%d)" % (tag, cell, mp["width"], mp["height"]))
                    continue
                if (x, y) in owner:
                    rep.fail("%s %s가 %s와 겹친다" % (tag, cell, owner[(x, y)]))
                else:
                    owner[(x, y)] = pid
                orig = at(mp, "attr", x, y)
                if orig == DOOR_ATTR:
                    rep.fail("%s %s가 문(ATT %d) 칸이다" % (tag, cell, DOOR_ATTR))
                elif orig not in PASSABLE_ATTR:
                    rep.fail(
                        "%s %s의 원본 ATT가 %d — 원래 지나갈 수 없던 칸이라 소품을 놓을 이유가 없다"
                        % (tag, cell, orig)
                    )
                if grid[dy][dx] == BLOCKING_ATTR:
                    near = [
                        d
                        for d in doors
                        if max(abs(d[0] - x), abs(d[1] - y)) <= DOOR_MARGIN
                    ]
                    if near:
                        rep.fail(
                            "%s %s가 막는데 문 %s에서 %d칸 안이다 — 문간이 물린다"
                            % (
                                tag,
                                cell,
                                "/".join("(%d,%d)" % d for d in sorted(near)),
                                DOOR_MARGIN,
                            )
                        )
                if at(mp, "object", x, y) != 0:
                    rep.warn(
                        "%s %s에 원본 object %d가 이미 그려져 있다 — 소품이 그 위에 겹친다"
                        % (tag, cell, at(mp, "object", x, y))
                    )
                if at(mp, "ground", x, y) == 0:
                    rep.warn(
                        "%s %s는 ground 0(벽면 그림) 행이다 — 소품이 벽에 파묻혀 보인다"
                        % (tag, cell)
                    )
        checked += 1
    return checked


def main(argv: list) -> int:
    rep = Report()
    paths = argv[1:]
    if not paths:
        paths = sorted(glob.glob(os.path.join(MAPS, "props_f*.json")))
    if not paths:
        print("[props_check] SKIP — 소품 덧층 파일이 없다(%s)" % MAPS)
        return 0

    spec = load_spec(rep)
    settable = collect_settable_flags()
    total = 0
    for path in paths:
        total += check_file(path, spec, settable, rep)

    for w in rep.warns:
        print("[props_check] WARN — %s" % w)
    for f in rep.fails:
        print("[props_check] FAIL — %s" % f)
    if rep.fails:
        print(
            "[props_check] 실패 %d건 · 경고 %d건 (파일 %d개)"
            % (len(rep.fails), len(rep.warns), len(paths))
        )
        return 1
    print(
        "[props_check] ok — 소품 %d개/파일 %d개 · 스키마·정본 id·크기·맵 범위·겹침·원본 ATT·문 간섭·플래그 사슬 통과 (경고 %d건)"
        % (total, len(paths), len(rep.warns))
    )
    print(
        "[props_check] note — 통로 차단(도달 가능성)은 여기서 재지 않는다: "
        "Placement.blocks_cells()가 정본이고 world_audit의 PropsProbe.check_choke가 그것을 부른다."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
