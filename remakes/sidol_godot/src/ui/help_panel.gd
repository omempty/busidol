class_name HelpPanel
extends Control
## 조작 도움말 — InputMap 액션 기준(하드코딩 아님, input_bootstrap ACTIONS 참조).
## 타이틀과 일시정지 메뉴 공용. Esc로 닫는다.

signal closed

const ROWS := [
	["이동", "방향키 / WASD"],
	["조사 · 대화 · 확인", "Space / Z"],
	["취소 · 일시정지", "Esc"],
	["가방 열기", "I"],
	["미니맵 토글", "M"],
	["세이브", "층 이동 · 전투 승리 시 자동 기록 (일시정지에서 수동 가능)"],
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
		line.text = "%s   %s" % [row[1], row[0]]
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		line.add_theme_font_size_override("font_size", 17)
		vbox.add_child(line)

	var hint := Label.new()
	hint.text = "Esc — 닫기"
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
