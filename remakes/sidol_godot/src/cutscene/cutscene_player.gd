class_name CutscenePlayer
extends CanvasLayer
## 컷신 재생기 — 순차 명령열 비동기 해석. 에디터 프리뷰와 동일 클래스 사용.
## docs/02_design/05_toolchain_editors.md §4 참조.
## op 계약:
##   dialogue  {steps:[{speaker,text(@t/@c)}]}   wait {seconds}
##   fade_in(밝아짐) / fade_out(어두워짐) {seconds}   shake {power, times}
##   sfx/bgm {id}   set_flags {args:{k:v}}   start_battle {enemies:[]}
##   grant_item {args:{item, count}}   craft {args:{requires:{}, grant:{}, flag}}
##   illustration {args:{id, fade}} — 키아트 한 장을 화면에 띄운다(id 비우면 내림)
##   minigame_quiz {id} — 통과할 때까지 재도전 후 다음 스텝 진행
##   blackout {args:{on:bool}} — F1 정전 토글(백로그 §1.3). field.set_blackout 문으로 간다.
##   choice {args:{options:[{text(@t/@c), steps:[op...]}]}} — 선택 강제, 수렴형.
##     각 옵션의 steps를 서브 열로 실행 후 다음 스텝 진행(WP-5, D4 승인).

signal finished(cutscene_id: StringName)

const CUTSCENES_DIR := "res://data/cutscenes"
## 채택된 키아트가 놓이는 자리 — 스펙은 assets/spec/keyart/<id>.json.
const KEYART_DIR := "res://assets/keyart/"
## 폴백 키아트 — **그림이 비면 늘 무언가는 나온다**는 방침(2026-08-29 유저 확정).
## 미납품 키아트는 컷신에 아무것도 안 띄웠고, 그러면 대사창만 뜬 채 말하는 자리가
## 텅 빈다. 생성기: tools/dev/make_keyart_fallback.py — 진짜 납품이 오면 그쪽이 이긴다.
const KEYART_FALLBACK_DIR := "res://assets/keyart/_fallback/"
const SHAKE_STEP := 0.05
## 레터박스(04_uiux §6 "스크린샷/녹화 친화") — 컷신 동안 상하 띠를 넣어 화면을 극장비로
## 자른다. 키아트가 뷰포트를 꽉 채우는 구조라(2026-08-30 결함의 배경) 띠가 없으면
## 필드와 컷신이 같은 프레임으로 보인다. 띠 위에 대사창이 앉아 자리도 정리된다.
const LETTERBOX_RATIO := 0.11  # 위·아래 각각 화면 높이의 비율
const LETTERBOX_TIME := 0.35

var _steps: Array = []
var _idx := 0
var _running := false
## 씬을 넘겨주고 끝났는가(전투 진입·씬 전환). **중단과 구별해야 한다** — 이때는
## 이 노드 자체가 사라지므로 마무리를 하면 안 되고, 그 밖의 중단(재료 부족 등)은
## 반드시 마무리해야 한다. 안 그러면 finished를 기다리는 쪽이 영영 안 깨어난다.
var _handoff := false
var _cutscene_id := &""
var _box: DialogueBox
var _overlay: ColorRect
var _illustration: TextureRect
var _letterbox_top: ColorRect
var _letterbox_bottom: ColorRect
var _field: Node2D


