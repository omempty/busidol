class_name SelfCheck
extends Node
## 자가 검증 러너 — 통합 지점 회귀 프루브(디버그 패널에서 실행).
## 원칙: 실행 전 상태를 저장하고 끝나면 복원한다. 씬 전환 없이 동기 검사만.
##
## 프루브 목록과 근거:
##  1) 전 층 맵 정의 로드            — 층 이동 직렬화의 기반
##  2) NPC 시퀀스 참조               — 대화 진입 시 push_warning 방지
##  3) 트리거 컷신/시퀀스 참조        — 이벤트 소실 조기 발견
##  4) 적 정의 커버리지              — 강제 전투/인카운터 유효 id 보장
##  5) 세이브 라운드트립             — Q1 회귀(smoke_save의 런타임판)
##  6) 트리거 done_flag 스킵 규약    — 8/25 실제 버그(F1 재방문 컷신 재생) 회귀 방지
##  7) 인벤토리 불변식               — add/remove/count 경계
##  8) 전층 착지 좌표 유효성(warn)    — transitions 오프셋과 맵 통행 정합(f0 격차 추적용)

const FLOORS := [1, 2, 3, 0, 4, 5]   # 마스터 시나리오 진행 순서


func run_all() -> PackedStringArray:
	var out := PackedStringArray()
	var fails := 0
	for res: Array in [
		_check_floors(),
		_check_npc_sequences(),
		_check_trigger_refs(),
		_check_enemy_defs(),
		_check_inventory(),
		_check_save_roundtrip(),
		_check_trigger_done_flag_skip(),
		_check_floor_landings(),
		_check_quest_flags(),
		_check_sequence_text_refs(),
	]:
		for line: String in res:
			out.append(line)
			if line.begins_with("[FAIL]"):
				fails += 1
	out.append("요약: %d건 실패 / %d라인" % [fails, out.size()])
	return out


func _ok(msg: String) -> Array:
	return ["[ok] " + msg]


func _fail(msg: String) -> Array:
	return ["[FAIL] " + msg]


func _check_floors() -> Array:
	var lines: Array = []
	for f: int in FLOORS:
		var def := MapDefinition.load_from_json("res://data/maps/f%d.json" % f)
		if def == null or def.width <= 0:
			lines += _fail("층 f%d 맵 로드 실패" % f)
		else:
			lines += _ok("f%d %dx%d" % [f, def.width, def.height])
	return lines


func _check_npc_sequences() -> Array:
	var lines: Array = []
	var bad := 0
	for f: int in FLOORS:
		var path := "res://data/maps/npcs_f%d.json" % f
		if not FileAccess.file_exists(path):
			lines += _ok("npcs_f%d 없음(스킵)" % f)
			continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(raw) != TYPE_DICTIONARY:
			lines += _fail("npcs_f%d 파싱 실패" % f)
			continue
		for n: Dictionary in raw.get("npcs", []):
			var seq := StringName(str(n.get("sequence_id", "")))
			if Database.sequence(seq).is_empty():
				bad += 1
				lines += _fail("NPC %s 시퀀스 없음: %s"
						% [str(n.get("id")), seq])
	if bad == 0:
		lines += _ok("모든 NPC 시퀀스 참조 유효")
	return lines


func _check_trigger_refs() -> Array:
	var lines: Array = []
	var bad := 0
	for f: int in FLOORS:
		var path := "res://data/maps/triggers_f%d.json" % f
		if not FileAccess.file_exists(path):
			continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(raw) != TYPE_DICTIONARY:
			lines += _fail("triggers_f%d 파싱 실패" % f)
			continue
		for t: Dictionary in raw.get("triggers", []):
			var action: Dictionary = t.get("action", {})
			if action.has("cutscene"):
				var cid := StringName(str(action["cutscene"]))
				if CutscenePlayer.load_cutscene(cid).is_empty():
					bad += 1
					lines += _fail("트리거 %s 컷신 없음: %s"
							% [str(t.get("id")), cid])
			elif action.has("sequence"):
				var sid := StringName(str(action["sequence"]))
				if Database.sequence(sid).is_empty():
					bad += 1
					lines += _fail("트리거 %s 시퀀스 없음: %s"
							% [str(t.get("id")), sid])
	if bad == 0:
		lines += _ok("모든 트리거 참조 유효")
	return lines


