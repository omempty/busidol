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
var _name_label: Label
var _body_label: Label
## 화자 초상 — PortraitLibrary가 speaker(또는 step.portrait)로 찾는다.
## 미설치 화자는 숨긴다(초상 16종이 다 차기 전에도 대화가 정상 동작해야 한다).
var _portrait: TextureRect


func _ready() -> void:
	layer = 30
	visible = false

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 12
	_panel.offset_right = -12
	_panel.offset_bottom = -12
	add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_panel.add_child(row)

	_portrait = TextureRect.new()
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 도트 보존
	_portrait.visible = false
	row.add_child(_portrait)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(vbox)
	_name_label = Label.new()
	# 초기색일 뿐 — 실제 색은 _load_step()이 화자마다 SpeakerColors로 덮어쓴다.
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(_name_label)
	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_body_label)

	_apply_text_scale()

	# 대화 로그 — 필드 대화창과 컷신 대사창이 각자 하나씩 갖지만 **내용은 한 저장소**다
	# (DialogueLog가 static). 동시에 열리는 일이 없으므로 창이 둘이어도 무해하다.
	_log_panel = DialogueLogPanel.new()
	add_child(_log_panel)


## Q9 접근성 — 본문 글자 크기 설정을 이름/본문/패널 높이에 반영.
func _apply_text_scale() -> void:
	var s := SettingsManager.get_text_scale()
	_panel.offset_top = -118 * s
	_body_label.custom_minimum_size = Vector2(0, 72 * s)
	_body_label.add_theme_font_size_override("font_size", int(17 * s))
	_name_label.add_theme_font_size_override("font_size", int(15 * s))
	if _portrait != null:
		# 패널 높이(118*s)에서 여백을 뺀 정사각 — 초상 셀이 256이라 축소만 일어난다.
		var side := 96.0 * s
		_portrait.custom_minimum_size = Vector2(side, side)


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
	finished.emit(seq_id)


func _load_step() -> void:
	var step: Dictionary = steps[index]
	var op := str(step.get("op", ""))
	if not op.is_empty():
		close()
		op_requested.emit(op, step.get("args", {}))
		return
	var speaker := str(step.get("speaker", ""))
	_name_label.text = speaker
	# 화자마다 다른 색 — 누가 말하는지 이름을 읽지 않고도 안다(04_uiux §1.2).
	_name_label.add_theme_color_override("font_color", SpeakerColors.color_for(speaker))
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
	_portrait.visible = tex != null


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
	# 진행 입력은 Field가 중재해 advance()를 호출한다(입력 엣지 유실 방지).