## field: 카메라 흔들림·전투 전환 대상 씬 루트
func setup(p_field: Node2D) -> void:
	layer = 40
	visible = false
	_field = p_field

	_box = DialogueBox.new()
	# **컷신 대사도 사람이 넘긴다.** 전에는 auto_advance를 켜 둬서 1.1초마다 저 혼자
	# 넘어갔다 — 읽는 속도와 무관하게 지나가 버려 이벤트 대사를 놓쳤다(2026-08-29
	# 유저 지적). 원작도 키 입력을 기다렸고, 필드 대화(입력 중재 모드)와도 어긋나
	# 있었다. 진행 입력은 아래 _unhandled_input이 받는다.
	_box.auto_advance = false
	add_child(_box)
	# **대사창은 키아트보다 위에 그린다.** DialogueBox는 제 CanvasLayer(30)를 쓰는데
	# 컷신은 40이라, 화면을 꽉 채우는 불투명 키아트가 대사창을 통째로 덮었다 —
	# 오프닝(번개 치는 비 그림)에서 대사·진행 표시가 하나도 안 보여 멈춘 것처럼
	# 보였다(2026-08-30 유저 신고, 실측 스크린샷으로 확인). move_child는 같은
	# 레이어 안에서만 순서를 바꾸므로 레이어 번호 자체를 올려야 한다.
	#
	# 그리는 순서 계약: 키아트 < 암전막 < 선택지  (모두 이 노드의 레이어 40)
	#                  < 대사창 41 < 미니게임 45.
	# 암전막이 대사창을 못 덮지만 둘은 동시에 뜨지 않는다 — op은 순차 실행이고
	# 대사 op은 _box.finished까지 await 한다.
	_box.layer = layer + 1

	# 키아트(일러스트) 판 — 대사창보다 **아래**에 있어야 글자를 가리지 않는다.
	_illustration = TextureRect.new()
	_illustration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_illustration.modulate.a = 0.0
	_illustration.visible = false
	add_child(_illustration)
	move_child(_illustration, 0)

	# 암전 막 — **이 레이어 안에서** 키아트 뒤 자식이라 그림 위, 선택지(실행 중 마지막
	# 자식으로 붙는다) 아래다. 별도 CanvasLayer로 빼지 말 것: 그러면 컷신이 끝나며
	# 거는 visible=false가 안 먹어 중단 경로(craft 재료 부족 등)에서 검은 화면이
	# 그대로 남고, 암전 중 선택지도 막 뒤로 숨는다.
	# 레터박스 띠 — 키아트 위, 암전막 아래. 암전 때는 띠도 같이 묻혀야 자연스럽다.
	_letterbox_top = _make_bar(Control.PRESET_TOP_WIDE)
	_letterbox_bottom = _make_bar(Control.PRESET_BOTTOM_WIDE)

	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)


## 상·하 띠 한 장. 높이는 뷰포트가 정해지는 시점에 _set_letterbox가 채운다.
func _make_bar(preset: int) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 1)
	bar.set_anchors_preset(preset as Control.LayoutPreset)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# size를 직접 건드리지 말 것 — 상·하단 앵커라 _ready 뒤에 엔진이 덮어쓰고, 그때마다
	# "non-equal opposite anchors" 경고가 필드 진입마다 찍힌다(2026-08-30 실측).
	# 높이는 _set_letterbox()가 offset으로만 정한다.
	bar.custom_minimum_size = Vector2(0, 0)
	bar.offset_top = 0.0
	bar.offset_bottom = 0.0
	add_child(bar)
	return bar


## 띠 높이를 h로 맞춘다(0이면 사라진다). 앵커가 상·하단이라 offset으로 키운다.
func _set_letterbox(h: float) -> void:
	if _letterbox_top == null:
		return
	_letterbox_top.offset_bottom = h
	_letterbox_bottom.offset_top = -h


func _tween_letterbox(show_bars: bool) -> void:
	# setup() 없이 play()만 부르는 쓰임이 있다(tests/smoke_choice_test). 그때는 띠도
	# 대사창도 없으므로 조용히 건너뛴다 — 여기서 죽으면 그 경로가 통째로 막힌다.
	if _letterbox_top == null:
		return
	var vp := get_viewport()
	var height := float(vp.get_visible_rect().size.y) if vp != null else 540.0
	var target := height * LETTERBOX_RATIO if show_bars else 0.0
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_letterbox, _letterbox_top.offset_bottom, target, LETTERBOX_TIME)


