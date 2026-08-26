class_name BattleSceneController
extends Node2D
## 전투 씬 조립 + 턴 흐름 중재. UI는 BattleUI, 연출은 BattlePresenter,
## 판정은 BattleController — 각 계층 분리(docs/02_design/01_oop_redesign.md §5).

signal battle_ended(result: StringName, rewards: Dictionary)

var controller := BattleController.new()
var player_combatant: Combatant
var enemies: Array[Combatant] = []
var _enemy_ids: Array[String] = []
var _on_win_flag := ""  # 승리 시 세팅되는 시나리오 플래그 (pending_encounter에서 전달)

var _ui: BattleUI
var _busy := false
var _skills: Array[Dictionary] = []

# 연출 (로직↔연출 분리: ChoreographyRunner + BattlePresenter)
var _runner: ChoreographyRunner
var _presenter: BattlePresenter
var _dodge: DodgePhase  # 보스전 회피 페이즈 (턴제+회피 하이브리드)
var _pending_action := {}
var _pending_pops: Array[Dictionary] = []  # damages 표현 큐 (apply_damage 프레임마다 1개)
var _pending_element := &"physical"
var _timing_cfg := {}  # skills.json timing 섹션 — 타임윈도우·보너스 배율


func _ready() -> void:
	var def: Dictionary = GameState.pending_encounter
	GameState.pending_encounter = {}
	_on_win_flag = str(def.get("on_win_flag", ""))
	_setup_combatants(def)
	_load_skills()
	_setup_ui()
	_setup_presentation()
	controller.start(player_combatant, enemies)
	AudioManager.play_bgm(&"bgm_boss" if _is_boss_fight() else &"bgm_battle")
	_ui.show_command_menu()


func _is_boss_fight() -> bool:
	for eid in _enemy_ids:
		if bool(Database.get_enemy_def(StringName(eid)).get("is_boss", false)):
			return true
	return false


func _setup_ui() -> void:
	_ui = BattleUI.new()
	add_child(_ui)
	_ui.build(player_combatant, enemies, _skills)
	_ui.command_selected.connect(_on_command)
	_ui.skill_selected.connect(_on_skill_selected)


## 연출 계층 구성 — 안무 실행기와 프리젠터를 바인딩
func _setup_presentation() -> void:
	_presenter = BattlePresenter.new()
	add_child(_presenter)
	_presenter.setup(self)
	_presenter.build_sprites(_enemy_ids)

	_runner = ChoreographyRunner.new()
	add_child(_runner)
	_runner.bind_presenter(_presenter)
	_runner.damage_frame.connect(_on_choreo_damage_frame)
	_runner.move_finished.connect(_on_choreo_finished)

	_dodge = DodgePhase.new()
	_dodge.visible = false
	add_child(_dodge)


func _load_skills() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/skills.json"))
	if typeof(raw) == TYPE_DICTIONARY:
		for s: Dictionary in raw.get("skills", []):
			_skills.append(s)
		_timing_cfg = raw.get("timing", {})


func _setup_combatants(def: Dictionary) -> void:
	var stats: Dictionary = GameState.player_stats
	player_combatant = Combatant.new("부싯돌", int(stats["hp"]), int(stats["ap"]), 10)
	player_combatant.skills = [
		&"combo_punch", &"flame_beaker", &"debug_shield", &"volt_arc", &"ember_of_flint"
	]

	for eid in def.get("enemies", ["mad_eye"]):
		# field/cutscene은 species 원본 딕셔너리를 넘길 수 있다 — id만 추출
		var eid_str := str(eid.get("id", eid)) if eid is Dictionary else str(eid)
		var edef: Dictionary = Database.get_enemy_def(StringName(eid_str))
		var hp_r: Array = edef.get("hp_range", [20, 40])
		var hp_val: int = randi_range(int(hp_r[0]), int(hp_r[1]))
		var c := Combatant.new(
			str(edef.get("display_name", eid_str)), hp_val,
			int(edef.get("ap", 15)), int(edef.get("dp", 5))
		)
		for w in edef.get("weaknesses", []):
			c.weaknesses.append(StringName(str(w)))
		enemies.append(c)
		_enemy_ids.append(eid_str)


func _on_command(cmd_text: String) -> void:
	if _busy:
		return
	match cmd_text:
		"공격":
			_begin_player_action(
				{
					"type": &"attack",
					"ap": player_combatant.ap,
					"target": _first_alive_enemy(),
				},
				&"atk_basic"
			)
		"기술":
			_ui.show_skill_menu()
		"방어":
			player_combatant.attach_effect(
				{"kind": &"buff_damage_taken", "turns": 1, "magnitude": 50}
			)
			_end_player_defend()
		"도망":
			battle_ended.emit(&"flee", {})
			_exit_battle(&"flee", {})


