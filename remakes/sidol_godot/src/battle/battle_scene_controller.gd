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
	_ui.item_selected.connect(_on_item_selected)


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
	var data := BattleSetup.load_skills()
	_skills.assign(data["skills"])
	_timing_cfg = data["timing"]


func _setup_combatants(def: Dictionary) -> void:
	var stats: Dictionary = GameState.player_stats
	# 공격력은 장착 무기를 더한 값 — GameState가 단일 출처.
	player_combatant = Combatant.new(
		"부싯돌", int(stats["hp"]), GameState.attack_power(), GameState.defense_power()
	)
	# 보유 스킬은 GameState가 단일 출처 — 구판은 여기 5종이 하드코딩돼 있었고
	# 아무도 읽지 않았으며 이름도 틀렸다(flame_beaker ≠ flame_beaker_throw).
	player_combatant.skills.assign(GameState.owned_skill_ids())
	var built := BattleSetup.build_enemies(def)
	enemies.assign(built["combatants"])
	_enemy_ids.assign(built["ids"])


## 커맨드 분기는 번역 불변 id로 한다 — 구판은 tr()로 만든 한국어 문자열을 그대로 비교해
## 언어를 바꾸면 전투 커맨드가 통째로 먹통이 됐다(2026-08-28 l10n 도입 후 실측).
func _on_command(cmd_id: StringName) -> void:
	if _busy:
		return
	match cmd_id:
		&"attack":
			_begin_player_action(
				{
					"type": &"attack",
					"ap": player_combatant.attack_stat(),
					"target": _first_alive_enemy(),
				},
				&"atk_basic"
			)
		&"skill":
			_ui.show_skill_menu()
		&"guard":
			player_combatant.attach_effect(
				{"kind": &"buff_damage_taken", "turns": 1, "magnitude": 50}
			)
			_end_player_defend()
		&"item":
			_ui.show_item_menu()
		&"flee":
			battle_ended.emit(&"flee", {})
			BattleRewards.apply(&"flee", {}, player_combatant.hp, _on_win_flag)
			get_tree().change_scene_to_file("res://scenes/field.tscn")


func _on_skill_selected(skill: Dictionary) -> void:
	var move_id := StringName(str(skill.get("choreography_id", "atk_flint_basic")))
	_begin_player_action(
		{
			"type": &"skill",
			"skill": skill,
			"ap": player_combatant.attack_stat(),
		},
		move_id
	)


## 도구 사용 — 회복·상태이상 해제·공격 버프. 판정과 적용은 ItemEffects가 단일 창구.
## 구판은 hp_restore만 처리해 진통 파스·해열제·녹용주 같은 항목이 메뉴에도 안 떴다.
func _on_item_selected(item_def: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	_ui.hide_menu()
	var results := ItemEffects.use_in_battle(item_def, player_combatant)
	GameState.inventory.remove(StringName(str(item_def["id"])), 1)
	var healed := int(item_def.get("hp_restore", 0))
	if healed > 0:
		_presenter.show_player_heal(mini(healed, player_combatant.max_hp))
	if not results.is_empty():
		_presenter.show_player_note(" · ".join(results))
	_ui.refresh_bars()
	_end_player_defend()


## 플레이어 액션 개시 — 커맨드 제출(판정) → 안무 재생(표현) → 종료 시 턴 해결
func _begin_player_action(command: Dictionary, move_id: StringName) -> void:
	if _busy:
		return
	_busy = true
	_ui.hide_menu()
	# 타이밍 버튼 — sweet zone 입력 시 피해 보너스(skills.json timing 섹션)
	var window := TimingRing.window_for(command, _timing_cfg)
	if window > 0.0:
		var just: bool = await _presenter.play_timing_ring(_alive_enemy_index(), window)
		command["timing_mult"] = float(_timing_cfg.get("mult", 1.2)) if just else 1.0
	controller.submit_player_command(command)
	_pending_action = command
	_pending_pops.assign(command.get("damages", []))
	var skill: Dictionary = command.get("skill", {})
	_pending_element = StringName(str(skill.get("element", "physical")))
	_play_move(move_id)


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
		controller.apply_skill_effects(_pending_action["skill"])
	_pending_action = {}
	_pending_pops.clear()
	_resolve_turn()


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
			await BattleEnemyPhase.dodge_sequence(_dodge, edef, _presenter, _ui, player_combatant)
		elif actor != null:
			BattleEnemyPhase.regular_attack(actor, player_combatant, _presenter)
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


func _end_player_defend() -> void:
	# 적 턴만 진행
	var attacker := _first_alive_enemy()
	if attacker != null:
		BattleEnemyPhase.regular_attack(attacker, player_combatant, _presenter)
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
	await get_tree().create_timer(0.9).timeout
	var rewards := BattleRewards.compute(_enemy_ids)
	battle_ended.emit(result, rewards)
	# apply가 성장 결과를 돌려준다 — 요약 패널에 레벨업을 실으려면 먼저 반영해야 한다.
	var growth := BattleRewards.apply(result, rewards, player_combatant.hp, _on_win_flag)
	if result == &"win":
		await _show_reward_summary(rewards, growth)
	else:
		await get_tree().create_timer(0.9).timeout
	get_tree().change_scene_to_file("res://scenes/field.tscn")


## 보상 요약(Q7) — 입력으로 넘기거나 자동으로 닫힌다.
func _show_reward_summary(rewards: Dictionary, growth: Dictionary) -> void:
	var panel := BattleResultPanel.new()
	add_child(panel)
	panel.show_summary(rewards, growth)
	await panel.dismissed


func _all_enemies_down() -> bool:
	for e in enemies:
		if not e.is_down():
			return false
	return true