func play(config: Dictionary) -> void:
	if _running:
		push_warning("컷신 중복 재생 무시: %s" % _cutscene_id)
		return
	_cutscene_id = StringName(str(config.get("id", "")))
	_steps = config.get("steps", [])
	_idx = 0
	_running = true
	_handoff = false
	visible = true
	_tween_letterbox(true)
	_run()


## 컷신 진행 입력. 필드 대화는 field가 중재하지만 컷신 대사창은 **아무도 눌러 주지
## 않아** 자동 진행에 기대고 있었다. 선택지·미니게임은 자기 _unhandled_input이 먼저
## 받아 소비하므로(자식이 먼저다) 여기까지 오지 않는다.
func _unhandled_input(event: InputEvent) -> void:
	if _box == null or not _box.is_open:
		return
	# 대화 로그 — 필드와 같은 키(ENTER)로 연다. 로그가 떠 있는 동안 진행 입력은
	# 로그 창이 먼저 받아 소비하므로 여기까지 오지 않는다.
	if event.is_action_pressed(&"menu"):
		_box.toggle_log()
		var vp0 := get_viewport()
		if vp0 != null:
			vp0.set_input_as_handled()
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"cancel"):
		_box.advance()
		# 씬 전환 중에는 뷰포트가 없다(전투 진입 프레임에 입력이 겹친다).
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


func stop() -> void:
	_running = false
	_set_letterbox(0.0)
	visible = false


func is_running() -> bool:
	return _running


func _run() -> void:
	await _run_steps(_steps)
	if _handoff:
		return  # 전투·씬 전환 — 이 노드는 곧 사라진다
	# 중간에 멎었어도(재료 부족 등) **마무리는 한다.** 여기서 그냥 빠져나가면
	# finished가 안 나가 필드가 입력을 영영 안 돌려받고 막까지 화면에 남는다 —
	# 재료 없이 그 자리를 조사한 플레이어는 게임이 멈춘 것으로 본다
	# (2026-08-29 자동 주행이 f1·f2에서 「진행 정지」로 실측).
	_running = false
	# 띠는 **거두는 것을 보여 준다** — 컷신이 끝났다는 신호라 즉시 지우면 뚝 끊긴다.
	# 이 노드 자체는 visible=false로 내려가므로 띠도 같이 사라지고, 다음 재생 때
	# _tween_letterbox(true)가 0에서 다시 연다.
	_set_letterbox(0.0)
	visible = false
	_clear_illustration()
	finished.emit(_cutscene_id)


## 스텝 열 실행 — choice op의 서브 열 재귀를 위해 본열과 분리.
func _run_steps(steps: Array) -> void:
	var saved_steps := _steps
	var saved_idx := _idx
	_steps = steps
	_idx = 0
	while _running and _idx < _steps.size():
		var step: Dictionary = _steps[_idx]
		_idx += 1
		await _execute(step)
	_steps = saved_steps
	_idx = saved_idx


