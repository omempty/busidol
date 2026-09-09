class_name PropsProbe
extends RefCounted
## 소품 덧층 **조립** 검증 — 데이터가 놓은 소품이 실제로 조사되고, 이벤트가 그 앞에서 나는가.
##
## props_check.py는 스키마·겹침·원본 ATT까지만 본다(그 파일 18~23행이 "통로·도달성은
## GDScript가 봐야 한다"고 적어 두었다). 여기가 그 자리다. 파이썬이 못 보는 이유는
## 판정 모양(InteractProbe)과 몸 크기(Placement)가 엔진 쪽 정본이기 때문이다 —
## 두 벌로 계산하기 시작하면 "도구는 닿는다는데 게임은 아니라고 한다"가 생긴다.

const TRIGGER_PATH := "res://data/maps/triggers_f%d.json"
## 서는 자리를 소품 둘레 몇 칸까지 뒤질 것인가. 2×2 몸 + 정면 2칸 판정이라 3이면 넉넉하다.
const STAND_MARGIN := 3


## 조사할 수 있는 소품인가 — 앞에 설 자리가 없으면 대사가 통째로 죽는다.
static func check_inspect_reach(
	rep: AuditReport, rt: MapRuntime, layer: PropsLayer, mover: GridMover
) -> void:
	if layer == null or layer.props.is_empty():
		rep.ok("소품 조사 도달성", "이 층에 소품 없음")
		return
	var bad := 0
	for prop: Dictionary in layer.props:
		var pid := String(prop.get("id", "?"))
		var lines := _inspect_lines(prop)
		if lines.is_empty():
			rep.warn("소품 조사 대사 없음", "%s — 조사해도 아무 말이 없다" % pid)
			continue
		if stand_that_sees(rt, mover, prop).x >= 0:
			continue
		bad += 1
		rep.fail(
			"조사 못 하는 소품",
			"%s @%s — 앞에 설 자리가 없어 대사 %d줄이 죽는다" % [pid, PropsLayer.anchor_of(prop), lines.size()]
		)
	if bad == 0:
		rep.ok("소품 조사 도달성", "소품 %d개 전부 조사 가능" % layer.props.size())


## 이벤트가 소품 앞에서 나는가.
##
## 연결은 데이터가 이미 선언하고 있다: 소품의 `state.open_flag`와 트리거의 완료 플래그가
## 같은 플래그다(f1_storage_lockers ↔ f1_gas / f1_mail_lockers ↔ f1_sopo).
## 그런데 그 둘이 같은 자리에 있는지는 아무도 재지 않았다 — 어긋나 있으면 플레이어는
## **빈 방의 좌표를 밟아** 이벤트를 얻는다(2026-09-09 유저 지적).
static func check_event_alignment(
	rep: AuditReport, floor_no: int, rt: MapRuntime, layer: PropsLayer, mover: GridMover
) -> void:
	if layer == null or layer.props.is_empty():
		return
	var by_flag := _triggers_by_completion_flag(floor_no)
	if by_flag.is_empty():
		return
	var checked := 0
	var bad := 0
	for prop: Dictionary in layer.props:
		var state: Variant = prop.get("state", {})
		if typeof(state) != TYPE_DICTIONARY:
			continue
		var flag := String((state as Dictionary).get("open_flag", ""))
		if flag.is_empty() or not by_flag.has(flag):
			continue
		checked += 1
		var trig: Dictionary = by_flag[flag]
		var cells: Dictionary = _cell_set(prop)
		# 타입마다 "같은 자리"의 뜻이 다르다(TriggerSystem):
		#   interact — 칸을 **앞에 두고** 조사하면 발동 → 칸이 소품 몸 안에 있어야 한다.
		#   zone     — 칸을 **밟으면** 발동 → 그 자리에 서서 소품이 보여야 한다.
		var by_interact := String(trig.get("type", "")) == "interact"
		var aligned := false
		var nearest := 9999
		for raw: Variant in trig["cells"] as Array:
			var arr := raw as Array
			if arr == null or arr.size() < 2:
				continue
			var tc := Vector2i(int(arr[0]), int(arr[1]))
			nearest = mini(nearest, _chebyshev_to(tc, cells))
			var hit := (
				cells.has(tc)
				if by_interact
				else (_sees_prop(mover, tc, cells) and Placement.body_fits(rt, tc))
			)
			if hit:
				aligned = true
				break
		if aligned:
			continue
		bad += 1
		rep.fail(
			"이벤트가 소품에서 떨어져 있다",
			(
				"%s(%s) ↔ 소품 %s — 가장 가까운 트리거 칸이 %d칸 밖이다. 빈 자리를 밟아 이벤트가 난다"
				% [String(trig["id"]), flag, String(prop.get("id", "?")), nearest]
			)
		)
	if checked > 0 and bad == 0:
		rep.ok("이벤트·소품 정렬", "플래그로 묶인 %d쌍 전부 소품 앞에서 난다" % checked)


