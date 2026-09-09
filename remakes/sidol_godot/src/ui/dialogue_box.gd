class_name DialogueBox
extends CanvasLayer
## 대화창 — 타이핑 효과 + 입력 진행(스킵). 원작 Talk_Window의 현대판 (04_uiux §1.2).

signal finished(seq_id: StringName)
## 시퀀스 스텝이 대사가 아니라 op일 때 — 필드가 받아 처리한다(예: shop).
## 구판은 op 스텝을 대사로 취급해 speaker/text가 빈 줄로 렌더됐고,
## `cafeteria_girl_shop`의 shop op이 아무 일도 하지 않았다.
signal op_requested(op_name: String, args: Dictionary)

const CPS := 40.0  # 초당 글자 수(설정 배율 전 기준값)
const INPUT_COOLDOWN := 0.05
const AUTO_DELAY := 1.1  # auto_advance 시 타이핑 완료 후 대기(초)

var seq_id := &""
var steps: Array = []
var index := 0
var is_open := false
## 컷신용 자동 진행 — 타이핑 완료 후 AUTO_DELAY 뒤 스스로 다음 스텝.
## 필드 대화(입력 중재 모드)에서는 반드시 false.
var auto_advance := false
var _revealed := 0.0
var _cooldown := 0.0
var _auto_wait := 0.0
var _log_panel: DialogueLogPanel


func is_typing() -> bool:
	return _body_label.text.length() > int(_revealed)


var _panel: PanelContainer
var _name_badge: PanelContainer
var _name_label: Label
var _body_label: Label
var _portrait_frame: PanelContainer
var _portrait: TextureRect
var _next_indicator: Label
var _auto_btn_label: Label


func _ready() -> void:
	layer = 30
	visible = false

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 28
	_panel.offset_right = -28
	_panel.offset_bottom = -14
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", HudTheme.panel(10, 14))
	_panel.gui_input.connect(
		func(e: InputEvent) -> void:
			if (
				e is InputEventMouseButton
				and e.pressed
				and (e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT)
			):
				advance()
	)
	add_child(_panel)

	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 14)
	_panel.add_child(main_row)

	# 초상화 프레임 (도트 보존 & 입체 액자)
	_portrait_frame = PanelContainer.new()
	_portrait_frame.custom_minimum_size = Vector2(104, 104)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	psb.border_color = Color(0.4, 0.45, 0.55, 0.6)
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(8)
	psb.shadow_size = 4
	psb.shadow_color = Color(0, 0, 0, 0.5)
	_portrait_frame.add_theme_stylebox_override("panel", psb)
	_portrait_frame.visible = false
	main_row.add_child(_portrait_frame)

	_portrait = TextureRect.new()
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 도트 보존
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.custom_minimum_size = Vector2(98, 98)
	_portrait_frame.add_child(_portrait)

	var content_col := VBoxContainer.new()
	content_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_col.add_theme_constant_override("separation", 6)
	main_row.add_child(content_col)

	# 헤더 바: [독립 화자 명찰 배지] + [스페이서] + [도구 버튼들: LOG, AUTO, SKIP]
	var header_bar := HBoxContainer.new()
	header_bar.add_theme_constant_override("separation", 8)
	content_col.add_child(header_bar)

	_name_badge = PanelContainer.new()
	_name_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_badge.add_theme_stylebox_override(
		"panel", HudTheme.chip(Color(0.14, 0.16, 0.22, 0.95), 4, 10, 3)
	)
	_name_label = Label.new()
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_name_badge.add_child(_name_label)
	header_bar.add_child(_name_badge)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_bar.add_child(sp)

	# 도구 버튼들
	var tools_row := HBoxContainer.new()
	tools_row.add_theme_constant_override("separation", 4)
	header_bar.add_child(tools_row)

	# [LOG]
	var log_btn := PanelContainer.new()
	log_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	log_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	log_btn.add_theme_stylebox_override("panel", HudTheme.chip(HudTheme.BG_SUNKEN, 4, 6, 2))
	var log_lbl := HudTheme.label(tr("UI_DLG_BTN_LOG"), 10, HudTheme.TEXT_MUTED)
	log_btn.add_child(log_lbl)
	log_btn.gui_input.connect(
		func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				toggle_log()
	)
	tools_row.add_child(log_btn)

	# [AUTO]
	var auto_btn := PanelContainer.new()
	auto_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	auto_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	auto_btn.add_theme_stylebox_override("panel", HudTheme.chip(HudTheme.BG_SUNKEN, 4, 6, 2))
	_auto_btn_label = HudTheme.label(tr("UI_DLG_BTN_AUTO"), 10, HudTheme.TEXT_MUTED)
	auto_btn.add_child(_auto_btn_label)
	auto_btn.gui_input.connect(
		func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				auto_advance = not auto_advance
				_refresh_auto_btn()
	)
	tools_row.add_child(auto_btn)

	# [SKIP]
	var skip_btn := PanelContainer.new()
	skip_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	skip_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	skip_btn.add_theme_stylebox_override("panel", HudTheme.chip(HudTheme.BG_SUNKEN, 4, 6, 2))
	var skip_lbl := HudTheme.label(tr("UI_DLG_BTN_SKIP"), 10, HudTheme.TEXT_MUTED)
	skip_btn.add_child(skip_lbl)
	skip_btn.gui_input.connect(
		func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				advance()
	)
	tools_row.add_child(skip_btn)

	# 본문 및 진행 인디케이터 컨테이너
	var body_box := HBoxContainer.new()
	body_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_col.add_child(body_box)

	_body_label = Label.new()
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_box.add_child(_body_label)

	_next_indicator = Label.new()
	_next_indicator.text = tr("UI_DLG_NEXT")
	_next_indicator.add_theme_color_override("font_color", HudTheme.ACCENT)
	_next_indicator.add_theme_font_size_override("font_size", 14)
	_next_indicator.size_flags_vertical = Control.SIZE_SHRINK_END
	_next_indicator.visible = false
	body_box.add_child(_next_indicator)

	_apply_text_scale()
	_refresh_auto_btn()

	_log_panel = DialogueLogPanel.new()
	add_child(_log_panel)