func _execute(step: Dictionary) -> void:
	match str(step.get("op", "")):
		"dialogue":
			var steps: Array = step.get("steps", [])
			if not steps.is_empty():
				_box.start(&"", steps)
				await _box.finished
		"choice":
			await _run_choice(step.get("args", {}))
		"wait":
			await get_tree().create_timer(maxf(float(step.get("seconds", 1.0)), 0.01)).timeout
		"fade_in":
			await _fade(float(step.get("seconds", 0.6)), 0.0)
		"fade_out":
			await _fade(float(step.get("seconds", 0.6)), 1.0)
		"shake":
			await _shake(int(step.get("times", 4)), float(step.get("power", 3.0)))
		"sfx":
			AudioManager.play_sfx(StringName(str(step.get("id", ""))))
		"bgm":
			AudioManager.play_bgm(StringName(str(step.get("id", ""))))
		"set_flags":
			var args: Dictionary = step.get("args", {})
			for k: String in args:
				GameState.set_flag(k, args[k])
		"grant_item":
			var g: Dictionary = step.get("args", {})
			var gid := StringName(str(g.get("item", "")))
			var gcount := int(g.get("count", 1))
			# money 계열은 소지품이 아니라 골드로 — 원작 DON 처리.
			if ItemEffects.on_acquire(gid, gcount):
				GameState.inventory.add(gid, gcount)
				GameState.acquired.emit(&"item", gid, gcount)
		"grant_skill":
			# 성장 트리(마스터 §2.2)의 습득 지점. skills.json에 starting이 없으면
			# 전 스킬이 이미 열려 있어 이 op은 무해하게 통과한다.
			var sk: Dictionary = step.get("args", {})
			var skid := StringName(str(sk.get("skill", "")))
			if GameState.grant_skill(skid):
				print("[cutscene] 스킬 습득: %s" % skid)
		"recover":
			# 층간 휴식(계단 앞 회복소). 비율까지만 채운다 — 깎지 않는다.
			# 다 찼으면 조용히 통과한다(토스트·효과음 없음 — 지나다니며 스팸이 되지 않게).
			var rargs: Dictionary = step.get("args", {})
			var ratio := clampf(float(rargs.get("ratio", 1.0)), 0.0, 1.0)
			var max_hp := GameState.max_hp()
			var before: int = int(GameState.player_stats.get("hp", 1))
			var target := mini(maxi(int(round(float(max_hp) * ratio)), 1), max_hp)
			if target > before:
				GameState.player_stats["hp"] = target
				GameState.state_changed.emit()
				GameState.acquired.emit(&"heal", &"rest", target - before)
				AudioManager.play_sfx(&"sfx_item_get")
		"craft":
			_execute_craft(step.get("args", {}))
		"illustration":
			await _show_illustration(step.get("args", {}))
		"minigame_quiz":
			await _run_quiz(StringName(str(step.get("id", ""))))
		"minigame_battery":
			await _run_battery(StringName(str(step.get("id", ""))))
		"change_scene":
			_handoff = true
			_running = false
			get_tree().change_scene_to_file(str(step.get("path", "")))
		"actor_move":
			await _actor_move(step)
		"damage":
			_apply_field_damage(step.get("args", {}))
		"blackout":
			var benabled := bool(step.get("args", {}).get("on", true))
			if _field != null and _field.has_method("set_blackout"):
				_field.call("set_blackout", benabled)
		"start_battle":
			GameState.pending_encounter = {
				"enemies": step.get("enemies", []), "on_win_flag": str(step.get("on_win_flag", ""))
			}
			_handoff = true
			_running = false
			get_tree().change_scene_to_file("res://scenes/battle.tscn")
		_:
			push_warning("알 수 없는 컷신 op: %s" % str(step.get("op", "")))


func _fade(seconds: float, target_a: float) -> void:
	_overlay.color.a = 1.0 - target_a
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", target_a, maxf(seconds, 0.01))
	await tw.finished


## choice op — 옵션 선택 강제(취소 없음), 선택한 옵션의 steps를 서브 열로 실행.
func _run_choice(args: Dictionary) -> void:
	var options: Array = args.get("options", [])
	if options.is_empty():
		push_warning("choice 옵션 없음: %s" % _cutscene_id)
		return
	var ui := ChoiceUI.new()
	add_child(ui)
	ui.setup(options)
	var pick: int = await ui.picked
	ui.queue_free()
	var chosen: Dictionary = options[pick]
	var sub: Array = chosen.get("steps", [])
	if not sub.is_empty():
		await _run_steps(sub)


