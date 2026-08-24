class_name CutscenePlayer
extends CanvasLayer
## 컷신 재생기 — 순차 명령열 비동기 해석. 에디터 프리뷰와 동일 클래스 사용.
## docs/02_design/05_toolchain_editors.md §4 참조.
## op 계약:
##   dialogue  {steps:[{speaker,text(@t/@c)}]}   wait {seconds}
##   fade_in(밝아짐) / fade_out(어두워짐) {seconds}   shake {power, times}
##   sfx/bgm {id}   set_flags {args:{k:v}}   start_battle {enemies:[]}

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
	while _running and _idx < _steps.size():
		var step: Dictionary = _steps[_idx]
		_idx += 1
		await _execute(step)
	if not _running:
		return
	_running = false
	visible = false
	finished.emit(_cutscene_id)


func _execute(step: Dictionary) -> void:
	match str(step.get("op", "")):
		"dialogue":
			var steps: Array = step.get("steps", [])
			if not steps.is_empty():
				_box.start(&"", steps)
				await _box.finished
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
		"actor_move":
			await _actor_move(step)
		"start_battle":
			GameState.pending_encounter = {"enemies": step.get("enemies", [])}
			_running = false
			get_tree().change_scene_to_file("res://scenes/battle.tscn")
		_:
			push_warning("알 수 없는 컷신 op: %s" % str(step.get("op", "")))


func _fade(seconds: float, target_a: float) -> void:
	_overlay.color.a = 1.0 - target_a
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", target_a, maxf(seconds, 0.01))
	await tw.finished


func _shake(times: int, power: float) -> void:
	if _field == null:
		return
	var base := _field.position
	for i in maxi(times, 1):
		_field.position = base + Vector2(randf_range(-power, power),
				randf_range(-power, power))
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
	var px := Vector2(float(at_arr[0]) + 0.5, float(at_arr[1]) + 1.0) \
			* MapDefinition.TILE_PX
	var tw := create_tween()
	tw.tween_property(target, "position", px, dur)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


static func load_cutscene(cutscene_id: StringName) -> Dictionary:
	var path := "%s/%s.json" % [CUTSCENES_DIR, cutscene_id]
	if not FileAccess.file_exists(path):
		push_warning("cutscene 없음: %s" % path)
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if typeof(raw) == TYPE_DICTIONARY else {}
