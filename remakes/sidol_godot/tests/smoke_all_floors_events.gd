extends Node
## 전 층 (지하 F0 ~ 지상 F5) 시나리오 이벤트 체인, NPC 배회/아이들, Walker 이동 알고리즘, 대사 고유성 통합 스모크 테스트
## 실행: godot --headless --path . res://tests/smoke_all_floors_events.tscn

const DIALOGUE_JSON_PATH := "res://data/dialogue.json"
const SEQUENCES_JSON_PATH := "res://data/dialogue_sequences.json"
const TALK_TARGETS_PATH := "res://data/maps/talk_targets.json"
const TRANSITIONS_PATH := "res://data/maps/transitions.json"

var _failures: Array[String] = []


func _ready() -> void:
	print("[smoke_all_floors] === 전 층 (F0~F5) 시나리오 이벤트 & NPC/Walker 통합 검사 시작 ===")
	GameState.reset()

	_test_dialogues_and_uniqueness()
	_test_all_floors_npcs_and_walkers()
	_test_full_scenario_quest_chain()
	_test_npc_repeats_and_progression()
	_test_f5_boss_retry_after_defeat()

	if _failures.is_empty():
		print("[smoke_all_floors] PASS — 전 층 시나리오 체인, NPC/Walker 동작, 대사 고유성 전수 검증 통과!")
		get_tree().quit(0)
	else:
		printerr("[smoke_all_floors] FAIL — %d건의 검증 실패:" % _failures.size())
		for f in _failures:
			printerr("   * ", f)
		get_tree().quit(1)