func _refresh_auto_btn() -> void:
	if _auto_btn_label != null:
		_auto_btn_label.add_theme_color_override(
			"font_color", HudTheme.ACCENT if auto_advance else HudTheme.TEXT_MUTED
		)


## Q9 접근성 — 본문 글자 크기 설정을 이름/본문/패널 높이에 반영.
func _apply_text_scale() -> void:
	var s := SettingsManager.get_text_scale()
	_panel.offset_top = -126 * s
	_body_label.custom_minimum_size = Vector2(0, 64 * s)
	_body_label.add_theme_font_size_override("font_size", int(16 * s))
	_name_label.add_theme_font_size_override("font_size", int(14 * s))
	if _portrait != null:
		var side := 98.0 * s
		_portrait.custom_minimum_size = Vector2(side, side)
	if _portrait_frame != null:
		var side_f := 104.0 * s
		_portrait_frame.custom_minimum_size = Vector2(side_f, side_f)


func start(p_seq_id: StringName, p_steps: Array) -> void:
	seq_id = p_seq_id
	steps = p_steps
	index = 0
	is_open = true
	visible = true
	# 오토플레이는 **설정이 정한다**(04_uiux §1.2). 기본은 꺼짐 — 2026-08-29에 정한
	# "대사는 사람이 넘긴다"가 기본 동작이고, 이 설정은 그것을 되돌릴 수 있게만 한다.
	auto_advance = SettingsManager.dialogue_auto
	_cooldown = INPUT_COOLDOWN
	_auto_wait = -1.0
	_sync_modal_group()
	_load_step()


## 대화 로그 열기/닫기 — 진행 입력을 중재하는 쪽(Field·CutscenePlayer)이 부른다.
func toggle_log() -> void:
	if _log_panel == null:
		return
	if _log_panel.is_open():
		_log_panel.close()
	else:
		_log_panel.open()


func is_log_open() -> bool:
	return _log_panel != null and _log_panel.is_open()


func current_text() -> String:
	return _body_label.text


