extends Node
## 타이틀 화면 — 새 게임/계속하기/설정/종료 + 아트 모드 선택.
## 아트 모드: LEGACY=원작 도트 세트(_original) / REMAKE=신규 세트(_remake).
## 경로 결정은 SpriteSets가 담당(부재 세트 자동 폴백).

const FIELD_SCENE := "res://scenes/field.tscn"
## 표시 문자열은 data/l10n/ui.csv — const는 tr()을 담을 수 없어 키만 둔다.
const ART_KEYS: Array[String] = ["UI_ART_LEGACY", "UI_ART_REMAKE"]
const MENU_ITEM_KEYS: Array[String] = [
	"UI_MENU_NEW_GAME", "UI_MENU_CONTINUE", "UI_MENU_SETTINGS", "UI_MENU_HELP", "UI_MENU_QUIT"
]

enum Screen { MENU, CONTINUE, SETTINGS, HELP }

var _screen: Screen = Screen.MENU
var _index := 0
var _menu_labels: Array[Label] = []
var _slot_list: SaveSlotList
var _settings_panel: SettingsPanel
var _help_panel: HelpPanel
var _mode_label: Label


func _ready() -> void:
	_build_menu()
	_slot_list = SaveSlotList.new()
	_slot_list.mode = SaveSlotList.Mode.LOAD
	_slot_list.visible = false
	_slot_list.slot_chosen.connect(_on_load_slot)
	_slot_list.canceled.connect(func() -> void: _switch(Screen.MENU))
	add_child(_slot_list)
	_settings_panel = SettingsPanel.new()
	_settings_panel.visible = false
	_settings_panel.closed.connect(func() -> void: _switch(Screen.MENU))
	_settings_panel.controls_requested.connect(func() -> void: _switch(Screen.HELP))
	add_child(_settings_panel)
	_help_panel = HelpPanel.new()
	_help_panel.visible = false
	_help_panel.closed.connect(func() -> void: _switch(Screen.MENU))
	add_child(_help_panel)


func _build_menu() -> void:
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ui)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	ui.add_child(vbox)

	var title := Label.new()
	title.text = tr("UI_MENU_TITLE")
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(title)

	vbox.add_child(_spacer(18))
	for item_key in MENU_ITEM_KEYS:
		var row := Label.new()
		row.text = tr(item_key)
		row.add_theme_font_size_override("font_size", 22)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(row)
		_menu_labels.append(row)

	vbox.add_child(_spacer(24))
	_mode_label = Label.new()
	_mode_label.add_theme_font_size_override("font_size", 16)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_mode_label)

	var hint := Label.new()
	hint.text = tr("UI_MENU_HINT")
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(hint)

	_refresh()


func _spacer(height: float) -> Control:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, height)
	return sp


func _unhandled_input(event: InputEvent) -> void:
	if _screen != Screen.MENU:
		return
	if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"move_right"):
		_cycle_art_mode(-1 if event.is_action_pressed(&"move_left") else 1)
		return
	if event.is_action_pressed(&"move_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_down"):
		_move(1)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact"):
		_confirm()


func _move(dir: int) -> void:
	_index = wrapi(_index + dir, 0, _menu_labels.size())
	_refresh()


func _confirm() -> void:
	match _index:
		0:
			GameState.reset()
			DialogueLog.clear()  # 새 이야기 — 지난 판의 대사가 남으면 안 된다
			get_tree().change_scene_to_file(FIELD_SCENE)
		1:
			if SaveManager.has_any_save():
				_switch(Screen.CONTINUE)
		2:
			_switch(Screen.SETTINGS)
		3:
			_switch(Screen.HELP)
		4:
			get_tree().quit()


func _switch(to: Screen) -> void:
	_screen = to
	_slot_list.visible = to == Screen.CONTINUE
	_settings_panel.visible = to == Screen.SETTINGS
	_help_panel.visible = to == Screen.HELP


func _on_load_slot(slot: int) -> void:
	if not SaveManager.load_slot(slot):
		push_warning("슬롯 %d 복원 실패" % slot)
		return
	DialogueLog.clear()  # 다른 시점으로 건너뛴다 — 이전 흐름의 대사는 무효
	get_tree().change_scene_to_file(FIELD_SCENE)


func _cycle_art_mode(dir: int) -> void:
	var values: Array = SettingsManager.ArtMode.values()
	var idx := values.find(SettingsManager.art_mode)
	var next_v: Variant = values[wrapi(idx + dir, 0, values.size())]
	SettingsManager.art_mode = next_v
	SettingsManager.save_settings()
	_refresh()


func _refresh() -> void:
	var has_save := SaveManager.has_any_save()
	for i in range(_menu_labels.size()):
		var selected := i == _index
		var prefix := "> " if selected else "  "
		if i == 1 and not has_save:
			_menu_labels[i].text = tr("UI_MENU_CONTINUE_EMPTY")
			_menu_labels[i].add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
		else:
			_menu_labels[i].text = prefix + tr(MENU_ITEM_KEYS[i])
			_menu_labels[i].add_theme_color_override(
				"font_color", Color(1.0, 0.95, 0.6) if selected else Color(1, 1, 1)
			)
	_mode_label.text = tr("UI_MENU_ART_MODE") % tr(ART_KEYS[int(SettingsManager.art_mode)])
