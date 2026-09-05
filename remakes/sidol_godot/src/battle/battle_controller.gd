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


## 적 턴이 끝났으니 다시 플레이어 차례 — 씬 컨트롤러가 적 페이즈를 직접 굴린 뒤 부른다.
##
## 2026-08-28 실측 버그: 씬 흐름은 `enemy_turn()`을 쓰지 않고 BattleEnemyPhase로 직접
## 적을 굴리는데, 상태를 되돌리는 곳이 `_advance_enemy()`뿐이라 아무도 그걸 부르지 않았다.
## 그래서 state가 ENEMY_TURN에 갇히고 `submit_player_command`가 조용히 무시돼
## **2턴째부터 플레이어 공격이 전혀 들어가지 않았다**(연출과 커맨드 창은 정상 동작해
## 화면만 보면 알 수 없다). 4턴 프루브: 데미지 1, 0, 0, 0.
func begin_player_phase() -> void:
	if state == TurnState.FINISHED:
		return
	if player_combatant != null and player_combatant.is_down():
		return
	if _all_enemies_down():
		return
	active_enemy_idx = 0
	state = TurnState.PLAYER_COMMAND


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


## 스킬 상태이상 부여 — targeting별 실제 대상(연출 종료 시점 호출).
##
## skills.json의 status_effects는 **효과 id**(burn 등)이지 Combatant의 kind가 아니다.
## 구판은 그 문자열을 kind로 그대로 넘겨, Combatant가 아는 dot/buff_damage_taken과
## 매칭되지 않아 **burn과 디버그 실드가 아무 효과도 내지 않았다**(paralysis만 우연히 일치).
## turns/magnitude도 3/10 하드코딩이라 실드의 50% 경감이 10%로 깎여 있었다.
func apply_skill_effects(skill: Dictionary) -> void:
	var defs: Dictionary = BattleSetup.status_effect_defs()
	var duration_mult := SettingsManager.difficulty_mult("status_duration_mult")
	for effect_id: String in skill.get("status_effects", []):
		var def: Dictionary = defs.get(effect_id, {})
		if def.is_empty():
			push_warning("정의 없는 상태이상 id: %s (skills.json status_effect_defs)" % effect_id)
			continue
		var turns := maxi(1, int(round(int(def.get("turns", 3)) * duration_mult)))
		for t in skill_targets(skill):
			(
				t
				. attach_effect(
					{
						"kind": StringName(str(def.get("kind", ""))),
						"turns": turns,
						"magnitude": int(def.get("magnitude", 0)),
					}
				)
			)


## 스킬 targeting에 따른 실제 대상 목록
func skill_targets(skill: Dictionary) -> Array[Combatant]:
	var out: Array[Combatant] = []
	match str(skill.get("targeting", "single")):
		"all_enemies":
			for e in enemy_combatants:
				if not e.is_down():
					out.append(e)
		"self":
			out.append(player_combatant)
		_:
			var t := _first_alive_enemy()
			if t != null:
				out.append(t)
	return out


func _resolve_attack(attacker: Combatant, target: Combatant, cmd: Dictionary) -> void:
	var base := DamageCalculator.player_hit(int(cmd.get("ap", attacker.ap)), EnemyManager.rng)
	# 기본 공격 속성 = 장착 무기의 element. 구판은 물리 고정이라 무기의 element 필드가
	# 사문화돼 있었다 — 전기충격기를 들어도 기계 계열 약점을 못 찔렀다.
	var entry := _apply_player_damage(target, base, GameState.attack_element(), cmd)
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
	var is_just := timing_mult > 1.0
	if is_just:
		dmg = int(dmg * timing_mult)

	# 크리티컬 판정: 기본 6% + 타이밍 성공(Just Hit) 시 60%
	var crit_rate := 0.60 if is_just else 0.06
	var crit := EnemyManager.rng.randf() < crit_rate
	if crit:
		dmg = int(dmg * 1.5)

	dmg = target.take_damage(dmg)
	var broke := false
	if weak:
		broke = target.register_weak_hit()
	return {
		"amount": dmg,
		"enemy_index": _alive_enemy_index(target),
		"weak": weak,
		"break": broke,
		"just": is_just,
		"crit": crit,
	}


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
			user.attack_stat(),
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