func advance() -> void:
	# 로그를 읽는 동안에는 대사가 넘어가지 않는다 — 되돌려 읽으려고 연 창인데
	# 그 사이에 진행되면 열어 둔 의미가 없다.
	if not is_open or _cooldown > 0.0 or is_log_open():
		return
	var total: int = _body_label.text.length()
	if _revealed < total:
		_revealed = float(total)  # 스킵: 즉시 완성
		_body_label.visible_characters = total
		_cooldown = INPUT_COOLDOWN * 0.5
		return
	index += 1
	if index >= steps.size():
		close()
	else:
		_load_step()
		_cooldown = INPUT_COOLDOWN * 0.5


func close() -> void:
	is_open = false
	visible = false
	_sync_modal_group()
	finished.emit(seq_id)


## 대화창도 '열려 있는 창'이다 — ESC가 메뉴로 새지 않게 ModalFrame과 같은 그룹에 든다.
## (대화창은 ModalFrame 껍데기를 쓰지 않아 자동으로 걸리지 않는다.)
func _sync_modal_group() -> void:
	if is_open and is_visible_in_tree():
		if not is_in_group(ModalFrame.MODAL_GROUP):
			add_to_group(ModalFrame.MODAL_GROUP)
	elif is_in_group(ModalFrame.MODAL_GROUP):
		remove_from_group(ModalFrame.MODAL_GROUP)


func _load_step() -> void:
	var step: Dictionary = steps[index]
	var op := str(step.get("op", ""))
	if not op.is_empty():
		close()
		op_requested.emit(op, step.get("args", {}))
		return
	var speaker := str(step.get("speaker", ""))
	_name_label.text = speaker
	var spk_color := SpeakerColors.color_for(speaker)
	_name_label.add_theme_color_override("font_color", spk_color)
	if _name_badge != null:
		_name_badge.visible = not speaker.is_empty()
		var bsb := HudTheme.chip(Color(0.12, 0.14, 0.18, 0.95), 4, 10, 3)
		bsb.border_color = Color(spk_color, 0.7)
		bsb.set_border_width_all(1)
		_name_badge.add_theme_stylebox_override("panel", bsb)
	_apply_portrait(step)
	_body_label.text = Database.text(str(step["text"]))
	DialogueLog.push(speaker, _body_label.text)
	# 타이핑 속도 "즉시"는 처음부터 다 보여 준다(설정 §1.2).
	_revealed = float(_body_label.text.length()) if SettingsManager.is_text_instant() else 0.0
	_auto_wait = -1.0
	_body_label.visible_characters = int(_revealed)


## 초상 적용 — step.portrait(에셋 id 직접 지정) 우선, 없으면 speaker 이름으로 조회.
## 표정은 step.expr(스펙 expressions 이름). 못 찾으면 초상 자리를 접는다.
func _apply_portrait(step: Dictionary) -> void:
	if _portrait == null:
		return
	var key := str(step.get("portrait", step.get("speaker", "")))
	var tex := PortraitLibrary.texture_for(key, str(step.get("expr", "")))
	_portrait.texture = tex
	var has_tex := tex != null
	_portrait.visible = has_tex
	if _portrait_frame != null:
		_portrait_frame.visible = has_tex
		if has_tex:
			var spk_color := SpeakerColors.color_for(str(step.get("speaker", "")))
			var psb: StyleBoxFlat = _portrait_frame.get_theme_stylebox("panel") as StyleBoxFlat
			if psb != null:
				psb.border_color = Color(spk_color, 0.8)


func _process(delta: float) -> void:
	if not is_open:
		return
	if _cooldown > 0.0:
		_cooldown -= delta
	var total := _body_label.text.length()
	var typing := _revealed < total
	if typing:
		var cps := CPS * SettingsManager.text_speed_factor()
		_revealed = minf(_revealed + cps * delta, float(total))
	elif auto_advance and _cooldown <= 0.0:
		if _auto_wait < 0.0:
			_auto_wait = AUTO_DELAY
		else:
			_auto_wait -= delta
			if _auto_wait <= 0.0:
				advance()
				return
	_body_label.visible_characters = int(_revealed)

	if _next_indicator != null:
		_next_indicator.visible = not typing and is_open
		if _next_indicator.visible:
			_next_indicator.modulate.a = 0.4 + 0.6 * absf(sin(Time.get_ticks_msec() * 0.006))
