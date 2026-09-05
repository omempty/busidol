class_name BattleSceneController
extends Node2D
## 전투 씬 조립 + 턴 흐름 중재. UI는 BattleUI, 연출은 BattlePresenter,
## 판정은 BattleController — 각 계층 분리(docs/02_design/01_oop_redesign.md §5).

signal battle_ended(result: StringName, rewards: Dictionary)

## 결과 id → 번역 키. **문자열을 이어 붙여 키를 만들지 않는다** — validate가
## ui.csv와 양방향 대조하는데 동적 키는 대조가 안 된다(2026-08-30 관문이 잡았다).
## 결과 id → 원작 보이스. 근거: WARMODE.C:1204~1206 —
##   case 0: domang.voc / case 1: win.voc / case -1: dead.voc
## **셋은 바이트 단위로 같은 파일이다**(sha256 c4f6afcc…) — 원작에서 승리·패배·도망이
## 한 소리였다. 고증이므로 그대로 둔다(obj 173과 같은 처리).
const RESULT_VOICES := {
	&"win": &"win",
	&"lose": &"dead",
	&"flee": &"domang",
}
const RESULT_KEYS := {
	&"win": "UI_BATTLE_RESULT_WIN",
	&"lose": "UI_BATTLE_RESULT_LOSE",
	&"flee": "UI_BATTLE_RESULT_FLEE",
}

var controller := BattleController.new()
var player_combatant: Combatant
var enemies: Array[Combatant] = []
var _enemy_ids: Array[String] = []
var _on_win_flag := ""  # 승리 시 세팅되는 시나리오 플래그 (pending_encounter에서 전달)

var _ui: BattleUI
var _pause_menu: PauseMenu
var _busy := false
## 현재 지목한 적(Q/E) · 직전 행동(R 반복) — 둘 다 UI가 아니라 여기서 상태를 갖는다.
var _target_index := 0
var _last_action: Dictionary = {}
var _skills: Array[Dictionary] = []
var _flee_failures := 0  # 이 전투에서 도망에 실패한 횟수 — 시도마다 확률이 오른다

# 연출 (로직↔연출 분리: ChoreographyRunner + BattlePresenter)
var _runner: ChoreographyRunner
var _presenter: BattlePresenter
var _dodge: DodgePhase  # 보스전 회피 페이즈 (턴제+회피 하이브리드)
var _pending_action := {}
var _pending_pops: Array[Dictionary] = []  # damages 표현 큐 (apply_damage 프레임마다 1개)
var _pending_element := &"physical"
var _timing_cfg := {}  # skills.json timing 섹션 — 타임윈도우·보너스 배율


func _ready() -> void:
	get_tree().paused = false
	var def: Dictionary = GameState.pending_encounter
	GameState.pending_encounter = {}
	_on_win_flag = str(def.get("on_win_flag", ""))
	var is_advantage := bool(def.get("advantage", false))
	var is_ambush := bool(def.get("ambush", false))
	_setup_combatants(def)
	_load_skills()
	_setup_ui()
	_setup_presentation()
	controller.start(player_combatant, enemies)
	AudioManager.play_bgm(&"bgm_boss" if _is_boss_fight() else &"bgm_battle")
	BattleLog.clear()  # 이전 판의 줄이 남으면 첫 화면부터 거짓말이 된다
	BattleLog.push(tr("UI_BLOG_START"), BattleLog.Kind.TURN)

	if is_advantage:
		BattleLog.push(tr("UI_BLOG_ADVANTAGE"), BattleLog.Kind.ACCENT)
		AudioManager.play_sfx(&"impact_heavy")
		_presenter.show_flag_pop("ADVANTAGE!", Color(1.0, 0.85, 0.2), 0)
		for e in enemies:
			e.break_gauge = mini(e.break_threshold - 1, e.break_gauge + 1)
	elif is_ambush:
		BattleLog.push(tr("UI_BLOG_AMBUSH"), BattleLog.Kind.DAMAGE)
		AudioManager.play_sfx(&"sfx_hit_enemy")
		_presenter.show_flag_pop("AMBUSH!", Color(1.0, 0.3, 0.3), 0)
		controller.state = BattleController.TurnState.ENEMY_TURN

	_ui.refresh_bars()
	_sync_player_state()
	_ui.refresh_log()

	if is_ambush:
		_resolve_turn()
	else:
		_ui.show_command_menu()


func _sync_player_state() -> void:
	if player_combatant != null:
		var ratio := float(player_combatant.hp) / float(maxi(player_combatant.max_hp, 1))
		var is_low := ratio <= 0.3
		if _presenter != null:
			_presenter.is_player_low_hp = is_low
		AudioManager.set_low_hp_warning(is_low)


