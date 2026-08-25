class_name CutscenePlayer
extends CanvasLayer
## 컷신 재생기 — 순차 명령열 비동기 해석. 에디터 프리뷰와 동일 클래스 사용.
## docs/02_design/05_toolchain_editors.md §4 참조.
## op 계약:
##   dialogue  {steps:[{speaker,text(@t/@c)}]}   wait {seconds}
##   fade_in(밝아짐) / fade_out(어두워짐) {seconds}   shake {power, times}
##   sfx/bgm {id}   set_flags {args:{k:v}}   start_battle {enemies:[]}
##   grant_item {args:{item, count}}   craft {args:{requires:{}, grant:{}, flag}}
##   minigame_quiz {id} — 통과할 때까지 재도전 후 다음 스텝 진행
##   choice {args:{options:[{text(@t/@c), steps:[op...]}]}} — 선택 강제, 수렴형.
##     각 옵션의 steps를 서브 열로 실행 후 다음 스텝 진행(WP-5, D4 승인).

signal finished(cutscene_id: StringName)

const CUTSCENES_DIR := "res://data/cutscenes"
const SHAKE_STEP := 0.05

var _steps: Array = []
var _idx := 0
var _running := false
var _cutscene_id := &""
var _box: DialogueBox
var _overlay: ColorRect
var _field: Node2D


## field: 카메라 흔들림·전투 전환 대상 씬 루트
func setup(p_field: Node2D) -> void:
	layer = 40
	visible = false
	_field = p_field

	_box = DialogueBox.new()
	_box.auto_advance = true
	add_child(_box)

	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)


func play(config: Dictionary) -> void:
	if _running:
		push_warning("컷신 중복 재생 무시: %s" % _cutscene_id)
		return
	_cutscene_id = StringName(str(config.get("id", "")))
	_steps = config.get("steps", [])
	_idx = 0
	_running = true
	visible = true
	_run()


func stop() -> void:
	_running = false
	visible = false


func is_running() -> bool:
	return _running


func _run() -> void:
	await _run_steps(_steps)
	if not _running:
		return
	_running = false
	visible = false
	finished.emit(_cutscene_id)


## 스텝 열 실행 — choice op의 서브 열 재귀를 위해 본열과 분리.
func _run_steps(steps: Array) -> void:
	var saved_steps := _steps
	var saved_idx := _idx
	_steps = steps
	_idx = 0
	while _running and _idx < _steps.size():
		var step: Dictionary = _steps[_idx]
		_idx += 1
		await _execute(step)
	_steps = saved_steps
	_idx = saved_idx


func _execute(step: Dictionary) -> void:
	match str(step.get("op", "")):
		"dialogue":
			var steps: Array = step.get("steps", [])
			if not steps.is_empty():
				_box.start(&"", steps)
				await _box.finished
		"choice":
			await _run_choice(step.get("args", {}))
		"wait":
			await get_tree().create_timer(maxf(float(step.get("seconds", 1.0)), 0.01)).timeout
		"fade_in":
			await _fade(float(step.get("seconds", 0.6)), 0.0)
		"fade_out":
			await _fade(float(step.get("seconds", 0.6)), 1.0)
		"shake":
			await _shake(int(step.get("times", 4)), float(step.get("power", 3.0)))
		"sfx":
			AudioManager.play_sfx(StringName(str(step.get("id", ""))))
		"bgm":
			AudioManager.play_bgm(StringName(str(step.get("id", ""))))
		"set_flags":
			var args: Dictionary = step.get("args", {})
			for k: String in args:
				GameState.set_flag(k, args[k])
		"grant_item":
			var g: Dictionary = step.get("args", {})
			GameState.inventory.add(StringName(str(g.get("item", ""))), int(g.get("count", 1)))
		"craft":
			_execute_craft(step.get("args", {}))
		"minigame_quiz":
			await _run_quiz(StringName(str(step.get("id", ""))))
		"minigame_battery":
			await _run_battery(StringName(str(step.get("id", ""))))
		"change_scene":
			_running = false
			get_tree().change_scene_to_file(str(step.get("path", "")))
		"actor_move":
			await _actor_move(step)
		"start_battle":
			GameState.pending_encounter = {
				"enemies": step.get("enemies", []), "on_win_flag": str(step.get("on_win_flag", ""))
			}
			_running = false
			get_tree().change_scene_to_file("res://scenes/battle.tscn")
		_:
			push_warning("알 수 없는 컷신 op: %s" % str(step.get("op", "")))


func _fade(seconds: float, target_a: float) -> void:
	_overlay.color.a = 1.0 - target_a
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", target_a, maxf(seconds, 0.01))
	await tw.finished


## choice op — 옵션 선택 강제(취소 없음), 선택한 옵션의 steps를 서브 열로 실행.
func _run_choice(args: Dictionary) -> void:
	var options: Array = args.get("options", [])
	if options.is_empty():
		push_warning("choice 옵션 없음: %s" % _cutscene_id)
		return
	var ui := ChoiceUI.new()
	add_child(ui)
	ui.setup(options)
	var pick: int = await ui.picked
	ui.queue_free()
	var chosen: Dictionary = options[pick]
	var sub: Array = chosen.get("steps", [])
	if not sub.is_empty():
		await _run_steps(sub)


