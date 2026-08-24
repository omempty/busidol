extends Node
## Phase 3 스모크 — NPC 상호작용 → 대화창 오픈 → 진행 → 종료 자동 검증.
## 실행: godot --headless --path . res://tests/smoke_dialogue.tscn   (exit 0=PASS)

const FIELD_SCENE := preload("res://scenes/field.tscn")


func _ready() -> void:
	var failures: Array[String] = []

	var field: Node2D = FIELD_SCENE.instantiate()
	add_child(field)
	await get_tree().process_frame
	await get_tree().process_frame

	var player: PlayerEntity = field.get_player()
	var npc: NpcEntity = field.get_npc("tutor_dumb")
	if npc == null:
		_finish(["tutor_dumb NPC 없음"])
		return
	print("[smoke_dlg] npc=%s cell=%s seq=%s" % [npc.npc_id, npc.cell, npc.sequence_id])

	# NPC 왼쪽 2셀에 앵커를 두고 오른쪽을 바라보면 전방 셀에 NPC가 위치한다.
	player.teleport(npc.cell + Vector2i(-2, 0))
	player.face(&"right")
	await get_tree().process_frame

	if field.front_cells().has(npc.cell):
		print("[smoke_tr] 전방 셀 판정 OK")
	else:
		failures.append("전방 셀 판정 실패")

	# 대화 시작
	Input.action_press(&"interact")
	var opened := await _wait_until(func() -> bool: return field.dialogue_box.is_open, 2.0)
	Input.action_release(&"interact")
	if not opened:
		failures.append("대화창 미오픈")
		_finish(failures)
		return

	# 스텝 수만큼: 타이핑 완료 대기 → 진행 1회
	var expected_steps: int = Database.sequence(npc.sequence_id).size()
	for s in range(expected_steps):
		await _wait_until(func() -> bool: return not field.dialogue_box.is_typing(), 2.0)
		if s < expected_steps - 1:
			if not field.dialogue_box.is_open:
				failures.append("중간 종료 @step %d" % s)
				break
		Input.action_press(&"interact")
		await get_tree().process_frame
		await get_tree().process_frame
		Input.action_release(&"interact")
		await _wait_until(func() -> bool: return not field.dialogue_box.is_typing() \
				or not field.dialogue_box.is_open, 1.0)

	if field.dialogue_box.is_open:
		failures.append("대화 종료 실패(스텝 소진 안 됨)")
	if player.mover.enabled:
		pass
	else:
		failures.append("종료 후에도 이동 잠금 지속")

	_finish(failures)


func _wait_until(pred: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if pred.call():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return false


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("[smoke_dlg] PASS")
		get_tree().quit(0)
	else:
		push_error("[smoke_dlg] FAIL: " + "; ".join(failures))
		get_tree().quit(1)
