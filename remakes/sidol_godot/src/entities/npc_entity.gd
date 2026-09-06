class_name NpcEntity
extends Node2D
## 필드 NPC — 2×2 셀 점유, 상호작용 시 DialogueBox로 시퀀스 재생.
## 전용 시트(<npc_id>_original/_remake)를 쓰고, 없을 때만 플레이어 시트 플레이스홀더.
## 제자리 호흡 아이들(Squash & Stretch) 및 필요 시 소폭 배회(wander_range) 지원.

var npc_id := &""
var display_name := ""
var sequence_id := &""
var repeat_sequence_id: Variant = null
## 상태에 따라 갈아 끼우는 대사. `[{requires_flag: String|Array, sequence_id: String}]`,
## **먼저 맞는 것이 이긴다**. 비어 있으면 sequence_id 하나만 쓴다.
var sequence_variants: Array = []
var cell := Vector2i.ZERO
var sprite := AnimatedSprite2D.new()
var wander_range := 0

var _paths: Dictionary = {}
var _meta: Dictionary = {}
var _runtime: MapRuntime
var _home_cell := Vector2i.ZERO

const LOOK_MIN := 2.6
const LOOK_MAX := 6.4
const WANDER_STEP_TIME := 0.38
const FACINGS: Array[StringName] = [&"down", &"left", &"right", &"up"]

var _look_wait := 0.0
var _wander_wait := 0.0
var _facing := &"down"
var _base_scale := Vector2.ONE
var _base_offset := Vector2.ZERO
var _breath_phase := 0.0
var _fidget_wait := 0.0
var _fidget_duration := 0.0
var _is_talking := false
var _is_wandering := false


func setup(
	p_id: StringName,
	p_name: String,
	p_seq: StringName,
	p_cell: Vector2i,
	tint: Color,
	p_variants: Array = [],
	p_wander_range: int = 0,
	p_runtime: MapRuntime = null,
	p_repeat_seq: Variant = null
) -> void:
	npc_id = p_id
	display_name = p_name
	sequence_id = p_seq
	repeat_sequence_id = p_repeat_seq
	sequence_variants = p_variants
	cell = p_cell
	_home_cell = p_cell
	wander_range = p_wander_range
	_runtime = p_runtime
	position = GridMover.block_center(cell)
	modulate = tint
	z_index = 15
	_build_visual()
	_wander_wait = randf_range(3.0, 7.0)


func resolve_sequence() -> StringName:
	return DialogueManager.resolve_npc_sequence(sequence_id, sequence_variants, repeat_sequence_id)


func body_cells() -> Array[Vector2i]:
	return Placement.body_cells(cell)


func occupies(c: Vector2i) -> bool:
	var d := c - cell
	return d.x >= 0 and d.y >= 0 and d.x < Placement.BODY.x and d.y < Placement.BODY.y


func sheet_path() -> String:
	return str(_paths.get("sheet", ""))


func set_talking(talking: bool) -> void:
	_is_talking = talking
	if not talking:
		_look_wait = randf_range(LOOK_MIN, LOOK_MAX)
		_wander_wait = randf_range(3.0, 6.0)


func face_towards(target_cell: Vector2i) -> void:
	var diff := target_cell - cell
	var next := _facing
	if absi(diff.x) > absi(diff.y):
		next = &"right" if diff.x > 0 else &"left"
	else:
		next = &"down" if diff.y > 0 else &"up"
	if next == _facing:
		return  # 매 프레임 접근 반응으로 불러도 같은 방향이면 손대지 않는다
	_apply_facing(next)


func _build_visual() -> void:
	_paths = SpriteSets.character_sheet(npc_id, true)
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
	_base_offset = sprite.offset
	sprite.animation = &"idle"
	sprite.play()
	add_child(sprite)
	_look_wait = randf_range(0.0, LOOK_MAX)
	_breath_phase = randf_range(0.0, PI * 2.0)
	_fidget_wait = randf_range(2.5, 5.5)


func _process(delta: float) -> void:
	_update_breathing(delta)
	if _is_talking or _is_wandering:
		return

	if wander_range > 0 and _runtime != null:
		_wander_wait -= delta
		if _wander_wait <= 0.0:
			_wander_wait = randf_range(4.0, 8.0)
			if _try_wander_step():
				return

	_look_wait -= delta
	if _look_wait > 0.0:
		return
	_look_wait = randf_range(LOOK_MIN, LOOK_MAX)
	var next: StringName = FACINGS[randi() % FACINGS.size()]
	if next != _facing:
		_apply_facing(next)