func _check_break_chance_cue(enemy: Combatant) -> void:
	if enemy != null and not enemy.is_down():
		if enemy.broken_turns > 0 or enemy.break_gauge >= maxi(1, enemy.break_threshold - 1):
			AudioManager.play_break_cue()


func _is_boss_fight() -> bool:
	for eid in _enemy_ids:
		if bool(Database.get_enemy_def(StringName(eid)).get("is_boss", false)):
			return true
	return false


func _setup_ui() -> void:
	_ui = BattleUI.new()
	add_child(_ui)
	_ui.build(player_combatant, enemies, _skills)
	# 보스전 도망 금지는 규칙(battle_rules.json)이 정한다 — 메뉴에서 미리 흐리게.
	_ui.set_command_enabled(&"flee", FleeRule.allowed(Database.flee_rules(), _is_boss_fight()))
	_ui.command_selected.connect(_on_command)
	_ui.skill_selected.connect(_on_skill_selected)
	_ui.item_selected.connect(_on_item_selected)
	_ui.target_cycled.connect(_on_target_cycled)
	_ui.repeat_requested.connect(_on_repeat_requested)
	_ui.cancel_requested.connect(_on_battle_cancel)
	_ui.set_target(_target_index)

	_pause_menu = PauseMenu.new()
	_pause_menu.allow_save = false  # 전투 중 수동 저장은 방지
	_pause_menu.can_open_on_cancel = false  # 전투 중에는 BattleUI가 cancel을 중재
	_pause_menu.layer = 80
	add_child(_pause_menu)

	add_child(DebugPanel.new())  # F9 개발자 모드·F10 — 필드와 동일(패널 내부 가드)


func _on_battle_cancel() -> void:
	if not _busy and not (_dodge != null and _dodge.is_active):
		_pause_menu.toggle()


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
	# 주인공 이름은 **번역표가 단일 출처**다(UI_BATTLE_PLAYER_NAME). 여기 문자열로
	# 박아 두면 이름을 바꿀 때 한 곳이 빠지고, 영어 로케일에서도 한글이 나온다
	# (2026-08-30 「부싯돌 → 시돌」 개명 때 실제로 이 자리가 걸렸다).
	player_combatant = Combatant.new(
		tr("UI_BATTLE_PLAYER_NAME"),
		int(stats["hp"]),
		GameState.attack_power(),
		GameState.defense_power()
	)
	# 보유 스킬은 GameState가 단일 출처 — 구판은 여기 5종이 하드코딩돼 있었고
	# 아무도 읽지 않았으며 이름도 틀렸다(flame_beaker ≠ flame_beaker_throw).
	player_combatant.skills.assign(GameState.owned_skill_ids())
	var built := BattleSetup.build_enemies(def)
	enemies.assign(built["combatants"])
	_enemy_ids.assign(built["ids"])


## 커맨드 분기는 번역 불변 id로 한다 — 구판은 tr()로 만든 한국어 문자열을 그대로 비교해
## 언어를 바꾸면 전투 커맨드가 통째로 먹통이 됐다(2026-08-28 l10n 도입 후 실측).
## Q/E — 살아 있는 적 사이에서 대상을 옮긴다. 대상 개념이 없어 늘 첫 번째 적만
## 때리던 것을 고친 자리(적 2체 이상 전투에서 뒤쪽 적을 지목할 방법이 없었다).
func _on_target_cycled(direction: int) -> void:
	if _busy or enemies.size() <= 1:
		return
	var start := _target_index
	for step in enemies.size():
		var idx := wrapi(start + direction * (step + 1), 0, enemies.size())
		if not enemies[idx].is_down():
			_target_index = idx
			_ui.set_target(idx)
			AudioManager.play_sfx(&"sfx_menu_move")
			_check_break_chance_cue(enemies[idx])
			return


## R — 직전 행동을 그대로 한 번 더. 턴제에서 같은 공격을 반복하는 조작 비용을 없앤다.
func _on_repeat_requested() -> void:
	if _busy or _last_action.is_empty():
		return
	match StringName(str(_last_action.get("kind", ""))):
		&"command":
			_on_command(StringName(str(_last_action["id"])))
		&"skill":
			_on_skill_selected(_last_action["skill"])
		&"item":
			var item_id := StringName(str(_last_action["item"].get("id", "")))
			if GameState.inventory.count(item_id) > 0:
				_on_item_selected(_last_action["item"])