func _check_enemy_defs() -> Array:
	var lines: Array = []
	var bad := 0
	for eid_str: String in _all_species_ids():
		var def := Database.get_enemy_def(StringName(eid_str))
		if str(def.get("display_name")) == eid_str:
			bad += 1
			lines += _fail("종 정의 누락(폴백 반환): %s" % eid_str)
	for bid: String in _monsters_raw().get("bosses", {}).keys():
		var def := Database.get_enemy_def(StringName(bid))
		if str(def.get("display_name")) == bid:
			bad += 1
			lines += _fail("보스 정의 누락: %s" % bid)
	if bad == 0:
		lines += _ok("전 종족/보스 정의 유효")
	return lines


## monsters.json species 항목은 문자열 또는 {id,...} 딕셔너리 — id만 추출.
func _all_species_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for floor_data: Dictionary in _monsters_raw().get("floors", {}).values():
		for s: Variant in floor_data.get("species", []):
			if s is Dictionary:
				out.append(str(s.get("id", "")))
			else:
				out.append(str(s))
	return out


func _check_inventory() -> Array:
	var inv := Inventory.new()
	var probe := &"__selftest_item"
	inv.add(probe, 3)
	if inv.count(probe) != 3:
		return _fail("인벤 add/count 불일치")
	if not inv.remove(probe, 2) or inv.count(probe) != 1:
		return _fail("인벤 remove 부분차감 불일치")
	if inv.remove(probe, 9):
		return _fail("잔량 초과 remove가 true 반환")
	if inv.count(probe) != 1 or inv.is_empty():
		return _fail("초과 제거 실패 후 잔존분 보존 위반")
	inv.remove(probe, 1)
	if not inv.is_empty():
		return _fail("전량 차감 후 비어있지 않음")
	return _ok("인벤토리 불변식")


func _check_save_roundtrip() -> Array:
	var slot := SaveManager.SLOT_COUNT
	GameState.flags["__selftest_flag"] = true
	var money_before: int = int(GameState.player_stats["money"])
	SaveManager.save_slot(slot, "selfcheck")
	GameState.flags.erase("__selftest_flag")
	GameState.player_stats["money"] = money_before + 777
	if not SaveManager.load_slot(slot):
		SaveManager.delete_slot(slot)
		return _fail("세이브 라운드트립 로드 실패")
	var ok := GameState.has_flag("__selftest_flag") \
			and int(GameState.player_stats["money"]) == money_before
	SaveManager.delete_slot(slot)
	GameState.flags.erase("__selftest_flag")
	GameState.player_stats["money"] = money_before   # 라운드트립 전 값 복원
	return _ok("세이브 라운드트립") if ok else _fail("세이브 복원 불일치")


func _check_trigger_done_flag_skip() -> Array:
	# 8/25 버그 회귀 프루브: done_flag 설정 시 auto 트리거가 발동되지 않아야 한다.
	var had := GameState.has_flag("Q_F1_START")
	GameState.flags["Q_F1_START"] = true
	var ts := TriggerSystem.new()
	add_child(ts)
	ts.load_for_floor(1)
	var fired := [false]
	ts.cutscene_requested.connect(func(_cid: StringName) -> void:
		fired[0] = true)
	for _i in range(4):
		ts.tick(Vector2i.ZERO, 0.25)
	ts.queue_free()
	if not had:
		GameState.flags.erase("Q_F1_START")
	if fired[0]:
		return _fail("done_flag 설정 후에도 auto 트리거 발동(회귀!)")
	return _ok("트리거 done_flag 스킵 규약")


func _monsters_raw() -> Dictionary:
	var path := "res://data/monsters.json"
	if not FileAccess.file_exists(path):
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


