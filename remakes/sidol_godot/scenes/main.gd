extends Node
## 루트 씬 — 아트 모드 선택 후 필드 전환.
## 모드: LEGACY=원작 도트 세트(_original) / REMAKE=신규 세트(_remake).
## 경로 결정은 SpriteSets가 담당(부재 세트 자동 폴백).

const FIELD_SCENE := "res://scenes/field.tscn"
const MODE_LABELS: Array[String] = ["레거시 (원작 도트)", "리메이크 (신규)"]

var _mode_label: Label


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ui)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ui.add_child(vbox)

	var title := Label.new()
	title.text = "BSD 시돌이의 모험"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(title)

	_mode_label = Label.new()
	_mode_label.add_theme_font_size_override("font_size", 22)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_mode_label)

	var hint := Label.new()
	hint.text = "←/→  아트 모드 선택      Enter/Z  시작"
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(hint)

	_refresh_mode_label()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := event as InputEventKey
		if key.is_action_pressed(&"move_left"):
			_cycle_mode(-1)
		elif key.is_action_pressed(&"move_right"):
			_cycle_mode(1)
		elif key.is_action_pressed(&"ui_accept") \
				or key.is_action_pressed(&"interact"):
			_start_game()


func _cycle_mode(dir: int) -> void:
	var values: Array = SettingsManager.ArtMode.values()
	var idx := values.find(SettingsManager.art_mode)
	SettingsManager.art_mode = values[wrapi(idx + dir, 0, values.size())]
	_refresh_mode_label()


func _refresh_mode_label() -> void:
	_mode_label.text = "< %s >" % MODE_LABELS[int(SettingsManager.art_mode)]


func _start_game() -> void:
	print("[boot] art_mode=", MODE_LABELS[int(SettingsManager.art_mode)])
	get_tree().change_scene_to_file(FIELD_SCENE)
