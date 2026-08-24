class_name BattleController
extends Node
## 턴제 전투 컨트롤러 — 빠르고 아픈 전투 (04_uiux §1.4 품질 기준).
## 설계: 로직(TurnStateMachine) ↔ 연출(BattlePresenter) 완전 분리.
## 스피디: 기본 애니 0.25s, 히트스톱 0.06s, 홀드 시 연속 진행.

signal battle_started(enemy_def: Dictionary)
signal turn_changed(turn_count: int)
signal battle_finished(result: StringName)  # &"win" / &"lose" / &"flee"

enum TurnState { PLAYER_COMMAND, RESOLVING, ENEMY_TURN, CHECK_END, FINISHED }

var state: TurnState = TurnState.PLAYER_COMMAND
var turn_count := 0
var player_combatant: Combatant
var enemy_combatants: Array[Combatant] = []
var active_enemy_idx := 0
var speed_multiplier := 1.0    # ×1/×2/×4 — SettingsManager에서 조절
var _rng := RandomNumberGenerator.new()


func start(p_player: Combatant, p_enemies: Array[Combatant]) -> void:
	player_combatant = p_player
	enemy_combatants = p_enemies
	active_enemy_idx = 0
	turn_count = 0
	state = TurnState.PLAYER_COMMAND
	battle_started.emit({})


func submit_player_command(cmd: Dictionary) -> void:
	if state != TurnState.PLAYER_COMMAND:
		return
	state = TurnState.RESOLVING
	var target: Combatant = cmd.get("target", _first_alive_enemy())
	match cmd.get("type", &"attack"):
		&"attack":
			_resolve_attack(player_combatant, target, cmd)
		&"skill":
			_resolve_skill(player_combatant, target, cmd)
		&"item":
			pass  # TODO(Phase 4): 소모품 사용
		&"flee":
			battle_finished.emit(&"flee")
			return
	_end_player_phase()


func _end_player_phase() -> void:
	if _all_enemies_down():
		state = TurnState.FINISHED
		battle_finished.emit(&"win")
		return
	state = TurnState.ENEMY_TURN


func enemy_turn() -> Dictionary:
	if state != TurnState.ENEMY_TURN:
		return {}
	var enemy := _current_enemy()
	if enemy == null or enemy.is_down():
		return _advance_enemy()
	var raw := DamageCalculator.enemy_hit(enemy.stats.ap, EnemyManager.rng)
	player_combatant.take_damage(raw)
	return {"damage": raw, "attacker": enemy}


func _advance_enemy() -> Dictionary:
	active_enemy_idx += 1
	if active_enemy_idx >= enemy_combatants.size():
		active_enemy_idx = 0
		turn_count += 1
		_tick_status_effects()
		state = TurnState.PLAYER_COMMAND if not player_combatant.is_down() else TurnState.FINISHED
		if state == TurnState.FINISHED:
			battle_finished.emit(&"lose")
	return {}


func _resolve_attack(attacker: Combatant, target: Combatant, cmd: Dictionary) -> void:
	var dmg := DamageCalculator.player_hit(
		int(cmd.get("ap", attacker.stats.ap)), EnemyManager.rng)
	target.take_damage(dmg)
	cmd["damage"] = dmg


func _resolve_skill(user: Combatant, target: Combatant, cmd: Dictionary) -> void:
	var skill: Dictionary = cmd.get("skill", {})
	var dmg := DamageCalculator.skill_hit(
		int(skill.get("power", 10)), user.stats.ap,
		StringName(str(skill.get("element", "physical"))),
		[], EnemyManager.rng)
	target.take_damage(dmg)
	cmd["damage"] = dmg


func _tick_status_effects() -> void:
	for c in _all_combatants():
		c.tick_status_effects()


func _current_enemy() -> Combatant:
	if active_enemy_idx < enemy_combatants.size():
		return enemy_combatants[active_enemy_idx]
	return null


func _first_alive_enemy() -> Combatant:
	for e in enemy_combatants:
		if not e.is_down():
			return e
	return null


func _all_enemies_down() -> bool:
	for e in enemy_combatants:
		if not e.is_down():
			return false
	return true


func _all_combatants() -> Array[Combatant]:
	var out: Array[Combatant] = [player_combatant]
	out.append_array(enemy_combatants)
	return out
