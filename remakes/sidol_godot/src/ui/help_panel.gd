class_name HelpPanel
extends Control
## 조작 도움말 — InputMap 액션 기준(하드코딩 아님, input_bootstrap ACTIONS 참조).
## 타이틀과 일시정지 메뉴 공용. Esc로 닫는다.

signal closed

## [번역 키, 번역 키 또는 키 이름] — 키 이름(Esc·I·M)은 언어와 무관해 그대로 둔다.
const ROWS := [
	["UI_HELP_MOVE", "UI_HELP_MOVE_KEYS"],
	["UI_HELP_INTERACT", "Space / Z"],
	["UI_HELP_CANCEL", "Esc"],
	["UI_HELP_BAG", "I"],
	["UI_HELP_MAP", "M"],
	["UI_HELP_SAVE", "UI_HELP_SAVE_DESC"],
]


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
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	for row: Array in ROWS:
		var line := Label.new()
		# 2열은 키 이름일 수도, 번역 키일 수도 있다 — tr()은 미등록 키를 원문 그대로 돌려준다.
		line.text = "%s   %s" % [tr(str(row[1])), tr(str(row[0]))]
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		line.add_theme_font_size_override("font_size", 17)
		vbox.add_child(line)

	var hint := Label.new()
	hint.text = tr("UI_CLOSE_ESC")
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"cancel") or event.is_action_pressed(&"ui_accept"):
		closed.emit()
		get_viewport().set_input_as_handled()
