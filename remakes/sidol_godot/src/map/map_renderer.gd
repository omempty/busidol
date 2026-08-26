class_name MapRenderer
extends Node2D
## 맵을 TileMapLayer 3층으로 빌드 (Ground z=0 / Object z=10 / Front z=20).
## 아틀라스: 원작 리마스터본(tiles_original_32 / obj_original_32) — docs/02_design/01 §3.4.

const Z_GROUND := 0
const Z_OBJECT := 10
const Z_FRONT := 20

const GROUND_ATLAS := "res://assets/sprites/tiles_original_32.png"
const OBJECT_ATLAS := "res://assets/sprites/obj_original_32.png"

## TileSet 소스 ID — 레이어 하나가 지면/오브젝트 두 아틀라스를 동시에 참조한다.
const SRC_GROUND := 0
const SRC_OBJECT := 1

var runtime: MapRuntime
var _warned_missing := false
var _layers: Array[TileMapLayer] = []


func build(rt: MapRuntime) -> void:
	runtime = rt
	var def := rt.definition
	var ground_meta := _tile_grid(load_texture_size(GROUND_ATLAS))
	var object_meta := _load_object_meta()

	_layers.clear()
	var shared_tileset := _build_tileset()
	for i in 3:
		var z: int = [Z_GROUND, Z_OBJECT, Z_FRONT][i]
		var layer := _make_layer(shared_tileset, z)
		layer.name = ["Ground", "Object", "Front"][i]
		_layers.append(layer)
		add_child(layer)

	for y in def.height:
		for x in def.width:
			var cell := Vector2i(x, y)
			var gid := def.ground_at(cell)
			var oid := def.object_at(cell)
			_set_ground(_layers[0], ground_meta, gid, cell)
			if oid > 0:
				_set_object(_layers[1], object_meta, oid, cell)
			if def.attr_at(cell) == 2:  # OVERHEAD — 액터 위 Front에도 그려 숨김 효과
				_set_ground(_layers[2], ground_meta, gid, cell)
				if oid > 0:
					_set_object(_layers[2], object_meta, oid, cell)


func load_texture_size(path: String) -> Vector2i:
	var tex: Texture2D = load(path)
	return Vector2i(tex.get_width(), tex.get_height())


func _tile_grid(size: Vector2i) -> Vector2i:
	return Vector2i(int(size.x / MapDefinition.TILE_PX), int(size.y / MapDefinition.TILE_PX))


func _load_object_meta() -> Dictionary:
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(OBJECT_ATLAS.replace(".png", ".json"))
	)
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("obj 메타 파싱 실패")
		return {}
	return raw


## 지면·오브젝트 두 아틀라스를 한 TileSet에 담는다(소스 0/1).
## 과거 결함: 오브젝트 레이어가 지면 아틀라스만 실었는데 set_cell은 소스 1을 지목 —
## 존재하지 않는 소스라 173종 오브젝트가 전부 미렌더(ATT 벽만 남아 "투명벽")였다.
func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(MapDefinition.TILE_PX, MapDefinition.TILE_PX)
	ts.add_source(_atlas_source(GROUND_ATLAS), SRC_GROUND)
	ts.add_source(_atlas_source(OBJECT_ATLAS), SRC_OBJECT)
	return ts


func _atlas_source(atlas_path: String) -> TileSetAtlasSource:
	var tex: Texture2D = load(atlas_path)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(MapDefinition.TILE_PX, MapDefinition.TILE_PX)
	var grid := _tile_grid(tex.get_size())
	for cy in grid.y:
		for cx in grid.x:
			src.create_tile(Vector2i(cx, cy))
	return src


func _make_layer(shared_tileset: TileSet, z_index_value: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = shared_tileset
	layer.z_index = z_index_value
	return layer


func _set_ground(layer: TileMapLayer, grid: Vector2i, id: int, cell: Vector2i) -> void:
	if id < 0 or id >= grid.x * grid.y:
		if not _warned_missing:
			push_warning("타일 ID 범위 밖: %d" % id)
			_warned_missing = true
		return
	layer.set_cell(cell, SRC_GROUND, Vector2i(id % grid.x, id / grid.x))


func _set_object(layer: TileMapLayer, meta: Dictionary, id: int, cell: Vector2i) -> void:
	var entry: Variant = (meta.get("objects", {}) as Dictionary).get(str(id))
	if entry == null:
		if not _warned_missing:
			push_warning("오브젝트 메타 누락 id=%d" % id)
			_warned_missing = true
		return
	var col: int = int(entry["col"])
	var row: int = int(entry["row"])
	layer.set_cell(cell, SRC_OBJECT, Vector2i(col, row))
