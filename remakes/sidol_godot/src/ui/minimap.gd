class_name MinimapLayer
extends CanvasLayer
## 미니맵(Q4) — M키 토글. 원작 map_view()의 현대판.
## 구판은 타일 ID를 해시해 색을 뽑아 지형이 아니라 노이즈로 보였다.
## 지금은 통행 의미(벽/바닥/문/상자)만 칠한다 — 길 찾기라는 용도에 맞춘 단색 스킴.

const SCALE := 2
const MARGIN := 12.0
const DOT := 7.0

## ATT 값 → 미니맵 색. 근거: docs/01_analysis/03_data_format_spec.md §1 ATT 표.
const C_WALL := Color(0.10, 0.11, 0.15)
const C_FLOOR := Color(0.31, 0.34, 0.42)
const C_OVERHEAD := Color(0.23, 0.26, 0.33)
const C_DOOR := Color(0.99, 0.76, 0.31)
const C_CHEST := Color(0.96, 0.86, 0.36)
const C_ROOM := Color(0.42, 0.50, 0.63)  # NPC/방 식별값 — 통행은 막히나 지형은 아님
const CHEST_MIN := 150
const CHEST_MAX := 184

var _card: PanelContainer
var _image_view: TextureRect
var _dot: Panel
var _title: Label
var _player: PlayerEntity
var _visible_now := false


func _ready() -> void:
	layer = 20
	visible = false
	_build_card()


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_card.offset_right = -MARGIN
	_card.offset_bottom = -MARGIN
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", HudTheme.panel(10, 8))
	add_child(_card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	_card.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	_title = HudTheme.label("", 10, HudTheme.TEXT_MUTED)
	header.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(HudTheme.label(tr("UI_MAP_CLOSE"), 10, HudTheme.TEXT_MUTED))

	_image_view = TextureRect.new()
	_image_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_image_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_image_view)

	_dot = Panel.new()
	_dot.size = Vector2(DOT, DOT)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := HudTheme.fill(Color(0.96, 0.32, 0.32), 4)
	sb.border_color = Color(1, 1, 1, 0.9)
	sb.set_border_width_all(1)
	_dot.add_theme_stylebox_override("panel", sb)
	_image_view.add_child(_dot)


func build(def: MapDefinition) -> void:
	var img := Image.create(def.width, def.height, false, Image.FORMAT_RGBA8)
	for y in def.height:
		for x in def.width:
			img.set_pixel(x, y, _color_for(def.attr_at(Vector2i(x, y))))
	_image_view.texture = ImageTexture.create_from_image(img)
	_image_view.custom_minimum_size = Vector2(def.width * SCALE, def.height * SCALE)
	_title.text = tr("UI_MAP_TITLE") % def.map_id.to_upper()


func track(player: PlayerEntity) -> void:
	_player = player


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"minimap"):
		_visible_now = not _visible_now
		visible = _visible_now
	if not (visible and _player != null and _image_view != null):
		return
	# 2×2 발판의 중심을 찍는다 — 셀 좌상단 기준이면 캐릭터가 반 칸 위로 보인다.
	var center := (Vector2(_player.mover.grid_pos) + Vector2.ONE) * SCALE
	_dot.position = center - Vector2(DOT, DOT) * 0.5


func _color_for(attr: int) -> Color:
	if attr >= CHEST_MIN and attr <= CHEST_MAX:
		return C_CHEST
	match attr:
		0:
			return C_FLOOR
		1:
			return C_WALL
		2:
			return C_OVERHEAD
		9:
			return C_DOOR
	return C_ROOM