## 선택지 오버레이 — ↑↓ 이동, Enter/Z 확정. 컷신 진행은 picked 이후 재개.
class ChoiceUI:
	extends Control
	signal picked(idx: int)

	var _labels: Array[Label] = []
	var _idx := 0

	func setup(options: Array) -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.45)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_CENTER)
		box.add_theme_constant_override("separation", 10)
		add_child(box)
		for opt: Dictionary in options:
			var lbl := Label.new()
			var raw_text := str(opt.get("text", ""))
			var shown := Database.text(raw_text) if raw_text.begins_with("@") else raw_text
			lbl.text = "▶ " + shown
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 18)
			box.add_child(lbl)
			_labels.append(lbl)
		_refresh()

	func _refresh() -> void:
		for i in range(_labels.size()):
			_labels[i].add_theme_color_override(
				"font_color", Color(1.0, 0.95, 0.6) if i == _idx else Color(0.8, 0.8, 0.9)
			)

	func _move(dir: int) -> void:
		_idx = wrapi(_idx + dir, 0, _labels.size())
		_refresh()

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed(&"move_up"):
			_move(-1)
		elif event.is_action_pressed(&"move_down"):
			_move(1)
		elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact"):
			picked.emit(_idx)
			get_viewport().set_input_as_handled()


func _shake(times: int, power: float) -> void:
	if _field == null:
		return
	var base := _field.position
	for i in maxi(times, 1):
		_field.position = base + Vector2(randf_range(-power, power), randf_range(-power, power))
		await get_tree().create_timer(SHAKE_STEP).timeout
	_field.position = base


## 액터 이동 MVP — npc_id 또는 $player를 대상 셀로 트윈. cell은 그리드 좌표.
func _actor_move(step: Dictionary) -> void:
	var who := str(step.get("actor", ""))
	var at_arr: Array = step.get("cell", [0, 0])
	var dur := maxf(float(step.get("seconds", 0.5)), 0.05)
	var target: Node2D = null
	if who == "$player" and _field != null and _field.has_method("get_player"):
		target = _field.get_player()
	elif _field != null and _field.has_method("get_npc"):
		var npc: Node2D = _field.get_npc(who)
		target = npc
	if target == null:
		push_warning("actor_move 대상 없음: %s" % who)
		return
	var px := Vector2(float(at_arr[0]) + 0.5, float(at_arr[1]) + 1.0) * MapDefinition.TILE_PX
	var tw := create_tween()
	tw.tween_property(target, "position", px, dur).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_IN_OUT
	)
	await tw.finished


static func load_cutscene(cutscene_id: StringName) -> Dictionary:
	var path := "%s/%s.json" % [CUTSCENES_DIR, cutscene_id]
	if not FileAccess.file_exists(path):
		push_warning("cutscene 없음: %s" % path)
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


const MINIGAMES_DIR := "res://data/minigames"


## 퀴즈 미니게임 — 통과(passed=true)할 때까지 재도전. 실패해도 컷신은 계속.
func _run_quiz(minigame_id: StringName) -> void:
	var cfg := _load_minigame(minigame_id)
	if cfg.is_empty():
		return
	var quiz := QuizMinigame.new()
	add_child(quiz)
	while true:
		quiz.start(cfg)
		var passed: bool = await quiz.finished
		if passed:
			break
	quiz.queue_free()


## 배터리 회로 퍼즐 — 목표 전압 일치 시 통과.
func _run_battery(minigame_id: StringName) -> void:
	var cfg := _load_minigame(minigame_id)
	if cfg.is_empty():
		return
	var game := BatteryCircuitMinigame.new()
	add_child(game)
	game.start(cfg)
	await game.finished
	game.queue_free()


func _load_minigame(minigame_id: StringName) -> Dictionary:
	var path := "%s/%s.json" % [MINIGAMES_DIR, minigame_id]
	if not FileAccess.file_exists(path):
		push_warning("미니게임 데이터 없음: %s" % path)
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


## craft op — requires 소비 후 grant 지급 + 플래그. 부족 시 경고하고 컷신 중단.
func _execute_craft(args: Dictionary) -> void:
	var inv := GameState.inventory
	var requires: Dictionary = args.get("requires", {})
	for item_id: String in requires:
		if inv.count(StringName(item_id)) < int(requires[item_id]):
			push_warning("craft 재료 부족: %s — 컷신 중단(%s)" % [item_id, _cutscene_id])
			_running = false
			return
	for item_id2: String in requires:
		inv.remove(StringName(item_id2), int(requires[item_id2]))
	var grant: Dictionary = args.get("grant", {})
	for item_id3: String in grant:
		inv.add(StringName(item_id3), int(grant[item_id3]))
	if args.has("flag"):
		GameState.set_flag(str(args["flag"]), true)
