class_name MapDressingOverlay
extends Node2D
## 맵 때·벽장식 오버레이 — 바닥 오염(먼지·녹슨 때·핏물)과 벽 장식(포스터·녹·그래피티).
##
## 왜 타일이 아니라 오버레이인가 — 오염이 타일 1개에 갇히면 스티커처럼 보인다.
## 큰 오염은 2~4타일에 걸쳐야 자연스럽고, 그것은 격자 타일로 못 찍는다.
## 위치 고정 스프라이트(결정적 해시 배치, 세이브 불요·재입장 동일)로 얹는다.
## 아트는 절차 생성(tools/dev/make_dressing.py) — 외부 의뢰로 교체 시 파일만 바꾼다.
##
## 데이터: data/maps/dressing.json —
##   {"floors": {"<n>": {"grime": {"density": int, "tint": [r,g,b]},
##     "walls": {"poster": int, "rust": int, "graffiti": int, "blood": int}}}}
## 벽 장식은 벽(attr 1) 옆 통행칸에만 둔다(좌표 측량 없이 mental — 코드는 통행을 본다).
## z=4 — 지면(0) 위·오브젝트(10)/액터(14~15) 아래. 바닥 때가 물건 밑에 깔린다.

const DIR := "res://assets/decals/"
const CFG := "res://data/maps/dressing.json"
const BLOB := "grime_blob.png"
const WALL_ART := {
	"poster": "poster.png",
	"rust": "rust.png",
	"graffiti": "graffiti.png",
	"blood": "blood.png",
}
## 크기 등급(타일 단위) — 큰 오염은 여러 타일에 걸친다. 비율 6:3:1.
const SIZE_BANDS := [
	[0.7, 1.2],
	[1.5, 2.2],
	[2.5, 3.5],
]
const BLOB_PX := 96.0


## 층이 갈릴 때마다 묶는다(필드가 renderer.build 직후에 부른다).
func bind_floor(floor_no: int, runtime: MapRuntime) -> void:
	for c in get_children():
		c.queue_free()
	if runtime == null or not FileAccess.file_exists(CFG):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CFG))
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("dressing 표 파싱 실패")
		return
	var cfg: Dictionary = ((raw as Dictionary).get("floors", {}) as Dictionary).get(
		str(floor_no), {}
	)
	if cfg.is_empty():
		return
	_lay_grime(runtime, cfg.get("grime", {}))
	_lay_walls(runtime, cfg.get("walls", {}))


## 바닥 오염 — 통행칸 해시 산포. 크기는 등급별, 회전·투명도도 해시.
func _lay_grime(runtime: MapRuntime, cfg: Dictionary) -> void:
	var density := int(cfg.get("density", 0))
	if density <= 0 or not ResourceLoader.exists(DIR + BLOB):
		return
	var tint_arr: Array = cfg.get("tint", [0.5, 0.5, 0.5])
	var tint := Color(
		float(tint_arr[0]) if tint_arr.size() > 0 else 0.5,
		float(tint_arr[1]) if tint_arr.size() > 1 else 0.5,
		float(tint_arr[2]) if tint_arr.size() > 2 else 0.5
	)
	var tex: Texture2D = load(DIR + BLOB)
	var cells := _floor_cells(runtime)
	if cells.is_empty():
		return
	for i in density:
		var cell: Vector2i = cells[absi(_hash(i, 11)) % cells.size()]
		var roll := _h01(i, 23)
		var band: Array = (
			SIZE_BANDS[0] if roll < 0.6 else (SIZE_BANDS[1] if roll < 0.9 else SIZE_BANDS[2])
		)
		var tiles := lerpf(float(band[0]), float(band[1]), _h01(i, 37))
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = true
		var sc := tiles * float(MapDefinition.TILE_PX) / BLOB_PX
		spr.scale = Vector2.ONE * sc
		spr.rotation = _h01(i, 51) * TAU
		spr.position = _cell_px(cell) + Vector2(_h01(i, 67) * 16.0 - 8.0, _h01(i, 83) * 16.0 - 8.0)
		spr.modulate = Color(tint.r, tint.g, tint.b, 0.35 + _h01(i, 97) * 0.25)
		spr.z_index = 4
		add_child(spr)


## 벽 장식 — 벽(attr 1) 옆 통행칸에만 둔다. 종류별 개수만큼 해시로 고른다.
func _lay_walls(runtime: MapRuntime, cfg: Dictionary) -> void:
	if not (cfg is Dictionary) or (cfg as Dictionary).is_empty():
		return
	var spots := _wall_spots(runtime)
	if spots.is_empty():
		return
	var n := 0
	for kind: String in cfg as Dictionary:
		if not WALL_ART.has(kind) or not ResourceLoader.exists(DIR + str(WALL_ART[kind])):
			continue
		for k in int((cfg as Dictionary).get(kind, 0)):
			var cell: Vector2i = spots[absi(_hash(n, 131 + k)) % spots.size()]
			var spr := Sprite2D.new()
			spr.texture = load(DIR + str(WALL_ART[kind]))
			spr.centered = true
			spr.flip_h = _h01(n, 137 + k) < 0.5
			spr.position = _cell_px(cell)
			spr.modulate = Color(1, 1, 1, 0.92)
			spr.z_index = 4
			add_child(spr)
			n += 1


## 통행 가능한 바닥칸 전부(밀도 분모). 상자·소품 오버라이드 반영은 runtime이 정본.
func _floor_cells(runtime: MapRuntime) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var def := runtime.definition
	for y in def.height:
		for x in def.width:
			var cell := Vector2i(x, y)
			if runtime.is_passable(cell):
				out.append(cell)
	return out


## 벽 옆 통행칸 — 벽(attr 1)과 4방향으로 맞닿은 통행칸만. 포스터가 허공에 안 뜬다.
func _wall_spots(runtime: MapRuntime) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var def := runtime.definition
	for cell in _floor_cells(runtime):
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var nb: Vector2i = cell + d
			if def.in_bounds(nb) and def.attr_at(nb) == 1:
				out.append(cell)
				break
	return out


func _cell_px(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * float(MapDefinition.TILE_PX)


func _hash(a: int, b: int) -> int:
	var h: int = (a * 73856093) ^ (b * 19349663)
	h ^= h >> 13
	return absi(h)


func _h01(a: int, b: int) -> float:
	return float(_hash(a, b) % 1000) / 1000.0
