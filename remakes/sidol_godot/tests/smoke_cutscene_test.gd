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

	if failures.is_empty():
		print("[smoke_cutscene] PASS")
		get_tree().quit(0)
	else:
		push_error("[smoke_cutscene] FAIL: " + "; ".join(failures))
		get_tree().quit(1)
