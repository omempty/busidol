extends Node
## 슬롯 세이브/오토세이브 — 원작 io()가 안내문만 출력하던 미구현 기능(Q1)의 신규 구현. Phase 9.

const SLOT_COUNT := 3


func save_slot(slot: int) -> void:
	push_warning("SaveManager.save_slot() 미구현(Phase 9): slot=%d" % slot)


func load_slot(slot: int) -> void:
	push_warning("SaveManager.load_slot() 미구현(Phase 9): slot=%d" % slot)