func _on_command(cmd_id: StringName) -> void:
	if _busy:
		return
	if cmd_id != &"skill" and cmd_id != &"item":
		_last_action = {"kind": &"command", "id": cmd_id}
		_log(tr("UI_BLOG_ACTION") % _ui.command_label(cmd_id))
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
			var heal_amount := maxi(2, int(player_combatant.max_hp * 0.06))
			var actual_heal := player_combatant.heal(heal_amount)
			if actual_heal > 0:
				_presenter.show_player_heal(actual_heal)
			AudioManager.play_sfx(&"cast_shield")
			_presenter.show_player_note(tr("UI_BLOG_GUARD"))
			_ui.refresh_bars()
			_end_player_defend()
		&"item":
			_ui.show_item_menu()
		&"flee":
			_try_flee()


## 도망 — 원작은 100% 성공이었으나 현대 편의로 확률제(FleeRule · data/battle_rules.json).
## 실패하면 턴을 잃고 적의 공격을 받되, 다음 시도의 확률이 오른다(같은 전투에 갇히지 않게).
func _try_flee() -> void:
	var rules := Database.flee_rules()
	if not FleeRule.allowed(rules, _is_boss_fight()):
		_presenter.show_player_note(tr("UI_BATTLE_FLEE_BLOCKED"))
		_ui.show_command_menu()
		return

	var hp_ratio := float(player_combatant.hp) / float(maxi(player_combatant.max_hp, 1))
	var p := FleeRule.chance(rules, _flee_failures, hp_ratio, GameState.current_floor)
	if EnemyManager.rng.randf() >= p:
		_flee_failures += 1
		_presenter.show_player_note(tr("UI_BATTLE_FLEE_FAIL"))
		print("[battle] 도망 실패 (확률 %.0f%%, 누적 실패 %d)" % [p * 100.0, _flee_failures])
		_end_player_defend()  # 턴 소비 — 적이 한 번 때린다
		return

	print("[battle] 도망 성공 (확률 %.0f%%)" % (p * 100.0))
	battle_ended.emit(&"flee", {})
	BattleRewards.apply(&"flee", {}, player_combatant.hp, _on_win_flag)
	get_tree().change_scene_to_file("res://scenes/field.tscn")


func _on_skill_selected(skill: Dictionary) -> void:
	_last_action = {"kind": &"skill", "skill": skill}
	var skill_name := str(skill.get("display_key", skill.get("name_ko", skill.get("id", ""))))
	_log(tr("UI_BLOG_ACTION") % skill_name)
	var move_id := StringName(str(skill.get("choreography_id", "atk_flint_basic")))
	_begin_player_action(
		{
			"type": &"skill",
			"skill": skill,
			"target": _first_alive_enemy(),
			"ap": player_combatant.attack_stat(),
		},
		move_id
	)


## 도구 사용 — 회복·상태이상 해제·공격 버프. 판정과 적용은 ItemEffects가 단일 창구.
## 구판은 hp_restore만 처리해 진통 파스·해열제·녹용주 같은 항목이 메뉴에도 안 떴다.
func _on_item_selected(item_def: Dictionary) -> void:
	if _busy:
		return
	_last_action = {"kind": &"item", "item": item_def}
	_log(tr("UI_BLOG_ACTION") % str(item_def.get("name_ko", item_def.get("id", ""))))
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
	_sync_player_state()
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
	# 공격 기합 — 원작 `AttackAni2()`가 애니 시작에 d1.voc를 냈다(WARMODE.C:321).
	# 방어·도구는 그 자리가 아니므로 여기(공격 개시)에만 둔다.
	AudioManager.play_voice(&"d1")
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
	var who := enemies[idx].display_name if idx < enemies.size() else "?"
	var broke := bool(pop.get("break", false))
	var crit := bool(pop.get("crit", false))
	var weak := bool(pop.get("weak", false))
	var just := bool(pop.get("just", false))

	if broke:
		_presenter.show_flag_pop("BREAK!", Color(1.0, 0.45, 0.2), idx)
		_log(tr("UI_BLOG_BREAK") % who, BattleLog.Kind.ACCENT)
		AudioManager.play_sfx(&"sfx_explosion")
		AudioManager.play_break_shatter()
		if SettingsManager.screen_shake:
			_presenter.play_screen_kf({"shake": 7.0, "flash": "#ffffff", "a": 0.3})
	elif crit:
		_presenter.show_flag_pop("CRITICAL!", Color(1.0, 0.85, 0.2), idx)
		_log(tr("UI_BLOG_CRIT") % [who, int(pop["amount"])], BattleLog.Kind.ACCENT)
		AudioManager.play_sfx(&"impact_heavy")
		if SettingsManager.screen_shake:
			_presenter.play_screen_kf({"shake": 5.0, "flash": "#ffe066", "a": 0.2})
	elif weak:
		_presenter.show_flag_pop("WEAK!", Color(1.0, 0.92, 0.35), idx)
		_log(tr("UI_BLOG_WEAK") % who, BattleLog.Kind.ACCENT)
		AudioManager.play_sfx(&"impact_heavy")
		if SettingsManager.screen_shake:
			_presenter.play_screen_kf({"shake": 4.0})
	elif just:
		_presenter.show_flag_pop("JUST!", Color(0.4, 1.0, 0.5), idx)
		_log(tr("UI_BLOG_HIT") % [who, int(pop["amount"])], BattleLog.Kind.DAMAGE)
		AudioManager.play_sfx(&"impact_light")
		if SettingsManager.screen_shake:
			_presenter.play_screen_kf({"shake": 2.5})
	else:
		_log(tr("UI_BLOG_HIT") % [who, int(pop["amount"])], BattleLog.Kind.DAMAGE)
		AudioManager.play_sfx(&"sfx_hit_enemy")
	if idx < _presenter.enemy_sprites.size():
		_presenter.hurt_flash(_presenter.enemy_sprites[idx])
	_presenter.hitstop()


