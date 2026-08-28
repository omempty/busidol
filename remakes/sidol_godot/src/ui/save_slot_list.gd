class_name SaveSlotList
extends Control
## 세이브 슬롯 목록(오토+수동 3슬롯) — 타이틀 계속하기와 필드 일시정지가 공용.
## SAVE 모드는 빈 슬롯 선택 가능(덮어쓰기), LOAD 모드는 기록 있는 슬롯만.

enum Mode { SAVE, LOAD }

signal slot_chosen(slot: int)
signal canceled

const ROW_KEYS := ["UI_SAVE_AUTO", "UI_SAVE_SLOT_1", "UI_SAVE_SLOT_2", "UI_SAVE_SLOT_3"]

var mode: Mode = Mode.LOAD
var _rows: Array[Label] = []
var _index := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	visibility_changed.connect(
		func() -> void:
			if visible:
				_index = 0
				_refresh()
	)


func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)
	for i in range(SaveManager.SLOT_COUNT + 1):
		var row := Label.new()
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 18)
		vbox.add_child(row)
		_rows.append(row)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"move_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_down"):
		_move(1)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact"):
		_choose()
	elif event.is_action_pressed(&"cancel"):
		canceled.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _move(dir: int) -> void:
	var count := _rows.size()
	for _attempt in count:
		_index = wrapi(_index + dir, 0, count)
		if mode == Mode.SAVE or not SaveManager.slot_meta(_index).is_empty():
			break
	_refresh()


func _choose() -> void:
	if mode == Mode.LOAD and SaveManager.slot_meta(_index).is_empty():
		return
	slot_chosen.emit(_index)


func _refresh() -> void:
	for i in range(_rows.size()):
		var meta := SaveManager.slot_meta(i)
		var text := ""
		if meta.is_empty():
			text = tr("UI_SAVE_EMPTY") % tr(ROW_KEYS[i])
		else:
			text = (
				tr("UI_SAVE_ENTRY")
				% [
					tr(ROW_KEYS[i]),
					int(meta["floor"]),
					int(meta["level"]),
					int(meta["money"]),
					str(meta["saved_at"])
				]
			)
		if i == _index:
			text = "> " + text
			row_modulate(_rows[i], Color(1.0, 0.95, 0.6))
		else:
			text = "  " + text
			row_modulate(_rows[i], Color(1, 1, 1))
		_rows[i].text = text


func row_modulate(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
