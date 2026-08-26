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
var speed_multiplier := 1.0  # ×1/×2/×4 — SettingsManager에서 조절
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
	var raw := DamageCalculator.enemy_hit(enemy.ap, EnemyManager.rng)
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
	var base := DamageCalculator.player_hit(int(cmd.get("ap", attacker.ap)), EnemyManager.rng)
	var entry := _apply_player_damage(target, base, &"physical", cmd)
	cmd["damage"] = int(entry["amount"])
	cmd["damages"] = [entry]


## 플레이어 피해 일원화 — 약점 ×1.5 · 타이밍 보너스 · 브레이크 게이지.
## skill_hit의 weaknesses 인자는 여기서 일원 처리하므로 빈 배열 전달.
func _apply_player_damage(
	target: Combatant, base: int, element: StringName, cmd: Dictionary
) -> Dictionary:
	var weak: bool = element in target.weaknesses
	var dmg := maxi(base, 1)
	if weak:
		dmg = int(dmg * 1.5)
	var timing_mult := float(cmd.get("timing_mult", 1.0))
	if timing_mult > 1.0:
		dmg = int(dmg * timing_mult)
	dmg = target.take_damage(dmg)
	var broke := false
	if weak:
		broke = target.register_weak_hit()
	return {"amount": dmg, "enemy_index": _alive_enemy_index(target), "weak": weak, "break": broke}


func _resolve_skill(user: Combatant, target: Combatant, cmd: Dictionary) -> void:
	var skill: Dictionary = cmd.get("skill", {})
	var targeting := str(skill.get("targeting", "single"))
	var targets: Array[Combatant] = [target]
	if targeting == "all_enemies":
		targets.clear()
		for e in enemy_combatants:
			if not e.is_down():
				targets.append(e)
	elif targeting == "self":
		targets = [user]
	var results: Array = []
	for t in targets:
		if t == user:
			continue  # 자기 버프 스킬 — 피해 판정 제외(효과는 상태이상으로만)
		var base := DamageCalculator.skill_hit(
			int(skill.get("power", 10)),
			user.ap,
			StringName(str(skill.get("element", "physical"))),
			[],
			EnemyManager.rng
		)
		results.append(
			_apply_player_damage(t, base, StringName(str(skill.get("element", "physical"))), cmd)
		)
	cmd["damage"] = 0 if results.is_empty() else int(results[0]["amount"])
	cmd["damages"] = results


## 적 배열에서의 생존 인덱스(프리젠테이션 팝 위치용)
func _alive_enemy_index(c: Combatant) -> int:
	for i in enemy_combatants.size():
		if enemy_combatants[i] == c:
			return i
	return 0


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
