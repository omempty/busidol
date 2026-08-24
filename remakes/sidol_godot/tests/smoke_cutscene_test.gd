extends Node
## 컷신 스모크 — Phase 7 수용 기준 자동화:
##   실제 opening.json 재생(프롤로그 씬 1-1) → finished 시그널 + 플래그 세팅 확인.
## 실행: godot --headless --path . res://tests/smoke_cutscene.tscn   (exit 0=PASS)

const TIMEOUT := 30.0
const SPEEDUP := 6.0


func _ready() -> void:
	var failures: Array[String] = []

	# 데이터 무결성 선검증
	for path: String in ["res://data/cutscenes/opening.json",
			"res://data/maps/triggers_f1.json"]:
		if not FileAccess.file_exists(path):
			failures.append("데이터 없음: %s" % path)
	if failures.is_empty():
		var raw: Variant = JSON.parse_string(
				FileAccess.get_file_as_string("res://data/cutscenes/opening.json"))
		if typeof(raw) != TYPE_DICTIONARY or str(raw.get("id", "")) != "opening":
			failures.append("opening.json 불량")

	GameState.flags.clear()

	var holder := Node2D.new()
	add_child(holder)
	var cp := CutscenePlayer.new()
	add_child(cp)
	cp.setup(holder)
	var fired := {"v": false}
	cp.finished.connect(func(_id: StringName) -> void: fired.v = true)

	# 타이핑 대기 단축을 위한 가속 (종료 후 복원)
	Engine.time_scale = SPEEDUP
	cp.play(CutscenePlayer.load_cutscene(&"opening"))
	var waited := 0.0
	while not fired.v and waited < TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
	Engine.time_scale = 1.0

	print("[smoke_cutscene] played=%.1fs running=%s" % [waited, cp.is_running()])
	if not fired.v:
		failures.append("컷신 finished 미발생")
	if cp.is_running():
		failures.append("컷신 running 잔존")
	if not GameState.has_flag("q_f1_prolog_done"):
		failures.append("set_flags(q_f1_prolog_done) 미적용")

	# --- 퀴즈 미니게임: 실제 데이터(퀴즈맨 3문항) 정답 순회 → 통과 시그널 ---
	GameState.flags.clear()
	var mg_raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/minigames/quiz_man.json"))
	if typeof(mg_raw) != TYPE_DICTIONARY:
		failures.append("quiz_man.json 파싱 실패")
	else:
		var quiz := QuizMinigame.new()
		add_child(quiz)
		var qpassed := { "v": false }
		quiz.finished.connect(func(p: bool) -> void: qpassed.v = p)
		quiz.start(mg_raw)
		while quiz.is_active():
			var qs: Array = (mg_raw as Dictionary).get("questions", [])
			quiz._sel = int(qs[quiz._qi]["answer"])   # 정답 선택 주입
			quiz._confirm()
		print("[smoke_cutscene] quiz passed=%s" % qpassed.v)
		if not qpassed.v:
			failures.append("퀴즈 finished(true) 미발생")

		# --- craft op 검증: 재료 충족 → 지급 + 플래그 ---
		GameState.flags.clear()
		GameState.inventory.clear()
		GameState.inventory.add(&"reagent_drag")
		GameState.inventory.add(&"reagent_allin")
		GameState.inventory.add(&"reagent_palin")
		cp._execute_craft({
			"requires": { "reagent_drag": 1, "reagent_allin": 1, "reagent_palin": 1 },
			"grant": { "antibiotic_x": 1 },
			"flag": "q_f3_cure_done",
		})
		var has_cure: int = GameState.inventory.count(&"antibiotic_x")
		print("[smoke_cutscene] craft antibiotic_x=%d flag=%s" % [has_cure,
				GameState.has_flag("q_f3_cure_done")])
		if has_cure != 1 or not GameState.has_flag("q_f3_cure_done"):
			failures.append("craft 결과 이상")

	# --- 배터리 회로 퍼즐: 해답 주입(400V × 25) → 통과 ---
	var bcfg: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/minigames/battery_circuit.json"))
	if typeof(bcfg) != TYPE_DICTIONARY:
		failures.append("battery_circuit.json 파싱 실패")
	else:
		var game := BatteryCircuitMinigame.new()
		add_child(game)
		var bpassed := { "v": false }
		game.finished.connect(func(p: bool) -> void: bpassed.v = p)
		game.start(bcfg)
		for i in 4:
			game._vals[i] = 100
		game._lever = 25
		game._refresh()
		print("[smoke_cutscene] battery passed=%s" % bpassed.v)
		if not bpassed.v:
			failures.append("회로 퍼즐 finished(true) 미발생")

	# --- 메타 퀴즈 데이터 무결성(10문항) ---
	var meta_raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/minigames/quiz_man_meta.json"))
	if typeof(meta_raw) != TYPE_DICTIONARY \
			or ((meta_raw as Dictionary).get("questions", []) as Array).size() != 10:
		failures.append("quiz_man_meta.json 불량(10문항 아님)")

	if failures.is_empty():
		print("[smoke_cutscene] PASS")
		get_tree().quit(0)
	else:
		push_error("[smoke_cutscene] FAIL: " + "; ".join(failures))
		get_tree().quit(1)
