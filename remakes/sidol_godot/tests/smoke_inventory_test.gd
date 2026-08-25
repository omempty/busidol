extends Node
## 인벤토리 스모크 — 패널 개방/월드 정지/목록 행/커서·상세 갱신/정지 복원 자동 검증.
## 실행: godot --headless --path . res://tests/smoke_inventory.tscn   (exit 0=PASS)


func _ready() -> void:
	get_tree().create_timer(15.0).timeout.connect(func() -> void:
		push_error("[smoke_inv] WATCHDOG timeout")
		get_tree().quit(1))
	var failures: Array[String] = []
	var panel := InventoryPanel.new()
	add_child(panel)

	GameState.inventory.clear()
	panel.open()
	if not panel.visible or not get_tree().paused:
		failures.append("개방 시 visible/paused 미설정")
	panel.close()
	if panel.visible or get_tree().paused:
		failures.append("닫기 후 정지 해제 안 됨")

	for id in ["potion", "ITEM_WEAPON_DANDO", "reagent_drag"]:
		GameState.inventory.add(StringName(id), 2)
	panel.open()
	if get_tree().paused != true:
		failures.append("재개방 paused 실패")
	var rows := panel._list_box.get_children().size()
	if rows < 3:
		failures.append("목록 행 부족: %d" % rows)
	panel._index = 1
	panel._move(1)   # 커서 이동 + 상세 갱신
	if panel._detail_name.text.is_empty():
		failures.append("상세 이름 공백")
	panel.close()

	if failures.is_empty():
		print("[smoke_inv] PASS")
		get_tree().quit(0)
	else:
		push_error("[smoke_inv] FAIL: " + "; ".join(failures))
		get_tree().quit(1)