## 착지 좌표 = transitions(anchor+offset)가 대상 맵에서 통행 가능해야 한다.
## 위반은 [warn] — 현재 f0가 원작 좌표공유 규약(04_game_systems §1.2)과 어긋난다.
func _check_floor_landings() -> Array:
	var lines: Array = []
	var path := "res://data/maps/transitions.json"
	if not FileAccess.file_exists(path):
		return _fail("transitions.json 없음")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		return _fail("transitions.json 파싱 실패")
	for t: Dictionary in raw.get("transitions", []):
		var delta := int(t.get("floor_delta", 0))
		var gmin := int(t.get("guard_min_floor", -99))
		var gmax := int(t.get("guard_max_floor", 99))
		var a: Array = t.get("anchor", [0, 0])
		var o: Array = t.get("spawn_offset", [0, 0])
		var land := Vector2i(int(a[0]) + int(o[0]), int(a[1]) + int(o[1]))
		var checked := {}
		for src in range(gmin, gmax + 1):
			var target := src + delta
			if checked.has(target):
				continue
			checked[target] = true
			var def := MapDefinition.load_from_json(
					"res://data/maps/f%d.json" % target)
			if def == null:
				lines += _fail("f%d 맵 없음(착지 검증 불가)" % target)
				continue
			if def.attr_at(land) != 0 and def.attr_at(land) != 2:
				lines.append("[warn] f%d 착지 %s 불통행 (%s)" %
						[target, land, str(t.get("id"))])
	if lines.any(func(l: String) -> bool: return l.begins_with("[FAIL]")):
		return lines
	if lines.is_empty():
		lines += _ok("전 전환 착지 좌표 통행")
	return lines


func _check_quest_flags() -> Array:
	var lines: Array = []
	var path := "res://data/quests_v2.json"
	if not FileAccess.file_exists(path):
		return _fail("quests_v2.json 없음")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		return _fail("quests_v2.json 파싱 실패")
		
	var quests: Array = raw.get("quests", [])
	var qmap := {}
	for q: Variant in quests:
		if q is Dictionary:
			var qid := str(q.get("id", ""))
			qmap[qid] = q
			
	var bad := 0
	for qid: String in qmap:
		var reqs: Variant = qmap[qid].get("requires", [])
		if reqs is String:
			reqs = [reqs]
		for r: Variant in reqs:
			if not qmap.has(str(r)):
				lines += _fail("퀘스트 %s의 선행 플래그 누락: %s" % [qid, str(r)])
				bad += 1

	var visited := {}
	var path_stack := {}
	var check_cycle: Callable
	check_cycle = func(node: String, f: Callable) -> bool:
		visited[node] = true
		path_stack[node] = true
		var rs: Variant = qmap.get(node, {}).get("requires", [])
		if rs is String: rs = [rs]
		for r: Variant in rs:
			var r_str := str(r)
			if not qmap.has(r_str): continue
			if path_stack.get(r_str, false):
				lines += _fail("퀘스트 체인 순환 발생: %s -> ... -> %s" % [node, r_str])
				return true
			if not visited.get(r_str, false):
				if f.call(r_str, f): return true
		path_stack[node] = false
		return false

	for qid: String in qmap:
		if not visited.get(qid, false):
			if check_cycle.call(qid, check_cycle):
				bad += 1

	if bad == 0:
		lines += _ok("퀘스트 플래그 체인 정합성 (순환/고아 없음)")
	return lines


func _check_sequence_text_refs() -> Array:
	var lines: Array = []
	var path_seq := "res://data/dialogue_sequences.json"
	var path_dial := "res://data/dialogue.json"
	
	if not FileAccess.file_exists(path_seq):
		return _fail("dialogue_sequences.json 없음")
	if not FileAccess.file_exists(path_dial):
		return _fail("dialogue.json 없음")
		
	var raw_seq: Variant = JSON.parse_string(FileAccess.get_file_as_string(path_seq))
	var raw_dial: Variant = JSON.parse_string(FileAccess.get_file_as_string(path_dial))
	
	if typeof(raw_seq) != TYPE_DICTIONARY:
		return _fail("dialogue_sequences.json 파싱 실패")
	if typeof(raw_dial) != TYPE_DICTIONARY:
		return _fail("dialogue.json 파싱 실패")
		
	var sequences: Dictionary = raw_seq.get("sequences", {})
	var bad := 0
	for seq_id: String in sequences:
		var seq: Dictionary = sequences[seq_id]
		var steps: Array = seq.get("steps", [])
		for step: Variant in steps:
			if not step is Dictionary: continue
			var text: String = step.get("text", "")
			if text.begins_with("@"):
				if not raw_dial.has(text):
					lines += _fail("시퀀스 '%s'에서 존재하지 않는 대사 참조: %s" % [seq_id, text])
					bad += 1
					
	if bad == 0:
		lines += _ok("모든 시퀀스 대사 참조 유효")
	return lines