func _on_choreo_finished(_move_id: StringName) -> void:
	if _pending_action.get("type", &"") == &"skill":
		controller.apply_skill_effects(_pending_action["skill"])
	_pending_action = {}
	_pending_pops.clear()
	_resolve_turn()


## 현재 대상 — 지목한 적이 살아 있으면 그 적, 아니면 첫 생존자.
func _alive_enemy_index() -> int:
	if (
		_target_index >= 0
		and _target_index < enemies.size()
		and not enemies[_target_index].is_down()
	):
		return _target_index
	for i in enemies.size():
		if not enemies[i].is_down():
			_target_index = i
			_ui.set_target(i)
			return i
	return 0


func _first_alive_enemy() -> Combatant:
	var idx := _alive_enemy_index()
	if idx < enemies.size() and not enemies[idx].is_down():
		return enemies[idx]
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
			# 누구 턴인지 글자로 — TURN N 라벨만으로는 적 공격이 안 보인다.
			_ui.set_turn_text(_enemy_turn_text(actor.display_name))
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
	_sync_player_state()
	_busy = false
	# 커맨드 창을 열기 전에 판정 상태도 플레이어 차례로 돌려놓는다 —
	# 이걸 빼먹으면 창은 열리는데 명령이 무시된다(2026-08-28 실측 버그).
	controller.begin_player_phase()
	_ui.set_turn_text("TURN %d" % (controller.turn_count + 1))
	_log(tr("UI_BLOG_TURN") % (controller.turn_count + 1), BattleLog.Kind.TURN)
	_ui.show_command_menu()
	if _target_index >= 0 and _target_index < enemies.size():
		_check_break_chance_cue(enemies[_target_index])


func _end_player_defend() -> void:
	# 적 턴만 진행
	var attacker := _first_alive_enemy()
	if attacker != null:
		_ui.set_turn_text(_enemy_turn_text(attacker.display_name))
		BattleEnemyPhase.regular_attack(attacker, player_combatant, _presenter)
	_tick_effects()
	_ui.refresh_bars()
	_sync_player_state()

	if player_combatant.is_down():
		_show_result(&"lose")
		return
	controller.begin_player_phase()
	_ui.show_command_menu()


## 적 턴 배너 — .translation이 csv보다 stale하면 tr()이 키 그대로를 돌려주고
## "%s"가 없어 % 연산이 터진다(2026-09-05 ambush 실측). 그때는 이름 병기로 폴백.
func _enemy_turn_text(enemy_name: String) -> String:
	var fmt := tr("UI_BATTLE_ENEMY_TURN")
	if "%s" in fmt:
		return fmt % enemy_name
	return "%s %s" % [fmt, enemy_name]


## 로그 한 줄 — 적립과 화면 갱신을 한 창구로 묶는다(둘로 나누면 한쪽만 부르는 자리가 생긴다).
func _log(text: String, kind: BattleLog.Kind = BattleLog.Kind.ACTION) -> void:
	BattleLog.push(text, kind)
	if _ui != null:
		_ui.refresh_log()


func _tick_effects() -> void:
	for c: Combatant in ([player_combatant] as Array[Combatant]) + enemies:
		c.tick_effects()


func _exit_tree() -> void:
	AudioManager.set_low_hp_warning(false)


func _show_result(result: StringName) -> void:
	AudioManager.set_low_hp_warning(false)
	_busy = true
	AudioManager.play_voice(StringName(str(RESULT_VOICES.get(result, ""))))
	_log(
		tr("UI_BLOG_RESULT") % tr(str(RESULT_KEYS.get(result, "UI_BATTLE_RESULT_WIN"))),
		BattleLog.Kind.RESULT
	)
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
