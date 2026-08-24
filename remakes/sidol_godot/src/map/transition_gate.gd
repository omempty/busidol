class_name TransitionGate
extends Node
## 문 통과(ATT==9, mapy±3)와 계단 층 전환 처리 — 원작 move_check_gate/floor_move 대체.
## 데이터: data/maps/transitions.json (좌표 하드코딩 금지). 페이드 연출은 walk_floor 대체.

const TRANSITIONS_PATH := "res://data/maps/transitions.json"
const FADE_TIME := 0.18
const DOOR_SLIDE_TIME := 0.4

var field: Node2D                    # rebuild_floor(new_anchor) / get_player / get_runtime 제공
var player: PlayerEntity
var active := false

var _transitions: Array = []
var _overlay: ColorRect


func setup(p_field: Node2D) -> void:
	field = p_field
	player = field.get_player()
	_transitions = _load_transitions()

	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 50
	add_child(overlay_layer)
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(_overlay)


func _load_transitions() -> Array:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(TRANSITIONS_PATH))
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("TransitionGate: transitions.json 파싱 실패")
		return []
	return raw["transitions"]


func _physics_process(_delta: float) -> void:
	if active or player == null or player.mover.moving:
		return
	var dir := Vector2i.ZERO
	if Input.is_action_pressed(&"move_down"):
		dir = Vector2i.DOWN
	elif Input.is_action_pressed(&"move_up"):
		dir = Vector2i.UP
	if dir == Vector2i.ZERO:
		return

	# 1) 문 우선 — 원작 move_check_gate: 발밑(아래 행) 또는 머리 위(위 행) 2셀 ATT==9
	if _try_door(dir):
		return
	# 2) 계단 — 앵커가 전환 정의와 일치하면 층 이동
	_try_stairs(dir)


func _try_door(dir: Vector2i) -> bool:
	var rt: MapRuntime = field.get_runtime()
	var anchor := player.mover.grid_pos
	var check_row := anchor.y + 2 if dir == Vector2i.DOWN else anchor.y - 1
	var a := Vector2i(anchor.x, check_row)
	var b := Vector2i(anchor.x + 1, check_row)
	if rt.definition.attr_at(a) != 9 or rt.definition.attr_at(b) != 9:
		return false

	active = true
	player.mover.enabled = false
	var tween := create_tween()
	tween.tween_property(player, "position",
			GridMover.block_center(anchor + dir * 3), DOOR_SLIDE_TIME)
	tween.finished.connect(func() -> void:
		player.mover.grid_pos = anchor + dir * 3
		player.mover.enabled = true
		active = false)
	return true


func _try_stairs(dir: Vector2i) -> void:
	if dir != Vector2i.DOWN:
		return   # 원작은 아래키 입력으로만 계단 트리거
	var anchor := player.mover.grid_pos
	for t: Dictionary in _transitions:
		var at := Vector2i(int(t["anchor"][0]), int(t["anchor"][1]))
		if anchor != at or str(t["trigger_dir"]) != "down":
			continue
		print("[gate] stair matched id=%s anchor=%s floor=%d" % [t["id"], anchor, GameState.current_floor])
		var floor_now := GameState.current_floor
		if floor_now < int(t["guard_min_floor"]) or floor_now > int(t["guard_max_floor"]):
			print("[gate] guard 차단 (min=%d max=%d)" % [int(t["guard_min_floor"]), int(t["guard_max_floor"])])
			continue
		var req: Variant = t.get("requires_flag")
		if req != null and not GameState.has_flag(str(req)):
			continue
		_start_floor_change(t)
		return


func _start_floor_change(t: Dictionary) -> void:
	active = true
	player.mover.enabled = false
	var tween := create_tween()
	tween.tween_property(_overlay, "color:a", 1.0, FADE_TIME)
	tween.finished.connect(func() -> void:
		GameState.current_floor += int(t["floor_delta"])
		EventBus.floor_changed.emit(GameState.current_floor)
		# 원작 walk_floor: 앵커를 유지한 채 오프셋 적용 (x+=3/-8 등, y-=2)
		var new_anchor := Vector2i(int(t["anchor"][0]), int(t["anchor"][1])) \
				+ Vector2i(int(t["spawn_offset"][0]), int(t["spawn_offset"][1]))
		field.rebuild_floor(new_anchor)
		var fade_back := create_tween()
		fade_back.tween_property(_overlay, "color:a", 0.0, FADE_TIME)
		fade_back.finished.connect(func() -> void:
			player.mover.enabled = true
			active = false))
