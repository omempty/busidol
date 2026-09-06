class_name QuestLogPanel
extends Control
## 진행 기록(Q3) — data/quests_v2.json 마일스톤. 일시정지 메뉴에서 연다. Esc로 닫는다.
##
## **`description`과 `reward`를 그린다.** 2026-09-06까지 이 패널은 `id·zone·name`만
## 그렸고 `description`을 읽는 줄이 **0개**였다 — 21개 퀘스트의 "무엇을 하는가"가
## 데이터에만 있고 화면에 없었다. 유저가 "물품 찾기가 힘들다"고 한 절반이 여기다.
## 상태 판정은 QuestState가 단일 출처다(HUD 트래커와 같은 것을 쓴다).

signal closed

var _rows: Array[VBoxContainer] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func _build() -> void:
	var frame := ModalFrame.new()
	frame.setup("UI_QUESTLOG_TITLE", "UI_CLOSE_ESC", Vector2(460, 0))
	frame.dismissed.connect(func() -> void: closed.emit())
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

	var quests: Array = QuestState.all()
	var last_zone := ""
	for q: Dictionary in quests:
		# 구역이 바뀌면 머리글을 넣는다 — 21줄을 통으로 늘어놓으면 훑을 수가 없다.
		var zone := str(q.get("zone", ""))
		if zone != last_zone:
			var head := HudTheme.label(zone, 13, HudTheme.TEXT_MUTED)
			head.add_theme_constant_override("line_spacing", 0)
			list.add_child(head)
			last_zone = zone
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		list.add_child(box)
		box.add_child(HudTheme.label("", 14, HudTheme.TEXT))  # 제목 줄
		box.add_child(HudTheme.label("", 12, HudTheme.TEXT_MUTED))  # 설명 줄
		box.set_meta("quest", q)
		_rows.append(box)

	visibility_changed.connect(
		func() -> void:
			if visible:
				_refresh()
	)


func _refresh() -> void:
	for box in _rows:
		var q: Dictionary = box.get_meta("quest")
		var st := QuestState.status_of(q)
		var title: Label = box.get_child(0)
		var desc: Label = box.get_child(1)
		var mark := "·"
		var col := Color(0.45, 0.45, 0.52)
		match st:
			QuestState.Status.DONE:
				mark = "✓"
				col = Color(1.0, 0.9, 0.5)
			QuestState.Status.ACTIVE:
				# **지금 할 수 있는 것**만 밝게 — 이게 이 창을 여는 이유다.
				mark = "▶"
				col = HudTheme.ACCENT
			_:
				mark = "·"
		title.text = "%s %s" % [mark, str(q.get("name", ""))]
		title.add_theme_color_override("font_color", col)
		# 잠긴 것은 내용을 감춘다 — 앞으로 할 일을 미리 다 보여 주면 읽을 이유가 없다.
		if st == QuestState.Status.LOCKED:
			desc.text = "     " + tr("UI_QUEST_LOCKED")
		else:
			var line := "     " + str(q.get("description", ""))
			var rw := str(q.get("reward", ""))
			if not rw.is_empty():
				line += "   (%s: %s)" % [tr("UI_QUEST_REWARD"), rw]
			desc.text = line
		desc.add_theme_color_override(
			"font_color", HudTheme.TEXT if st == QuestState.Status.ACTIVE else Color(0.5, 0.5, 0.57)
		)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		closed.emit()
		get_viewport().set_input_as_handled()
		return
	if (
		event.is_action_pressed(&"cancel")
		or (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)
		)
	):
		closed.emit()
		get_viewport().set_input_as_handled()
