class_name MapRuntime
extends RefCounted
## 런타임 맵 쿼리 + 오버라이드 계층 — 맵 원본은 불변, 변경만 기록 (02_design/01 §3.3).
## 통행 규칙: ATT 0(PASSABLE)·2(OVERHEAD)만 통과. 그 외(벽/NPC ID/상자/방 ID) 차단.

var definition: MapDefinition
var overrides := {}  # Vector2i -> {"attr": int}


func _init(def: MapDefinition) -> void:
	definition = def


## 이 칸의 **지금** ATT — 오버라이드가 있으면 그쪽이 답이다.
##
## 원본(`definition`)을 직접 읽으면 **연 상자가 그대로 상자로 보인다.** 실제로 필드가
## 그렇게 읽고 있어 같은 상자를 몇 번이고 다시 열 수 있었고(아이템·돈 무한 지급),
## 게다가 앞 상자가 같은 줄 뒤쪽 상자를 가려 그쪽은 영영 못 열었다
## (2026-08-29 자동 주행 실측 — f0에서 4덩어리, docs/05_status/01_autoplay.md).
func attr_at(cell: Vector2i) -> int:
	if overrides.has(cell):
		return int(overrides[cell]["attr"])
	return definition.attr_at(cell)


func is_passable(cell: Vector2i) -> bool:
	if not definition.in_bounds(cell):
		return false
	var a := attr_at(cell)
	return a == 0 or a == 2


func set_override_attr(cell: Vector2i, attr_value: int) -> void:
	overrides[cell] = {"attr": attr_value}
