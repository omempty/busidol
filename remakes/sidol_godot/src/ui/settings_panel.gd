class_name SettingsPanel
extends Control
## 설정 UI — 볼륨 4버스·연출속도·아트모드. 변경 즉시 적용+파일 저장.
## 타이틀과 일시정지 메뉴가 공용. 키보드: ↑↓ 행 이동, ←→ 값 변경, Esc 닫기.

signal closed

const SPEED_LABELS := ["보통", "빠름", "스킵"]
const ART_LABELS := ["레거시 (원작 도트)", "리메이크 (신규)"]
const TEXT_LABELS := ["작음", "보통", "크게"]
const VOLUME_STEP := 0.1

var _rows: Array[Label] = []
var _values: Array[Label] = []
var _index := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh()


func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)
	for i in range(7):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 24)
		vbox.add_child(row)
		var name_lbl := Label.new()
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.custom_minimum_size = Vector2(180, 0)
		row.add_child(name_lbl)
		var val_lbl := Label.new()
		val_lbl.add_theme_font_size_override("font_size", 18)
		val_lbl.custom_minimum_size = Vector2(240, 0)
		row.add_child(val_lbl)
		_rows.append(name_lbl)
		_values.append(val_lbl)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"move_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_down"):
		_move(1)
	elif event.is_action_pressed(&"move_left"):
		_adjust(-1)
	elif event.is_action_pressed(&"move_right"):
		_adjust(1)
	elif event.is_action_pressed(&"cancel"):
		closed.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _move(dir: int) -> void:
	_index = wrapi(_index + dir, 0, _rows.size())
	_refresh()


func _adjust(dir: int) -> void:
	match _index:
		0, 1, 2, 3:
			var bus: StringName = SettingsManager.BUSES[_index]
			SettingsManager.set_volume(bus,
					SettingsManager.get_volume(bus) + dir * VOLUME_STEP)
		4:
			var values: Array = SettingsManager.EffectSpeed.values()
			var idx: int = values.find(SettingsManager.effect_speed)
			var next_v: Variant = values[wrapi(idx + dir, 0, values.size())]
			SettingsManager.effect_speed = next_v
		5:
			var values: Array = SettingsManager.ArtMode.values()
			var idx: int = values.find(SettingsManager.art_mode)
			var next_v: Variant = values[wrapi(idx + dir, 0, values.size())]
			SettingsManager.art_mode = next_v
		6:
			var values: Array = SettingsManager.TextSize.values()
			var idx: int = values.find(SettingsManager.text_size)
			var next_v: Variant = values[wrapi(idx + dir, 0, values.size())]
			SettingsManager.text_size = next_v
	SettingsManager.save_settings()
	_refresh()


func _refresh() -> void:
	for i in range(4):
		var bus: StringName = SettingsManager.BUSES[i]
		var names := ["마스터 볼륨", "BGM 볼륨", "효과음 볼륨", "보이스 볼륨"]
		_set_row(i, names[i], "%d%%" % roundi(SettingsManager.get_volume(bus) * 100))
	_set_row(4, "연출 속도", SPEED_LABELS[int(SettingsManager.effect_speed)])
	_set_row(5, "아트 모드", ART_LABELS[int(SettingsManager.art_mode)])
	_set_row(6, "본문 글자 크기", TEXT_LABELS[int(SettingsManager.text_size)])


func _set_row(i: int, text: String, value_text: String) -> void:
	var selected := i == _index
	_rows[i].text = ("> " if selected else "  ") + text
	_values[i].text = ("< %s >" % value_text) if selected else value_text
	var color := Color(1.0, 0.95, 0.6) if selected else Color(1, 1, 1)
	_rows[i].add_theme_color_override("font_color", color)
	_values[i].add_theme_color_override("font_color", color)
