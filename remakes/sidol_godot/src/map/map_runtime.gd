class_name MapRuntime
extends RefCounted
## 런타임 맵 쿼리 + 오버라이드 계층 — 맵 원본은 불변, 변경만 기록 (02_design/01 §3.3).
## 통행 규칙: ATT 0(PASSABLE)·2(OVERHEAD)만 통과. 그 외(벽/NPC ID/상자/방 ID) 차단.


var definition: MapDefinition
var overrides := {}  # Vector2i -> {"attr": int}


func _init(def: MapDefinition) -> void:
	definition = def


func is_passable(cell: Vector2i) -> bool:
	if not definition.in_bounds(cell):
		return false
	if overrides.has(cell):
		var a: int = int(overrides[cell]["attr"])
		return a == 0 or a == 2
	var raw: int = definition.attr_at(cell)
	return raw == 0 or raw == 2


func set_override_attr(cell: Vector2i, attr_value: int) -> void:
	overrides[cell] = {"attr": attr_value}
