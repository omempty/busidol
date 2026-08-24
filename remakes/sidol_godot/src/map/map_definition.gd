class_name MapDefinition
extends RefCounted
## 불변 맵 데이터 — data/maps/f<N>.json 로딩 (docs/02_design/01_oop_redesign.md §3).
## 원본 MAP 바이트포맷과 무손실 호환(map_convert.py 산출물).

const TILE_PX := 32   # G-ART B안 확정(2026-08-24): 원작 12px → 32px 리드로우 규격

var map_id: String
var source: String
var width: int
var height: int
var ground := PackedByteArray()
var object := PackedByteArray()
var attr := PackedByteArray()


static func load_from_json(path: String) -> MapDefinition:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("MapDefinition: JSON 파싱 실패 %s" % path)
		return null
	var def := MapDefinition.new()
	def.map_id = str(raw["map_id"])
	def.source = str(raw["source"])
	def.width = int(raw["width"])
	def.height = int(raw["height"])
	def.ground = _flatten(raw["layers"]["ground"])
	def.object = _flatten(raw["layers"]["object"])
	def.attr = _flatten(raw["layers"]["attr"])
	return def


static func _flatten(rows: Array) -> PackedByteArray:
	var cols: int = (rows[0] as Array).size()
	var out := PackedByteArray()
	out.resize(rows.size() * cols)
	for y in rows.size():
		var row: Array = rows[y]
		for x in cols:
			out[y * cols + x] = int(row[x])
	return out


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func attr_at(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return 1  # 맵 밖은 벽 취급 — 문/계단 검사의 경계 읽기 안전화
	return attr[cell.y * width + cell.x]


func ground_at(cell: Vector2i) -> int:
	return ground[cell.y * width + cell.x]


func object_at(cell: Vector2i) -> int:
	return object[cell.y * width + cell.x]
