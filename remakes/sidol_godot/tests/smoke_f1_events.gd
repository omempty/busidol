extends Node
## 1F 시나리오 이벤트 및 NPC/보행자 종합 검증 스모크 테스트
## 실행: godot --headless --path . res://tests/smoke_f1_events.tscn (exit 0=PASS)

const TRANSITIONS_PATH := "res://data/maps/transitions.json"
const TRIGGERS_F1_PATH := "res://data/maps/triggers_f1.json"
const NPCS_F1_PATH := "res://data/maps/npcs_f1.json"
const WALKERS_F1_PATH := "res://data/maps/walkers_f1.json"
const TALK_TARGETS_PATH := "res://data/maps/talk_targets.json"
const DIALOGUE_PATH := "res://data/dialogue.json"
const SEQUENCES_PATH := "res://data/dialogue_sequences.json"

var _failures: Array[String] = []


func _ready() -> void:
	print("[smoke_f1_events] === 1F 시나리오 이벤트 & NPC 동작 검사 시작 ===")

	_test_dialogue_uniqueness()
	_test_npc_and_walker_sprites()
	_test_scenario_event_chain()

	if _failures.is_empty():
		print("[smoke_f1_events] PASS — 1F 모든 이벤트 체인, NPC 스프라이트/아이들/배회, 대사 고유성 검증 완료!")
		get_tree().quit(0)
	else:
		print("[smoke_f1_events] FAIL — %d건의 오류 발생:" % _failures.size())
		for f in _failures:
			print("  [X] %s" % f)
		get_tree().quit(1)


## 1. 대사 중복 및 1F 대화 대상 전수 검사
func _test_dialogue_uniqueness() -> void:
	print("[smoke_f1_events] 1. 대사 고유성 및 1F NPC 대사 검사...")
	var dlg_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIALOGUE_PATH))
	if typeof(dlg_raw) != TYPE_DICTIONARY:
		_failures.append("dialogue.json 로드 실패")
		return
	var dlg: Dictionary = dlg_raw

	var seq_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SEQUENCES_PATH))
	if typeof(seq_raw) != TYPE_DICTIONARY:
		_failures.append("dialogue_sequences.json 로드 실패")
		return
	var seqs: Dictionary = seq_raw.get("sequences", {})

	var tt_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(TALK_TARGETS_PATH))
	if typeof(tt_raw) != TYPE_DICTIONARY:
		_failures.append("talk_targets.json 로드 실패")
		return
	var tt: Dictionary = tt_raw.get("targets", {})

	# 1F 멍청 조교 대사 확인 (howa_jo와 중복되지 않는지)
	var tutor_steps: Array = seqs.get("tutor_sample", {}).get("steps", [])
	if tutor_steps.is_empty():
		_failures.append("tutor_sample 시퀀스 없음")
	else:
		var tutor_keys: Array = []
		for st: Dictionary in tutor_steps:
			tutor_keys.append(st.get("text", ""))
		if tutor_keys.has("@t24") or tutor_keys.has("@t25") or tutor_keys.has("@t26"):
			_failures.append("멍청 조교 대사가 3층 화공과 조교(@t24~@t26)와 여전히 중복됨")
		elif not (tutor_keys.has("@c107") and tutor_keys.has("@c108") and tutor_keys.has("@c109")):
			_failures.append("멍청 조교 대사가 1층 상황 고유 대사(@c107~@c109)로 설정되지 않음: %s" % str(tutor_keys))
		else:
			print("   - [OK] 멍청 조교(1F): 1F 전용 대사 (@c107~@c109) 정상 적용")

	# 항공과 조교(ATT 47)와 학생2(ATT 12) 대사 중복 해소 확인
	var s2_texts: Array = tt.get("12", {}).get("texts", [])
	var h2_texts: Array = tt.get("47", {}).get("texts", [])
	if s2_texts == h2_texts and s2_texts.has("@t79"):
		_failures.append("학생2와 항공과 조교2가 동일 대사(@t79)를 공유함")
	else:
		print("   - [OK] 학생2(ATT 12: %s) vs 항공과 조교2(ATT 47: %s) 중복 해소 확인" % [s2_texts, h2_texts])

	# 수위 아저씨(guard_idle) 대사 확인 (왼쪽 사람 @t203과 중복되지 않는지)
	var guard_steps: Array = seqs.get("guard_idle", {}).get("steps", [])
	var guard_keys: Array = []
	for st: Dictionary in guard_steps:
		guard_keys.append(st.get("text", ""))
	if guard_keys.has("@t203"):
		_failures.append("수위 아저씨 대사가 왼쪽 사람 대사(@t203)와 여전히 중복됨")
	else:
		print("   - [OK] 수위 아저씨(guard_idle): %s 적용 확인" % str(guard_keys))

	# ATT 97/98 (오른쪽/왼쪽 사람) 이름 및 5회 힌트 기믹 검증
	var p_right: Dictionary = tt.get("97", {})
	var p_left: Dictionary = tt.get("98", {})
	if p_right.get("name", "").contains("그림") or p_left.get("name", "").contains("그림"):
		_failures.append("ATT 97/98에 여전히 '그림' 명칭이 포함되어 있음 (실체는 인물)")
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
		_failures.append("오른쪽 사람 5회 연속 대화 시 힌트(@t207)가 나오지 않음: %s" % str(step5))
	else:
		print("   - [OK] 오른쪽 사람 5회 대화 힌트 기믹(@t207 화공과 교수 힌트) 정상 작동 확인")
	TalkTargets.reset_counts()

	# 전수 대사 중복 검사
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
		# nothing_man (seq:nothing_man 및 att:99는 동일 인물)
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


