class_name PropsLayer
extends RefCounted
## 정적 소품 덧층 — data/maps/props_f<N>.json 로더 (docs/02_design/01_oop_redesign.md §3.3).
##
## 맵 3평면(ground/object/attr)은 원본과 바이트 일치로 잠겨 있다(tools/dev/originals_check.py).
## 그래서 소품은 원본에 **쓰지 않고** 덧씌움으로만 얹는다 — 상자를 열면 그 칸 ATT가 바뀌는
## `GameState.chest_overrides`의 **정적 판**이다. 다른 점은 하나뿐: 상자는 플레이 중에 생기고
## 세이브에 실리지만, 소품은 층을 열 때 데이터에서 곧바로 선다(저장할 것이 없다).
##
## 두 층을 섞지 않는다 — 파일의 `_layers` 주석과 같은 구분이다.
##   칸 속성 층: `attr_overrides()` — 칸 → ATT. MapRuntime이 먹는 유일한 모양.
##   소품 속성 층: `prop_at()` — 칸 → 소품 사전(이름·상태·조사 대사).
## 「책장은 막으면서 조사도 된다」는 두 사전이 각각 그 칸을 갖는 것이지 한 필드가 아니다.

const DATA_PATH := "res://data/maps/props_f%d.json"

var floor_index: int = -1
## 파일에 적힌 순서 그대로의 소품 목록(렌더러가 쓰는 원본 사전).
var props: Array = []

var _attrs: Dictionary = {}  # Vector2i -> int
var _by_cell: Dictionary = {}  # Vector2i -> Dictionary(소품)


## 층 소품 덧층을 읽는다. 파일이 없는 층은 **빈 층**이다(정상 — 오류가 아니다).
static func load_floor(floor_no: int) -> PropsLayer:
	var layer := PropsLayer.new()
	layer.floor_index = floor_no
	var path := DATA_PATH % floor_no
	if not FileAccess.file_exists(path):
		return layer
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("PropsLayer: JSON 파싱 실패 %s" % path)
		return layer
	var data: Dictionary = raw
	# floor가 파일 이름과 어긋나면 다른 층 소품을 이 층에 세우게 된다 — 조용히 틀리는 대신 운다.
	var declared := int(data.get("floor", floor_no))
	if declared != floor_no:
		push_error("PropsLayer: %s의 floor=%d (기대 %d)" % [path, declared, floor_no])
		return layer
	var list: Variant = data.get("props", [])
	if typeof(list) != TYPE_ARRAY:
		push_error("PropsLayer: %s props가 배열이 아니다" % path)
		return layer
	for entry: Variant in list:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		layer._ingest(entry)
	return layer


func is_empty() -> bool:
	return props.is_empty()


## 칸 → ATT 덧씌움. `GameState.chest_overrides_for()`와 **같은 모양**이라
## field가 상자를 얹는 것과 똑같은 순회로 얹을 수 있다.
func attr_overrides() -> Dictionary:
	return _attrs


## 런타임에 덧씌움을 얹는다. 반환값은 얹은 칸 수(감사 도구가 「몇 칸이 바뀌었나」를 잰다).
##
## **호출 순서 주의**: 상자 오버라이드보다 **먼저** 얹어야 한다. 소품은 정적이고 상자는
## 플레이 결과라, 같은 칸이 겹치면 나중에 열린 상자 쪽이 답이어야 한다.
func apply_to(rt: MapRuntime) -> int:
	for cell: Vector2i in _attrs:
		rt.set_override_attr(cell, int(_attrs[cell]))
	return _attrs.size()


## 이 칸에 깔린 소품(없으면 빈 사전). 조사(SPACE) 대상 조회용.
func prop_at(cell: Vector2i) -> Dictionary:
	return _by_cell.get(cell, {})


func prop_by_id(prop_id: String) -> Dictionary:
	for prop: Dictionary in props:
		if String(prop.get("id", "")) == prop_id:
			return prop
	return {}


static func anchor_of(prop: Dictionary) -> Vector2i:
	return _vec(prop.get("footprint", {}).get("anchor", [0, 0]))


static func size_of(prop: Dictionary) -> Vector2i:
	return _vec(prop.get("footprint", {}).get("size", [1, 1]))


## 소품이 덮는 칸들(앵커 기준 w×h). 렌더러가 조각을 놓을 때 쓰는 순서와 같다.
static func cells_of(prop: Dictionary) -> Array[Vector2i]:
	var anchor := anchor_of(prop)
	var size := size_of(prop)
	var out: Array[Vector2i] = []
	for dy in size.y:
		for dx in size.x:
			out.append(anchor + Vector2i(dx, dy))
	return out


## 소품이 지금 열려 있는가 — `state.open_flag`가 서 있으면 열림, 아니면 `state.default`.
## 상태가 없는 소품(책상 따위)은 언제나 닫힘으로 답한다.
static func is_open(prop: Dictionary, flags: Dictionary) -> bool:
	var state: Variant = prop.get("state", {})
	if typeof(state) != TYPE_DICTIONARY:
		return false
	var open_flag := String((state as Dictionary).get("open_flag", ""))
	if not open_flag.is_empty() and flags.has(open_flag):
		return true
	return String((state as Dictionary).get("default", "closed")) == "open"


func _ingest(prop: Dictionary) -> void:
	var footprint: Variant = prop.get("footprint", {})
	if typeof(footprint) != TYPE_DICTIONARY:
		push_error("PropsLayer: footprint 없음 (%s)" % str(prop.get("id", "?")))
		return
	var anchor := anchor_of(prop)
	var size := size_of(prop)
	var grid: Variant = (footprint as Dictionary).get("attr_grid", [])
	if typeof(grid) != TYPE_ARRAY or (grid as Array).size() != size.y:
		push_error("PropsLayer: attr_grid 행 수 불일치 (%s)" % str(prop.get("id", "?")))
		return
	props.append(prop)
	for dy in size.y:
		var row: Variant = (grid as Array)[dy]
		if typeof(row) != TYPE_ARRAY or (row as Array).size() != size.x:
			push_error("PropsLayer: attr_grid 열 수 불일치 (%s)" % str(prop.get("id", "?")))
			continue
		for dx in size.x:
			var cell := anchor + Vector2i(dx, dy)
			_by_cell[cell] = prop
			_attrs[cell] = int((row as Array)[dx])


static func _vec(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i.ZERO