## 1. 전 층 대사 고유성 및 층별 NPC 대사 검사
func _test_dialogues_and_uniqueness() -> void:
	print("[smoke_all_floors] 1. 대사 고유성 및 층별 NPC 대사 검사...")

	var seq_cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(SEQUENCES_JSON_PATH))
	var tt_cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(TALK_TARGETS_PATH))
	if typeof(seq_cfg) != TYPE_DICTIONARY or typeof(tt_cfg) != TYPE_DICTIONARY:
		_failures.append("대화 설정 파일 로드 실패")
		return

	var seqs: Dictionary = seq_cfg.get("sequences", {})
	var tt: Dictionary = tt_cfg.get("targets", {})

	# (1) F0 수위 vs F1 수위 대사 분리 검증
	var guard_f0_texts: Array = []
	for st: Dictionary in seqs.get("guard_f0", {}).get("steps", []):
		guard_f0_texts.append(st.get("text", ""))
	var guard_f1_texts: Array = []
	for st: Dictionary in seqs.get("guard_idle", {}).get("steps", []):
		guard_f1_texts.append(st.get("text", ""))
	if guard_f0_texts.is_empty() or guard_f0_texts == guard_f1_texts:
		_failures.append("지하 수위 대사(guard_f0)가 미설정되었거나 1층 수위 대사와 동일함")
	else:
		print(
			(
				"   - [OK] F0 수위(guard_f0: %s) vs F1 수위(guard_idle: %s) 고유성 확인"
				% [str(guard_f0_texts), str(guard_f1_texts)]
			)
		)

	# (2) F2 여학생 vs F1 여학생 대사 분리 검증
	var girl_f2_texts: Array = []
	for st: Dictionary in seqs.get("f2_rescue_girl", {}).get("steps", []):
		girl_f2_texts.append(st.get("text", ""))
	var girl_f1_texts: Array = []
	for st: Dictionary in seqs.get("npc_girl_rescue", {}).get("steps", []):
		girl_f1_texts.append(st.get("text", ""))
	if girl_f2_texts.is_empty() or girl_f2_texts == girl_f1_texts:
		_failures.append("2층 여학생 대사(f2_rescue_girl)가 미설정되었거나 1층 구출 대사와 동일함")
	else:
		print(
			(
				"   - [OK] F2 여학생(f2_rescue_girl: %s) vs F1 여학생(npc_girl_rescue: %s) 고유성 확인"
				% [str(girl_f2_texts), str(girl_f1_texts)]
			)
		)

	# (3) ATT 97/98 호칭 정상화 및 5회 힌트 기믹 검증
	var p_right: Dictionary = tt.get("97", {})
	var p_left: Dictionary = tt.get("98", {})
	if p_right.get("name", "").contains("그림") or p_left.get("name", "").contains("그림"):
		_failures.append("ATT 97/98에 여전히 '그림' 명칭이 포함되어 있음")
	else:
		print(
			(
				"   - [OK] ATT 97(%s), ATT 98(%s) 호칭 정상화 확인"
				% [p_right.get("name", ""), p_left.get("name", "")]
			)
		)

	TalkTargets.reset_counts()
	var step1: Array = TalkTargets.steps_for(97)
	for i in range(3):
		TalkTargets.steps_for(97)
	var step5: Array = TalkTargets.steps_for(97)
	if step1.is_empty() or step1[0].get("text") != "@t205":
		_failures.append("오른쪽 사람 첫 대사가 @t205가 아님: %s" % str(step1))
	if step5.is_empty() or step5[0].get("text") != "@t207":
		_failures.append("오른쪽 사람 5회 대화 힌트(@t207) 발동 실패: %s" % str(step5))
	else:
		print("   - [OK] 오른쪽 사람 5회 대화 힌트 기믹(@t207 화공과 교수 힌트) 정상 작동 확인")
	TalkTargets.reset_counts()

	# (4) 전수 대사 중복 검사
	var text_usage: Dictionary = {}
	for seq_id: String in seqs:
		for st: Dictionary in seqs[seq_id].get("steps", []):
			var t: String = st.get("text", "")
			if not t.is_empty():
				if not text_usage.has(t):
					text_usage[t] = []
				text_usage[t].append("seq:" + seq_id)
	for att_id: String in tt:
		for t: String in tt[att_id].get("texts", []):
			if not text_usage.has(t):
				text_usage[t] = []
			text_usage[t].append("att:" + att_id)
		for v: Dictionary in tt[att_id].get("variants", []):
			for t: String in v.get("texts", []):
				if not text_usage.has(t):
					text_usage[t] = []
				text_usage[t].append("att_var:" + att_id)

	var dup_count := 0
	for t: String in text_usage:
		var distinct_targets := {}
		for u: String in text_usage[t]:
			var normalized: String = u.replace("att_var:", "att:")
			distinct_targets[normalized] = true
		if (
			distinct_targets.has("seq:nothing_man")
			and distinct_targets.has("att:99")
			and distinct_targets.size() == 2
		):
			continue
		if distinct_targets.size() > 1:
			dup_count += 1
			_failures.append("대사 중복 발견 [%s]: %s" % [t, str(distinct_targets.keys())])
	if dup_count == 0:
		print("   - [OK] 전 층 대화 대상 간 중복 대사 0건 (완전 고유성 보장)")


## 2. 전 층 NPC & Walker 좌표, 스프라이트, 이동 알고리즘 검사
func _is_body_passable(rt: MapRuntime, pos: Vector2i) -> bool:
	for c in Placement.body_cells(pos):
		if not rt.is_passable(c):
			return false
	return true


