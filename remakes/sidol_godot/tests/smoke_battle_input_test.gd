extends Node
## 전투 단축키 스모크 — 숫자 즉시 선택 · Q/E 대상 전환 · R 반복이 실제 입력으로 도는가.
##
## 왜 관문에 두나: 전투는 원래 **키보드로 커맨드를 고를 수조차 없었다**(2026-08-28 재작성 전).
## 그런 종류의 퇴행은 스크린샷으로도 잘 안 보이고 파스 검사에도 안 걸린다 —
## 액션 이름이 바뀌거나 InputMap 등록이 빠지면 조용히 조작 불가가 된다.
## 그래서 InputEventAction을 실제로 흘려보내 시그널이 나오는지까지 본다.
##
## 실행: godot --headless --path . res://tests/smoke_battle_input.tscn   (exit 0=PASS)

var _got_command := &""
var _got_target := 0
var _got_repeat := false
var _got_cancel := false


func _ready() -> void:
	var failures: Array[String] = []

	get_tree().create_timer(20.0).timeout.connect(
		func() -> void:
			push_error("[smoke_input] WATCHDOG timeout")
			get_tree().quit(1)
	)

	# InputMap 등록 확인 — 단축키 액션이 하나라도 빠지면 조작이 조용히 죽는다.
	var required: Array[StringName] = [
		&"battle_slot_1",
		&"battle_slot_9",
		&"battle_target_prev",
		&"battle_target_next",
		&"battle_repeat",
	]
	for action in required:
		if not InputMap.has_action(action):
			failures.append("InputMap에 %s 액션이 없다" % action)

	var ui := BattleUI.new()
	add_child(ui)
	ui.command_selected.connect(func(cmd: StringName) -> void: _got_command = cmd)
	ui.target_cycled.connect(func(dir: int) -> void: _got_target = dir)
	ui.repeat_requested.connect(func() -> void: _got_repeat = true)
	ui.show_command_menu()
	await get_tree().process_frame

	# ① 숫자키 — 2번 항목(기술)을 한 번에 고른다. COMMANDS 순서가 계약이다.
	await _send(&"battle_slot_2")
	var expected: StringName = StringName(str(BattleUI.COMMANDS[1]["id"]))
	if _got_command != expected:
		failures.append("숫자키 2 → 기대 '%s', 실제 '%s'" % [expected, _got_command])
	else:
		print("[smoke_input] 숫자키 2 -> %s" % _got_command)

	# ② Q/E — 대상 전환 방향이 그대로 전달돼야 한다.
	await _send(&"battle_target_next")
	if _got_target != 1:
		failures.append("E(다음 대상) → 기대 +1, 실제 %d" % _got_target)
	await _send(&"battle_target_prev")
	if _got_target != -1:
		failures.append("Q(이전 대상) → 기대 -1, 실제 %d" % _got_target)
	if _got_target == -1:
		print("[smoke_input] Q/E 대상 전환 OK")

	# ③ R — 직전 행동 반복 요청.
	await _send(&"battle_repeat")
	if not _got_repeat:
		failures.append("R(반복) 시그널이 오지 않았다")
	else:
		print("[smoke_input] R 반복 요청 OK")

	# ④ 메뉴가 닫힌 뒤에도 대상 전환·반복은 받아야 한다(연출 대기 중 조작).
	ui.hide_menu()
	await get_tree().process_frame
	_got_repeat = false
	await _send(&"battle_repeat")
	if not _got_repeat:
		failures.append("메뉴가 닫힌 상태에서 R이 먹히지 않았다")

	# ⑤ Enter 키로 현재 선택 항목 결정
	ui.show_command_menu()
	await get_tree().process_frame
	_got_command = &""
	var enter_ev := InputEventKey.new()
	enter_ev.keycode = KEY_ENTER
	enter_ev.pressed = true
	Input.parse_input_event(enter_ev)
	await get_tree().process_frame
	await get_tree().process_frame
	if _got_command != &"attack":
		failures.append("Enter 키 커맨드 결정 실패: 기대 'attack', 실제 '%s'" % _got_command)
	else:
		print("[smoke_input] Enter 키 결정 OK -> attack")

	# ⑥ 커맨드 메뉴에서 Esc 누르면 cancel_requested 시그널 발생
	ui.show_command_menu()
	await get_tree().process_frame
	_got_cancel = false
	ui.cancel_requested.connect(func() -> void: _got_cancel = true)
	var esc_ev := InputEventKey.new()
	esc_ev.keycode = KEY_ESCAPE
	esc_ev.pressed = true
	Input.parse_input_event(esc_ev)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _got_cancel:
		failures.append("커맨드 메뉴에서 Esc 시 cancel_requested 누락")
	else:
		print("[smoke_input] 커맨드 메뉴 Esc -> cancel_requested OK")

	# ⑦ 서브메뉴(Skill) 열려 있을 때 Esc 누르면 커맨드 메뉴로 복귀
	ui.show_skill_menu()
	await get_tree().process_frame
	if ui._menu_kind != &"skill":
		failures.append("스킬 메뉴 열기 실패")
	var esc_ev2 := InputEventKey.new()
	esc_ev2.keycode = KEY_ESCAPE
	esc_ev2.pressed = true
	Input.parse_input_event(esc_ev2)
	await get_tree().process_frame
	await get_tree().process_frame
	if ui._menu_kind != &"command":
		failures.append("서브메뉴에서 Esc 후 커맨드 메뉴 미복귀: %s" % ui._menu_kind)
	else:
		print("[smoke_input] 서브메뉴에서 Esc -> 커맨드 메뉴 복귀 OK")

	# ⑧ 마우스 좌클릭으로 항목 선택 및 결정 (자식 Label 클릭 포함)
	ui.show_command_menu()
	await get_tree().process_frame
	_got_command = &""
	if ui._menu_rows.size() > 2:
		var guard_row: Control = ui._menu_rows[2]  # guard
		var click_ev := InputEventMouseButton.new()
		click_ev.button_index = MOUSE_BUTTON_LEFT
		click_ev.pressed = true
		guard_row.gui_input.emit(click_ev)
		await get_tree().process_frame
		if _got_command != &"guard":
			failures.append("마우스 좌클릭 커맨드 선택 실패: 기대 'guard', 실제 '%s'" % _got_command)
		else:
			print("[smoke_input] 마우스 좌클릭 결정 OK -> guard")

	# ⑨ PauseMenu 연동 검증: can_open_on_cancel = false 확인 및 toggle 후 Esc 닫기
	var pause := PauseMenu.new()
	pause.allow_save = false
	pause.can_open_on_cancel = false
	pause.layer = 80
	add_child(pause)
	await get_tree().process_frame
	# 전투 중에는 보이지 않는 상태에서 Esc로 스스로 열리지 않아야 함
	var esc_ev3 := InputEventKey.new()
	esc_ev3.keycode = KEY_ESCAPE
	esc_ev3.pressed = true
	pause._unhandled_input(esc_ev3)
	if pause.visible:
		failures.append("can_open_on_cancel=false인데 Esc로 PauseMenu가 자동 오픈됨")
	# 수동 toggle 시 열리고, 열린 상태에서 Esc로 닫혀야 함
	pause.toggle()
	if not pause.visible:
		failures.append("PauseMenu toggle() 오픈 실패")
	pause._unhandled_input(esc_ev3)
	if pause.visible:
		failures.append("열린 PauseMenu에서 Esc 닫기 실패")
	else:
		print("[smoke_input] PauseMenu toggle 및 Esc 닫기 OK")
	pause.queue_free()

	_finish(failures)


## 액션 이벤트를 실제 입력 경로로 흘려보낸다(_unhandled_input까지 도달).
func _send(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("[smoke_input] PASS")
		get_tree().quit(0)
		return
	for f in failures:
		push_error("[smoke_input] FAIL %s" % f)
	get_tree().quit(1)
