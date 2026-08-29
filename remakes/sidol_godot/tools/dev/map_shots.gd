extends Node
## 층 지도를 PNG로 굽는다 — **좌표를 눈으로 짚기 위한 도구.**
##
## 실행: godot --headless --path . res://tools/dev/map_shots.tscn -- [출력폴더]
##       (기본 출력: tools/dev/mapshots/ — .gitignore 대상, 언제든 다시 굽는다)
## 보기: tools/dev/map_viewer.html 을 더블클릭 (마우스를 올리면 그 칸의 좌표를 읽어 준다)
##
## 왜 필요한가 — 자동 주행이 "이벤트 트리거 7종의 좌표가 자리표시자라 F3~F5에 갈 수
## 없다"를 짚었는데(docs/05_status/01_autoplay.md), **실좌표를 정하려면 맵을 봐야 한다.**
## 200×65 격자를 숫자로만 더듬으면 임의 배치가 되고, 임의 배치는 고증도 재미도 아니다.
##
## 색은 미니맵과 **같은 표**를 쓴다(`MinimapLayer.color_for`) — 도구에서 고른 자리와
## 게임 안에서 보이는 지형이 어긋나면 안 된다. 그 위에 겹치는 표시만 여기서 정한다.

const OUT_DEFAULT := "res://tools/dev/mapshots"
const FLOORS := [0, 1, 2, 3, 4, 5]
## 한 칸을 몇 픽셀로 그릴 것인가. 200×65 맵이 800×260이 된다.
const SCALE := 4
## 격자 눈금 간격(칸).
const GRID := 10

const C_GRID := Color(1.0, 1.0, 1.0, 0.10)
const C_GRID_MAJOR := Color(1.0, 1.0, 1.0, 0.22)
const C_STAIRS := Color(0.45, 0.85, 1.0)
const C_NPC := Color(0.55, 1.0, 0.6)
const C_TRIGGER := Color(1.0, 0.35, 0.45)
## 눈금을 굵게 그리는 간격(칸) — 50칸마다 한 줄.
const GRID_MAJOR := 50


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if not args.is_empty() else OUT_DEFAULT
	DirAccess.make_dir_recursive_absolute(out_dir)
	var overlays: Dictionary = {}
	for floor_variant: Variant in FLOORS:
		var floor_no := int(floor_variant)
		var def := MapDefinition.load_from_json("res://data/maps/f%d.json" % floor_no)
		if def == null:
			push_error("[map_shots] 맵 없음: f%d" % floor_no)
			continue
		var marks := _marks(floor_no)
		_bake(def, marks).save_png("%s/f%d.png" % [out_dir, floor_no])
		overlays["f%d" % floor_no] = {
			"width": def.width,
			"height": def.height,
			"scale": SCALE,
			"marks": marks,
		}
		print("[map_shots] f%d %d×%d — 표시 %d개" % [floor_no, def.width, def.height, marks.size()])
	# `.js`로 쓴다 — `file://`로 연 페이지는 `fetch`가 막히지만 `<script src>`는 열린다.
	# 뷰어를 더블클릭만으로 열 수 있어야 쓰인다(로컬 서버를 띄우게 하면 아무도 안 본다).
	var file := FileAccess.open("%s/overlays.js" % out_dir, FileAccess.WRITE)
	if file != null:
		file.store_string("window.MAP_DATA = %s;" % JSON.stringify(overlays, "  "))
		file.close()
	print("-> %s" % out_dir)
	get_tree().quit(0)


## 겹쳐 찍을 것들 — 좌표가 데이터에 적힌 것 전부. 자리표시자 좌표는 여기서 **엉뚱한
## 데 찍혀** 한눈에 드러난다(전부 맵 왼쪽 위 구석에 몰려 있다).
func _marks(floor_no: int) -> Array:
	var out: Array = []
	var transitions := JsonUtil.load_dict("res://data/maps/transitions.json", "map_shots")
	for t: Dictionary in transitions.get("transitions", []):
		if floor_no < int(t["guard_min_floor"]) or floor_no > int(t["guard_max_floor"]):
			continue
		out.append(_mark("계단", str(t["id"]), Vector2i(int(t["anchor"][0]), int(t["anchor"][1]))))

	var npc_path := "res://data/maps/npcs_f%d.json" % floor_no
	if FileAccess.file_exists(npc_path):
		for n: Dictionary in JsonUtil.load_dict(npc_path, "map_shots").get("npcs", []):
			var pos: Array = n["pos"]
			out.append(_mark("NPC", str(n["id"]), Vector2i(int(pos[0]), int(pos[1]))))

	var trigger_path := "res://data/maps/triggers_f%d.json" % floor_no
	if FileAccess.file_exists(trigger_path):
		for t: Dictionary in JsonUtil.load_dict(trigger_path, "map_shots").get("triggers", []):
			var kind := str(t.get("type", ""))
			for c: Variant in t.get("cells", []):
				var label := "%s (%s)" % [str(t.get("id", "")), kind]
				out.append(_mark("트리거", label, Vector2i(int(c[0]), int(c[1]))))
	return out


func _mark(kind: String, label: String, cell: Vector2i) -> Dictionary:
	return {"kind": kind, "label": label, "x": cell.x, "y": cell.y}


func _bake(def: MapDefinition, marks: Array) -> Image:
	var img := Image.create(def.width * SCALE, def.height * SCALE, false, Image.FORMAT_RGBA8)
	for y in def.height:
		for x in def.width:
			_fill(img, x, y, MinimapLayer.color_for(def.attr_at(Vector2i(x, y))))
	_draw_grid(img, def)
	for mark_variant: Variant in marks:
		var mark: Dictionary = mark_variant
		_draw_mark(img, int(mark["x"]), int(mark["y"]), _mark_color(String(mark["kind"])))
	return img


func _mark_color(kind: String) -> Color:
	match kind:
		"계단":
			return C_STAIRS
		"NPC":
			return C_NPC
	return C_TRIGGER


func _fill(img: Image, cx: int, cy: int, color: Color) -> void:
	for dy in SCALE:
		for dx in SCALE:
			img.set_pixel(cx * SCALE + dx, cy * SCALE + dy, color)


## 눈금 — 10칸마다 옅게, 50칸마다 진하게. 칸을 세어 좌표를 읽는 유일한 수단이다.
func _draw_grid(img: Image, def: MapDefinition) -> void:
	for x in range(0, def.width, GRID):
		var tone := C_GRID_MAJOR if x % GRID_MAJOR == 0 else C_GRID
		for py in def.height * SCALE:
			_blend(img, x * SCALE, py, tone)
	for y in range(0, def.height, GRID):
		var tone := C_GRID_MAJOR if y % GRID_MAJOR == 0 else C_GRID
		for px in def.width * SCALE:
			_blend(img, px, y * SCALE, tone)


## 표시는 칸을 채우지 않고 **테두리만** 그린다 — 그 자리 지형이 그대로 보여야 한다.
func _draw_mark(img: Image, cx: int, cy: int, color: Color) -> void:
	var x0 := cx * SCALE
	var y0 := cy * SCALE
	for i in SCALE:
		_blend(img, x0 + i, y0, color)
		_blend(img, x0 + i, y0 + SCALE - 1, color)
		_blend(img, x0, y0 + i, color)
		_blend(img, x0 + SCALE - 1, y0 + i, color)


func _blend(img: Image, px: int, py: int, color: Color) -> void:
	if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
		return
	img.set_pixel(px, py, img.get_pixel(px, py).lerp(color, color.a))
