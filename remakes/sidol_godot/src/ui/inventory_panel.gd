class_name InventoryPanel
extends CanvasLayer
## 인벤토리 창(I키) — JRPG 컨벤션: 좌측 아이템 목록+커서, 우측 상세 창.
## 열리는 동안 get_tree().paused 로 월드 정지(PauseMenu와 동일 규약).
## 표시 데이터는 전부 data/items.json 경유(콘텐츠 하드코딩 금지).

const MAX_ROWS_SHOWN := 9

var _list_box: VBoxContainer
var _detail_name: Label
var _detail_kind: Label
var _detail_body: RichTextLabel
var _hint_label: Label
var _rows: Array[Dictionary] = []  # 파생 목록 캐시 [{item_id, count}]
var _index := 0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	GameState.inventory.changed.connect(
		func() -> void:
			if visible:
				_rebuild_list()
	)


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(600, 380)
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "— 가방 —"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	vbox.add_child(columns)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(_list_box)

	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(220, 0)
	columns.add_child(detail)
	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 15)
	detail.add_child(_detail_name)
	_detail_kind = Label.new()
	_detail_kind.add_theme_font_size_override("font_size", 11)
	_detail_kind.modulate = Color(1, 1, 1, 0.5)
	detail.add_child(_detail_kind)
	_detail_body = RichTextLabel.new()
	_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_body.add_theme_font_size_override("normal_font_size", 12)
	detail.add_child(_detail_body)

	_hint_label = Label.new()
	_hint_label.text = "↑↓ 선택    I / ESC 닫기"
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.modulate = Color(1, 1, 1, 0.45)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_hint_label)


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.94)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	return sb


func open() -> void:
	_index = 0
	visible = true
	get_tree().paused = true
	_rebuild_list()


func close() -> void:
	visible = false
	get_tree().paused = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"cancel") or event.is_action_pressed(&"inventory"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_up"):
		_move(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_down"):
		_move(1)
		get_viewport().set_input_as_handled()


func _move(delta: int) -> void:
	if _rows.is_empty():
		return
	_index = wrapi(_index + delta, 0, _rows.size())
	_refresh_rows()
	_refresh_detail()


func _rebuild_list() -> void:
	_rows = GameState.inventory.all_slots()
	for child in _list_box.get_children():
		child.queue_free()
	if _rows.is_empty():
		var empty := Label.new()
		empty.text = "가방이 비어 있다."
		empty.modulate = Color(1, 1, 1, 0.5)
		empty.add_theme_font_size_override("font_size", 13)
		_list_box.add_child(empty)
		_refresh_detail()
		return
	_index = clampi(_index, 0, _rows.size() - 1)
	for i in mini(_rows.size(), MAX_ROWS_SHOWN):
		_list_box.add_child(_make_row(i))
	if _rows.size() > MAX_ROWS_SHOWN:
		var more := Label.new()
		more.text = "… 외 %d개" % (_rows.size() - MAX_ROWS_SHOWN)
		more.add_theme_font_size_override("font_size", 11)
		more.modulate = Color(1, 1, 1, 0.4)
		_list_box.add_child(more)
	_refresh_detail()


func _make_row(i: int) -> Control:
	var slot: Dictionary = _rows[i]
	var item_def := Database.get_item(StringName(str(slot["item_id"])))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(26, 26)
	var icon_sb := StyleBoxFlat.new()
	icon_sb.bg_color = ItemIcons.kind_color(StringName(str(item_def.get("kind", ""))))
	icon_sb.set_corner_radius_all(5)
	icon.add_theme_stylebox_override("panel", icon_sb)
	var tex := ItemIcons.texture(item_def)
	if tex != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = tex
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.add_child(tex_rect)
	else:
		var glyph := Label.new()
		glyph.text = ItemIcons.glyph(item_def)
		glyph.add_theme_font_size_override("font_size", 14)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.add_child(glyph)
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = str(item_def.get("name_ko", str(slot["item_id"])))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var count_label := Label.new()
	count_label.text = "×%d" % int(slot["count"])
	count_label.modulate = Color(1, 1, 1, 0.65)
	row.add_child(count_label)

	if i == _index:
		row.modulate = Color(1.0, 0.95, 0.6)
		name_label.text = "▶ " + name_label.text
	elif i % 2 == 1:
		row.modulate = Color(1, 1, 1, 0.82)
	return row


func _refresh_rows() -> void:
	# 커서 이동 시 전행 재표현 — 행 수가 적어 재구축 비용 무시 가능.
	_rebuild_list()


func _refresh_detail() -> void:
	if _rows.is_empty():
		_detail_name.text = ""
		_detail_kind.text = ""
		_detail_body.text = ""
		return
	var slot: Dictionary = _rows[clampi(_index, 0, _rows.size() - 1)]
	var item_def := Database.get_item(StringName(str(slot["item_id"])))
	_detail_name.text = str(item_def.get("name_ko", str(slot["item_id"])))
	_detail_kind.text = str(item_def.get("kind", ""))
	_detail_body.clear()
	var desc := str(item_def.get("desc", ""))
	if not desc.is_empty():
		_detail_body.append_text(desc + "\n\n")
	if item_def.has("ap"):
		_detail_body.append_text("공격력 %d\n" % int(item_def["ap"]))
	if item_def.has("element") and str(item_def["element"]) != "physical":
		_detail_body.append_text("속성 %s\n" % str(item_def["element"]))
	if item_def.has("hp_restore"):
		_detail_body.append_text("HP %d 회복\n" % int(item_def["hp_restore"]))
	if item_def.has("price"):
		_detail_body.append_text("\n가격 %d G" % int(item_def["price"]))