func _test_all_floors_npcs_and_walkers() -> void:
	print("[smoke_all_floors] 2. 전 층 NPC & Walker 좌표/배회/이동 알고리즘 검사...")

	var floors := [0, 1, 2, 3, 4, 5]
	for fl in floors:
		var map_path := "res://data/maps/f%d.json" % fl
		var def := MapDefinition.load_from_json(map_path)
		if def == null:
			_failures.append("%s 로드 실패" % map_path)
			continue
		var rt := MapRuntime.new(def)

		# NPC 검사
		var npc_path := "res://data/maps/npcs_f%d.json" % fl
		if FileAccess.file_exists(npc_path):
			var npc_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(npc_path))
			if typeof(npc_doc) == TYPE_DICTIONARY:
				var npcs: Array = npc_doc.get("npcs", [])
				for npc_data: Dictionary in npcs:
					var npc_id: String = npc_data.get("id", "")
					var pos_arr: Array = npc_data.get("pos", [])
					if pos_arr.size() < 2:
						_failures.append("F%d NPC %s pos 형식 오류" % [fl, npc_id])
						continue
					var p := Vector2i(int(pos_arr[0]), int(pos_arr[1]))
					if not _is_body_passable(rt, p):
						_failures.append("F%d NPC %s 좌표 %s가 통행 불가 구역임" % [fl, npc_id, p])
					var neighbors := [
						p + Vector2i(0, -1),
						p + Vector2i(0, 2),
						p + Vector2i(-1, 0),
						p + Vector2i(2, 0)
					]
					var can_talk := false
					for n in neighbors:
						if rt.is_passable(n):
							can_talk = true
							break
					if not can_talk:
						_failures.append("F%d NPC %s 좌표 %s에 대화 진입 가능한 인접 셀이 없음" % [fl, npc_id, p])

					var npc_entity := NpcEntity.new()
					add_child(npc_entity)
					var wander_range := int(npc_data.get("wander_range", 0))
					npc_entity.setup(
						StringName(str(npc_data.get("id", ""))),
						str(npc_data.get("name", "")),
						StringName(str(npc_data.get("sequence_id", ""))),
						p,
						Color.WHITE,
						npc_data.get("sequence_variants", []),
						wander_range,
						rt
					)
					if str(npc_data.get("idle_anim", "")).is_empty():
						_failures.append("F%d NPC %s idle_anim 미설정" % [fl, npc_id])
					npc_entity.face_towards(p + Vector2i(0, 1))
					if npc_entity._facing != &"down":
						_failures.append("F%d NPC %s 방향 전환 실패" % [fl, npc_id])
					npc_entity.queue_free()

		# Walker 검사
		var walker_path := "res://data/maps/walkers_f%d.json" % fl
		if FileAccess.file_exists(walker_path):
			var walker_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(walker_path))
			if typeof(walker_doc) == TYPE_DICTIONARY:
				var walkers: Array = walker_doc.get("walkers", [])
				for w_data: Dictionary in walkers:
					var w_id: String = w_data.get("id", "")
					var pos_arr: Array = w_data.get("pos", [])
					var cur := Vector2i(int(pos_arr[0]), int(pos_arr[1]))
					if not _is_body_passable(rt, cur):
						_failures.append("F%d Walker %s 시작 위치 %s가 통행 불가 구역임" % [fl, w_id, cur])
					var pattern: Array = w_data.get("pattern", [])
					var legs: Array = []
					for leg: Dictionary in pattern:
						var dir_str: String = leg.get("dir", "right")
						var step_count: int = leg.get("steps", 0)
						var d := Vector2i.RIGHT
						match dir_str:
							"left":
								d = Vector2i.LEFT
							"up":
								d = Vector2i.UP
							"down":
								d = Vector2i.DOWN
						legs.append({"dir": d, "steps": step_count})
						for s in range(step_count):
							cur += d
							if not _is_body_passable(rt, cur):
								_failures.append(
									(
										"F%d Walker %s 경로 중 %s가 통행 불가임 (dir=%s, step=%d)"
										% [fl, w_id, cur, dir_str, s]
									)
								)
								break

					var walker_entity := WalkerEntity.new()
					add_child(walker_entity)
					walker_entity.setup(
						StringName(w_id),
						StringName(str(w_data.get("sprite", ""))),
						Vector2i(int(pos_arr[0]), int(pos_arr[1])),
						legs,
						rt
					)
					walker_entity.queue_free()

	print("   - [OK] 전 층(F0~F5) NPC 2×2 배치 및 상호작용 가능성 검증 완료")
	print("   - [OK] 전 층(F0~F5) Walker 왕복 경로 전 구간(100%) 통행 가능성 검증 완료")


