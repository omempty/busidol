extends Control
## 크레딧룸(HP방) — 원작 Run_Event_HP의 현대판.
## 모드: 멤버 탐색 / 엔딩 후일담 카드 3종 / 리메이크 스탭롤.
## 콘텐츠는 data/credits.json, 대사 키는 dialogue.json(@c) 참조.

const CREDITS_PATH := "res://data/credits.json"
const ROLL_SPEED := 24.0

var _members: Array = []
var _cards: Array = []
var _roll_lines: Array = []

var _mode := 0
var _mode_names: Array[String] = ["부싯돌 개발팀", "엔딩 후일담", "스탭롤"]
var _idx := 0

var _mode_lbl: Label
var _panel: PanelContainer
var _title_lbl: Label
var _sub_lbl: Label
var _quote_lbl: Label
var _roll_clip: Control
var _roll_lbl: Label


func _ready() -> void:
	_load_data()

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_mode_lbl = Label.new()
	_mode_lbl.add_theme_font_size_override("font_size", 20)
	_mode_lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	_mode_lbl.position = Vector2(180, 36)
	add_child(_mode_lbl)

	_panel = PanelContainer.new()
	_panel.position = Vector2(90, 90)
	_panel.custom_minimum_size = Vector2(460, 140)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)
	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_title_lbl)
	_sub_lbl = Label.new()
	_sub_lbl.modulate = Color(0.7, 0.7, 0.9)
	_sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_sub_lbl)
	_quote_lbl = Label.new()
	_quote_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_quote_lbl)

	# 스탭롤 — 클리핑 영역 안을 위에서 아래로 흐르는 라벨
	_roll_clip = Control.new()
	_roll_clip.position = Vector2(60, 90)
	_roll_clip.size = Vector2(520, 170)
	_roll_clip.clip_contents = true
	add_child(_roll_clip)
	_roll_lbl = Label.new()
	_roll_lbl.position = Vector2(0, 170)
	_roll_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_roll_lbl.custom_minimum_size = Vector2(520, 0)
	_roll_clip.add_child(_roll_lbl)

	var hint := Label.new()
	hint.text = "↑↓ 모드 | ← → 항목 | ESC 나가기"
	hint.position = Vector2(220, 288)
	hint.modulate = Color(1, 1, 1, 0.4)
	add_child(hint)

	_apply_mode()


func _load_data() -> void:
	if not FileAccess.file_exists(CREDITS_PATH):
		push_error("credits.json 없음")
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CREDITS_PATH))
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("credits.json 파싱 실패")
		return
	_members = raw.get("members", [])
	_cards = raw.get("ending_cards", [])
	_roll_lines = raw.get("staff_roll", [])


func _apply_mode() -> void:
	_idx = 0
	_mode_lbl.text = "[%d/3] %s" % [_mode + 1, _mode_names[_mode]]
	_panel.visible = _mode != 2
	_roll_clip.visible = _mode == 2
	if _mode == 2:
		_roll_lbl.text = "\n".join(PackedStringArray(
				Array(_roll_lines, TYPE_STRING, "", "")))
	match _mode:
		0: _refresh_member()
		1: _refresh_card()
		_: pass


func _refresh_member() -> void:
	var m: Dictionary = _members[_idx]
	_title_lbl.text = "%d. %s" % [_idx + 1, str(m["name"])]
	_sub_lbl.text = str(m["role"])
	_quote_lbl.text = "\"%s\"" % str(m["quote"])


func _refresh_card() -> void:
	var c: Dictionary = _cards[_idx]
	_title_lbl.text = str(c["title"])
	_sub_lbl.text = str(c.get("sub", ""))
	_quote_lbl.text = "\"%s\"" % Database.text(str(c["text_key"]))


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"move_up"):
		_mode = (_mode - 1 + 3) % 3
		_apply_mode()
	elif event.is_action_pressed(&"move_down"):
		_mode = (_mode + 1) % 3
		_apply_mode()
	elif event.is_action_pressed(&"move_right"):
		_step(1)
	elif event.is_action_pressed(&"move_left"):
		_step(-1)
	elif event.is_action_pressed(&"cancel"):
		get_tree().change_scene_to_file("res://scenes/field.tscn")


func _step(dir: int) -> void:
	var count := _members.size() if _mode == 0 else _cards.size()
	if count == 0:
		return
	_idx = (_idx + dir + count) % count
	if _mode == 0:
		_refresh_member()
	elif _mode == 1:
		_refresh_card()


func _process(delta: float) -> void:
	if _mode != 2:
		return
	_roll_lbl.position.y -= ROLL_SPEED * delta
	var bottom := _roll_lbl.position.y + _roll_lbl.size.y
	if bottom < 0.0:
		_roll_lbl.position.y = _roll_clip.size.y