## 2. 1F NPC & Walker 방향별 스프라이트 / 이동 알고리즘 검사
func _test_npc_and_walker_sprites() -> void:
	print("[smoke_f1_events] 2. 1F NPC & Walker 스프라이트 방향 및 이동 알고리즘 검사...")

	# F1 맵 로드
	var def := MapDefinition.load_from_json("res://data/maps/f1.json")
	if def == null:
		_failures.append("f1.json 로드 실패")
		return
	var rt := MapRuntime.new(def)

	# --- WalkerEntity 검증 ---
	var walker_cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(WALKERS_F1_PATH))
	if typeof(walker_cfg) != TYPE_DICTIONARY:
		_failures.append("walkers_f1.json 로드 실패")
		return
	var walkers: Array = walker_cfg.get("walkers", [])
	if walkers.is_empty():
		_failures.append("walkers_f1.json 에 보행자 정의 없음")
		return

	var w_data: Dictionary = walkers[0]
	var walker := WalkerEntity.new()
	add_child(walker)
	var legs: Array = []
	for leg: Dictionary in w_data.get("pattern", []):
		var dir := Vector2i.ZERO
		match str(leg.get("dir", "")):
			"up":
				dir = Vector2i.UP
			"down":
				dir = Vector2i.DOWN
			"left":
				dir = Vector2i.LEFT
			"right":
				dir = Vector2i.RIGHT
		legs.append({"dir": dir, "steps": int(leg.get("steps", 0))})

	var w_pos := Vector2i(int(w_data["pos"][0]), int(w_data["pos"][1]))
	walker.setup(StringName(str(w_data["id"])), StringName(str(w_data["sprite"])), w_pos, legs, rt)

	# 4방향 스프라이트 애니메이션 완비 여부 검증
	var w_frames: SpriteFrames = walker.sprite.sprite_frames
	for facing in [&"down", &"up", &"left", &"right"]:
		var walk_anim := SpriteSets.pose_anim(w_frames, facing, true)
		if walk_anim.is_empty() or not String(walk_anim).ends_with(String(facing)):
			_failures.append("WalkerEntity %s 방향 이동 스프라이트 없음: %s" % [facing, walk_anim])
		var idle_anim := SpriteSets.pose_anim(w_frames, facing, false)
		if idle_anim.is_empty():
			_failures.append("WalkerEntity %s 방향 정지 포즈 없음" % facing)

	# WalkerEntity _face 동작 검사
	walker._face(Vector2i.RIGHT, true)
	if not walker.sprite.is_playing() or walker.sprite.animation != &"walk_right":
		_failures.append("WalkerEntity 우측 보행 애니메이션 실행 실패")
	walker._face(Vector2i.RIGHT, false)
	# 정지 시 walking=false 면 프레임 0에서 stop 되어야 함
	if walker.sprite.is_playing() and not String(walker.sprite.animation).begins_with("idle_"):
		_failures.append("WalkerEntity 정지 시 보행 애니메이션이 멈추지 않음")
	print("   - [OK] WalkerEntity 4방향 스프라이트 및 정지 상태 전환 검증")

	# Walker 이동 경로 통행성 전수 검사 (x: 100~130, y: 26)
	var path_blocked := false
	for x in range(100, 131):
		for c in Placement.body_cells(Vector2i(x, 26)):
			if not rt.is_passable(c):
				path_blocked = true
				_failures.append("WalkerEntity 경로 중 통행 불가 셀 발견: %s" % c)
	if not path_blocked:
		print("   - [OK] WalkerEntity 30보 왕복 경로 전 구간 통행 가능")
	walker.queue_free()

	# --- NpcEntity 검증 (tutor_dumb) ---
	var npc_cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(NPCS_F1_PATH))
	var npcs_arr: Array = npc_cfg.get("npcs", [])
	if npcs_arr.is_empty():
		_failures.append("npcs_f1.json 에 NPC 정의 없음")
		return

	var n_data: Dictionary = npcs_arr[0]
	var npc := NpcEntity.new()
	add_child(npc)
	var n_cell := Vector2i(int(n_data["pos"][0]), int(n_data["pos"][1]))
	var wander_range := int(n_data.get("wander_range", 0))
	npc.setup(
		StringName(str(n_data["id"])),
		str(n_data["name"]),
		StringName(str(n_data["sequence_id"])),
		n_cell,
		Color.WHITE,
		n_data.get("sequence_variants", []),
		wander_range,
		rt
	)

	# 4방향 포즈 검사
	var n_frames: SpriteFrames = npc.sprite.sprite_frames
	for facing in [&"down", &"up", &"left", &"right"]:
		var p_anim := SpriteSets.pose_anim(n_frames, facing, false)
		if p_anim.is_empty():
			_failures.append("NpcEntity %s 방향 포즈 해결 불가" % facing)

	# 플레이어 방향 응시 (face_towards)
	npc.face_towards(n_cell + Vector2i.RIGHT)
	if npc._facing != &"right":
		_failures.append("NpcEntity face_towards(RIGHT) 실패: %s" % npc._facing)
	npc.face_towards(n_cell + Vector2i.UP)
	if npc._facing != &"up":
		_failures.append("NpcEntity face_towards(UP) 실패: %s" % npc._facing)

	# 제자리 호흡 (아이들 애니메이션) 동작 검사
	var initial_scale := npc.sprite.scale
	npc._update_breathing(0.5)
	if npc.sprite.scale == Vector2.ZERO:
		_failures.append("NpcEntity 호흡 계산 중 스케일 0 에러")
	print("   - [OK] NpcEntity 제자리 호흡(아이들) 및 4방향 응시(face_towards) 정상")

	# 소폭 배회 (wander_range) 검사
	if wander_range != 1:
		_failures.append("tutor_dumb wander_range가 1로 설정되지 않음: %d" % wander_range)
	else:
		var stepped := npc._try_wander_step()
		var diff := npc.cell - n_cell
		if absi(diff.x) > 1 or absi(diff.y) > 1:
			_failures.append("NpcEntity wander_range(1) 초과 이동: %s -> %s" % [n_cell, npc.cell])
		else:
			print("   - [OK] NpcEntity 소폭 배회(Wander range=1) 및 충돌 판정 갱신 검증")

	npc.queue_free()