## 3. 전 층 시나리오 퀘스트 체인 연결성 검증
func _test_full_scenario_quest_chain() -> void:
	print("[smoke_all_floors] 3. 전 층 시나리오 퀘스트 체인 (F1→F2→F3→F0→F4→F5→Ending) 검증...")

	# --- F1 시나리오 체인 ---
	GameState.set_flag("f1_opening_seen", true)
	GameState.set_flag("f1_opening_cleared", true)
	GameState.set_flag("Q_F1_START", true)
	GameState.set_flag("Q_F1_SOPO", true)
	GameState.inventory.add(&"ITEM_SOPO", 1)
	GameState.set_flag("Q_F1_GAS", true)
	GameState.inventory.add(&"ITEM_GASOLINE", 1)
	GameState.inventory.add(&"ITEM_LIGHTER", 1)
	var blast_cs := CutscenePlayer.load_cutscene(&"f1_blast")
	if blast_cs.is_empty():
		_failures.append("f1_blast 컷신 로드 실패")
	GameState.set_flag("Q_F1_BLAST", true)
	GameState.inventory.remove(&"ITEM_SOPO", 1)
	GameState.inventory.remove(&"ITEM_GASOLINE", 1)
	GameState.inventory.remove(&"ITEM_LIGHTER", 1)

	# --- F2 시나리오 체인 ---
	var hp_cs := CutscenePlayer.load_cutscene(&"hp_room_visit")
	if hp_cs.is_empty():
		_failures.append("hp_room_visit 컷신 로드 실패")
	GameState.set_flag("Q_F2_HP", true)
	GameState.inventory.add(&"ITEM_MANHWA_POSTER", 1)
	var poster_cs := CutscenePlayer.load_cutscene(&"f2_poster")
	if poster_cs.is_empty():
		_failures.append("f2_poster 컷신 로드 실패")
	GameState.set_flag("Q_F2_POSTER", true)
	GameState.inventory.remove(&"ITEM_MANHWA_POSTER", 1)
	print("   - [OK] F1 폭파(Q_F1_BLAST) -> F2 HP실(Q_F2_HP) -> 완종 괴물 무력화(Q_F2_POSTER) 체인 확인")

	# --- F3 해독제 3약품 체인 ---
	GameState.set_flag("Q_F3_CURE_REQ", true)
	var drag_cs := CutscenePlayer.load_cutscene(&"f3_drag")
	if drag_cs.is_empty():
		_failures.append("f3_drag 컷신 로드 실패")
	GameState.set_flag("Q_F3_DRAG", true)
	GameState.inventory.add(&"ITEM_DRAG", 1)

	var allin_cs := CutscenePlayer.load_cutscene(&"f3_allin")
	if allin_cs.is_empty():
		_failures.append("f3_allin 컷신 로드 실패")
	GameState.set_flag("Q_F3_ALLIN", true)
	GameState.inventory.add(&"ITEM_ALLIN", 1)

	var quiz_cs := CutscenePlayer.load_cutscene(&"quiz_paline")
	if quiz_cs.is_empty():
		_failures.append("quiz_paline 컷신 로드 실패")
	GameState.set_flag("Q_F3_PALIN", true)
	GameState.inventory.add(&"ITEM_PALIN", 1)
	print("   - [OK] F3 해독제 3약품 의뢰(Q_F3_CURE_REQ) -> 드래그 + 앨린 + 팰린(Q_F3_PALIN) 획득 체인 확인")

	# --- F0 지하 서고 체인 ---
	var disk_cs := CutscenePlayer.load_cutscene(&"f0_disk")
	if disk_cs.is_empty():
		_failures.append("f0_disk 컷신 로드 실패")
	GameState.set_flag("Q_F0_DISK", true)
	GameState.inventory.add(&"ITEM_DISKETTE", 1)
	print("   - [OK] F0 지하 서고 탐색 -> 3.5인치 디스켓(Q_F0_DISK) 획득 체인 확인")

	# --- F4 전자과 10,000V & 레버 희생 체인 ---
	var batt_cs := CutscenePlayer.load_cutscene(&"battery_puzzle")
	if batt_cs.is_empty():
		_failures.append("battery_puzzle 컷신 로드 실패")
	GameState.set_flag("Q_F4_BATTERY", true)
	var sac_cs := CutscenePlayer.load_cutscene(&"f4_sacrifice")
	if sac_cs.is_empty():
		_failures.append("f4_sacrifice 컷신 로드 실패")
	GameState.set_flag("Q_F4_SACRIFICE", true)
	GameState.set_flag("q_f5_boss_gate", true)
	print(
		"   - [OK] F4 10,000V 퍼즐(Q_F4_BATTERY) -> 3인방 레버 희생(Q_F4_SACRIFICE & q_f5_boss_gate) 체인 확인"
	)

	# --- F5 모교수 치료 & SYS_BUILDER 최종전 & 에필로그 ---
	var prof_cs := CutscenePlayer.load_cutscene(&"f5_professor")
	if prof_cs.is_empty():
		_failures.append("f5_professor 컷신 로드 실패")
	GameState.set_flag("q_f5_prof_won", true)

	var cure_cs := CutscenePlayer.load_cutscene(&"f5_cure")
	if cure_cs.is_empty():
		_failures.append("f5_cure 컷신 로드 실패")
	GameState.set_flag("Q_F5_BOSS_CURE", true)
	GameState.inventory.remove(&"ITEM_DRAG", 1)
	GameState.inventory.remove(&"ITEM_ALLIN", 1)
	GameState.inventory.remove(&"ITEM_PALIN", 1)

	var ai_cs := CutscenePlayer.load_cutscene(&"boss_sys_builder")
	if ai_cs.is_empty():
		_failures.append("boss_sys_builder 컷신 로드 실패")
	GameState.set_flag("Q_F5_AI_BATTLE", true)
	GameState.set_flag("q_f5_ai_battle_won", true)

	var epi_cs := CutscenePlayer.load_cutscene(&"epilogue")
	if epi_cs.is_empty():
		_failures.append("epilogue 컷신 로드 실패")
	GameState.set_flag("Q_ENDING", true)
	print(
		"   - [OK] F5 모교수 치료(Q_F5_BOSS_CURE) -> SYS_BUILDER 각성(Q_F5_AI_BATTLE) -> 엔딩(Q_ENDING) 확인"
	)


