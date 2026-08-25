class_name TriggerSystem
extends Node
## 이벤트 트리거 — zone(셀 진입) / interact(전방 SPACE) / auto(층 진입 즉시).
## 데이터: data/maps/triggers_f<층>.json (docs/02_design/05_toolchain_editors.md §3.1 준용)
## 발동 결과는 시그널로 통지 — 씬(field)이 컷신·대화를 실행한다.

signal cutscene_requested(cutscene_id: StringName)
signal sequence_requested(sequence_id: StringName)

const AUTO_TICK_DELAY := 0.2   # auto 판정을 첫 물리 프레임에 몰아주지 않기 위한 지연

var _triggers: Array = []
var _fired: Dictionary = {}
var _elapsed := 0.0
var _auto_checked := false


func load_for_floor(floor_no: int) -> void:
	_triggers.clear()
	_fired.clear()
	_auto_checked = false
	var path := "res://data/maps/triggers_f%d.json" % floor_no
	if not FileAccess.file_exists(path):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("트리거 파일 파싱 실패: %s" % path)
		return
	_triggers = raw.get("triggers", [])


## zone/auto 트리거 — 매물리틱에 플레이어 셀과 함께 호출
func tick(player_cell: Vector2i, delta: float) -> void:
	_elapsed += delta
	for t: Dictionary in _triggers:
		if _consumed(t):
			continue
		match str(t.get("type", "")):
			"auto":
				if _auto_checked and _elapsed > AUTO_TICK_DELAY:
					_fire(t)
			"zone":
				if _in_zone(t, player_cell):
					_fire(t)
	_auto_checked = true


## interact 트리거 — 전방 셀 목록과 대조. 소비했으면 true.
func try_interact(front_cells: Array[Vector2i]) -> bool:
	for t: Dictionary in _triggers:
		if _consumed(t) or str(t.get("type", "")) != "interact":
			continue
		var cells := _trigger_cells(t)
		for c in front_cells:
			if c in cells:
				_fire(t)
				return true
	return false


func _consumed(t: Dictionary) -> bool:
	if bool(t.get("once", true)) and _fired.has(str(t["id"])):
		return true
	# done_flag 규약(triggers_f*.json 주석): 설정된 플래그면 재발동 없음
	var done := str(t.get("done_flag", ""))
	if not done.is_empty() and GameState.has_flag(done):
		return true
	var req: Variant = t.get("requires_flag")
	if req != null and not GameState.has_flag(str(req)):
		return true
	return false


func _trigger_cells(t: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for a: Variant in t.get("cells", []):
		out.append(Vector2i(int(a[0]), int(a[1])))
	return out


func _in_zone(t: Dictionary, cell: Vector2i) -> bool:
	for c in _trigger_cells(t):
		if c == cell:
			return true
	return false


func _fire(t: Dictionary) -> void:
	_fired[str(t["id"])] = true
	var done := str(t.get("done_flag", ""))
	if not done.is_empty():
		GameState.set_flag(done, true)
	var action: Dictionary = t.get("action", {})
	if action.has("cutscene"):
		cutscene_requested.emit(StringName(str(action["cutscene"])))
	elif action.has("sequence"):
		sequence_requested.emit(StringName(str(action["sequence"])))
