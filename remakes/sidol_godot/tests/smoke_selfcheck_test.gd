extends Node
## 자가검증 스모크 — SelfCheck 프루브 전부 통과 확인(디버그 패널과 동일 로직).
## 실행: godot --headless --path . res://tests/smoke_selfcheck.tscn  (exit 0=PASS)

const TIMEOUT_S := 20.0


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_S).timeout.connect(
		func() -> void:
			push_error("[smoke_selfcheck] WATCHDOG timeout")
			get_tree().quit(1)
	)
	var pm := PauseMenu.new()
	add_child(pm)
	print("--- PAUSE MENU DIAGNOSTICS ---")
	print("pm.visible: ", pm.visible)
	print(
		"pm._root_box.visible: ",
		pm._root_box.visible,
		" in_tree: ",
		pm._root_box.is_visible_in_tree()
	)
	print(
		"pm._settings_panel.visible: ",
		pm._settings_panel.visible,
		" in_tree: ",
		pm._settings_panel.is_visible_in_tree()
	)
	var s_frame: Control = pm._settings_panel.get_child(0) as Control
	print("s_frame.visible: ", s_frame.visible, " in_tree: ", s_frame.is_visible_in_tree())
	var s_dim: Control = s_frame.get_node("Dim") as Control
	print(
		"s_dim.visible: ",
		s_dim.visible,
		" in_tree: ",
		s_dim.is_visible_in_tree(),
		" mouse_filter: ",
		s_dim.mouse_filter
	)
	pm.queue_free()
	print("--------------------------------")

	var checker := SelfCheck.new()
	add_child(checker)
	var report := checker.run_all()
	checker.queue_free()
	for line in report:
		print("[selfcheck] ", line)
	for line in report:
		if line.begins_with("[FAIL]"):
			push_error("[smoke_selfcheck] FAIL: " + line)
			get_tree().quit(1)
			return
	print("[smoke_selfcheck] PASS")
	get_tree().quit(0)
