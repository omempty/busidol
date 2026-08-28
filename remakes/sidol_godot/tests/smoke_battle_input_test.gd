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
