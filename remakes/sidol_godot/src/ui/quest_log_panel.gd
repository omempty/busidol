class_name QuestLogPanel
extends Control
## 진행 기록(Q3) — data/quests_v2.json 마일스톤을 플래그 달성 여부로 표시.
## 일시정지 메뉴에서 연다. Esc로 닫는다.

signal closed

const QUESTS_PATH := "res://data/quests_v2.json"

var _rows: Array[Label] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var caption := Label.new()
	caption.text = tr("UI_QUESTLOG_TITLE")
	caption.add_theme_font_size_override("font_size", 20)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(caption)

	var quests: Array = _load_quests()
	for q: Dictionary in quests:
		var row := Label.new()
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		row.add_theme_font_size_override("font_size", 15)
		vbox.add_child(row)
		row.set_meta("flag_id", str(q["id"]))
		row.set_meta("zone", str(q.get("zone", "")))
		row.set_meta("name", str(q.get("name", "")))
		_rows.append(row)

	var hint := Label.new()
	hint.text = tr("UI_CLOSE_ESC")
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(hint)

	visibility_changed.connect(
		func() -> void:
			if visible:
				_refresh()
	)


func _load_quests() -> Array:
	if not FileAccess.file_exists(QUESTS_PATH):
		push_warning("quests 데이터 없음: %s" % QUESTS_PATH)
		return []
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(QUESTS_PATH))
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("quests 파싱 실패")
		return []
	return raw.get("quests", [])


func _refresh() -> void:
	for row in _rows:
		var done := GameState.has_flag(str(row.get_meta("flag_id")))
		var mark := "✓" if done else "·"
		row.text = "%s  %s — %s" % [mark, str(row.get_meta("zone")), str(row.get_meta("name"))]
		row.add_theme_color_override(
			"font_color", Color(1.0, 0.9, 0.5) if done else Color(0.55, 0.55, 0.62)
		)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
