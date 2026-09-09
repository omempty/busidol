extends Node
## 필드 스모크 — 로드맵 Phase 1 수용 기준 자동화:
##   부팅(필드 로드) → 이동(통행 방향 1보행) → 벽 차단(막힌 방향 무이동)
## 실행: godot --headless --path . res://tests/smoke_field.tscn   (exit 0=PASS)

const FIELD_SCENE := preload("res://scenes/field.tscn")
const TIMEOUT := 1.5


func _ready() -> void:
	var failures: Array[String] = []

	# 프롤로그 컷신(auto 트리거) 스킵 + F1 존 트리거 게이트 개방 — 이동 검증에 집중
	GameState.flags["q_f1_opening_seen"] = true
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
		Vector2i.UP: &"move_up",
		Vector2i.DOWN: &"move_down",
		Vector2i.LEFT: &"move_left",
		Vector2i.RIGHT: &"move_right",
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

	# --- 3) 나를 막은 그 셀을 조사할 수 있는가 — 네 방향 전부 ---
	# 구판은 좌/하 전방 오프셋만 한 칸 멀어(x−2 · y+3) 왼쪽·아래 상자와 NPC가
	# 영영 조사 불가였다. front_cells가 이동 차단 셀과 같은 곳을 보는지 고정한다.
	for d: Vector2i in dirs:
		var spot := _find_blocked_from(player, rt, d)
		if spot == Vector2i(-9, -9):
			push_warning("[smoke_field] 차단 지점 미발견 %s — 생략" % d)
			continue
		player.teleport(spot)
		player.face(player.dir_to_name(d))
		await get_tree().process_frame
		var front: Array[Vector2i] = field.front_cells()
		var missing: Array[Vector2i] = []
		for e in player.mover.edge_cells(spot, d):
			if not rt.is_passable(e) and not front.has(e):
				missing.append(e)
		print("[smoke_field] 전방 조사 %s @%s front=%s 누락=%s" % [d, spot, front, missing])
		if not missing.is_empty():
			failures.append("차단 셀이 전방 목록에 없음 %s: %s" % [d, missing])

	# --- 12시 방향 상자: 아래에서 위를 보고 열 수 있는가 ---
	#
	# 상자는 2칸 높이이고 **마커가 윗칸**이라, 아래에서 접근하면 몸 바로 위는 상자
	# 아랫칸(막힘)이다. 원작 check_item()은 한 칸 더 읽어 이 자리를 살렸는데 우리는
	# 그러지 않아 **아래에서는 어떤 상자도 열리지 않았다**(2026-08-30 유저 신고,
	# f1 실측 12곳 중 0곳). 규칙을 다시 좁히면 여기서 걸린다.
	#
	# 판정은 게임이 쓰는 field.chest_cells()를 그대로 부른다 — 두 벌로 만들면
	# "도구는 된다는데 게임은 아니라고 한다"가 생긴다.
	var tried := 0
	var opened := 0
	var first_fail := ""
	for cy in range(2, rt.definition.height - 4):
		for cx in range(2, rt.definition.width - 3):
			var marker := Vector2i(cx, cy)
			if not field._is_chest(rt.attr_at(marker)):
				continue
			var anchor := marker + Vector2i(0, 2)  # 상자 아랫칸(막힘) 바로 아래에 선다
			if not Placement.body_fits(rt, anchor):
				continue
			tried += 1
			player.mover.grid_pos = anchor
			player.facing = &"up"
			if field._chest_in_front().x >= 0:
				opened += 1
			elif first_fail.is_empty():
				first_fail = "상자%s 서는자리%s" % [marker, anchor]
	print("[smoke_field] 12시 상자 %d자리 중 %d 성공" % [tried, opened])
	# --- 4) ESC 일시정지 메뉴 토글 검증 ---
	var pause_menu: PauseMenu = null
	for child in field.get_children():
		if child is PauseMenu:
			pause_menu = child
			break
	if pause_menu == null:
		failures.append("field에 PauseMenu 없음")
	else:
		if pause_menu.visible:
			failures.append("PauseMenu 초기 상태가 visible")
		var ev_cancel := InputEventAction.new()
		ev_cancel.action = &"cancel"
		ev_cancel.pressed = true
		Input.parse_input_event(ev_cancel)
		await get_tree().process_frame
		await get_tree().process_frame
		if not pause_menu.visible:
			failures.append("ESC 눌렀을 때 PauseMenu가 열리지 않음")
		else:
			print("[smoke_field] ESC -> PauseMenu 열림 확인 OK")
			Input.parse_input_event(ev_cancel)
			await get_tree().process_frame
			await get_tree().process_frame
			if pause_menu.visible:
				failures.append("ESC 재입력 시 PauseMenu가 닫히지 않음")
			else:
				print("[smoke_field] ESC 재입력 -> PauseMenu 닫힘 확인 OK")

	# --- 5) idle_anim 계약이 데이터에서 엔티티까지 실제로 건너오는가 ---
	#
	# 왜 여기서 재나: 이 계약은 2026-09-09까지 **선언만 있고 읽는 코드가 0곳**이었다.
	# 값을 고치는 것만으로는 다시 죽으므로, 정상 경로와 부정 경로를 같이 세워 둔다.
	for npc: NpcEntity in field.npcs:
		if not NpcEntity.is_idle_anim_implemented(String(npc.idle_anim)):
			failures.append("NPC %s의 idle_anim이 미구현: %s" % [npc.npc_id, npc.idle_anim])
		elif npc.idle_motion != bool(NpcEntity.IDLE_ANIMS[npc.idle_anim]):
			# 계약 이름만 갈아 끼우고 동작은 안 바뀌는 것 — 사문화가 되살아나는 정확한 모양이다.
			failures.append(
				"NPC %s: 계약 %s인데 idle_motion=%s" % [npc.npc_id, npc.idle_anim, npc.idle_motion]
			)
	if not field.npcs.is_empty():
		var probe: NpcEntity = field.npcs[0]
		var keep: StringName = probe.idle_anim

		# 부정 시험 ①: 모르는 이름은 조용히 다른 연출이 되지 않고 기본값으로 떨어진다.
		if NpcEntity.is_idle_anim_implemented("squash"):
			failures.append("못 쓰는 값 squash가 구현 목록에 들어 있다")
		probe.set_idle_anim(&"squash")
		if probe.idle_anim != NpcEntity.DEFAULT_IDLE_ANIM or not probe.idle_motion:
			failures.append("모르는 idle_anim이 기본값으로 안 떨어짐: %s" % probe.idle_anim)

		# 부정 시험 ②: "none"은 이름만 받는 것이 아니라 **연출이 실제로 멈춰야** 한다.
		probe.set_idle_anim(&"none")
		probe.sprite.position.y = -1.0
		probe._update_breathing(0.5)
		if probe.idle_motion or not is_zero_approx(probe.sprite.position.y):
			failures.append("idle_anim=none인데 연출이 계속 돈다(y=%s)" % probe.sprite.position.y)

		probe.set_idle_anim(keep)
		print("[smoke_field] idle_anim 계약 %d명 확인(%s)" % [field.npcs.size(), keep])

	# --- 6) 소품 조사(SPACE)가 데이터에서 대사창까지 이어지는가 ---
	#
	# 2026-09-09까지 props_f1.json의 inspect 5개와 PropsLayer.prop_at()은 **부르는 곳이 0곳**이었다.
	# 정상 경로 하나로는 다시 죽는 것을 못 막는다 — requires_flag 부정 경로를 같이 세운다.
	var layer: PropsLayer = field.props_layer()
	if layer == null or layer.props.is_empty():
		failures.append("f%d 소품 덧층이 비었다" % GameState.current_floor)
	else:
		var open_prop: Dictionary = {}
		var gated_prop: Dictionary = {}
		for prop: Dictionary in layer.props:
			var ins: Dictionary = prop.get("inspect", {})
			var need := String(ins.get("requires_flag", ""))
			if need.is_empty():
				if open_prop.is_empty():
					open_prop = prop
			elif gated_prop.is_empty():
				gated_prop = prop

		# 부정 시험: requires_flag가 안 선 소품은 **조사 대상에서 빠진다**(알약도 안 뜬다).
		if not gated_prop.is_empty():
			var need: String = String(
				(gated_prop.get("inspect", {}) as Dictionary)["requires_flag"]
			)
			var g_stand := PropsProbe.stand_that_sees(rt, player.mover, gated_prop)
			if g_stand.x < 0:
				failures.append("소품 %s 앞에 설 자리가 없다" % gated_prop.get("id", "?"))
			else:
				GameState.flags[need] = true
				player.mover.grid_pos = g_stand
				var g_facing := &""
				for f: StringName in [&"up", &"down", &"left", &"right"]:
					player.facing = f
					if field._prop_in_front().x >= 0:
						g_facing = f
						break
				if g_facing.is_empty():
					failures.append("%s: 플래그를 세워도 조사 대상이 안 된다" % gated_prop.get("id", "?"))
				else:
					GameState.flags.erase(need)
					player.facing = g_facing
					if field._prop_in_front().x >= 0:
						failures.append("%s: %s가 없는데도 조사된다" % [gated_prop.get("id", "?"), need])
					if not PropsLayer.inspect_steps(gated_prop, {}).is_empty():
						failures.append("%s: 플래그 없이 대사가 만들어진다" % gated_prop.get("id", "?"))

		# 정상 경로: 앞에 서면 잡히고 대사창이 실제로 열린다.
		if open_prop.is_empty():
			failures.append("requires_flag 없는 소품이 하나도 없다")
		else:
			var stand := PropsProbe.stand_that_sees(rt, player.mover, open_prop)
			if stand.x < 0:
				failures.append("소품 %s 앞에 설 자리가 없다" % open_prop.get("id", "?"))
			else:
				player.mover.grid_pos = stand
				var found := false
				for f: StringName in [&"up", &"down", &"left", &"right"]:
					player.facing = f
					if field._prop_in_front().x >= 0:
						found = true
						break
				if not found:
					failures.append("소품 %s 앞에 섰는데 못 잡는다(@%s)" % [open_prop.get("id", "?"), stand])
				else:
					field._start_inspect(open_prop)
					await get_tree().process_frame
					if not field.dialogue_box.is_open:
						failures.append("소품 조사했는데 대사창이 안 열린다")
					else:
						print(
							(
								"[smoke_field] 소품 조사 OK — %s @%s %d줄"
								% [
									open_prop.get("id", "?"),
									stand,
									PropsLayer.inspect_steps(open_prop, GameState.flags).size()
								]
							)
						)

	_finish(failures)


## 몸(2×2)이 온전히 들어가면서 진행 방향만 막힌 셀 — 전방 조사 검증 지점.
func _find_blocked_from(player: PlayerEntity, rt: MapRuntime, d: Vector2i) -> Vector2i:
	for y in range(1, rt.definition.height - 3):
		for x in range(1, rt.definition.width - 3):
			var c := Vector2i(x, y)
			if not _body_fits(rt, c):
				continue
			for e in player.mover.edge_cells(c, d):
				if not rt.is_passable(e):
					return c
	return Vector2i(-9, -9)


func _body_fits(rt: MapRuntime, c: Vector2i) -> bool:
	for o in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		if not rt.is_passable(c + o):
			return false
	return true


func _find_free_with_wall_east(rt: MapRuntime) -> Vector2i:
	for y in range(rt.definition.height):
		for x in range(rt.definition.width - 1):
			var c := Vector2i(x, y)
			if (
				rt.is_passable(c)
				and not rt.is_passable(c + Vector2i.RIGHT)
				and rt.is_passable(c + Vector2i.DOWN)
				and rt.is_passable(c + Vector2i.LEFT)
			):
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