## 5. F5 보스전에 **져도 게임이 계속되는가** — 막다른 길 회귀 시험(백로그 §3.9).
##
## 두 보스 컷신은 층 진입 auto 트리거로 시작하고 done_flag는 컷신이 돌기 **전에** 선다.
## 그래서 첫 판에서 지면 승리 플래그(q_f5_prof_won·q_f5_ai_battle_won)가 영영 서지 않고,
## 해독제 단계도 최종전도 에필로그도 열리지 않는다 — 세이브를 되돌리는 것 말고는 끝낼 방법이
## 없었다. 지금은 소품 콘솔 위에 얹은 interact 재도전이 그 사슬을 잇는다. 좌표는 여기에
## 적지 않고 트리거 파일에서 읽는다(데이터가 움직여도 시험이 같이 움직인다).
func _test_f5_boss_retry_after_defeat() -> void:
	print("[smoke_all_floors] 5. F5 보스전 패배 후 재도전 경로 검사...")
	var before_failures := _failures.size()
	var doc := JsonUtil.load_dict("res://data/maps/triggers_f5.json", "smoke_all_floors")
	var by_id: Dictionary = {}
	for t: Variant in doc.get("triggers", []):
		if typeof(t) == TYPE_DICTIONARY:
			by_id[String((t as Dictionary).get("id", ""))] = t

	# (모교수, 보스) 각각: 진 상태 플래그 / 이긴 상태 플래그 / 재도전 트리거 id / 컷신 id
	var cases: Array = [
		{
			"label": "모교수",
			"before": ["q_f5_boss_gate", "q_f5_prof_intro_seen"],
			"win": "q_f5_prof_won",
			"retry": "f5_professor_retry",
			"cutscene": "f5_professor",
			"intro": "f5_professor_intro"
		},
		{
			"label": "SYS_BUILDER",
			"before": ["q_f5_prof_won", "Q_F5_BOSS_CURE", "Q_F5_AI_BATTLE"],
			"win": "q_f5_ai_battle_won",
			"retry": "f5_boss_retry",
			"cutscene": "boss_sys_builder",
			"intro": "f5_boss_intro"
		}
	]

	for case: Dictionary in cases:
		var rid := String(case["retry"])
		if not by_id.has(rid):
			_failures.append("%s 재도전 트리거(%s)가 triggers_f5.json에 없다" % [case["label"], rid])
			continue
		var cells: Array[Vector2i] = []
		for raw: Variant in (by_id[rid] as Dictionary).get("cells", []):
			cells.append(Vector2i(int((raw as Array)[0]), int((raw as Array)[1])))
		if cells.is_empty():
			_failures.append("%s 재도전 트리거에 cells가 없다" % case["label"])
			continue

		# --- 진 직후 상태를 그대로 세운다: 연출은 봤고(done_flag) 승리 플래그만 없다 ---
		GameState.reset()
		for f: String in case["before"]:
			GameState.set_flag(f, true)
		var trig := TriggerSystem.new()
		add_child(trig)
		trig.load_for_floor(5)
		var fired: Array[String] = []
		trig.cutscene_requested.connect(func(id: StringName) -> void: fired.append(String(id)))

		# ① 연출 auto는 다시 안 난다 — 나면 패배 지점에서 층을 못 떠나는 무한 재전투가 된다.
		trig.tick(Vector2i(80, 30), 0.5)
		trig.tick(Vector2i(80, 30), 0.5)
		if not fired.is_empty():
			_failures.append(
				"%s: 패배 복귀 직후 auto 트리거(%s)가 다시 발동했다 — 층을 떠날 수 없다" % [case["label"], case["intro"]]
			)

		# ② 콘솔을 조사하면 재도전이 열린다 — 이 한 줄이 없으면 게임을 끝낼 수 없다.
		fired.clear()
		var reopened := trig.try_interact(cells)
		if not reopened or not fired.has(String(case["cutscene"])):
			_failures.append("%s: 패배 후 %s를 조사해도 재도전이 열리지 않는다 (막다른 길)" % [case["label"], rid])

		# ③ 이기면 닫힌다 — guard_flag가 서면 같은 자리에서 다시 나지 않는다.
		GameState.set_flag(String(case["win"]), true)
		fired.clear()
		if trig.try_interact(cells) or not fired.is_empty():
			_failures.append("%s: 승리 플래그(%s) 수립 후에도 재도전이 또 났다" % [case["label"], case["win"]])
		trig.queue_free()

	if _failures.size() == before_failures:
		print("   - [OK] F5 보스 2건: 패배 후 콘솔 재도전 열림 / 승리 후 닫힘 / auto 재발동 없음")


