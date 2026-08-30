class_name DialogueLogPanel
extends CanvasLayer
## 대화 로그 열람 창 — 지나간 대사를 되돌려 읽는다(04_uiux §1.2).
##
## 대화창(필드 30 · 컷신 41)과 미니게임(45)보다 위에 떠야 한다. 로그는 그 위에 겹쳐
## 여는 창이고, 아래에 깔리면 어제 키아트가 대사창을 덮은 것과 같은 일이 난다.
const LAYER := 60
## 한 번에 넘기는 줄 수(PageUp/PageDown 대신 방향키 길게 누르기를 전제).
const SCROLL_STEP := 34.0

var _scroll: ScrollContainer
var _list: VBoxContainer
var _built := false


func _ready() -> void:
	layer = LAYER
	visible = false


func open() -> void:
	_build()
	_fill()
	visible = true
	# 마지막 줄부터 본다 — 방금 넘긴 것을 되돌려 보는 것이 이 창의 용도다.
	await get_tree().process_frame
	if _scroll != null:
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _build() -> void:
	if _built:
		return
	_built = true
	var frame := ModalFrame.new()
	frame.setup("UI_DLGLOG_TITLE", "UI_DLGLOG_HINT", Vector2(620, 340))
	add_child(frame)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 268)
	frame.body.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)


func _fill() -> void:
	for child in _list.get_children():
		child.queue_free()
	if DialogueLog.is_empty():
		_list.add_child(HudTheme.label(tr("UI_DLGLOG_EMPTY"), 14, HudTheme.TEXT_MUTED))
		return
	for entry: Dictionary in DialogueLog.lines():
		var row := VBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 1)
		var speaker := str(entry.get("speaker", ""))
		if not speaker.is_empty():
			# 화자색은 대화창과 **같은 규칙**을 쓴다 — 로그에서 색이 달라지면 누가
			# 말했는지 두 번 배워야 한다.
			row.add_child(HudTheme.label(speaker, 12, SpeakerColors.color_for(speaker)))
		var body := HudTheme.label(str(entry.get("text", "")), 14, HudTheme.TEXT)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.custom_minimum_size = Vector2(560, 0)
		row.add_child(body)
		_list.add_child(row)


## ↑↓ 스크롤 · Esc/Enter 닫기. 창이 떠 있는 동안 대사 진행은 DialogueBox가 막는다.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"move_up", true):
		_scroll.scroll_vertical -= int(SCROLL_STEP)
	elif event.is_action_pressed(&"move_down", true):
		_scroll.scroll_vertical += int(SCROLL_STEP)
	elif event.is_action_pressed(&"cancel") or event.is_action_pressed(&"menu"):
		close()
	else:
		return
	get_viewport().set_input_as_handled()
