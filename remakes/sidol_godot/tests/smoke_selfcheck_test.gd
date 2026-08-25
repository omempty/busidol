extends Node
## 자가검증 스모크 — SelfCheck 프루브 전부 통과 확인(디버그 패널과 동일 로직).
## 실행: godot --headless --path . res://tests/smoke_selfcheck.tscn  (exit 0=PASS)

const TIMEOUT_S := 20.0


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_S).timeout.connect(func() -> void:
		push_error("[smoke_selfcheck] WATCHDOG timeout")
		get_tree().quit(1))
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
