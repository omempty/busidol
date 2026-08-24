class_name QuizMinigame
extends CanvasLayer
## 퀴즈 미니게임 프레임워크 — 문항/선택지/정답은 전부 JSON(data/minigames/*.json).
## 입력: ↑↓ 선택, SPACE(interact) 확정. 오답 시 fail_text 표시 후 재선택(무한 재도전).
## 종료는 finished(passed) 시그널로만 통지 — 호출자(CutscenePlayer)가 흐름을 결정.

signal finished(passed: bool)

const PANEL_POS := Vector2(70, 60)
const PANEL_SIZE := Vector2(500, 180)

var _config: Dictionary = {}
var _qi := 0            # 현재 문항 인덱스
var _sel := 0           # 현재 선택지 인덱스
var _mistakes := 0
var _active := false

var _title_lbl: Label
var _q_lbl: Label
var _choice_lbls: Array[Label] = []
var _msg_lbl: Label


func _ready() -> void:
	layer = 45
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.05, 0.08, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.position = PANEL_POS
	panel.custom_minimum_size = PANEL_SIZE
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	_title_lbl = Label.new()
	_title_lbl.text = "공대생 생존 퀴즈"
	_title_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
	vbox.add_child(_title_lbl)
	_q_lbl = Label.new()
	_q_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_q_lbl.custom_minimum_size = Vector2(PANEL_SIZE.x - 40, 50)
	vbox.add_child(_q_lbl)
	for i in 3:
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 14)
		vbox.add_child(lbl)
		_choice_lbls.append(lbl)
	_msg_lbl = Label.new()
	_msg_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_msg_lbl)


## config: {"questions": [{q, choices[], answer}], "fail_text_key": "@c.."}
func start(config: Dictionary) -> void:
	_config = config
	_qi = 0
	_sel = 0
	_mistakes = 0
	_active = true
	visible = true
	_load_question()


func is_active() -> bool:
	return _active


func _load_question() -> void:
	var qs: Array = _config.get("questions", [])
	if _qi >= qs.size():
		_finish(true)
		return
	var q: Dictionary = qs[_qi]
	_q_lbl.text = "Q%d. %s" % [_qi + 1, _fmt(str(q["q"]))]
	_sel = 0
	var choices: Array = q.get("choices", [])
	for i in _choice_lbls.size():
		if i < choices.size():
			_choice_lbls[i].visible = true
			_choice_lbls[i].text = "%d) %s" % [i + 1, _fmt(str(choices[i]))]
		else:
			_choice_lbls[i].visible = false
	_refresh_highlight()


## "@t3" 같은 대사 키면 dialogue.json에서 조회, 아니면 원문 그대로 사용.
func _fmt(key_or_text: String) -> String:
	return Database.text(key_or_text) if key_or_text.begins_with("@") \
			else key_or_text


func _refresh_highlight() -> void:
	for i in _choice_lbls.size():
		_choice_lbls[i].text = "> " + _choice_lbls[i].text.trim_prefix("> ") \
				if i == _sel else "  " + _choice_lbls[i].text.trim_prefix("> ")
		_choice_lbls[i].modulate = Color(1.0, 0.9, 0.3) if i == _sel \
				else Color(1, 1, 1, 0.75)
	_msg_lbl.text = ""


func _input(event: InputEvent) -> void:
	if not _active:
		return
	var qs: Array = _config.get("questions", [])
	if _qi >= qs.size():
		return
	var choices: Array = qs[_qi].get("choices", [])
	if event.is_action_pressed(&"move_up"):
		_sel = (_sel - 1 + choices.size()) % choices.size()
		_refresh_highlight()
	elif event.is_action_pressed(&"move_down"):
		_sel = (_sel + 1) % choices.size()
		_refresh_highlight()
	elif event.is_action_pressed(&"interact"):
		_confirm()


func _confirm() -> void:
	var q: Dictionary = (_config.get("questions", []) as Array)[_qi]
	if _sel == int(q.get("answer", 0)):
		_qi += 1
		_msg_lbl.text = ""
		_load_question()
	else:
		_mistakes += 1
		_msg_lbl.text = _fmt(str(_config.get("fail_text_key", "")))


func _finish(passed: bool) -> void:
	_active = false
	visible = false
	finished.emit(passed)