func _update_breathing(delta: float) -> void:
	if _is_wandering:
		sprite.scale = _base_scale
		sprite.position = Vector2.ZERO
		return
	_breath_phase += delta * 2.8
	var breath := sin(_breath_phase) * 0.035
	sprite.position.y = sin(_breath_phase) * 2.2
	sprite.scale.y = _base_scale.y * (1.0 + breath)
	sprite.scale.x = _base_scale.x * (1.0 - breath * 0.5)

	# 고정 NPC 주기적 미세 움직임: 단방향 1프레임 시트에서도 보이도록
	# 발돋움 홉(offset — 호흡과 채널이 달라 묻히지 않는다) + 고개 까딱(회전).
	# 프레임 복구는 idle 계열 포함(예전 조건은 idle에서 frame 1에 stuck됐다).
	if not _is_talking:
		_fidget_wait -= delta
		if _fidget_wait <= 0.0:
			_fidget_wait = randf_range(3.5, 6.5)
			_fidget_duration = 0.18
			if (
				sprite.sprite_frames != null
				and sprite.sprite_frames.has_animation(sprite.animation)
			):
				if sprite.sprite_frames.get_frame_count(sprite.animation) > 1:
					sprite.frame = 1
			var fg := create_tween().set_parallel(true)
			fg.tween_property(sprite, "offset:y", _base_offset.y - 5.0, 0.09)
			fg.tween_property(sprite, "rotation", 0.09, 0.09)
			fg.chain().tween_property(sprite, "offset:y", _base_offset.y, 0.12)
			fg.parallel().tween_property(sprite, "rotation", 0.0, 0.12)
		elif _fidget_duration > 0.0:
			_fidget_duration -= delta
			if _fidget_duration <= 0.0:
				sprite.frame = 0


func _apply_facing(next: StringName) -> void:
	var anim := SpriteSets.pose_anim(sprite.sprite_frames, next, false)
	if anim.is_empty():
		return
	_facing = next
	sprite.animation = anim
	if String(anim).begins_with("idle_"):
		sprite.play()
	else:
		sprite.stop()
		sprite.frame = 0
	# 단방향 시트는 방향을 바꿔도 같은 그림이라, 고개 돌림을 까딱으로 보여 준다.
	var nod := create_tween()
	nod.tween_property(sprite, "rotation", 0.08, 0.08)
	nod.tween_property(sprite, "rotation", 0.0, 0.10)


func _try_wander_step() -> bool:
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	dirs.shuffle()
	if cell != _home_cell and randf() < 0.5:
		var back := _step_towards(cell, _home_cell)
		if back != Vector2i.ZERO:
			dirs.push_front(back)

	for dir in dirs:
		var target := cell + dir
		if (
			absi(target.x - _home_cell.x) > wander_range
			or absi(target.y - _home_cell.y) > wander_range
		):
			continue
		for c in body_cells():
			_runtime.set_override_attr(c, 0)
		var fits := Placement.body_fits(_runtime, target)
		if not fits:
			for c in body_cells():
				_runtime.set_override_attr(c, 1)
			continue
		if Placement.bodies_touch(target, GameState.player_cell):
			for c in body_cells():
				_runtime.set_override_attr(c, 1)
			continue

		cell = target
		for c in body_cells():
			_runtime.set_override_attr(c, 1)

		_is_wandering = true
		var face_name := &"down"
		if dir.x < 0:
			face_name = &"left"
		elif dir.x > 0:
			face_name = &"right"
		elif dir.y < 0:
			face_name = &"up"

		var walk_anim := SpriteSets.pose_anim(sprite.sprite_frames, face_name, true)
		if not walk_anim.is_empty():
			sprite.animation = walk_anim
			sprite.play()
		_facing = face_name

		var tw := create_tween()
		tw.tween_property(self, "position", GridMover.block_center(cell), WANDER_STEP_TIME)
		tw.finished.connect(
			func() -> void:
				_is_wandering = false
				_apply_facing(_facing)
		)
		return true
	return false


func _step_towards(from: Vector2i, to: Vector2i) -> Vector2i:
	var diff := to - from
	if absi(diff.x) >= absi(diff.y) and diff.x != 0:
		return Vector2i(1 if diff.x > 0 else -1, 0)
	elif diff.y != 0:
		return Vector2i(0, 1 if diff.y > 0 else -1)
	return Vector2i.ZERO