func _on_skill_selected(skill: Dictionary) -> void:
	var move_id := StringName(str(skill.get("choreography_id", "atk_flint_basic")))
	_begin_player_action(
		{
			"type": &"skill",
			"skill": skill,
			"ap": player_combatant.ap,
		},
		move_id
	)


## 플레이어 액션 개시 — 커맨드 제출(판정) → 안무 재생(표현) → 종료 시 턴 해결
func _begin_player_action(command: Dictionary, move_id: StringName) -> void:
	if _busy:
		return
	_busy = true
	_ui.hide_menu()
	# 타이밍 버튼 — sweet zone 입력 시 피해 보너스(skills.json timing 섹션)
	var window := _timing_window_for(command)
	if window > 0.0:
		var just: bool = await _presenter.play_timing_ring(_alive_enemy_index(), window)
		command["timing_mult"] = float(_timing_cfg.get("mult", 1.2)) if just else 1.0
	controller.submit_player_command(command)
	_pending_action = command
	_pending_pops.assign(command.get("damages", []))
	var skill: Dictionary = command.get("skill", {})
	_pending_element = StringName(str(skill.get("element", "physical")))
	_play_move(move_id)


## 타이밍 윈도우 — 공격·단일 대상 공격 스킬만 (버프/자기 스킬 제외)
func _timing_window_for(command: Dictionary) -> float:
	var window := float(_timing_cfg.get("window", 0.0))
	if window <= 0.0:
		return 0.0
	var ctype := StringName(str(command.get("type", &"attack")))
	if ctype == &"attack":
		return window
	if ctype == &"skill":
		var skill: Dictionary = command.get("skill", {})
		if String(skill.get("targeting", "")) == "single":
			return window
	return 0.0


## 안무 재생 — battle_moves JSON을 러너로 재생(연출은 프리젠터 위임).
func _play_move(move_id: StringName) -> void:
	_presenter.target_index = _alive_enemy_index()
	if _runner.is_playing():
		return
	var move_data := _runner.load_move_by_id(move_id)
	if move_data.is_empty():
		move_finished_fallback()
		return
	_runner.play(move_data)


## 안무 데이터 부재 시 폴백 — 즉시 턴 해결
func move_finished_fallback() -> void:
	push_warning("안무 폴백: 데이터 없음, 즉시 해결")
	_pending_action = {}
	_pending_pops.clear()
	_resolve_turn()


## logic 채널 apply_damage 타이밍 — 판정은 이미 BattleController가 수행했고
## 여기서는 그 결과(damages 큐)를 화면에 표현만 한다(이중 적용 금지).
func _on_choreo_damage_frame() -> void:
	if _pending_pops.is_empty():
		return
	var pop: Dictionary = _pending_pops.pop_front()
	var idx := int(pop.get("enemy_index", 0))
	_presenter.show_damage_number(int(pop["amount"]), false, _pending_element, idx)
	if bool(pop.get("weak", false)):
		_presenter.show_flag_pop("WEAK!", Color(1.0, 0.92, 0.35), idx)
	if bool(pop.get("break", false)):
		_presenter.show_flag_pop("BREAK!", Color(1.0, 0.45, 0.2), idx)
	if idx < _presenter.enemy_sprites.size():
		_presenter.hurt_flash(_presenter.enemy_sprites[idx])
	_presenter.hitstop()


func _on_choreo_finished(_move_id: StringName) -> void:
	if _pending_action.get("type", &"") == &"skill":
		var skill: Dictionary = _pending_action["skill"]
		for effect_kind: String in skill.get("status_effects", []):
			for t in _skill_targets(skill):
				t.attach_effect({"kind": StringName(effect_kind), "turns": 3, "magnitude": 10})
	_pending_action = {}
	_pending_pops.clear()
	_resolve_turn()


## 스킬 targeting에 따른 실제 대상 목록
func _skill_targets(skill: Dictionary) -> Array[Combatant]:
	var out: Array[Combatant] = []
	match str(skill.get("targeting", "single")):
		"all_enemies":
			for e in enemies:
				if not e.is_down():
					out.append(e)
		"self":
			out.append(player_combatant)
		_:
			var t := _first_alive_enemy()
			if t != null:
				out.append(t)
	return out


func _alive_enemy_index() -> int:
	for i in enemies.size():
		if not enemies[i].is_down():
			return i
	return 0


func _first_alive_enemy() -> Combatant:
	for e in enemies:
		if not e.is_down():
			return e
	return null