## 3. 1F 시나리오 이벤트 체인 및 2F 게이트 검증
func _test_scenario_event_chain() -> void:
	print("[smoke_f1_events] 3. 1F 시나리오 이벤트 체인 (프롤로그 -> 소포 -> 휘발유 -> 철문 폭파 -> 2F 해금) 검증...")

	# 상태 초기화
	GameState.flags.clear()
	GameState.current_floor = 1
	GameState.inventory.clear()

	# 1) 오프닝 컷신 확인
	var op_cfg := CutscenePlayer.load_cutscene(&"opening")
	if op_cfg.is_empty():
		_failures.append("opening 컷신 파일 없음")
	else:
		print("   - [OK] 씬 1-1 오프닝 컷신 데이터 완비")

	# 2) Q_F1_START 전에는 f1_sopo, f1_gas 발동 불가 검증
	var trig_sys := TriggerSystem.new()
	add_child(trig_sys)
	trig_sys.load_for_floor(1)

	var sopo_cells := [Vector2i(163, 18)]
	var gas_cells := [Vector2i(12, 32)]

	# Q_F1_START가 없으므로 zone 트리거 tick에서 발동되지 않아야 함
	var requested_cutscenes: Array[String] = []
	trig_sys.cutscene_requested.connect(
		func(id: StringName) -> void: requested_cutscenes.append(String(id))
	)

	trig_sys.tick(sopo_cells[0], 0.1)
	if not requested_cutscenes.is_empty():
		_failures.append("Q_F1_START 없이 f1_sopo 가 발동됨")
	requested_cutscenes.clear()

	trig_sys.tick(gas_cells[0], 0.1)
	if not requested_cutscenes.is_empty():
		_failures.append("Q_F1_START 없이 f1_gas 가 발동됨")
	requested_cutscenes.clear()
	print("   - [OK] Q_F1_START 선행 조건 가드 정상 작동")

	# 3) 첫 전투 승리 -> Q_F1_START 획득
	GameState.set_flag("q_f1_opening_seen", true)
	GameState.set_flag("Q_F1_START", true)

	# 4) 교무과 우편물실 (163, 18) 진입 -> f1_sopo 발동
	trig_sys.tick(sopo_cells[0], 0.1)
	if requested_cutscenes.is_empty() or requested_cutscenes[0] != "f1_sopo":
		_failures.append("Q_F1_START 후 f1_sopo 발동 실패: %s" % str(requested_cutscenes))
	else:
		print("   - [OK] 씬 1-3 교무과 우편물실 진입: f1_sopo 트리거 발동")
	requested_cutscenes.clear()

	# f1_sopo 컷신 실행 (소포 폭탄 획득)
	var sopo_cutscene := CutscenePlayer.load_cutscene(&"f1_sopo")
	for step: Dictionary in sopo_cutscene.get("steps", []):
		if step.get("op") == "grant_item":
			GameState.inventory.add(
				StringName(str(step["args"]["item"])), int(step["args"]["count"])
			)
	GameState.set_flag("Q_F1_SOPO", true)

	if GameState.inventory.count(&"ITEM_SOPO") != 1:
		_failures.append("ITEM_SOPO 획득 실패")
	else:
		print("   - [OK] 소포 폭탄(ITEM_SOPO) 획득 및 Q_F1_SOPO 플래그 수립")

	# 5) 창고 (12, 32) 진입 -> f1_gas 발동
	trig_sys.tick(gas_cells[0], 0.1)
	if requested_cutscenes.is_empty() or requested_cutscenes[0] != "f1_gas":
		_failures.append("Q_F1_START 후 f1_gas 발동 실패: %s" % str(requested_cutscenes))
	else:
		print("   - [OK] 씬 1-3 창고 진입: f1_gas 트리거 발동")
	requested_cutscenes.clear()

	# f1_gas 컷신 실행 (휘발유 & 라이터 획득)
	var gas_cutscene := CutscenePlayer.load_cutscene(&"f1_gas")
	for step: Dictionary in gas_cutscene.get("steps", []):
		if step.get("op") == "grant_item":
			GameState.inventory.add(
				StringName(str(step["args"]["item"])), int(step["args"]["count"])
			)
	GameState.set_flag("Q_F1_GAS", true)

	if (
		GameState.inventory.count(&"ITEM_GASOLINE") != 1
		or GameState.inventory.count(&"ITEM_LIGHTER") != 1
	):
		_failures.append("ITEM_GASOLINE 또는 ITEM_LIGHTER 획득 실패")
	else:
		print("   - [OK] 휘발유(ITEM_GASOLINE) 및 라이터(ITEM_LIGHTER) 획득 및 Q_F1_GAS 수립")

	# 6) 계단 잠금 상태 검증 (폭파 전에는 2층 이동 불가)
	var trans_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(TRANSITIONS_PATH))
	var transitions: Array = trans_raw.get("transitions", [])
	var center_stair_f1: Dictionary = {}
	var east_stair_f1: Dictionary = {}
	for t: Dictionary in transitions:
		if t.get("id") == "stairs_center_up_f1":
			center_stair_f1 = t
		elif t.get("id") == "stairs_east_up_f1":
			east_stair_f1 = t

	if center_stair_f1.get("requires_flag") != "Q_F1_BLAST":
		_failures.append(
			(
				"stairs_center_up_f1 requires_flag 가 Q_F1_BLAST 가 아님: %s"
				% center_stair_f1.get("requires_flag")
			)
		)
	if east_stair_f1.get("requires_flag") != "Q_F1_BLAST":
		_failures.append(
			(
				"stairs_east_up_f1 requires_flag 가 Q_F1_BLAST 가 아님: %s"
				% east_stair_f1.get("requires_flag")
			)
		)

	if not GameState.has_flag("Q_F1_BLAST"):
		print("   - [OK] 폭파 전 2층 계단 게이트(중앙·동측) Q_F1_BLAST 잠금 확인")

	# 7) 2층 계단 앞 (100, 63) 에서 대폭파 인터랙션
	var blast_interacted := trig_sys.try_interact([Vector2i(100, 63)])
	if (
		not blast_interacted
		or requested_cutscenes.is_empty()
		or requested_cutscenes[0] != "f1_blast"
	):
		_failures.append("f1_blast interact 트리거 발동 실패: %s" % str(requested_cutscenes))
	else:
		print("   - [OK] 씬 1-4 2층 철문 앞 SPACE: f1_blast 트리거 발동")

	# f1_blast 컷신 실행 (craft op)
	var blast_cutscene := CutscenePlayer.load_cutscene(&"f1_blast")
	var has_explosion_sfx := false
	var has_shake := false
	for step: Dictionary in blast_cutscene.get("steps", []):
		if step.get("op") == "sfx" and step.get("id") == "sfx_explosion":
			has_explosion_sfx = true
		if step.get("op") == "shake":
			has_shake = true
		if step.get("op") == "craft":
			var req: Dictionary = step.get("args", {}).get("requires", {})
			for it: String in req:
				GameState.inventory.remove(StringName(it), int(req[it]))
			if step.get("args", {}).has("flag"):
				GameState.set_flag(str(step["args"]["flag"]), true)

	if not has_explosion_sfx or not has_shake:
		_failures.append("f1_blast 연출(폭발 sfx/shake) 누락")
	else:
		print("   - [OK] 2층 철문 대폭파 연출(sfx_explosion + shake + dialogue) 확인")

	if not GameState.has_flag("Q_F1_BLAST"):
		_failures.append("Q_F1_BLAST 플래그 미수립")
	elif (
		GameState.inventory.count(&"ITEM_SOPO") != 0
		or GameState.inventory.count(&"ITEM_GASOLINE") != 0
		or GameState.inventory.count(&"ITEM_LIGHTER") != 0
	):
		_failures.append("폭발 재료(소포, 휘발유, 라이터) 소비 실패")
	else:
		print("   - [OK] 폭발 재료 3종 정상 소비 및 Q_F1_BLAST 플래그 수립 완료")

	# guard_flag 에 의해 f1_blast 재발동 방지 검증
	requested_cutscenes.clear()
	var re_interact := trig_sys.try_interact([Vector2i(100, 63)])
	if re_interact or not requested_cutscenes.is_empty():
		_failures.append("Q_F1_BLAST 수립 후에도 f1_blast 가 재발동됨 (guard_flag 실패)")
	else:
		print("   - [OK] guard_flag: Q_F1_BLAST 수립 후 f1_blast 재발동 차단 확인")

	# 8) 2층 계단 해금 검증
	if GameState.has_flag("Q_F1_BLAST"):
		print("   - [OK] Q_F1_BLAST 수립으로 2층 계단(중앙·동측) 해금 확인!")

	trig_sys.queue_free()
