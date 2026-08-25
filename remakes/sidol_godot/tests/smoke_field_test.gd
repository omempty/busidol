extends Node
## 필드 스모크 — 로드맵 Phase 1 수용 기준 자동화:
##   부팅(필드 로드) → 이동(통행 방향 1보행) → 벽 차단(막힌 방향 무이동)
## 실행: godot --headless --path . res://tests/smoke_field.tscn   (exit 0=PASS)

const FIELD_SCENE := preload("res://scenes/field.tscn")
const TIMEOUT := 1.5


func _ready() -> void:
	var failures: Array[String] = []

	# 프롤로그 컷신(auto 트리거) 스킵 — 이동 검증에 집중
	GameState.flags["Q_F1_START"] = true

	var field: Node2D = FIELD_SCENE.instantiate()
	add_child(field)
	# 접촉→전투 전환 레이스 차단: 이동 검증에 몬스터 불필요
	if field.enemy_manager != null:
		field.enemy_manager.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var player: PlayerEntity = field.get_player()
	if player == null:
		_finish(["player 없음"])
		return
	var rt: MapRuntime = field.get_runtime()
	var start := player.mover.grid_pos
	print("[smoke_field] spawn=%s passable=%s" % [start, rt.is_passable(start)])

	# --- 1) 통행 가능한 방향으로 1보행 ---
	var dirs := {
		Vector2i.UP: &"move_up", Vector2i.DOWN: &"move_down",
		Vector2i.LEFT: &"move_left", Vector2i.RIGHT: &"move_right",
	}
	var action: StringName = &""
	var dir := Vector2i.ZERO
	for d: Vector2i in dirs:
		if rt.is_passable(start + d):
			dir = d
			action = dirs[d]
			break
	if action == &"":
		failures.append("스폰 주변 전면 차단(테스트 불가)")
	else:
		# 짧게 눌렀다 뗀다 — 버퍼 체인 과보행 없이 1보행만 검증.
		# physics_frame 대기: 프로세스 프레임만으로는 물리 틱 전에 해제될 수 있다.
		Input.action_press(action)
		await get_tree().physics_frame
		await get_tree().physics_frame
		Input.action_release(action)
		await _settle()
		var moved := player.mover.grid_pos == start + dir
		print("[smoke_field] move %s -> %s (moved=%s)" % [dir, player.mover.grid_pos, moved])
		if not moved:
			failures.append("통행 방향 이동 실패: %s" % action)

	# --- 2) 벽 차단: 동쪽이 막힌 통행 셀로 순간이동 후 우측 입력 ---
	var free_cell := _find_free_with_wall_east(rt)
	if free_cell == Vector2i(-9, -9):
		push_warning("벽차단 테스트 셀 미발견 — 생략")
	else:
		player.teleport(free_cell)
		await get_tree().process_frame
		Input.action_press(&"move_right")
		await _settle()
		Input.action_release(&"move_right")
		var blocked_ok := player.mover.grid_pos == free_cell
		print("[smoke_field] wall-block @%s stayed=%s" % [free_cell, blocked_ok])
		if not blocked_ok:
			failures.append("벽 통과 발생: %s" % str(player.mover.grid_pos))

	_finish(failures)


func _find_free_with_wall_east(rt: MapRuntime) -> Vector2i:
	for y in range(rt.definition.height):
		for x in range(rt.definition.width - 1):
			var c := Vector2i(x, y)
			if rt.is_passable(c) and not rt.is_passable(c + Vector2i.RIGHT) \
					and rt.is_passable(c + Vector2i.DOWN) and rt.is_passable(c + Vector2i.LEFT):
				return c
	return Vector2i(-9, -9)


func _settle() -> void:
	# 보행 완료 또는 타임아웃까지 대기(버퍼 체인 포함 안정화)
	var t := 0.0
	while t < TIMEOUT:
		await get_tree().process_frame
		t += get_process_delta_time()


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("[smoke_field] PASS")
		get_tree().quit(0)
	else:
		push_error("[smoke_field] FAIL: " + "; ".join(failures))
		get_tree().quit(1)
