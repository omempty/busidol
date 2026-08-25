extends Node
## Phase 3 스모크 — NPC 상호작용 → 대화창 오픈 → 진행 → 종료 자동 검증.
## 실행: godot --headless --path . res://tests/smoke_dialogue.tscn   (exit 0=PASS)

const FIELD_SCENE := preload("res://scenes/field.tscn")


func _ready() -> void:
	var failures: Array[String] = []

	# 감시자 — 무응답 행을 막는다(파스 실패 등으로 _ready가 멎으면 CI가 매달린다)
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		push_error("[smoke_dlg] WATCHDOG timeout")
		get_tree().quit(1))

	# 프롤로그 자동 컷신(skip) — Phase 7 도입 트리거가 입력을 탈취하지 않도록.
	# (smoke_field와 동일 패턴. 미설정 시 컷신이 대화 검증을 대체해 실패했었다.)
	# 마커=컷신 소비, Q_F1_START=F1 존 트리거 게이트 개방.
	GameState.flags["q_f1_opening_seen"] = true
	GameState.flags["Q_F1_START"] = true

	var field: Node2D = FIELD_SCENE.instantiate()
	add_child(field)
	# 접촉→전투 전환 레이스 차단 — 대화 진행 검증 방해 금지
	if field.enemy_manager != null:
		field.enemy_manager.queue_free()
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

	# 대화 시작 — 오픈 감지까지 홀드(물리 프레임 동기, 레이스 제거)
	var opened := await _press_until(
			func() -> bool: return field.dialogue_box.is_open, 90)
	if not opened:
		failures.append("대화창 미오픈")
		_finish(failures)
		return

	# 스텝 수만큼: 타이핑 완료 대기 → 진행(인덱스/종료 변화 감지까지 홀드)
	# 마지막 스텝도 실전과 동일하게 진행 입력 한 번으로 닫힌다.
	var expected_steps: int = Database.sequence(npc.sequence_id).size()
	for s in range(expected_steps):
		await _wait_until(func() -> bool: return not field.dialogue_box.is_typing(), 2.0)
		if not field.dialogue_box.is_open:
			failures.append("조기 종료 @step %d" % s)
			break
		var before: int = field.dialogue_box.index
		var advanced := await _press_until(
				_index_moved.bind(field.dialogue_box, before), 90)
		if not advanced:
			failures.append("스텝 진행 실패 @step %d" % s)
			break

	if field.dialogue_box.is_open:
		failures.append("대화 종료 실패(스텝 소진 안 됨)")
	if player.mover.enabled:
		pass
	else:
		failures.append("종료 후에도 이동 잠금 지속")

	_finish(failures)


func _index_moved(box: DialogueBox, before: int) -> bool:
	return not box.is_open or box.index != before


## interact 탭 — pred가 충족될 때까지 물리 프레임 단위로 홀드한다.
func _press_until(pred: Callable, max_ticks: int) -> bool:
	Input.action_press(&"interact")
	var ok := false
	for _f in range(max_ticks):
		await get_tree().physics_frame
		if pred.call():
			ok = true
			break
	Input.action_release(&"interact")
	return ok


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
