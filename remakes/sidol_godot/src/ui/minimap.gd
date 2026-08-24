class_name MinimapLayer
extends CanvasLayer
## 미니맵(Q4) — M키 토글. 원작 map_view()의 현대판.
## 지면 타일 ID → 플레이스홀더와 동일 해시 색상, 벽은 어둡게, 문은 밝게.

const SCALE := 2

var _image_view: TextureRect
var _dot: ColorRect
var _player: PlayerEntity
var _visible_now := false


func _ready() -> void:
	layer = 20
	visible = false


func build(def: MapDefinition) -> void:
	var img := Image.create(def.width, def.height, false, Image.FORMAT_RGBA8)
	for y in def.height:
		for x in def.width:
			var cell := Vector2i(x, y)
			var attr := def.attr_at(cell)
			img.set_pixel(x, y, _color_for(def.ground_at(cell), attr))
	var tex := ImageTexture.create_from_image(img)

	if _image_view == null:
		_image_view = TextureRect.new()
		_image_view.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_image_view.position = Vector2(-def.width * SCALE - 10, -def.height * SCALE - 10)
		_image_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_image_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_image_view)

	_image_view.texture = tex
	_image_view.custom_minimum_size = Vector2(def.width * SCALE, def.height * SCALE)
	_image_view.size = _image_view.custom_minimum_size

	if _dot == null:
		_dot = ColorRect.new()
		_dot.color = Color(1, 0.25, 0.25)
		_dot.size = Vector2(4, 4)
		_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_image_view.add_child(_dot)


func track(player: PlayerEntity) -> void:
	_player = player


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"minimap"):
		_visible_now = not _visible_now
		visible = _visible_now
	if visible and _player != null and _image_view != null:
		var p := Vector2(_player.mover.grid_pos) * SCALE
		_dot.position = p + Vector2(SCALE, SCALE)


func _color_for(tile_id: int, attr: int) -> Color:
	var r := float((tile_id * 61) % 170 + 50) / 255.0
	var g := float((tile_id * 97) % 150 + 60) / 255.0
	var b := float((tile_id * 151) % 180 + 65) / 255.0
	var c := Color(r, g, b)
	if attr == 1:
		c *= 0.45
	elif attr == 9:
		c = Color(1, 1, 0.7)
	return c