func _resolve_turn() -> void:
	_busy = true
	_ui.hide_menu()

	# 적 턴 처리
	if controller.state == BattleController.TurnState.ENEMY_TURN:
		var idx := _alive_enemy_index()
		var edef: Dictionary = Database.get_enemy_def(StringName(_enemy_ids[idx]))
		var actor: Combatant = null
		for e in enemies:
			if not e.is_down():
				actor = e
				break
		if actor != null and actor.is_broken():
			# 브레이크 지속 — 행동 불가, 턴 소비로 해제
			actor.broken_turns -= 1
			_presenter.show_flag_pop("BREAK!", Color(1.0, 0.45, 0.2), idx)
		elif actor != null and not (edef.get("dodge_phase", {}) as Dictionary).is_empty():
			await _run_dodge_phase(edef)  # 보스 특수공격 — 회피 페이즈
		elif actor != null:
			var raw := DamageCalculator.enemy_hit(actor.ap, EnemyManager.rng)
			var actual: int = player_combatant.take_damage(raw)
			_presenter.show_damage_number(actual, true)
			_presenter.hurt_flash(_presenter.player_sprite)
			_presenter.play_screen_kf({"shake": 3})
		controller.turn_count += 1
		_tick_effects()

	if (
		controller.state == BattleController.TurnState.FINISHED
		or player_combatant.is_down()
		or _all_enemies_down()
	):
		var result: StringName = &"win" if _all_enemies_down() else &"lose"
		_show_result(result)
		return

	_ui.refresh_bars()
	_busy = false
	_ui.set_turn_text("TURN %d" % (controller.turn_count + 1))
	_ui.show_command_menu()


## 보스전 회피 페이즈 — 탄막을 실시간으로 피해야 한다(턴제+회피 하이브리드).
## 피격 횟수 × dodge_damage_per_hit 가 플레이어 피해로 환산된다.
func _run_dodge_phase(edef: Dictionary) -> int:
	var cfg: Dictionary = edef["dodge_phase"]
	_ui.set_turn_text("!! 피하라 !!")
	_dodge.visible = true
	_dodge.start(maxf(float(cfg.get("duration", 4.0)), 0.5), cfg)
	var hits: int = await _dodge.phase_complete
	_dodge.stop()
	_dodge.visible = false

	var per_hit := maxi(int(edef.get("dodge_damage_per_hit", 3)), 0)
	var actual: int = player_combatant.take_damage(hits * per_hit)
	if actual > 0:
		_presenter.show_damage_number(actual, true)
		_presenter.hurt_flash(_presenter.player_sprite)
		_presenter.play_screen_kf({"shake": 3, "flash": "#ff3333", "a": 0.25})
	print("[battle] dodge phase done: hits=%d dmg=%d" % [hits, actual])
	return hits


func _end_player_defend() -> void:
	# 적 턴만 진행
	for e in enemies:
		if not e.is_down():
			var raw := DamageCalculator.enemy_hit(e.ap, EnemyManager.rng)
			var actual: int = player_combatant.take_damage(raw)
			_presenter.show_damage_number(actual, true)
			_presenter.hurt_flash(_presenter.player_sprite)
			_presenter.play_screen_kf({"shake": 3})
			break
	_tick_effects()
	_ui.refresh_bars()

	if player_combatant.is_down():
		_show_result(&"lose")
		return
	_ui.show_command_menu()


func _tick_effects() -> void:
	for c: Combatant in ([player_combatant] as Array[Combatant]) + enemies:
		c.tick_effects()


func _show_result(result: StringName) -> void:
	_busy = true
	_ui.show_result(result)
	await get_tree().create_timer(1.2).timeout
	var rewards := _compute_rewards()
	battle_ended.emit(result, rewards)
	_exit_battle(result, rewards)


## 보상 산출 — monsters.json 종별 exp/money 범위에서 난수 합산(하드코딩 금지).
func _compute_rewards() -> Dictionary:
	var exp_total := 0
	var money_total := 0
	for eid in _enemy_ids:
		var edef := Database.get_enemy_def(StringName(eid))
		var exp_range: Array = edef.get("exp", [5, 10])
		var money_range: Array = edef.get("money", [50, 100])
		exp_total += randi_range(int(exp_range[0]), int(exp_range[1]))
		money_total += randi_range(int(money_range[0]), int(money_range[1]))
	return {"exp": exp_total, "money": money_total}


func _exit_battle(result: StringName, rewards: Dictionary) -> void:
	# 전투 결과를 GameState에 반영
	GameState.player_stats["hp"] = player_combatant.hp
	if result == &"win":
		GameState.player_stats["money"] = (
			int(GameState.player_stats["money"]) + int(rewards["money"])
		)
		var growth := GameState.grant_exp(int(rewards["exp"]))
		if bool(growth["level_up"]):
			print("[battle] level up → %d" % int(growth["level"]))
		if not _on_win_flag.is_empty():
			GameState.set_flag(_on_win_flag, true)
		SaveManager.request_autosave("전투 승리")  # 필드 복귀 후 consume
	get_tree().change_scene_to_file("res://scenes/field.tscn")


func _all_enemies_down() -> bool:
	for e in enemies:
		if not e.is_down():
			return false
	return true
