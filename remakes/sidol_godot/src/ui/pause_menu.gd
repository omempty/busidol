class_name PauseMenu
extends CanvasLayer
## 필드 일시정지 메뉴(Esc) — 계속하기/세이브/로드/설정/타이틀. Phase 9(Q1).
## get_tree().paused 로 필드 정지, 자신은 ALWAYS 모드로 입력 유지.

const FIELD_SCENE := "res://scenes/field.tscn"
const TITLE_SCENE := "res://scenes/main.tscn"
const ROOT_ITEM_KEYS: Array[String] = [
	"UI_PAUSE_RESUME",
	"UI_PAUSE_SAVE",
	"UI_PAUSE_LOAD",
	"UI_PAUSE_QUESTLOG",
	"UI_PAUSE_HELP",
	"UI_PAUSE_SETTINGS",
	"UI_PAUSE_TO_TITLE",
]

enum Screen { ROOT, SAVE, LOAD, LOG, HELP, SETTINGS }

var _screen: Screen = Screen.ROOT
var _index := 0
var _root_box: ModalFrame
var _root_labels: Array[HBoxContainer] = []
var _slot_list: SaveSlotList
var _settings_panel: SettingsPanel
var _help_panel: HelpPanel
var _quest_log: QuestLogPanel
var allow_save: bool = true
var can_open_on_cancel: bool = true


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_root()

	_slot_list = SaveSlotList.new()
	_slot_list.visible = false
	_slot_list.slot_chosen.connect(_on_slot_chosen)
	_slot_list.canceled.connect(func() -> void: _switch(Screen.ROOT))
	add_child(_slot_list)

	_quest_log = QuestLogPanel.new()
	_quest_log.visible = false
	_quest_log.closed.connect(func() -> void: _switch(Screen.ROOT))
	add_child(_quest_log)

	_help_panel = HelpPanel.new()
	_help_panel.visible = false
	_help_panel.closed.connect(func() -> void: _switch(Screen.ROOT))
	add_child(_help_panel)

	_settings_panel = SettingsPanel.new()
	_settings_panel.visible = false
	_settings_panel.closed.connect(func() -> void: _switch(Screen.ROOT))
	_settings_panel.controls_requested.connect(func() -> void: _switch(Screen.HELP))
	add_child(_settings_panel)


func _build_root() -> void:
	var frame := ModalFrame.new()
	frame.setup("UI_PAUSE_TITLE", "UI_PAUSE_HINT", Vector2(300, 0))
	frame.dismissed.connect(toggle)
	add_child(frame)
	_root_box = frame

	for i in ROOT_ITEM_KEYS.size():
		var row := ModalFrame.row(tr(str(ROOT_ITEM_KEYS[i])), 17)
		frame.body.add_child(row)
		_root_labels.append(row)
		_bind_mouse(row, i)


## 나 말고 열려 있는 모달이 있는가.
##
## 왜 필요한가: `_unhandled_input`은 뒤쪽 형제부터 받는데, field.gd는 대화창(114행)과
## 가방(175행)을 PauseMenu(178행)보다 **앞에** 붙여 놓았다. 그래서 대화·로그·가방이
## 열려 있어도 ESC를 여기서 먼저 집어 메뉴가 떴다 — 로그를 닫으려던 ESC가 메뉴를 여는
## 것이 유저가 신고한 증상이다. 순서에 기대지 않고 **떠 있는 창이 있으면 안 연다**.
##
## 이벤트를 소비하지 않고 그냥 빠진다 — 그래야 진짜 주인(로그창 등)이 받아서 닫는다.
func _other_modal_open() -> bool:
	for node in get_tree().get_nodes_in_group(ModalFrame.MODAL_GROUP):
		if node == self or is_ancestor_of(node):
			continue  # 내 껍데기는 '다른 창'이 아니다
		# 모달은 두 종류다: ModalFrame은 Control(CanvasItem), 대화창은 CanvasLayer.
		# CanvasLayer에는 is_visible_in_tree()가 없으므로 타입별로 본다.
		if node is CanvasItem:
			if (node as CanvasItem).is_visible_in_tree():
				return true
		elif node is CanvasLayer:
			if (node as CanvasLayer).visible:
				return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed(&"cancel")
		or (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)
		)
	):
		if visible:
			if _screen == Screen.ROOT:
				toggle()
			else:
				_switch(Screen.ROOT)
			get_viewport().set_input_as_handled()
			return
		elif can_open_on_cancel and not _other_modal_open():
			if _screen == Screen.ROOT:
				toggle()
				get_viewport().set_input_as_handled()
				return
	if not visible or _screen != Screen.ROOT:
		return
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"move_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_down"):
		_move(1)
	elif (
		event.is_action_pressed(&"ui_accept")
		or event.is_action_pressed(&"interact")
		or event.is_action_pressed(&"menu")
		or (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and (
				event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_Z]
				or event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_Z]
			)
		)
	):
		_confirm()


