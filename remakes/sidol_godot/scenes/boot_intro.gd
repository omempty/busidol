extends Node
## 도스 부팅 인트로 — 원작 수행 감성 연출. 아무 키로 스킵, 종료 시 타이틀 전환.
## roadmap Phase 9 "부팅 연출(SYS_BUILDER 부팅화면 가짜 스크립트)".

const TITLE_SCENE := "res://scenes/main.tscn"
const LINES: Array[String] = [
	"Busidol Micro BIOS v1.95",
	"Memory Test : 640K OK",
	"",
	"C:\\> cd BUSIDOL\\SIDOL",
	"C:\\BUSIDOL\\SIDOL> RUN.BAT",
	"",
	"loading . . .",
]
const CHAR_TIME := 0.03  # 글자 1개 타이핑 간격(초)
const LINE_TIME := 0.22  # 줄바꿈 후 대기
const HOLD_AFTER := 1.1  # 전문 출력 후 자동 전환 대기

var _label: Label
var _full := ""
var _budget := 0.0  # 누적 타이핑 예산(초→글자 환산)
var _line_wait := 0.0
var _hold := 0.0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_label = Label.new()
	_label.position = Vector2(28, 24)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.55, 0.9, 0.6))
	add_child(_label)

	for i in range(LINES.size()):
		_full += LINES[i]
		if i < LINES.size() - 1:
			_full += "\n"


func _process(delta: float) -> void:
	var total := _full.length()
	var shown := _label.text.length()
	if shown < total:
		if _line_wait > 0.0:
			_line_wait -= delta
			return
		_budget += delta / CHAR_TIME
		var take := mini(int(_budget), total - shown)
		_budget -= float(take)
		var next_text := _full.substr(0, shown + take)
		if next_text.ends_with("\n"):
			_line_wait = LINE_TIME
		_label.text = next_text + "_"
	elif shown >= total:
		_label.text = _full + "_"
		_hold += delta
		if _hold >= HOLD_AFTER:
			_go_title()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed(&"interact")
		or event.is_action_pressed(&"cancel")
		or event.is_action_pressed(&"ui_accept")
	):
		_go_title()


func _go_title() -> void:
	set_process(false)
	get_tree().change_scene_to_file(TITLE_SCENE)