## 선택지 오버레이 — ↑↓ 이동, Enter/Z 확정. 컷신 진행은 picked 이후 재개.
class ChoiceUI:
	extends Control
	signal picked(idx: int)

	var _labels: Array[Label] = []
	var _idx := 0

	func setup(options: Array) -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.45)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_CENTER)
		box.add_theme_constant_override("separation", 10)
		add_child(box)
		for opt: Dictionary in options:
			var lbl := Label.new()
			var raw_text := str(opt.get("text", ""))
			var shown := Database.text(raw_text) if raw_text.begins_with("@") else raw_text
			lbl.text = "▶ " + shown
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 18)
			box.add_child(lbl)
			_labels.append(lbl)
		_refresh()

	func _refresh() -> void:
		for i in range(_labels.size()):
			_labels[i].add_theme_color_override(
				"font_color", Color(1.0, 0.95, 0.6) if i == _idx else Color(0.8, 0.8, 0.9)
			)

	func _move(dir: int) -> void:
		_idx = wrapi(_idx + dir, 0, _labels.size())
		_refresh()

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed(&"move_up"):
			_move(-1)
		elif event.is_action_pressed(&"move_down"):
			_move(1)
		elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact"):
			picked.emit(_idx)
			get_viewport().set_input_as_handled()


func _shake(times: int, power: float) -> void:
	if _field == null or not SettingsManager.screen_shake:
		return
	var base := _field.position
	for i in maxi(times, 1):
		_field.position = base + Vector2(randf_range(-power, power), randf_range(-power, power))
		await get_tree().create_timer(SHAKE_STEP).timeout
	_field.position = base


## 액터 이동 MVP — npc_id 또는 $player를 대상 셀로 트윈. cell은 그리드 좌표.
func _actor_move(step: Dictionary) -> void:
	var who := str(step.get("actor", ""))
	var at_arr: Array = step.get("cell", [0, 0])
	var dur := maxf(float(step.get("seconds", 0.5)), 0.05)
	var target: Node2D = null
	if who == "$player" and _field != null and _field.has_method("get_player"):
		target = _field.get_player()
	elif _field != null and _field.has_method("get_npc"):
		var npc: Node2D = _field.get_npc(who)
		target = npc
	if target == null:
		push_warning("actor_move 대상 없음: %s" % who)
		return
	var px := Vector2(float(at_arr[0]) + 0.5, float(at_arr[1]) + 1.0) * MapDefinition.TILE_PX
	var tw := create_tween()
	tw.tween_property(target, "position", px, dur).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_IN_OUT
	)
	await tw.finished


## 필드 피해 — 함정·독안개·고전압 바닥(백로그 §1.2 층별 소기믹 공용).
## 수치·조건은 전부 데이터(args)가 소유한다(AGENTS.md: 소스 하드코딩 금지):
##   amount:int(>0, 필수) · protect_item:String(선택, 1개 이상 보유 시 무효) ·
##   sfx:String(선택, 효과음 id).
## HP는 1에 멈춘다 — 필드 사망 흐름(게임 오버 씬·부활)이 없어 0이 되면 화면만
## 살아 있고 입력만 막힌 상태가 된다. 독·전류 바닥이 "통행료"가 되는 것이 의도다.
## 보호 보유 시에는 조용히 통과한다 — zone 트리거가 안에 서 있는 동안 매 틱 발동
## 하므로(TriggerSystem은 통과 차단이 아니라 발동만 한다), 막았다는 연출을 매 틱
## 내면 방독면을 쓰고도 독안개를 뚫을 때마다 화면이 떨려 "쓴 게 손해"가 된다.
func _apply_field_damage(args: Dictionary) -> void:
	var amount := maxi(int(args.get("amount", 0)), 0)
	if amount <= 0:
		push_warning("damage amount 누락/무효: %s" % _cutscene_id)
		return
	var protect := StringName(str(args.get("protect_item", "")))
	if not String(protect).is_empty() and GameState.inventory.count(protect) > 0:
		return
	var sfx := StringName(str(args.get("sfx", "")))
	if not String(sfx).is_empty():
		AudioManager.play_sfx(sfx)
	var stats: Dictionary = GameState.player_stats
	stats["hp"] = maxi(int(stats.get("hp", 1)) - amount, 1)
	GameState.state_changed.emit()


