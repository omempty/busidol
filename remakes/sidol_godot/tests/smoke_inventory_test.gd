extends Node
## 캐릭터 메뉴 스모크 — 개방/월드 정지/아이템 그리드/커서·상세 갱신/정지 복원 +
## **탭 4장이 전부 그려지는가**(2026-08-30 탭형 재구성, 04_uiux §1.3).
## 실행: godot --headless --path . res://tests/smoke_inventory.tscn   (exit 0=PASS)


func _ready() -> void:
	get_tree().create_timer(15.0).timeout.connect(
		func() -> void:
			push_error("[smoke_inv] WATCHDOG timeout")
			get_tree().quit(1)
	)
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
	var cells := panel._grid.get_children().size()
	if cells < 3:
		failures.append("아이템 그리드 칸 부족: %d" % cells)
	panel._index = 1
	panel._move(1)  # 커서 이동 + 상세 갱신
	if panel._detail_name.text.is_empty():
		failures.append("상세 이름 공백")

	# 탭 4장 — 각 탭이 실제로 내용을 그리는가(빈 탭은 「있는데 안 보이는」 자리가 된다)
	panel._set_tab(InventoryPanel.Tab.GEAR)
	if panel._gear_box.get_child_count() < 2:
		failures.append("장비 탭 비어 있음")
	panel._set_tab(InventoryPanel.Tab.STATUS)
	if panel._status_box.get_child_count() < 5:
		failures.append("상태 탭 항목 부족: %d" % panel._status_box.get_child_count())
	panel._set_tab(InventoryPanel.Tab.SYSTEM)
	if panel._system_box.get_child_count() != InventoryPanel.SYSTEM_ITEMS.size():
		failures.append("시스템 탭 항목 수 불일치")
	var got := {"v": &""}
	panel.system_requested.connect(func(a: StringName) -> void: got.v = a)
	panel._sub_index = 0
	panel._confirm()
	if got.v != &"save":
		failures.append("시스템 탭이 신호를 안 보냈다: %s" % got.v)
	print("[smoke_inv] 그리드 %d칸 · 탭 4장 · 시스템 신호 %s" % [cells, got.v])
	panel.close()

	if failures.is_empty():
		print("[smoke_inv] PASS")
		get_tree().quit(0)
	else:
		push_error("[smoke_inv] FAIL: " + "; ".join(failures))
		get_tree().quit(1)
