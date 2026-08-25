extends Node
## choice op 스모크 — 선택 UI 분기 수렴 검증 (WP-5 스파이크).
## 실행: godot --headless --path . --quit-after 3600 res://tests/smoke_choice.tscn
## 입력은 parse_input_event(실제 이벤트 전파)로 시뮬레이션한다.

const PLAYER := preload("res://src/cutscene/cutscene_player.gd")

const FIXTURE := {
	"id": "smoke_choice",
	"steps":
	[
		{
			"op": "choice",
			"args":
			{
				"options":
				[
					{"text": "@c520", "steps": [{"op": "set_flags", "args": {"__choice_a": true}}]},
					{"text": "@c531", "steps": [{"op": "set_flags", "args": {"__choice_b": true}}]},
				]
			}
		},
		{"op": "set_flags", "args": {"__converged": true}},
	],
}


func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(
		func() -> void:
			push_error("[smoke_choice] WATCHDOG")
			get_tree().quit(1)
	)
	GameState.flags["__choice_a"] = false
	GameState.flags["__choice_b"] = false
	GameState.flags["__converged"] = false

	var player: CutscenePlayer = PLAYER.new()
	add_child(player)
	player.play(FIXTURE)

	# 선택 UI 뜰 때까지 대기
	var ui: Control = null
	for _f in range(300):
		await get_tree().process_frame
		for child in player.get_children():
			if child is Control and child.has_signal("picked"):
				ui = child
				break
		if ui != null:
			break
	if ui == null:
		push_error("[smoke_choice] FAIL: choice UI 미표출")
		get_tree().quit(1)
		return

	# ↓ 한 칸(옵션 B) → Enter 확정
	_tap_key(KEY_DOWN)
	await get_tree().process_frame
	_tap_key(KEY_ENTER)

	var done := await _wait_finished(player, 5.0)
	if not done:
		push_error("[smoke_choice] FAIL: 컷신 미종료(수렴 실패)")
		get_tree().quit(1)
		return

	var ok_b: bool = GameState.has_flag("__choice_b")
	var no_a: bool = not GameState.has_flag("__choice_a")
	var conv: bool = GameState.has_flag("__converged")
	if ok_b and no_a and conv:
		print("[smoke_choice] PASS - B 선택·수렴 확인")
		get_tree().quit(0)
	else:
		push_error("[smoke_choice] FAIL b=%s a=%s conv=%s" % [ok_b, no_a, conv])
		get_tree().quit(1)


func _tap_key(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	var rel := InputEventKey.new()
	rel.keycode = keycode
	rel.physical_keycode = keycode
	rel.pressed = false
	Input.parse_input_event(rel)


func _wait_finished(player: CutscenePlayer, timeout: float) -> bool:
	var done := [false]
	player.finished.connect(func(_id: StringName) -> void: done[0] = true)
	var t := 0.0
	while t < timeout:
		if done[0]:
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return done[0]