func toggle() -> void:
	if _screen != Screen.ROOT:
		_switch(Screen.ROOT)
		visible = false
		get_tree().paused = false
		return
	visible = not visible
	get_tree().paused = visible
	if visible:
		_index = 0
		_refresh()


func _move(dir: int) -> void:
	_index = wrapi(_index + dir, 0, _root_labels.size())
	_refresh()


func _confirm() -> void:
	match _index:
		0:
			toggle()
		1:
			if not allow_save:
				AudioManager.play_sfx(&"sfx_menu_cancel")
				return
			_slot_list.mode = SaveSlotList.Mode.SAVE
			_switch(Screen.SAVE)
		2:
			_slot_list.mode = SaveSlotList.Mode.LOAD
			_switch(Screen.LOAD)
		3:
			_switch(Screen.LOG)
		4:
			_switch(Screen.HELP)
		5:
			_switch(Screen.SETTINGS)
		6:
			_to_title()


## 바깥(캐릭터 메뉴 시스템 탭)에서 특정 기능을 바로 연다. **기능은 여기 하나뿐이고**
## 부르는 쪽은 어느 화면인지만 고른다 — 세이브/로드가 두 벌이 되지 않게.
func open_action(action: StringName) -> void:
	visible = true
	match action:
		&"save":
			_slot_list.mode = SaveSlotList.Mode.SAVE
			_switch(Screen.SAVE)
		&"load":
			_slot_list.mode = SaveSlotList.Mode.LOAD
			_switch(Screen.LOAD)
		&"questlog":
			_switch(Screen.LOG)
		&"help":
			_switch(Screen.HELP)
		&"settings":
			_switch(Screen.SETTINGS)
		_:
			_switch(Screen.ROOT)


## 마우스 — 항목에 올리면 선택, 누르면 확정(04_uiux §1.3 삼중 내비).
func _bind_mouse(row: Control, idx: int) -> void:
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.mouse_entered.connect(
		func() -> void:
			if visible and _screen == Screen.ROOT:
				_index = idx
				_refresh()
	)
	row.gui_input.connect(
		func(e: InputEvent) -> void:
			if not visible or _screen != Screen.ROOT:
				return
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_index = idx
				_confirm()
	)


func _switch(to: Screen) -> void:
	_screen = to
	var save_or_load := to == Screen.SAVE or to == Screen.LOAD
	_slot_list.visible = save_or_load
	_quest_log.visible = to == Screen.LOG
	_help_panel.visible = to == Screen.HELP
	_settings_panel.visible = to == Screen.SETTINGS
	_root_box.visible = to == Screen.ROOT


func _on_slot_chosen(slot: int) -> void:
	if _screen == Screen.SAVE:
		SaveManager.save_slot(slot, "수동 세이브")
		_switch(Screen.ROOT)
		return
	if SaveManager.load_slot(slot):
		get_tree().paused = false
		get_tree().change_scene_to_file(FIELD_SCENE)


func _to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)


func _refresh() -> void:
	for i in range(_root_labels.size()):
		ModalFrame.set_row_selected(_root_labels[i], i == _index)
		if i == 1 and not allow_save:
			var label := _root_labels[i].get_node("Text") as Label
			label.add_theme_color_override("font_color", HudTheme.TEXT_MUTED)