## 소품이 길목을 막는가 — 판정 정본은 Placement(NPC 배치가 쓰는 그 규칙)다.
##
## props_check.py가 "통로 차단은 여기서 안 본다"고 남겨 둔 마지막 구멍이다.
## **주의(조용히 초록이 되는 자리)**: 이 관문이 도는 시점에 소품은 이미 런타임에 얹혀
## 있다. 그대로 물어보면 창(window) 자체가 소품을 뺀 상태로 계산돼 "막은 적 없음"이
## 나온다. 그래서 그 소품의 덧씌움만 잠깐 걷어내고 묻고 되돌린다 — 다른 소품·상자
## 덧씌움은 그대로 둔다(여럿이 함께 만드는 길목도 그 상태에서 잡힌다).
static func check_choke(rep: AuditReport, rt: MapRuntime, layer: PropsLayer) -> void:
	if layer == null or layer.props.is_empty():
		return
	var bad := 0
	for prop: Dictionary in layer.props:
		var blocked := blocking_cells(prop)
		if blocked.is_empty():
			continue
		var saved: Dictionary = {}
		for c: Vector2i in blocked:
			if rt.overrides.has(c):
				saved[c] = rt.overrides[c]
				rt.overrides.erase(c)
		var chokes := Placement.blocks_cells(rt, blocked)
		for c: Vector2i in saved:
			rt.overrides[c] = saved[c]
		if chokes:
			bad += 1
			rep.fail(
				"소품이 길목을 막는다",
				(
					"%s @%s — 막는 칸 %d개가 통로를 쪼갠다(플레이어 2×2가 못 지나간다)"
					% [String(prop.get("id", "?")), PropsLayer.anchor_of(prop), blocked.size()]
				)
			)
	if bad == 0:
		rep.ok("소품 통로", "소품 %d개 중 길목을 막는 것 없음" % layer.props.size())


