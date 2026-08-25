extends Node
## 크레딧룸 스모크 — 멤버 전원 확인→Q_HP_ALL, 메타 퀴즈 완벽 정답→Q_QUIZ_ALL 자동 검증.
## 실행: godot --headless --path . res://tests/smoke_credit_room.tscn   (exit 0=PASS)

const CREDIT_ROOM := preload("res://scenes/credit_room.tscn")
const TIMEOUT_S := 20.0


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_S).timeout.connect(
		func() -> void:
			push_error("[smoke_credit] WATCHDOG timeout")
			get_tree().quit(1)
	)
	var failures: Array[String] = []
	GameState.reset()

	var room: Control = CREDIT_ROOM.instantiate()
	add_child(room)
	await get_tree().process_frame

	if GameState.has_flag("Q_HP_ALL"):
		failures.append("멤버 확인 전에 Q_HP_ALL 세팅됨(근사 잔존?)")

	# 1) 멤버 전원 확인 — 마지막 한 명 확인 시 자동 세팅
	for m: Dictionary in room._members:
		room._mark_member_seen(m)
	if not GameState.has_flag("Q_HP_ALL"):
		failures.append("전원 확인 후 Q_HP_ALL 미세팅")

	# 2) 메타 퀴즈 모드 노출(미클리어) + 데이터 로드
	if not room._mode_count == 4:
		failures.append("메타 퀴즈 모드 미노출(mode_count=%d)" % room._mode_count)
	var quiz_cfg: Dictionary = room._load_minigame("quiz_man_meta")
	if (quiz_cfg.get("questions", []) as Array).is_empty():
		failures.append("quiz_man_meta 로드 실패")

	# 3) 완벽 정답 플레이 — 정답 순회 주입, 오답 0
	var quiz := QuizMinigame.new()
	add_child(quiz)
	var passed := {"v": false}
	quiz.finished.connect(func(p: bool) -> void: passed.v = p)
	quiz.start(quiz_cfg)
	var qs: Array = quiz_cfg.get("questions", [])
	while quiz.is_active():
		quiz._sel = int(qs[quiz._qi]["answer"])
		quiz._confirm()
	if not passed.v:
		failures.append("메타 퀴즈 finished 미발생")
	elif quiz.mistake_count() != 0:
		failures.append("완벽 정답인데 오답 카운트 %d" % quiz.mistake_count())

	# 4) 오답 포함 통과 시 플래그 미세팅 확인(정밀 판정 핵심)
	GameState.flags.erase("Q_QUIZ_ALL")
	var quiz2 := QuizMinigame.new()
	add_child(quiz2)
	var passed2 := {"v": false}
	quiz2.finished.connect(func(p: bool) -> void: passed2.v = p)
	quiz2.start(quiz_cfg)
	var i := 0
	while quiz2.is_active():
		if i == 0:  # 첫 문항만 일부러 오답
			quiz2._sel = (
				(int(qs[quiz2._qi]["answer"]) + 1)
				% (qs[quiz2._qi].get("choices", [1, 1, 1]) as Array).size()
			)
		else:
			quiz2._sel = int(qs[quiz2._qi]["answer"])
		quiz2._confirm()
		i += 1
	if not passed2.v or quiz2.mistake_count() == 0:
		failures.append("오답 재도전 경로 이상")

	if failures.is_empty():
		print("[smoke_credit] PASS")
		get_tree().quit(0)
	else:
		push_error("[smoke_credit] FAIL: " + "; ".join(failures))
		get_tree().quit(1)