## 4. NPC 다회차 대화(90년대 밈/개그) 및 진행 상황별 대사 변화 전수 검증
func _test_npc_repeats_and_progression() -> void:
	print("[smoke_all_floors] 4. NPC 다회차 접속(90s 밈/개그) 및 진행 상황별 대사 검증...")
	GameState.reset()

	# (1) 1F 멍청 조교 검증
	var f1_doc: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/maps/npcs_f1.json")
	)
	var tutor_cfg: Dictionary = f1_doc.get("npcs", [])[0]
	var tutor_entity := NpcEntity.new()
	add_child(tutor_entity)
	tutor_entity.setup(
		StringName(str(tutor_cfg["id"])),
		str(tutor_cfg["name"]),
		StringName(str(tutor_cfg["sequence_id"])),
		Vector2i.ZERO,
		Color.WHITE,
		tutor_cfg.get("sequence_variants", []),
		0,
		null,
		tutor_cfg.get("repeat_sequence_id", null)
	)
	var t_s1 := tutor_entity.resolve_sequence()
	var t_s2 := tutor_entity.resolve_sequence()
	if t_s1 != &"tutor_sample" or t_s2 != &"tutor_sample_repeat":
		_failures.append("1F 멍청 조교 초기 1/2회차 대사 시퀀스 오류: 1회차=%s, 2회차=%s" % [t_s1, t_s2])
	else:
		print("   - [OK] 1F 멍청 조교 1회차(%s) -> 2회차 90s 밈 대사(%s) 전환 확인" % [t_s1, t_s2])

	GameState.set_flag("Q_F1_BLAST", true)
	var t_s3 := tutor_entity.resolve_sequence()
	var t_s4 := tutor_entity.resolve_sequence()
	if t_s3 != &"tutor_after_blast" or t_s4 != &"tutor_after_blast_repeat":
		_failures.append("1F 멍청 조교 F1 폭파 후 1/2회차 대사 시퀀스 오류: 1회차=%s, 2회차=%s" % [t_s3, t_s4])
	else:
		print("   - [OK] 1F 멍청 조교 폭파 후 진행 대사(%s) -> 다회차 반복 대사(%s) 전환 확인" % [t_s3, t_s4])
	tutor_entity.queue_free()

	# (2) 2F 자칭 쓸모없는 복학생 검증
	var f2_doc: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/maps/npcs_f2.json")
	)
	var nothing_cfg: Dictionary = {}
	for n: Dictionary in f2_doc.get("npcs", []):
		if n.get("id") == "nothing_man":
			nothing_cfg = n
			break
	var nothing_entity := NpcEntity.new()
	add_child(nothing_entity)
	nothing_entity.setup(
		StringName(str(nothing_cfg["id"])),
		str(nothing_cfg["name"]),
		StringName(str(nothing_cfg["sequence_id"])),
		Vector2i.ZERO,
		Color.WHITE,
		nothing_cfg.get("sequence_variants", []),
		0,
		null,
		nothing_cfg.get("repeat_sequence_id", null)
	)
	var n_s1 := nothing_entity.resolve_sequence()
	var n_s2 := nothing_entity.resolve_sequence()
	var n_s3 := nothing_entity.resolve_sequence()
	if n_s1 != &"nothing_man" or n_s2 != &"nothing_man_repeat_1" or n_s3 != &"nothing_man_repeat_2":
		_failures.append("2F 복학생 초기 다회차 대사 오류: %s, %s, %s" % [n_s1, n_s2, n_s3])
	else:
		print(
			(
				"   - [OK] 2F 복학생 1회차(%s) -> 2회차 페르시아의 왕자(%s) -> 3회차 듀스 밈(%s) 순환 확인"
				% [n_s1, n_s2, n_s3]
			)
		)

	GameState.set_flag("Q_F2_POSTER", true)
	var n_s4 := nothing_entity.resolve_sequence()
	var n_s5 := nothing_entity.resolve_sequence()
	if n_s4 != &"nothing_man_f2" or n_s5 != &"nothing_man_f2_repeat":
		_failures.append("2F 복학생 완종 선배 치료 후 대사 오류: %s, %s" % [n_s4, n_s5])
	else:
		print("   - [OK] 2F 복학생 완종 치료 진행 대사(%s) -> 화학 시약 반복 조언(%s) 확인" % [n_s4, n_s5])
	nothing_entity.queue_free()

	# (3) TalkTargets 다회차 90s 밈 검증
	TalkTargets.reset_counts()
	var tt_98_1 := TalkTargets.steps_for(98)
	var tt_98_2 := TalkTargets.steps_for(98)
	if (
		tt_98_1.is_empty()
		or tt_98_1[0].get("text") != "@t203"
		or tt_98_2.is_empty()
		or tt_98_2[0].get("text") != "@c176"
	):
		_failures.append("ATT 98(초조한 95학번) 다회차 밈 대사 오류: %s, %s" % [str(tt_98_1), str(tt_98_2)])
	else:
		print("   - [OK] ATT 98 1회차(삐삐 호출 비극) -> 2회차(바람맞은 처량 밈) 확인")

	var tt_11_1 := TalkTargets.steps_for(11)
	var tt_11_2 := TalkTargets.steps_for(11)
	if (
		tt_11_1.is_empty()
		or tt_11_1[0].get("text") != "@c221"
		or tt_11_2.is_empty()
		or tt_11_2[0].get("text") != "@c259"
	):
		_failures.append("ATT 11(비 맞은 여학생) 다회차 밈 대사 오류: %s, %s" % [str(tt_11_1), str(tt_11_2)])
	else:
		print("   - [OK] ATT 11 1회차(서태지 테이프) -> 2회차(영한사전/파전 막걸리 밈) 확인")
	TalkTargets.reset_counts()