## 소품이 **실제로 막는** 칸(ATT 0·2는 지나갈 수 있으므로 뺀다).
## 사물함처럼 윗칸은 머리 위(2)로 지나가고 아랫칸만 막는 모양이 표준이다.
static func blocking_cells(prop: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var fp: Variant = prop.get("footprint", {})
	if typeof(fp) != TYPE_DICTIONARY:
		return out
	var grid: Variant = (fp as Dictionary).get("attr_grid", [])
	if typeof(grid) != TYPE_ARRAY:
		return out
	var anchor := PropsLayer.anchor_of(prop)
	for dy in (grid as Array).size():
		var row: Variant = (grid as Array)[dy]
		if typeof(row) != TYPE_ARRAY:
			continue
		for dx in (row as Array).size():
			var att := int((row as Array)[dx])
			if att != 0 and att != 2:
				out.append(anchor + Vector2i(dx, dy))
	return out


static func _inspect_lines(prop: Dictionary) -> Array:
	var ins: Variant = prop.get("inspect", {})
	if typeof(ins) != TYPE_DICTIONARY:
		return []
	var lines: Variant = (ins as Dictionary).get("lines", [])
	return lines as Array if typeof(lines) == TYPE_ARRAY else []


static func _cell_set(prop: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for c: Vector2i in PropsLayer.cells_of(prop):
		out[c] = true
	return out


## 그 자리에 서서 네 방향 중 하나를 보면 소품이 잡히는가 — 판정은 게임과 같은 InteractProbe.
static func _sees_prop(mover: GridMover, stand: Vector2i, cells: Dictionary) -> bool:
	for facing: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		for c: Vector2i in InteractProbe.probe_cells(mover, stand, facing):
			if cells.has(c):
				return true
	return false


## 소품을 조사할 수 있는 서는 자리 하나(없으면 (-9,-9)).
## 관문과 스모크가 같이 쓴다 — 시험이 좌표를 따로 적어 두면 데이터가 움직일 때 시험만 녹슨다.
static func stand_that_sees(rt: MapRuntime, mover: GridMover, prop: Dictionary) -> Vector2i:
	var cells := _cell_set(prop)
	var anchor := PropsLayer.anchor_of(prop)
	var size := PropsLayer.size_of(prop)
	for y in range(anchor.y - STAND_MARGIN, anchor.y + size.y + STAND_MARGIN):
		for x in range(anchor.x - STAND_MARGIN, anchor.x + size.x + STAND_MARGIN):
			var stand := Vector2i(x, y)
			if cells.has(stand) or not Placement.body_fits(rt, stand):
				continue
			if _sees_prop(mover, stand, cells):
				return stand
	return Vector2i(-9, -9)


static func _chebyshev_to(from: Vector2i, cells: Dictionary) -> int:
	var best := 9999
	for c: Vector2i in cells:
		best = mini(best, maxi(absi(c.x - from.x), absi(c.y - from.y)))
	return best


## 완료 플래그 → {id, type, cells}. zone·interact 트리거만 자리를 가진다(auto는 층에 들어서면 바로 돈다).
##
## **done_flag와 guard_flag를 함께 색인한다.** 둘은 "이 트리거가 끝났다는 표식"이라는
## 뜻이 같고, 세우는 시점만 다르다(done은 발동 직전에 TriggerSystem이, guard는 결과가
## 성공했을 때 컷신 쪽이). done_flag만 보면 **져도 되는 트리거는 통째로 이 관문 밖**이었다 —
## F5 보스 재도전 둘이 정확히 그 꼴이라 소품과 어긋나도 초록이었을 것이다(2026-09-09).
##
## 파일 모양 주의: triggers_f*.json은 **배열이 아니라 `{schema_version, _comment, triggers[]}`**다.
## 처음에 배열로 읽었더니 이 관문이 아무 짝도 못 찾고 **조용히 초록**이었다(2026-09-09 실측).
## 그래서 ReachProbe와 같은 정본 로더(JsonUtil)를 쓴다 — 읽는 방법이 두 벌이면 또 갈린다.
static func _triggers_by_completion_flag(floor_no: int) -> Dictionary:
	var out: Dictionary = {}
	var doc := JsonUtil.load_dict(TRIGGER_PATH % floor_no, "PropsProbe")
	for t: Variant in doc.get("triggers", []):
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var td := t as Dictionary
		var flag := String(td.get("done_flag", ""))
		if flag.is_empty():
			flag = String(td.get("guard_flag", ""))
		var cells: Variant = td.get("cells", [])
		if flag.is_empty() or typeof(cells) != TYPE_ARRAY or (cells as Array).is_empty():
			continue
		out[flag] = ({
			"id": String(td.get("id", "?")), "type": String(td.get("type", "")), "cells": cells
		})
	return out
