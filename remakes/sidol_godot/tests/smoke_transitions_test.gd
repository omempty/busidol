extends Node
## Phase 2 스모크 — 계단 6층 왕복(1↔…↔5↔…↔1) + 문 통과(mapy±3) 자동 검증.
## 실행: godot --headless --path . res://tests/smoke_transitions.tscn   (exit 0=PASS)
## 주의: 층변경 감지 즉시 입력을 해제한다(홀드 시 착지 후 계속 보행하는 것은 정상 동작).

const FIELD_SCENE := preload("res://scenes/field.tscn")
const UP_ANCHOR := Vector2i(100, 63)  # stairs_center_up   (+3,-2)
const DOWN_ANCHOR := Vector2i(103, 63)  # stairs_center_down (-3,-2)

var failures: Array[String] = []


func _ready() -> void:
	var field: Node2D = FIELD_SCENE.instantiate()
	add_child(field)
	# 접촉→전투 전환 레이스 차단(8/25 헹 원인) — 층 전환 검증에 몬스터 불필요
	if field.enemy_manager != null:
		field.enemy_manager.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var player: PlayerEntity = field.get_player()
	var gate: TransitionGate = field.gate

	# --- 상행: 1→5 (F2→F3는 Q_F2_POSTER 게이트) ---
	var expected := 2
	while expected <= 5:
		player.teleport(UP_ANCHOR)
		await get_tree().process_frame
		if expected == 3 and not GameState.has_flag("Q_F2_POSTER"):
			# 잠금 확인 — 플래그 없이는 f2에 머물러야 한다.
			Input.action_press(&"move_down")
			var locked := await _wait_until(
				func() -> bool: return GameState.current_floor != 2, 0.8
			)
			Input.action_release(&"move_down")
			if locked:
				failures.append("F2→F3 잠금 해제(플래그 없이 통과)")
			else:
				print("[smoke_tr] F2→F3 locked (no flag) — ok")
			# 프리셋: 퀘스트 플래그 부여 후 재도전(게임 내 = 포스터 퀘스트 완료).
			GameState.flags["Q_F2_POSTER"] = true
			player.teleport(UP_ANCHOR)
			await get_tree().process_frame
		Input.action_press(&"move_down")
		var changed := await _wait_until(
			func() -> bool: return GameState.current_floor == expected and not gate.active, 3.0
		)
		Input.action_release(&"move_down")
		if not changed:
			failures.append("상행 실패: f%d→%d 미발생" % [expected - 1, expected])
			break
		await _wait_until(func() -> bool: return not player.mover.moving, 1.0)
		var want := UP_ANCHOR + Vector2i(3, -2)
		if not _anchor_ok(player.mover.grid_pos, want):
			failures.append("f%d 도착 앵커=%s (기대 %s)" % [expected, player.mover.grid_pos, want])
		print("[smoke_tr] climbed to f%d anchor=%s" % [expected, player.mover.grid_pos])
		expected += 1

	# --- 하행: 5→1 ---
	var descend_target := 4
	while descend_target >= 1:
		player.teleport(DOWN_ANCHOR)
		await get_tree().process_frame
		Input.action_press(&"move_down")
		var changed := await _wait_until(
			func() -> bool: return GameState.current_floor == descend_target and not gate.active,
			3.0
		)
		Input.action_release(&"move_down")
		if not changed:
			failures.append("하행 실패: f%d→%d 미발생" % [descend_target + 1, descend_target])
			break
		await _wait_until(func() -> bool: return not player.mover.moving, 1.0)
		var want := DOWN_ANCHOR + Vector2i(-3, -2)
		if not _anchor_ok(player.mover.grid_pos, want):
			failures.append("f%d 도착 앵커=%s (기대 %s)" % [descend_target, player.mover.grid_pos, want])
		print("[smoke_tr] descended to f%d anchor=%s" % [descend_target, player.mover.grid_pos])
		descend_target -= 1

	# --- 문 통과(f1): 아래 행이 문(ATT==9 2셀)인 앵커에서 하단 슬라이드 ---
	GameState.current_floor = 1
	field.rebuild_floor(player.mover.grid_pos)
	await get_tree().process_frame
	var rt: MapRuntime = field.get_runtime()
	var door_anchor := _find_door_anchor(rt)
	if door_anchor == Vector2i(-9, -9):
		push_warning("문 테스트 셀 미발견 — 생략")
	else:
		player.teleport(door_anchor)
		await get_tree().process_frame
		Input.action_press(&"move_down")
		# 슬라이드 완료 프레임에 다음 보행·연쇄 문 발화가 겹칠 수 있으므로
		# gate 발화를 감지하면 즉시 키를 떼고 완료만 기다린다.
		var started := await _wait_until(func() -> bool: return gate.active, 3.0)
		Input.action_release(&"move_down")
		var arrived := false
		if started:
			arrived = await _wait_until(
				func() -> bool:
					return not gate.active and player.mover.grid_pos == door_anchor + Vector2i(0, 3),
				3.0
			)
		print("[smoke_tr] door @%s -> %s (ok=%s)" % [door_anchor, player.mover.grid_pos, arrived])
		if not arrived:
			failures.append("문 통과 실패 @%s" % str(door_anchor))

	if failures.is_empty():
		print("[smoke_tr] PASS — 최종 층 f%d" % GameState.current_floor)
		get_tree().quit(0)
	else:
		push_error("[smoke_tr] FAIL: " + "; ".join(failures))
		get_tree().quit(1)


## 도착 앵커 판정 — 입력 해제 직후 한 걸음 추가 보행(홀드 잔량)은 정상 동작이므로
## x는 정확히, y는 기대치~+1행까지 허용한다.
func _anchor_ok(actual: Vector2i, want: Vector2i) -> bool:
	return actual.x == want.x and actual.y >= want.y and actual.y <= want.y + 1


func _wait_until(pred: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if pred.call():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return false


func _find_door_anchor(rt: MapRuntime) -> Vector2i:
	for y in range(rt.definition.height - 3):
		for x in range(rt.definition.width - 1):
			if (
				rt.definition.attr_at(Vector2i(x, y + 2)) == 9
				and rt.definition.attr_at(Vector2i(x + 1, y + 2)) == 9
				and rt.is_passable(Vector2i(x, y))
				and rt.is_passable(Vector2i(x + 1, y))
			):
				return Vector2i(x, y)
	return Vector2i(-9, -9)
