extends Node
## 세이브 스모크 — 저장→변형→복원 라운드트립 + 오토세이브 요청 흐름 검증. Phase 9.
## 실행:
##   godot --headless --path . res://tests/smoke_save.tscn
## 종료코드 0=PASS / 1=FAIL

const SLOT := SaveManager.SLOT_COUNT   # 수동 슬롯 마지막 칸 사용(테스트 전용 파일)


func _ready() -> void:
	var failures: Array[String] = []

	# 테스트용 user:// 파일 정리(이전 실행 잔재)
	SaveManager.delete_slot(SLOT)

	# 1) 상태 구성 → 저장
	GameState.reset()
	GameState.current_floor = 3
	GameState.set_flag("q_f1_prolog_done", true)
	GameState.player_stats["level"] = 7
	GameState.player_stats["money"] = 4321
	GameState.player_cell = Vector2i(12, 8)
	GameState.inventory.add(&"potion", 3)
	GameState.set_chest_override(Vector2i(5, 5), 1)
	SaveManager.save_slot(SLOT, "스모크")

	# 2) 상태 변형 후 복원
	GameState.reset()
	if GameState.has_flag("q_f1_prolog_done"):
		failures.append("reset 후 플래그 잔존")
	if not SaveManager.load_slot(SLOT):
		failures.append("load_slot 실패")

	# 3) 복원 결과 대조
	if GameState.current_floor != 3:
		failures.append("floor=%d != 3" % GameState.current_floor)
	if not GameState.has_flag("q_f1_prolog_done"):
		failures.append("플래그 미복원")
	if int(GameState.player_stats["level"]) != 7 \
			or int(GameState.player_stats["money"]) != 4321:
		failures.append("스탯 미복원: %s" % str(GameState.player_stats))
	if GameState.player_cell != Vector2i(12, 8):
		failures.append("좌표 미복원: %s" % str(GameState.player_cell))
	if not GameState.inventory.has(&"potion") \
			or GameState.inventory.count(&"potion") != 3:
		failures.append("인벤 미복원")
	var cells := GameState.chest_overrides_for(3)
	if cells.get(Vector2i(5, 5), -1) != 1:
		failures.append("상자 오버라이드 미복원: %s" % str(cells))

	# 4) 메타/오토 요청 API
	var meta := SaveManager.slot_meta(SLOT)
	if meta.is_empty() or int(meta["floor"]) != 3 or str(meta["note"]) != "스모크":
		failures.append("슬롯 메타 이상: %s" % str(meta))
	SaveManager.request_autosave("테스트")
	SaveManager.consume_autosave()
	var auto_meta := SaveManager.slot_meta(SaveManager.AUTO_SLOT)
	if auto_meta.is_empty():
		failures.append("오토세이브 미기록")

	# 정리 — 테스트가 만든 파일은 남기지 않는다
	SaveManager.delete_slot(SLOT)
	SaveManager.delete_slot(SaveManager.AUTO_SLOT)

	if failures.is_empty():
		print("[smoke_save] PASS - save/load roundtrip ok")
		get_tree().quit(0)
	else:
		for f in failures:
			push_error("[smoke_save] " + f)
		get_tree().quit(1)
