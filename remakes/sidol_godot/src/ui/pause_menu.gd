class_name PauseMenu
extends CanvasLayer
## 필드 일시정지 메뉴(Esc) — 계속하기/세이브/로드/설정/타이틀. Phase 9(Q1).
## get_tree().paused 로 필드 정지, 자신은 ALWAYS 모드로 입력 유지.

const FIELD_SCENE := "res://scenes/field.tscn"
const TITLE_SCENE := "res://scenes/main.tscn"
const ROOT_ITEMS: Array[String] = [
	"계속하기",
	"세이브",
	"로드",
	"진행 기록",
	"도움말",
	"설정",
	"타이틀로",
]

enum Screen { ROOT, SAVE, LOAD, LOG, HELP, SETTINGS }

var _screen: Screen = Screen.ROOT
var _index := 0
var _root_box: VBoxContainer
var _root_labels: Array[Label] = []
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
	add_child(_settings_panel)


func _build_root() -> void:
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ui)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	ui.add_child(vbox)
	_root_box = vbox

	var caption := Label.new()
	caption.text = "— 일시정지 —"
	caption.add_theme_font_size_override("font_size", 20)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(caption)

	for item in ROOT_ITEMS:
		var row := Label.new()
		row.text = item
		row.add_theme_font_size_override("font_size", 18)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(row)
		_root_labels.append(row)


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
		var selected := i == _index
		var prefix := "> " if selected else "  "
		_root_labels[i].text = prefix + ROOT_ITEMS[i]
		_root_labels[i].add_theme_color_override(
			"font_color", Color(1.0, 0.95, 0.6) if selected else Color(1, 1, 1)
		)
