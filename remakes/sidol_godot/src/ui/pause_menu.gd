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
	add_child(frame)
	_root_box = frame

	for i in ROOT_ITEM_KEYS.size():
		var row := ModalFrame.row(tr(str(ROOT_ITEM_KEYS[i])), 17)
		frame.body.add_child(row)
		_root_labels.append(row)
		_bind_mouse(row, i)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"cancel"):
		if _screen == Screen.ROOT:
			toggle()
			get_viewport().set_input_as_handled()
		return
	if not visible or _screen != Screen.ROOT:
		return
	if event.is_action_pressed(&"move_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_down"):
		_move(1)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact"):
		_confirm()


func toggle() -> void:
	if _screen != Screen.ROOT:
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
