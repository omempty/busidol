class_name MapTileAnimator
extends Node
## 맵아트 인물 최소 움직임 — 위치는 고수하고 오브젝트 타일만 갈아 끼운다.
##
## 데이터: data/maps/tile_anim.json —
##   {"floors": {"<n>": [{"cells": [[x,y]...], "frames": [{"tile": int, "hold": float}...]}]}}
## frames는 한 부위(눈 등) 교대용 — 항목의 cells 전체에 같은 프레임을 찍는다.
## 부위가 2칸이면 항목을 2개(칸별 교대 id)로 나눈다.
## frames[0].tile은 맵에 깔린 그 타일과 같아야 한다(복귀점이자 첫 박자).
## 표가 비어 있으면 no-op — 아트 미납품 상태에서도 게임이 돌아간다.
## 교체는 런타임에만 살고 층을 나가면 사라진다(맵 데이터 불변 = 원본 바이트 일치 관문과 무관).
## 위상은 셀 해시 분산 — steady-state 난수 없음(재입장 후에도 같은 박자).

const PATH := "res://data/maps/tile_anim.json"

var _renderer: MapRenderer = null
## [{cells: Array[Vector2i], frames: Array, bounds: PackedFloat32Array, total: float, clock: float, idx: int}]
var _entries: Array = []


## 층이 갈릴 때마다 렌더러와 함께 묶는다(필드가 renderer.build 직후에 부른다).
func bind_floor(floor_no: int, renderer: MapRenderer) -> void:
	_renderer = renderer
	_entries.clear()
	if renderer == null or not FileAccess.file_exists(PATH):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("tile_anim 표 파싱 실패")
		return
	var list: Array = ((raw as Dictionary).get("floors", {}) as Dictionary).get(str(floor_no), [])
	for e: Variant in list:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		var cells: Array[Vector2i] = []
		for c: Variant in d.get("cells", []):
			var pair: Array = c as Array
			if pair != null and pair.size() >= 2:
				cells.append(Vector2i(int(pair[0]), int(pair[1])))
		var frames: Array = d.get("frames", [])
		if cells.is_empty() or frames.size() < 2:
			continue
		var bounds := PackedFloat32Array()
		var total := 0.0
		for f: Variant in frames:
			total += maxf(float((f as Dictionary).get("hold", 0.5)), 0.05)
			bounds.append(total)
		var seed_cell: Vector2i = cells[0]
		var h: int = absi((seed_cell.x * 73856093) ^ (seed_cell.y * 19349663))
		(
			_entries
			. append(
				{
					"cells": cells,
					"frames": frames,
					"bounds": bounds,
					"total": total,
					"clock": float(h % 1000) / 1000.0 * total,
					"idx": -1,
				}
			)
		)


func _process(delta: float) -> void:
	if _renderer == null or _entries.is_empty():
		return
	for e: Variant in _entries:
		var d: Dictionary = e
		d["clock"] = fmod(float(d["clock"]) + delta, maxf(float(d["total"]), 0.05))
		var idx := _frame_at(d)
		if idx == int(d["idx"]):
			continue
		d["idx"] = idx
		var tile := int((d["frames"] as Array)[idx].get("tile", 0))
		if tile <= 0:
			continue
		for cell: Vector2i in d["cells"]:
			_renderer.swap_object_tile(cell, tile)


## clock이 가리키는 프레임 번호.
func _frame_at(d: Dictionary) -> int:
	var bounds: PackedFloat32Array = d["bounds"]
	var clock := float(d["clock"])
	for i in bounds.size():
		if clock < bounds[i]:
			return i
	return bounds.size() - 1
