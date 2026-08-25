extends Control
## 크레딧룸(HP방) — 원작 Run_Event_HP의 현대판.
## 모드: 멤버 탐색 / 엔딩 후일담 카드 3종 / 리메이크 스탭롤.
## 콘텐츠는 data/credits.json, 대사 키는 dialogue.json(@c) 참조.

const CREDITS_PATH := "res://data/credits.json"
const ROLL_SPEED := 24.0

var _members: Array = []
var _cards: Array = []
var _roll_lines: Array = []
var _all_seen_flag := ""  # 전원 확인 시 세팅되는 플래그(credits.json)
var _quiz_cfg := {}  # {"minigame","perfect_flag","intro"} — 부재 시 퀴즈 모드 없음
var _quiz_active := false

var _mode := 0
var _mode_count := 3
var _mode_names: Array[String] = ["부싯돌 개발팀", "엔딩 후일담", "스탭롤", "공식 퀴즈"]
var _idx := 0

var _mode_lbl: Label
var _panel: PanelContainer
var _title_lbl: Label
var _sub_lbl: Label
var _quote_lbl: Label
var _roll_clip: Control
var _roll_lbl: Label
var _quiz: QuizMinigame


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
	var all_cards: Array = raw.get("ending_cards", [])
	_cards = []
	for c: Dictionary in all_cards:
		var req = str(c.get("requires_flag", ""))
		if req.is_empty() or GameState.has_flag(req):
			_cards.append(c)
	_roll_lines = raw.get("staff_roll", [])
	_all_seen_flag = str(raw.get("all_seen_flag", ""))
	_quiz_cfg = raw.get("meta_quiz", {}) if raw.get("meta_quiz", {}) is Dictionary else {}
	# 메타 퀴즈 — 미클리어일 때만 모드 노출(클리어 후에는 후일담 카드로 대체)
	_mode_count = 3
	if not _quiz_cfg.is_empty() and not GameState.has_flag(str(_quiz_cfg.get("perfect_flag", ""))):
		_mode_count = 4


func _apply_mode() -> void:
	_idx = 0
	_mode_lbl.text = "[%d/%d] %s" % [_mode + 1, _mode_count, _mode_names[_mode]]
	_panel.visible = _mode != 2
	_roll_clip.visible = _mode == 2
	if _mode == 2:
		_roll_lbl.text = "\n".join(PackedStringArray(Array(_roll_lines, TYPE_STRING, "", "")))
	match _mode:
		0:
			_refresh_member()
		1:
			_refresh_card()
		3:
			_refresh_quiz()
		_:
			pass


func _refresh_member() -> void:
	var m: Dictionary = _members[_idx]
	_title_lbl.text = "%d. %s" % [_idx + 1, str(m["name"])]
	_sub_lbl.text = str(m["role"])
	_quote_lbl.text = '"%s"' % str(m["quote"])
	_mark_member_seen(m)


## 멤버 확인 기록 — 전원 확인 시 all_seen_flag(Q_HP_ALL) 자동 세팅.
func _mark_member_seen(m: Dictionary) -> void:
	var id := str(m.get("id", ""))
	if id.is_empty() or _all_seen_flag.is_empty():
		return
	if GameState.has_flag(_all_seen_flag):
		return  # 이미 완료 — 재귀 방지
	GameState.set_flag("hp_seen_" + id)
	for other: Dictionary in _members:
		if not GameState.has_flag("hp_seen_" + str(other.get("id", ""))):
			return
	GameState.set_flag(_all_seen_flag)
	_load_data()  # 방금 플래그로 열리는 후일담 카드 즉시 반영
	if _mode >= _mode_count:
		_mode = 0
	_apply_mode()


func _refresh_card() -> void:
	var c: Dictionary = _cards[_idx]
	_title_lbl.text = str(c["title"])
	_sub_lbl.text = str(c.get("sub", ""))
	_quote_lbl.text = '"%s"' % Database.text(str(c["text_key"]))


func _refresh_quiz() -> void:
	_title_lbl.text = "공식 퀴즈 도전"
	_sub_lbl.text = str(_quiz_cfg.get("intro", "10문항 전부 정답에 도전한다."))
	_quote_lbl.text = "SPACE: 도전"


func _start_quiz() -> void:
	if _quiz_active or _quiz_cfg.is_empty():
		return
	_quiz_active = true
	_quiz = QuizMinigame.new()
	add_child(_quiz)
	_quiz.finished.connect(_on_quiz_finished)
	_quiz.start(_load_minigame(str(_quiz_cfg.get("minigame", ""))))


func _load_minigame(id: String) -> Dictionary:
	var path := "res://data/minigames/%s.json" % id
	if not FileAccess.file_exists(path):
		push_warning("미니게임 데이터 없음: %s" % path)
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


## 완벽 정답(오답 0)일 때만 perfect_flag(Q_QUIZ_ALL) 세팅 — 재도전 가능.
func _on_quiz_finished(passed: bool) -> void:
	_quiz_active = false
	var flag := str(_quiz_cfg.get("perfect_flag", ""))
	if passed and not flag.is_empty() and _quiz.mistake_count() == 0:
		GameState.set_flag(flag)
	_refresh_hint_cleared()


func _refresh_hint_cleared() -> void:
	if GameState.has_flag(str(_quiz_cfg.get("perfect_flag", ""))):
		_quote_lbl.text = '"%s"' % "완벽했다. 자랑스럽게도 말이지."


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"move_up"):
		_mode = (_mode - 1 + _mode_count) % _mode_count
		_apply_mode()
	elif event.is_action_pressed(&"move_down"):
		_mode = (_mode + 1) % _mode_count
		_apply_mode()
	elif event.is_action_pressed(&"move_right"):
		_step(1)
	elif event.is_action_pressed(&"move_left"):
		_step(-1)
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		if _mode == 3:
			_start_quiz()
	elif event.is_action_pressed(&"cancel"):
		# 엔딩 도달 상태면 CRT 콘솔(E-2)로 마무리, 아니면 필드 복귀.
		if GameState.has_flag("Q_ENDING"):
			get_tree().change_scene_to_file("res://scenes/ending_console.tscn")
		else:
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
