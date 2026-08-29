class_name MapRenderer
extends Node2D
## 맵을 TileMapLayer 3층으로 빌드 (Ground z=0 / Object z=10 / Front z=20).
## 아틀라스: 원작 리마스터본(tiles_original_32 / obj_original_32) — docs/02_design/01 §3.4.

const Z_GROUND := 0
const Z_OBJECT := 10
const Z_FRONT := 20

const GROUND_ATLAS := "res://assets/sprites/tiles_original_32.png"
## 리마스터 지면 아틀라스 — **있으면 쓰고 없으면 원본으로 돌아간다.**
## 원본 파일은 손대지 않으므로 이 두 파일(png·json)을 지우면 그대로 원복된다.
##
## 왜 새 파일인가 — 맵 데이터(어느 칸에 어느 타일)는 원본 F*.MAP과 바이트 단위로
## 같아야 한다(originals_check 관문). 그래서 자동 타일링으로 다시 깔 수는 없고,
## **같은 타일 id에 그림을 여러 벌** 두고 렌더에서 골라 32px 격자 반복을 지운다.
const GROUND_REMASTER := "res://assets/sprites/tiles_remaster_32.png"
const OBJECT_ATLAS := "res://assets/sprites/obj_original_32.png"

## TileSet 소스 ID — 레이어 하나가 지면/오브젝트 두 아틀라스를 동시에 참조한다.
const SRC_GROUND := 0
const SRC_OBJECT := 1

var runtime: MapRuntime
var _warned_missing := false
var _object_meta := {}
var _ground_atlas := GROUND_ATLAS
var _bank_rows := 0
var _banks := 1
var _layers: Array[TileMapLayer] = []


func build(rt: MapRuntime) -> void:
	runtime = rt
	var def := rt.definition
	_load_ground_atlas()
	var ground_meta := _tile_grid(load_texture_size(_ground_atlas))
	var object_meta := _load_object_meta()
	_object_meta = object_meta

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
	ts.add_source(_atlas_source(_ground_atlas), SRC_GROUND)
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
	var span := _bank_rows * grid.x if _bank_rows > 0 else grid.x * grid.y
	if id < 0 or id >= span:
		if not _warned_missing:
			push_warning("타일 ID 범위 밖: %d" % id)
			_warned_missing = true
		return
	layer.set_cell(
		cell, SRC_GROUND, Vector2i(id % grid.x, id / grid.x + _bank_of(cell) * _bank_rows)
	)


## 이 칸이 어느 변종을 쓰는가. **좌표만으로 정해진다** — 층을 다시 지어도 같은 칸은
## 같은 그림이어야 한다(난수를 쓰면 상자를 열 때마다 바닥 무늬가 바뀐다).
func _bank_of(cell: Vector2i) -> int:
	if _banks <= 1:
		return 0
	var h: int = (cell.x * 73856093) ^ (cell.y * 19349663)
	h ^= h >> 13
	return absi(h) % _banks


## 리마스터 아틀라스가 있으면 그것을 쓴다. 없으면 원본 — 두 파일을 지우는 것이
## 곧 원복이다. 메타(뱅크 수·뱅크당 행 수)는 아틀라스 옆 json이 정본이다.
func _load_ground_atlas() -> void:
	_ground_atlas = GROUND_ATLAS
	_bank_rows = 0
	_banks = 1
	if not ResourceLoader.exists(GROUND_REMASTER):
		return
	var meta_path := GROUND_REMASTER.replace(".png", ".json")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("리마스터 타일 메타 없음/불량 — 원본 아틀라스로 돌아간다")
		return
	var meta: Dictionary = raw
	_ground_atlas = GROUND_REMASTER
	_bank_rows = int(meta.get("rows_per_bank", 0))
	_banks = maxi(1, int(meta.get("banks", 1)))


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


## 이 칸의 오브젝트 그림 텍스처 — 연출(FieldFx)이 같은 그림을 복제해 띄우는 데 쓴다.
func object_texture_at(cell: Vector2i) -> AtlasTexture:
	if runtime == null:
		return null
	return object_texture(runtime.definition.object_at(cell))


## 오브젝트 id → 아틀라스 조각. 메타에 없는 id(원작에도 빈 슬롯이 있다)면 null.
func object_texture(id: int) -> AtlasTexture:
	var entry: Variant = (_object_meta.get("objects", {}) as Dictionary).get(str(id))
	if entry == null:
		return null
	var tex := AtlasTexture.new()
	tex.atlas = load(OBJECT_ATLAS)
	var px := MapDefinition.TILE_PX
	tex.region = Rect2(int(entry["col"]) * px, int(entry["row"]) * px, px, px)
	return tex


## 이 칸의 오브젝트 그림을 지운다.
##
## 상자를 열면 ATT만 바뀌고 **그림은 그대로 남아 있었다** — 이미 연 상자가 계속
## 상자로 보인다(2026-08-29 유저 지적). 판정은 이미 런타임 ATT로 하고 있었으므로
## 어긋난 것은 화면뿐이다.
func clear_object(cell: Vector2i) -> void:
	if _layers.size() < 2:
		return
	_layers[1].erase_cell(cell)
