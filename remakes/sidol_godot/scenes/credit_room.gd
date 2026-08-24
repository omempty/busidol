extends Control
## 크레딧룸(HP방) — 원작 Run_Event_HP의 현대판.
## 멤버 9명의 이름·역할·대사 표시, 좌우 탐색.

const MEMBERS := [
	{"name": "마은빈", "role": "리더",       "quote": "나를 믿어라"},
	{"name": "윤관식", "role": "매니저",     "quote": "HP방은 부싯돌 아지트에요"},
	{"name": "이태하", "role": "전투 프로그래머","quote": "전투모드는 내게 맡겨"},
	{"name": "이윤우", "role": "서포터",     "quote": "우리모두 최선을......."},
	{"name": "김현진", "role": "이펙트",     "quote": "특수효과는 제가 맡겠습니다."},
	{"name": "김완종", "role": "그래픽",     "quote": "포스트를 빨리 그려야지.."},
	{"name": "김영은", "role": "레벨 디자인", "quote": "빨리 집에 가야지"},
	{"name": "한병준", "role": "테스터",     "quote": "자고 일어나면 다 되어있도다!"},
	{"name": "서정훈", "role": "이벤트",     "quote": "테니스의 천재 ,,DDDD"},
]

var _idx := 0
var _panel: PanelContainer
var _name_lbl: Label
var _role_lbl: Label
var _quote_lbl: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "=== 부싯돌 개발팀 ==="
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	title.position = Vector2(180, 40)
	add_child(title)

	_panel = PanelContainer.new()
	_panel.position = Vector2(140, 100)
	_panel.custom_minimum_size = Vector2(360, 120)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)
	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_name_lbl)
	_role_lbl = Label.new()
	_role_lbl.modulate = Color(0.7, 0.7, 0.9)
	vbox.add_child(_role_lbl)
	_quote_lbl = Label.new()
	_quote_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_quote_lbl)

	var hint := Label.new()
	hint.text = "← → 멤버 탐색 | ESC 나가기"
	hint.position = Vector2(220, 280)
	hint.modulate = Color(1, 1, 1, 0.4)
	add_child(hint)

	_refresh()


func _refresh() -> void:
	var m: Dictionary = MEMBERS[_idx]
	_name_lbl.text = "%d. %s" % [_idx + 1, m["name"]]
	_role_lbl.text = m["role"]
	_quote_lbl.text = "\"%s\"" % m["quote"]


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"move_right"):
		_idx = (_idx + 1) % MEMBERS.size()
		_refresh()
	elif event.is_action_pressed(&"move_left"):
		_idx = (_idx - 1 + MEMBERS.size()) % MEMBERS.size()
		_refresh()
	elif event.is_action_pressed(&"cancel"):
		get_tree().change_scene_to_file("res://scenes/field.tscn")
