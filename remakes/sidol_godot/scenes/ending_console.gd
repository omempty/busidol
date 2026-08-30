extends Control
## E-2 CRT/DOS 콘솔 메타 엔딩 — 1995년 DOS 화면 연출(타이핑 리빌+커서 점멸).
## 텍스트는 전부 data/ending_report.json 원문(마스터 시나리오 E-2) — 엔진은 렌더만.
## 진입: 크레딧룸 종료 시(Q_ENDING 설정 상태) / 종료: 아무 키 → 타이틀.

const REPORT_PATH := "res://data/ending_report.json"
const NEXT_SCENE := "res://scenes/main.tscn"
const CHARS_PER_SEC := 60.0  # 설정 '대사 속도' 배율 전 기준값(04_uiux §1.5)
const LINE_PAUSE := 0.12

var _report := {}
var _text_label: Label
var _hint_label: Label
var _full_text := ""
var _revealed := 0.0
var _done := false


func _ready() -> void:
	_report = JsonUtil.load_dict(REPORT_PATH, "EndingConsole")
	_build_ui()
	_full_text = _compose_text()
	if _full_text.is_empty():
		push_warning("엔딩 리포트 비어 있음 — 즉시 종료")
		_finish()
		return


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.02, 0.01)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 40)
	add_child(margin)

	_text_label = Label.new()
	_text_label.add_theme_font_size_override("font_size", 16)
	_text_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.45))
	_text_label.add_theme_color_override("font_shadow_color", Color(0.1, 0.5, 0.15, 0.6))
	_text_label.add_theme_constant_override("shadow_offset_x", 0)
	_text_label.add_theme_constant_override("shadow_offset_y", 0)
	_text_label.add_theme_constant_override("shadow_outline_size", 4)
	margin.add_child(_text_label)

	_hint_label = Label.new()
	_hint_label.text = str(_report.get("exit_hint", "- PRESS ANY KEY -"))
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.modulate = Color(0.35, 1.0, 0.45, 0.0)
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint_label.offset_left = -260
	_hint_label.offset_top = -50
	_hint_label.offset_right = -32
	_hint_label.offset_bottom = -24
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_hint_label)


func _compose_text() -> String:
	var lines: Array = [_str(_report.get("prompt", ""))]
	lines.append_array(
		(_report.get("lines", []) as Array).map(func(l: Variant) -> String: return str(l))
	)
	return "\n".join(PackedStringArray(lines))


func _str(v: Variant) -> String:
	return str(v)


func _process(delta: float) -> void:
	if _done or _full_text.is_empty():
		return
	# 엔딩 리포트도 대화창과 **같은 속도 설정**을 따른다 — 한 게임 안에서 글자가
	# 흐르는 속도가 두 가지면 설정을 바꾼 사람이 여기서 다시 답답해진다.
	if SettingsManager.is_text_instant():
		_revealed = float(_full_text.length())
	else:
		var cps := CHARS_PER_SEC * SettingsManager.text_speed_factor()
		_revealed = minf(_revealed + delta * cps, float(_full_text.length()))
	var chars := int(_revealed)
	var cursor := "▌" if fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0 else " "
	_text_label.text = _full_text.substr(0, chars) + cursor
	if chars >= _full_text.length():
		_done = true
		_text_label.text = _full_text
		_hint_label.modulate.a = 1.0


## 스킵 — 타이핑 중이면 전문 즉시 표시.
func reveal_all() -> void:
	if not _done:
		_revealed = float(_full_text.length())
		_done = true
		_text_label.text = _full_text
		_hint_label.modulate.a = 1.0


func is_typing() -> bool:
	return not _done


func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed(&"interact")
		or event.is_action_pressed(&"cancel")
		or event.is_action_pressed(&"ui_accept")
	):
		# **씬을 바꾸기 전에 소비 표시를 한다.** _finish()의 change_scene_to_file이 이
		# 노드를 지우므로, 그 뒤에 get_viewport()를 부르면 null이라 엔진이 통째로 죽는다
		# (2026-08-29 F5 훑기에서 signal 11로 실측 — 게임을 끝까지 깬 플레이어가 맞는다).
		get_viewport().set_input_as_handled()
		if not _done:
			reveal_all()
		else:
			_finish()


func _finish() -> void:
	get_tree().change_scene_to_file(NEXT_SCENE)
