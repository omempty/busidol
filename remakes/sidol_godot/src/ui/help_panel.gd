class_name HelpPanel
extends Control
## 조작 도움말 — InputMap 액션 기준(하드코딩 아님, input_bootstrap ACTIONS 참조).
## 타이틀과 일시정지 메뉴 공용. Esc로 닫는다.

signal closed

## [번역 키, 번역 키 또는 키 이름] — 키 이름(Esc·I·M·패드 버튼)은 언어와 무관해 그대로 둔다.
## 패드 표기는 input_bootstrap.PAD_BUTTONS와 같은 배치(Xbox 기준)를 적는다.
const ROWS := [
	["UI_HELP_MOVE", "UI_HELP_MOVE_KEYS"],
	["UI_HELP_RUN", "Shift"],
	["UI_HELP_INTERACT", "Space / Z / PAD A"],
	["UI_HELP_CANCEL", "Esc / PAD B"],
	["UI_HELP_BAG", "I / PAD Y"],
	["UI_HELP_MAP", "M / PAD BACK"],
	["UI_HELP_DLGLOG", "Enter / PAD START"],
	["UI_HELP_SAVE", "UI_HELP_SAVE_DESC"],
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func _build() -> void:
	var frame := ModalFrame.new()
	frame.setup("UI_HELP_TITLE", "UI_CLOSE_ESC", Vector2(420, 0))
	frame.dismissed.connect(func() -> void: closed.emit())
	add_child(frame)

	# 키캡(고정 폭) + 설명 2열 — 구판은 한 줄에 이어 붙여 눈이 키를 찾기 어려웠다.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	frame.body.add_child(grid)
	for row: Array in ROWS:
		var cap := PanelContainer.new()
		cap.add_theme_stylebox_override("panel", HudTheme.chip(HudTheme.BG_SUNKEN, 5, 8, 3))
		cap.size_flags_horizontal = Control.SIZE_SHRINK_END
		# 2열은 키 이름일 수도, 번역 키일 수도 있다 — tr()은 미등록 키를 원문 그대로 돌려준다.
		cap.add_child(HudTheme.label(tr(str(row[1])), 13, HudTheme.ACCENT))
		grid.add_child(cap)
		grid.add_child(HudTheme.label(tr(str(row[0])), 14, HudTheme.TEXT))


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
		or event.is_action_pressed(&"ui_accept")
		or (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)
		)
	):
		closed.emit()
		get_viewport().set_input_as_handled()
