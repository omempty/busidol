class_name WalkerEntity
extends Node2D
## 배경 보행자 — 정해진 경로를 왕복하는, **말 걸 수 없는** 사람.
##
## 원작 대조: `EVENT.C:move_eventer()`가 층당 1명을 `EVE_PATTERN[i][40]`의 40스텝
## 방향표대로 왕복시킨다(예: UP 21회 → DOWN 19회). 이동 전 `ATT==0`을 2셀 검사하고,
## 걸을 때마다 `mode`를 토글해 2프레임 걷기를 낸다.
##
## **길을 막지 않는다 — 그게 원작이다.** 원작 eventer는 ATT를 쓰지 않아 주인공이
## 그대로 통과했다. 막게 만들면 지나간 자리를 되돌려 놓아야 하고, 자동 주행이 짜 둔
## 경로가 도중에 끊긴다. 대화도 없다: 보행자와 대화를 잇는 `Talk_eventer()` 호출은
## 원작 소스에서 주석 처리돼 있다.

const STEP_TIME := 0.34
const TURN_PAUSE_TIME := 1.0

var walker_id := &""
var sprite_id := &""
var display_name := ""
var sequence_id := &""
var repeat_sequence_id: Variant = null
var sequence_variants: Array = []
var cell := Vector2i.ZERO
var sprite := AnimatedSprite2D.new()

var _runtime: MapRuntime
var _legs: Array = []  # [{dir: Vector2i, steps: int}, ...]
var _leg := 0
var _left := 0
var _wait := 0.0
var _current_dir := Vector2i.DOWN
var _is_stepping := false
var _is_talking := false
var _breath_phase := 0.0
var _base_scale := Vector2.ONE
var _paths: Dictionary = {}
var _meta: Dictionary = {}


func setup(
	p_id: StringName,
	p_sprite: StringName,
	p_cell: Vector2i,
	legs: Array,
	rt: MapRuntime,
	p_name: String = "",
	p_seq: StringName = &"",
	p_variants: Array = [],
	p_repeat_seq: Variant = null
) -> void:
	walker_id = p_id
	sprite_id = p_sprite
	cell = p_cell
	_legs = legs
	_runtime = rt
	display_name = p_name
	sequence_id = p_seq
	sequence_variants = p_variants
	repeat_sequence_id = p_repeat_seq
	position = GridMover.block_center(cell)
	z_index = 14
	_build_visual()
	if not _legs.is_empty():
		_left = int(Dictionary(_legs[0]).get("steps", 0))
		_current_dir = Dictionary(_legs[0]).get("dir", Vector2i.DOWN)
	_wait = randf_range(0.0, STEP_TIME)
	_breath_phase = randf_range(0.0, PI * 2.0)


func resolve_sequence() -> StringName:
	return DialogueManager.resolve_npc_sequence(
		walker_id, sequence_id, sequence_variants, repeat_sequence_id
	)


func occupies(c: Vector2i) -> bool:
	return c in Placement.body_cells(cell)


func set_talking(talking: bool) -> void:
	_is_talking = talking
	if not talking:
		_face(_current_dir, false)
		_wait = 0.6


func face_towards(target_cell: Vector2i) -> void:
	var diff := target_cell - cell
	var next := _current_dir
	if absi(diff.x) > absi(diff.y):
		next = Vector2i.RIGHT if diff.x > 0 else Vector2i.LEFT
	else:
		next = Vector2i.DOWN if diff.y > 0 else Vector2i.UP
	_face(next, false)


func _build_visual() -> void:
	_paths = SpriteSets.character_sheet(sprite_id, true)
	if str(_paths["sheet"]).is_empty():
		_paths = SpriteSets.character_sheet(&"player")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(_paths["meta"])))
	if typeof(raw) == TYPE_DICTIONARY:
		_meta = raw
	ShadowBlob.attach(self)
	sprite.sprite_frames = SpriteSets.build_frames(str(_paths["sheet"]), _meta)
	if not _meta.is_empty():
		sprite.scale = Vector2.ONE * float(_meta.get("scale", 1.0))
		sprite.offset = Vector2(0.0, SpriteSets.foot_offset(_meta))
	_base_scale = sprite.scale
	add_child(sprite)
	_face(Vector2i.DOWN, false)


func _process(delta: float) -> void:
	if _legs.is_empty() or _runtime == null:
		return
	if _is_talking:
		_update_breathing(delta)
		return
	_wait -= delta
	if _wait > 0.0:
		if not _is_stepping:
			_update_breathing(delta)
		return


func _update_breathing(delta: float) -> void:
	_breath_phase += delta * 2.8
	var breath := sin(_breath_phase) * 0.02
	sprite.position.y = sin(_breath_phase) * 1.5
	sprite.scale.y = _base_scale.y * (1.0 + breath)
	sprite.scale.x = _base_scale.x * (1.0 - breath * 0.5)

	if _left <= 0:
		_face(_current_dir, false)
		_leg = (_leg + 1) % _legs.size()
		_left = int(Dictionary(_legs[_leg]).get("steps", 0))
		_current_dir = Dictionary(_legs[_leg]).get("dir", Vector2i.DOWN)
		_wait = TURN_PAUSE_TIME
		if _left <= 0:
			return

	var dir: Vector2i = Dictionary(_legs[_leg]).get("dir", Vector2i.ZERO)
	if dir == Vector2i.ZERO:
		return
	_current_dir = dir

	# 2×2 몸 진입 가능 여부 검사
	var want := cell + dir
	var blocked := false
	for c in Placement.body_cells(want):
		if not _runtime.is_passable(c):
			blocked = true
			break

	if blocked:
		_face(dir, false)
		# 장애물 충돌 시 반대 경로로 전환하고 대기
		_leg = (_leg + 1) % _legs.size()
		_left = int(Dictionary(_legs[_leg]).get("steps", 0))
		_current_dir = Dictionary(_legs[_leg]).get("dir", Vector2i.DOWN)
		_wait = TURN_PAUSE_TIME
		return

	_left -= 1
	_wait = STEP_TIME
	_face(dir, true)
	cell = want
	_is_stepping = true
	var tw := create_tween()
	tw.tween_property(self, "position", GridMover.block_center(cell), STEP_TIME)
	tw.finished.connect(
		func() -> void:
			_is_stepping = false
			if _left <= 0:
				_face(_current_dir, false)
	)


func _face(dir: Vector2i, walking: bool) -> void:
	var name := &"down"
	if dir.x < 0:
		name = &"left"
	elif dir.x > 0:
		name = &"right"
	elif dir.y < 0:
		name = &"up"
	var anim := SpriteSets.pose_anim(sprite.sprite_frames, name, walking)
	if anim.is_empty():
		return
	if sprite.animation != anim:
		sprite.animation = anim
	if walking:
		sprite.play()
	else:
		if String(anim).begins_with("idle_"):
			sprite.play()
		else:
			sprite.stop()
			sprite.frame = 0
