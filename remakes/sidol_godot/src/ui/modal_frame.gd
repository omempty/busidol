class_name ModalFrame
extends Control
## 모달 공용 껍데기 — 딤 + 중앙 패널 + 제목 + 본문 + 하단 힌트.
##
## 2026-08-28 캡처 실측: 일시정지·설정·도움말·진행기록은 **패널 배경이 아예 없어**
## 글자가 맵 위에 그대로 떠 있었다(가방·상점만 배경을 갖고 있었다). 같은 게임 안에서
## 창마다 규격이 다른 것이 원인이라, 껍데기를 한 곳에서 만든다.
##
## 사용:
##   var frame := ModalFrame.new()
##   frame.setup("UI_PAUSE_TITLE", "UI_CLOSE_ESC", Vector2(320, 0))
##   add_child(frame)
##   frame.body.add_child(...)

const DIM := Color(0, 0, 0, 0.62)
const PAD := 18
const RADIUS := 12
const TITLE_SIZE := 18
const HINT_SIZE := 11
const BODY_SEPARATION := 6

signal dismissed

var body: VBoxContainer
var _title: Label
var _hint: Label
var _close_btn: PanelContainer
var _dim: ColorRect

## 열려 있는 모달임을 알리는 그룹. PauseMenu가 이걸 보고 "이미 창이 떠 있으면 메뉴를
## 열지 않는다"를 판단한다 — 창을 새로 만들어도 ModalFrame만 쓰면 자동으로 걸린다.
const MODAL_GROUP := &"ui_modal"


## 뷰포트 접근은 트리에 들어온 뒤에만 가능하다 — setup()은 add_child 전에 불린다.
func _ready() -> void:
	_fit_viewport()
	get_viewport().size_changed.connect(_fit_viewport)
	visibility_changed.connect(_sync_modal_group)
	_sync_modal_group()


## 보이면 그룹에 들고, 숨으면 뺀다. 트리에서 빠질 때도 반드시 빼야 한다 —
## 남아 있으면 닫힌 창 때문에 ESC가 영영 메뉴를 못 연다.
func _sync_modal_group() -> void:
	if is_visible_in_tree():
		if not is_in_group(MODAL_GROUP):
			add_to_group(MODAL_GROUP)
	elif is_in_group(MODAL_GROUP):
		remove_from_group(MODAL_GROUP)


func _exit_tree() -> void:
	if is_in_group(MODAL_GROUP):
		remove_from_group(MODAL_GROUP)


func setup(title_key: String, hint_key: String = "", min_size: Vector2 = Vector2(320, 0)) -> void:
	# 부모가 무엇이든(0 크기 Control이어도) 화면 전체를 덮어야 한다 — 딤이 반쪽만 깔리면
	# 뒤 월드가 그대로 보여 모달로 읽히지 않는다. 앵커 대신 뷰포트 크기를 직접 따라간다.
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_dim = ColorRect.new()
	_dim.color = DIM
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.name = "Dim"
	_dim.gui_input.connect(
		func(e: InputEvent) -> void:
			if (
				e is InputEventMouseButton
				and e.pressed
				and (e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT)
			):
				dismissed.emit()
	)
	add_child(_dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	# PRESET_CENTER는 앵커만 옮긴다 — 양방향 성장을 켜야 패널이 실제로 가운데 선다.
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = min_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(
		func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
				dismissed.emit()
	)
	panel.add_theme_stylebox_override("panel", HudTheme.panel(RADIUS, PAD))
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	_title = HudTheme.label(tr(title_key), TITLE_SIZE, HudTheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)

	_close_btn = PanelContainer.new()
	_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_btn.add_theme_stylebox_override("panel", HudTheme.chip(HudTheme.BG_SUNKEN, 4, 8, 2))
	var close_lbl := HudTheme.label("✕", 12, HudTheme.TEXT_MUTED)
	close_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close_btn.add_child(close_lbl)
	_close_btn.mouse_entered.connect(
		func() -> void: close_lbl.add_theme_color_override("font_color", HudTheme.HP_LOW)
	)
	_close_btn.mouse_exited.connect(
		func() -> void: close_lbl.add_theme_color_override("font_color", HudTheme.TEXT_MUTED)
	)
	_close_btn.gui_input.connect(
		func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				dismissed.emit()
	)
	header.add_child(_close_btn)

	var rule := HSeparator.new()
	rule.add_theme_stylebox_override("separator", HudTheme.rule())
	column.add_child(rule)

	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", BODY_SEPARATION)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	_hint = HudTheme.label("", HINT_SIZE, HudTheme.TEXT_MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_hint)
	set_hint(hint_key)


## 뷰포트 전체를 덮도록 자기 사각형을 맞춘다(창 크기 변경에도 따라간다).
func _fit_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func set_title(title_key: String) -> void:
	_title.text = tr(title_key)


func set_hint(hint_key: String) -> void:
	_hint.text = tr(hint_key) if not hint_key.is_empty() else ""
	_hint.visible = not _hint.text.is_empty()


func set_close_button_visible(v: bool) -> void:
	if _close_btn != null:
		_close_btn.visible = v


## 목록 한 줄 — 커서 자리를 고정 폭으로 따로 두어 선택 시 글자가 흔들리지 않게 한다.
## 구판은 "> "를 텍스트 앞에 붙여, 커서가 옮겨 다닐 때마다 항목이 좌우로 튀었다.
static func row(text: String, size: int = 16) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var cursor := HudTheme.label("", size, HudTheme.ACCENT)
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor.custom_minimum_size = Vector2(14, 0)
	cursor.name = "Cursor"
	line.add_child(cursor)
	var label := HudTheme.label(text, size, HudTheme.TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.name = "Text"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	return line


## 목록 줄의 선택 상태 — 커서 문자와 글자색만 바뀐다(레이아웃 불변).
static func set_row_selected(line: HBoxContainer, selected: bool) -> void:
	var cursor := line.get_node("Cursor") as Label
	var label := line.get_node("Text") as Label
	cursor.text = "▶" if selected else ""
	label.add_theme_color_override("font_color", HudTheme.ACCENT if selected else HudTheme.TEXT)
