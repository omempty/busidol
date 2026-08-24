class_name DialogueBox
extends CanvasLayer
## 대화창 — 타이핑 효과 + 입력 진행(스킵). 원작 Talk_Window의 현대판 (04_uiux §1.2).

signal finished(seq_id: StringName)

const CPS := 40.0          # 초당 글자 수
const INPUT_COOLDOWN := 0.05

var seq_id := &""
var steps: Array = []
var index := 0
var is_open := false
var _revealed := 0.0
var _cooldown := 0.0


func is_typing() -> bool:
	return _body_label.text.length() > int(_revealed)

var _panel: PanelContainer
var _name_label: Label
var _body_label: Label


func _ready() -> void:
	layer = 30
	visible = false

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 12
	_panel.offset_right = -12
	_panel.offset_top = -118
	_panel.offset_bottom = -12
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)
	_name_label = Label.new()
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(_name_label)
	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(0, 72)
	vbox.add_child(_body_label)


func start(p_seq_id: StringName, p_steps: Array) -> void:
	seq_id = p_seq_id
	steps = p_steps
	index = 0
	is_open = true
	visible = true
	_cooldown = INPUT_COOLDOWN
	_load_step()


func current_text() -> String:
	return _body_label.text


func advance() -> void:
	if not is_open or _cooldown > 0.0:
		return
	var total: int = _body_label.text.length()
	if _revealed < total:
		_revealed = float(total)          # 스킵: 즉시 완성
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
	_name_label.text = str(step.get("speaker", ""))
	_body_label.text = Database.text(str(step["text"]))
	_revealed = 0.0
	_body_label.visible_characters = 0


func _process(delta: float) -> void:
	if not is_open:
		return
	if _cooldown > 0.0:
		_cooldown -= delta
	var total := _body_label.text.length()
	if _revealed < total:
		_revealed = minf(_revealed + CPS * delta, float(total))
	_body_label.visible_characters = int(_revealed)
	# 진행 입력은 Field가 중재해 advance()를 호출한다(입력 엣지 유실 방지).