static func load_cutscene(cutscene_id: StringName) -> Dictionary:
	var path := "%s/%s.json" % [CUTSCENES_DIR, cutscene_id]
	if not FileAccess.file_exists(path):
		push_warning("cutscene 없음: %s" % path)
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


const MINIGAMES_DIR := "res://data/minigames"


## 퀴즈 미니게임 — 통과(passed=true)할 때까지 재도전. 실패해도 컷신은 계속.
func _run_quiz(minigame_id: StringName) -> void:
	var cfg := _load_minigame(minigame_id)
	if cfg.is_empty():
		return
	var quiz := QuizMinigame.new()
	add_child(quiz)
	while true:
		quiz.start(cfg)
		var passed: bool = await quiz.finished
		if passed:
			break
	quiz.queue_free()


## 배터리 회로 퍼즐 — 목표 전압 일치 시 통과.
func _run_battery(minigame_id: StringName) -> void:
	var cfg := _load_minigame(minigame_id)
	if cfg.is_empty():
		return
	var game := BatteryCircuitMinigame.new()
	add_child(game)
	game.start(cfg)
	await game.finished
	game.queue_free()


func _load_minigame(minigame_id: StringName) -> Dictionary:
	var path := "%s/%s.json" % [MINIGAMES_DIR, minigame_id]
	if not FileAccess.file_exists(path):
		push_warning("미니게임 데이터 없음: %s" % path)
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


## craft op — requires 소비 후 grant 지급 + 플래그. 부족 시 경고하고 컷신 중단.
func _execute_craft(args: Dictionary) -> void:
	var inv := GameState.inventory
	var requires: Dictionary = args.get("requires", {})
	for item_id: String in requires:
		if inv.count(StringName(item_id)) < int(requires[item_id]):
			push_warning("craft 재료 부족: %s — 컷신 중단(%s)" % [item_id, _cutscene_id])
			_running = false
			return
	for item_id2: String in requires:
		inv.remove(StringName(item_id2), int(requires[item_id2]))
	var grant: Dictionary = args.get("grant", {})
	for item_id3: String in grant:
		inv.add(StringName(item_id3), int(grant[item_id3]))
	if args.has("flag"):
		GameState.set_flag(str(args["flag"]), true)


## 키아트 표시 — assets/keyart/<id>.png. **그림이 아직 없으면 조용히 건너뛴다.**
##
## 데이터(컷신)가 그림보다 먼저 들어오는 순서라, 미납품을 오류로 다루면 컷신 전체가 멈춘다.
## 대신 validate가 "키아트 미납품 N종"을 상시 보고해 잊히지 않게 한다.
func _show_illustration(args: Dictionary) -> void:
	var art_id := str(args.get("id", ""))
	var fade := float(args.get("fade", 0.4)) / SettingsManager.battle_speed_factor()
	if art_id.is_empty():
		await _fade_illustration(0.0, fade)
		_clear_illustration()
		return
	var path := "%s%s.png" % [KEYART_DIR, art_id]
	if not ResourceLoader.exists(path):
		path = "%s%s.png" % [KEYART_FALLBACK_DIR, art_id]
	if not ResourceLoader.exists(path):
		return  # 폴백조차 없다 — 대사·연출은 그대로 진행된다
	_illustration.texture = load(path)
	_illustration.visible = true
	await _fade_illustration(1.0, fade)


func _fade_illustration(target: float, seconds: float) -> void:
	if seconds <= 0.01:
		_illustration.modulate.a = target
		return
	var tween := create_tween()
	tween.tween_property(_illustration, "modulate:a", target, seconds)
	await tween.finished


func _clear_illustration() -> void:
	if _illustration == null:
		return
	_illustration.visible = false
	_illustration.texture = null
	_illustration.modulate.a = 0.0
