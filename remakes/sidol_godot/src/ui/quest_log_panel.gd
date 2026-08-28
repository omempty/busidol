class_name QuestLogPanel
extends Control
## 진행 기록(Q3) — data/quests_v2.json 마일스톤을 플래그 달성 여부로 표시.
## 일시정지 메뉴에서 연다. Esc로 닫는다.

signal closed

const QUESTS_PATH := "res://data/quests_v2.json"

var _rows: Array[Label] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func _build() -> void:
	var frame := ModalFrame.new()
	frame.setup("UI_QUESTLOG_TITLE", "UI_CLOSE_ESC", Vector2(460, 0))
	add_child(frame)

	# 목록이 길어 화면을 넘길 수 있다 — 스크롤 안에 담고 높이를 묶는다.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	var quests: Array = _load_quests()
	for q: Dictionary in quests:
		var row := HudTheme.label("", 14, HudTheme.TEXT)
		list.add_child(row)
		row.set_meta("flag_id", str(q["id"]))
		row.set_meta("zone", str(q.get("zone", "")))
		row.set_meta("name", str(q.get("name", "")))
		_rows.append(row)

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
