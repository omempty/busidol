class_name FastTravelPanel
extends CanvasLayer
## 빠른 이동(Q5) — 계단 위에서 열리는 층 선택창.
##
## 원작은 층을 옮길 때마다 계단까지 걸어가야 했다. 6층 왕복 동선이 그대로 남아 있어
## 되돌아가기가 곧 피로였다(04_uiux Q5). **해금제** — 한 번이라도 발을 들인 층만 뜬다.
##
## 층 이름은 data/maps/floors.json이 소유한다(소스에 표기 하드코딩 금지).

signal floor_chosen(floor_no: int)
signal closed

const FLOORS_PATH := "res://data/maps/floors.json"
const PANEL_WIDTH := 300.0

var _rows: Array[Label] = []
var _floors: Array[int] = []
var _index := 0
var _open := false


func is_open() -> bool:
	return _open


## 방문한 층 중 현재 층을 뺀 목록으로 연다. 갈 곳이 없으면 열지 않고 false를 돌려준다.
func open_for(current_floor: int) -> bool:
	_floors.clear()
	for f: int in GameState.visited_list():
		if f != current_floor:
			_floors.append(f)
	if _floors.is_empty():
		return false
	_index = 0
	_open = true
	visible = true
	_build()
	_refresh()
	return true


func close() -> void:
	_open = false
	visible = false
	closed.emit()


func _ready() -> void:
	layer = 45
	visible = false


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_rows.clear()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", HudTheme.panel(10, 14))
	add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var title := HudTheme.label("계단 — 어디로 갈까", 15, HudTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var rule := ColorRect.new()
	rule.color = HudTheme.BORDER
	rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule)

	var names := _floor_names()
	for f: int in _floors:
		var row := HudTheme.label(str(names.get(f, "F%d" % f)), 14, HudTheme.TEXT)
		box.add_child(row)
		_rows.append(row)

	var rule2 := ColorRect.new()
	rule2.color = HudTheme.BORDER
	rule2.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule2)
	var hint := HudTheme.label("↑↓ 선택   SPACE 이동   ESC 취소", 11, HudTheme.TEXT_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _floor_names() -> Dictionary:
	var out: Dictionary = {}
	var raw: Dictionary = JsonUtil.load_dict(FLOORS_PATH, "FastTravelPanel").get("floors", {})
	for key: String in raw:
		out[int(key)] = str((raw[key] as Dictionary).get("name_ko", "F" + key))
	return out


func _refresh() -> void:
	for i in _rows.size():
		var selected := i == _index
		_rows[i].add_theme_color_override(
			"font_color", HudTheme.ACCENT if selected else HudTheme.TEXT
		)
		var name_only := _rows[i].text.trim_prefix("> ").trim_prefix("  ")
		_rows[i].text = ("> " if selected else "  ") + name_only


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(&"cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"move_up"):
		_index = wrapi(_index - 1, 0, _rows.size())
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"move_down"):
		_index = wrapi(_index + 1, 0, _rows.size())
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"interact"):
		var target := _floors[_index]
		_open = false
		visible = false
		floor_chosen.emit(target)
		get_viewport().set_input_as_handled()
