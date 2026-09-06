extends Node
## 슬롯 세이브/오토세이브 — 원작 io()가 안내문만 출력하던 미구현 기능(Q1)의 실구현. Phase 9.
## 파일: user://save_auto.json + user://save_slot_1..3.json (사람이 읽는 JSON).
##
## 오토세이브 흐름(층 이동·전투 승리): 전투/게이트가 request_autosave()만 걸고,
## 필드 씬이 준비된 뒤 consume_autosave()가 실행한다 — 플레이어 좌표 확정 보장.

const SLOT_COUNT := 3
const SAVE_VERSION := 1
const AUTO_SLOT := 0  # 0=오토세이브, 1..3=수동 슬롯

var _autosave_reason := ""  # 비어있지 않으면 다음 필드 진입 시 오토세이브


func _slot_path(slot: int) -> String:
	if slot == AUTO_SLOT:
		return "user://save_auto.json"
	return "user://save_slot_%d.json" % slot


## 층 이동·전투 종료 측에서 호출 — 실제 기록은 필드 진입 후로 미룬다.
func request_autosave(reason: String) -> void:
	_autosave_reason = reason


## field._ready 마지막에 호출 — 대기 중 오토세이브를 실행(좌표 확정 후).
func consume_autosave() -> void:
	if _autosave_reason.is_empty():
		return
	var reason := _autosave_reason
	_autosave_reason = ""
	save_slot(AUTO_SLOT, reason)


func save_slot(slot: int, note: String = "") -> void:
	var data := _snapshot()
	data["note"] = note
	var fh := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if fh == null:
		push_error("세이브 실패 slot=%d: %s" % [slot, FileAccess.get_open_error()])
		return
	fh.store_string(JSON.stringify(data, "\t"))
	print("[save] slot=%d 기록 (%s)" % [slot, str(data["saved_at"])])


## GameState로 복원. 성공 시 호출자가 필드 씬으로 전환한다.
func load_slot(slot: int) -> bool:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("세이브 손상 slot=%d" % slot)
		return false
	var data: Dictionary = raw
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("세이브 버전 불일치 slot=%d (%s)" % [slot, str(data.get("version"))])
		return false
	_apply(data)
	print("[save] slot=%d 복원 (floor=%d)" % [slot, GameState.current_floor])
	return true


func delete_slot(slot: int) -> bool:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


## 슬롯 목록 UI용 메타. 빈 슬롯이면 빈 Dictionary.
func slot_meta(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = raw
	var stats: Dictionary = data.get("player_stats", {})
	return {
		"floor": int(data.get("floor", 1)),
		"level": int(stats.get("level", 1)),
		"money": int(stats.get("money", 0)),
		"saved_at": str(data.get("saved_at", "")),
		"note": str(data.get("note", "")),
	}


func has_any_save() -> bool:
	for slot in range(0, SLOT_COUNT + 1):
		if FileAccess.file_exists(_slot_path(slot)):
			return true
	return false


## ---- 스냅샷 / 복원 ----


func _snapshot() -> Dictionary:
	var chests := {}
	for floor_key: int in GameState.chest_overrides:
		var cells := {}
		for cell: Vector2i in GameState.chest_overrides[floor_key]:
			cells["%d,%d" % [cell.x, cell.y]] = int(GameState.chest_overrides[floor_key][cell])
		chests[str(floor_key)] = cells
	return {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"floor": GameState.current_floor,
		"player_cell": [GameState.player_cell.x, GameState.player_cell.y],
		"player_stats": GameState.player_stats.duplicate(),
		"inventory": GameState.inventory.to_data(),
		"flags": GameState.flags.duplicate(),
		"chest_overrides": chests,
		"visited_floors": GameState.visited_list(),
		"equipped": GameState.equipped.duplicate(),
		"owned_skills": GameState.owned_skill_ids(),
		# 들은 대사 기록 — 이게 빠져 있어서 불러오면 모든 NPC가 첫 만남으로 되돌아갔다.
		# 13차 세션이 넣은 반복/밈 순환(시퀀스 91종)이 통째로 초기화되던 자리다.
		"npc_seen_sequences": GameState.npc_seen_sequences.duplicate(),
	}


func _apply(data: Dictionary) -> void:
	GameState.current_floor = int(data.get("floor", 1))
	GameState.equipped = (data.get("equipped", {}) as Dictionary).duplicate()
	GameState.owned_skills = {}
	for sid: Variant in data.get("owned_skills", []):
		GameState.owned_skills[str(sid)] = true
	GameState.init_skills()  # 구 세이브(스킬 미기록) 호환 — 비어 있으면 기본값
	GameState.visited_floors = {}
	for f: Variant in data.get("visited_floors", []):
		GameState.visited_floors[int(f)] = true
	var cell_arr: Array = data.get("player_cell", [-1, -1])
	GameState.player_cell = Vector2i(int(cell_arr[0]), int(cell_arr[1]))
	var saved_stats: Dictionary = data.get("player_stats", {})
	for key: String in GameState.player_stats:
		GameState.player_stats[key] = int(saved_stats.get(key, GameState.player_stats[key]))
	GameState.inventory.restore(data.get("inventory", []))
	var flags_v: Variant = data.get("flags", {})
	GameState.flags = flags_v if typeof(flags_v) == TYPE_DICTIONARY else {}
	GameState.chest_overrides = {}
	var chests: Dictionary = data.get("chest_overrides", {})
	for floor_str: String in chests:
		var cells := {}
		for cell_str: String in chests[floor_str]:
			var parts := cell_str.split(",")
			cells[Vector2i(int(parts[0]), int(parts[1]))] = int(chests[floor_str][cell_str])
		GameState.chest_overrides[int(floor_str)] = cells
	# 구 세이브(이 키가 없던 시절)는 빈 기록으로 시작한다 — 첫 만남 대사부터 다시.
	var seen_v: Variant = data.get("npc_seen_sequences", {})
	GameState.npc_seen_sequences = {}
	if typeof(seen_v) == TYPE_DICTIONARY:
		for k: Variant in Dictionary(seen_v):
			GameState.npc_seen_sequences[str(k)] = int(Dictionary(seen_v)[k])
	GameState.pending_encounter = {}
	GameState.state_changed.emit()
