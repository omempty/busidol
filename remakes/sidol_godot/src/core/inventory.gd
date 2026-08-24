class_name Inventory
extends RefCounted
## 인벤토리 — 원작 view[50]의 OOP 대체. 중첩 지원, 시그널 발행.

signal changed

var _slots: Array[Dictionary] = []   # [{"item_id": StringName, "count": int}]


func add(item_id: StringName, count: int = 1) -> void:
	if count <= 0:
		return
	for slot in _slots:
		if slot["item_id"] == item_id:
			slot["count"] += count
			changed.emit()
			return
	_slots.append({"item_id": item_id, "count": count})
	changed.emit()


func remove(item_id: StringName, count: int = 1) -> bool:
	for i in _slots.size():
		if _slots[i]["item_id"] == item_id:
			if _slots[i]["count"] >= count:
				_slots[i]["count"] -= count
				if _slots[i]["count"] <= 0:
					_slots.remove_at(i)
				changed.emit()
				return true
	return false


func count(item_id: StringName) -> int:
	for s in _slots:
		if s["item_id"] == item_id:
			return int(s["count"])
	return 0


func has(item_id: StringName) -> bool:
	return count(item_id) > 0


func is_empty() -> bool:
	return _slots.is_empty()


func total_items() -> int:
	var t := 0
	for s in _slots:
		t += int(s["count"])
	return t


func all_slots() -> Array[Dictionary]:
	return _slots.duplicate(true)


func clear() -> void:
	_slots.clear()
	changed.emit()
