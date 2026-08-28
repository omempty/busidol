class_name DebugPanel
extends CanvasLayer
## 개발자 디버그 패널(F10, 디버그 빌드 한정) — 수동 QA 가속 + 자가 검증.
##  · 층 이동(transitions.json 앵커 파생) / 수치 변경 / 아이템 지급
##  · 전투 강제(monsters.json species+bosses) / 플래그 토글(quests_v2.json)
##  · SelfCheck 자가 검증 실행 → 콘솔 + user://debug_report.txt

const FIELD_SCENE := "res://scenes/field.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
const TRANSITIONS_PATH := "res://data/maps/transitions.json"
const ITEMS_PATH := "res://data/items.json"
const QUESTS_PATH := "res://data/quests_v2.json"
const REPORT_PATH := "user://debug_report.txt"

var _log: Label
var _flag_buttons := {}


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).keycode == KEY_F10 and OS.is_debug_build():
			toggle()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	if visible:
		_refresh_flags()


func _logline(text: String) -> void:
	print("[debug] ", text)
	_log.text = text


## ---- UI ----


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.02, 0.08, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16
	vbox.offset_top = 12
	vbox.offset_right = -16
	vbox.offset_bottom = -40
	add_child(vbox)

	var caption := Label.new()
	caption.text = "DEBUG (F10 닫기) — 변경은 즉시 적용"
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", Color(1.0, 0.6, 0.9))
	vbox.add_child(caption)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var grid := VBoxContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	_section(grid, "— 층 이동 —")
	var floors := HFlowContainer.new()
	grid.add_child(floors)
	for f: int in [1, 2, 3, 0, 4, 5]:
		floors.add_child(_btn("F%d" % f, func() -> void: _teleport_floor(f)))

	_section(grid, "— 수치 —")
	var stats := HFlowContainer.new()
	grid.add_child(stats)
	stats.add_child(_btn("Lv+1", _debug_level_up))
	stats.add_child(_btn("HP/AP 전회", _debug_max_stats))
	stats.add_child(_btn("+1000원", _debug_add_money))

	_section(grid, "— 아이템 지급(×5) —")
	var items := HFlowContainer.new()
	grid.add_child(items)
	for entry: Dictionary in _load_list(ITEMS_PATH, "items"):
		var iid := str(entry["id"])
		items.add_child(_btn(str(entry.get("name_ko", iid)), func() -> void: _grant_item(iid)))

	_section(grid, "— 전투 강제 —")
	var battles := HFlowContainer.new()
	grid.add_child(battles)
	for eid in _all_enemy_ids():
		battles.add_child(_btn(eid, func() -> void: _force_battle(eid)))

	_section(grid, "— 플래그 토글 —")
	var flags := VBoxContainer.new()
	grid.add_child(flags)
	for q: Dictionary in _load_list(QUESTS_PATH, "quests"):
		var fid := str(q["id"])
		var b := _btn("", func() -> void: _toggle_flag(fid))
		_flag_buttons[fid] = b
		flags.add_child(b)
	_refresh_flags()

	_section(grid, "— 자가 검증 —")
	grid.add_child(_btn("SelfCheck 실행", run_self_check))

	_log = Label.new()
	_log.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_log.offset_left = 16
	_log.offset_bottom = -14
	_log.offset_top = -36
	_log.add_theme_color_override("font_color", Color(0.6, 0.95, 0.7))
	add_child(_log)


func _section(parent: Control, title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
	parent.add_child(lbl)


func _btn(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b


func _debug_level_up() -> void:
	GameState.player_stats["level"] = int(GameState.player_stats["level"]) + 1
	_logline("level → %d" % int(GameState.player_stats["level"]))


func _debug_max_stats() -> void:
	GameState.player_stats["hp"] = 999
	GameState.player_stats["ap"] = 999
	_logline("hp/ap → 999")


func _debug_add_money() -> void:
	GameState.player_stats["money"] = int(GameState.player_stats["money"]) + 1000
	_logline("money → %d" % int(GameState.player_stats["money"]))


func _grant_item(item_id: String) -> void:
	GameState.inventory.add(StringName(item_id), 5)
	_logline("지급: %s ×5" % item_id)


func _refresh_flags() -> void:
	for fid: String in _flag_buttons:
		var on := GameState.has_flag(fid)
		var b: Button = _flag_buttons[fid]
		b.text = ("✓ " if on else "· ") + fid


func _toggle_flag(fid: String) -> void:
	if GameState.has_flag(fid):
		GameState.flags.erase(fid)
	else:
		GameState.set_flag(fid, true)
	_refresh_flags()
	_logline("플래그 %s" % fid)


func _teleport_floor(floor_no: int) -> void:
	GameState.current_floor = floor_no
	GameState.player_cell = _entry_anchor(floor_no)
	get_tree().paused = false
	get_tree().change_scene_to_file(FIELD_SCENE)


func _force_battle(enemy_id: String) -> void:
	GameState.pending_encounter = {"enemies": [enemy_id]}
	get_tree().paused = false
	get_tree().change_scene_to_file(BATTLE_SCENE)


func run_self_check() -> void:
	var checker := SelfCheck.new()
	add_child(checker)
	var report := checker.run_all()
	checker.queue_free()
	var stamp := Time.get_datetime_string_from_system(false, true)
	var text := "\n".join(report)
	print("[selfcheck]\n", text)
	var fh := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if fh != null:
		fh.store_string("=== SelfCheck %s ===\n%s\n" % [stamp, text])
	_logline("검증 완료 → user://debug_report.txt (%s)" % report[report.size() - 1])


## ---- 데이터 로더 ----


func _load_list(path: String, key: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		return []
	return raw.get(key, [])


func _all_enemy_ids() -> PackedStringArray:
	var out := PackedStringArray()
	var raw := _monsters_dict()
	for floor_data: Dictionary in raw.get("floors", {}).values():
		for s: Variant in floor_data.get("species", []):
			if s is Dictionary:
				out.append(str(s.get("id", "")))
			else:
				out.append(str(s))
	for bid: String in raw.get("bosses", {}).keys():
		out.append(bid)
	return out


func _monsters_dict() -> Dictionary:
	var path := "res://data/monsters.json"
	if not FileAccess.file_exists(path):
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


## 대상 층으로 착지하는 전환의 도착 좌표(anchor+offset)를 찾는다.
## 소스 층은 guard_min/max_floor 범위에서 역산한다(데이터에 명시 필드 없음).
func _entry_anchor(target_floor: int) -> Vector2i:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(TRANSITIONS_PATH))
	if typeof(raw) == TYPE_DICTIONARY:
		for t: Dictionary in raw.get("transitions", []):
			var delta := int(t.get("floor_delta", 0))
			var gmin := int(t.get("guard_min_floor", -99))
			var gmax := int(t.get("guard_max_floor", 99))
			for src in range(gmin, gmax + 1):
				if src + delta == target_floor:
					var anchor: Array = t.get("anchor", [9, 9])
					var off: Array = t.get("spawn_offset", [0, 0])
					return Vector2i(int(anchor[0]) + int(off[0]), int(anchor[1]) + int(off[1]))
	push_warning("[debug] f%d 진입 앵커 미발견 — 기본 스폰 사용" % target_floor)
	return Vector2i(-1, -1)
