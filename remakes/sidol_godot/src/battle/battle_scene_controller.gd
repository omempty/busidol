class_name BattleSceneController
extends Node2D
## 전투 씬 — 커맨드 선택→해결→적 턴→판정 루프.
## 스피디·박력 원칙: 데미지 팝+히트스톱+화면 흔들림+속도 배율.

signal battle_ended(result: StringName, rewards: Dictionary)

enum CmdMenu { MAIN, SKILL_SELECT, ITEM_SELECT }

var controller := BattleController.new()
var player_combatant: Combatant
var enemies: Array[Combatant] = []
var enemy_defs: Array[Dictionary] = []

# UI
var _hp_bars := {}
var _cmd_buttons: Array[Button] = []
var _skill_panel: VBoxContainer
var _menu_root: VBoxContainer
var _turn_label: Label
var _result_label: Label
var _busy := false
var _skills: Array[Dictionary] = []

# 카메라 흔들림
var _shake_power := 0.0
var _base_pos := Vector2.ZERO

# 전투 스프라이트
var _player_sprite: Sprite2D
var _enemy_sprites: Array[Sprite2D] = []


func _setup_battle_sprites() -> void:
	# 플레이어 스프라이트 (원작 도트)
	_player_sprite = Sprite2D.new()
	var ptex: Texture2D = load("res://assets/sprites/player_original.png")
	if ptex != null:
		var at := AtlasTexture.new()
		at.atlas = ptex
		at.region = Rect2(0, 0, 64, 64)   # row0 col0 = walk_down f0
		_player_sprite.texture = at
	_player_sprite.position = Vector2(80, 140)
	_player_sprite.scale = Vector2(1.5, 1.5)
	add_child(_player_sprite)

	# 적 스프라이트 (원작 e1~e8에서 로드 or 색상 사각형 폴백)
	for i in enemies.size():
		var es := Sprite2D.new()
		var e_tex_path := "res://assets/originals_ref/bmp_spr/e%d/frame_000.bmp" % (i % 8 + 1)
		if ResourceLoader.exists(e_tex_path):
			es.texture = load(e_tex_path)
		else:
			# 폴백: 색상 사각형
			var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
			img.fill(Color(randf_range(0.5, 1.0), randf_range(0.2, 0.6), randf_range(0.2, 0.5)))
			es.texture = ImageTexture.create_from_image(img)
		es.position = Vector2(380 + i * 70, 120)
		es.scale = Vector2(1.5, 1.5)
		add_child(es)
		_enemy_sprites.append(es)


## 공격 애니메이션 — 공격자가 전방으로 러지 → 복귀
func play_attack_animation(attacker_sprite: Sprite2D, target_pos: Vector2) -> void:
	var orig := attacker_sprite.position
	var dir := (target_pos - orig).normalized() * 30
	var tw := create_tween()
	tw.tween_property(attacker_sprite, "position", orig + dir, 0.08)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(attacker_sprite, "position", orig, 0.12)\
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


## 피격 플래시 — 타겟이 빨갛게 깜빡임
func play_hurt_flash(target_sprite: Sprite2D) -> void:
	var tw := create_tween()
	tw.tween_property(target_sprite, "modulate", Color(5, 0.3, 0.3), 0.05)
	tw.tween_property(target_sprite, "modulate", Color.WHITE, 0.1)


func _ready() -> void:
	var def: Dictionary = GameState.pending_encounter
	GameState.pending_encounter = {}
	_setup_combatants(def)
	_load_skills()
	_build_ui()
	controller.start(player_combatant, enemies)
	_setup_battle_sprites()
	_show_command_menu()


func _load_skills() -> void:
	var raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/skills.json"))
	if typeof(raw) == TYPE_DICTIONARY:
		for s: Dictionary in raw.get("skills", []):
			_skills.append(s)


func _setup_combatants(def: Dictionary) -> void:
	var stats: Dictionary = GameState.player_stats
	player_combatant = Combatant.new("부싯돌", int(stats["hp"]), int(stats["ap"]), 10)
	player_combatant.skills = [&"combo_punch", &"flame_beaker", &"debug_shield",
			&"volt_arc", &"ember_of_flint"]

	for eid in def.get("enemies", ["mad_eye"]):
		var edef: Dictionary = Database.get_enemy_def(StringName(str(eid)))
		var hp_r: Array = edef.get("hp_range", [20, 40])
		var hp_val: int = randi_range(int(hp_r[0]), int(hp_r[1]))
		enemies.append(Combatant.new(str(edef.get("display_name", eid)), hp_val,
				int(edef.get("ap", 15)), int(edef.get("dp", 5))))


func _build_ui() -> void:
	# 배경
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 적 이름 + HP 바
	for i in enemies.size():
		var e := enemies[i]
		var name_lbl := Label.new()
		name_lbl.text = e.display_name
		name_lbl.position = Vector2(180 + i * 80, 30)
		name_lbl.add_theme_font_size_override("font_size", 10)
		add_child(name_lbl)

		var bar := ProgressBar.new()
		bar.max_value = e.max_hp
		bar.value = e.hp
		bar.position = Vector2(180 + i * 80, 46)
		bar.size = Vector2(64, 8)
		bar.show_percentage = false
		bar.modulate = Color(1, 0.3, 0.3)
		add_child(bar)
		_hp_bars[e] = bar

	# 플레이어 상태
	var pname := Label.new()
	pname.text = "부싯돌"
	pname.position = Vector2(16, 14)
	add_child(pname)

	var php := ProgressBar.new()
	php.max_value = player_combatant.max_hp
	php.value = player_combatant.hp
	php.position = Vector2(16, 32)
	php.size = Vector2(140, 10)
	php.show_percentage = false
	php.modulate = Color(0.3, 1.0, 0.5)
	add_child(php)
	_hp_bars[&"player"] = php

	var pap := Label.new()
	pap.text = "AP %d" % player_combatant.ap
	pap.position = Vector2(16, 48)
	add_child(pap)

	# 턴 라벨
	_turn_label = Label.new()
	_turn_label.text = "TURN 1"
	_turn_label.position = Vector2(280, 14)
	_turn_label.add_theme_font_size_override("font_size", 14)
	add_child(_turn_label)

	# 결과 라벨 (숨김)
	_result_label = Label.new()
	_result_label.text = ""
	_result_label.position = Vector2(240, 100)
	_result_label.add_theme_font_size_override("font_size", 28)
	_result_label.visible = false
	add_child(_result_label)


func _show_command_menu() -> void:
	if _menu_root != null:
		_menu_root.queue_free()
	_menu_root = VBoxContainer.new()
	_menu_root.position = Vector2(420, 200)
	_menu_root.custom_minimum_size = Vector2(120, 0)
	add_child(_menu_root)

	for cmd_text: String in ["공격", "기술", "방어", "도망"]:
		var btn := Button.new()
		btn.text = cmd_text
		btn.pressed.connect(_on_command.bind(cmd_text))
		_menu_root.add_child(btn)
		_cmd_buttons.append(btn)


func _on_command(cmd_text: String) -> void:
	if _busy:
		return
	match cmd_text:
		"공격":
			controller.submit_player_command({
				"type": &"attack",
				"ap": player_combatant.ap,
				"target": _first_alive_enemy(),
			})
			_spawn_damage_number(
					DamageCalculator.player_hit(player_combatant.ap, EnemyManager.rng),
					false)
			_resolve_turn()
		"기술":
			_show_skill_menu()
		"방어":
			player_combatant.attach_effect(
					{"kind": &"buff_damage_taken", "turns": 1, "magnitude": 50})
			_end_player_defend()
		"도망":
			battle_ended.emit(&"flee", {})
			_exit_battle(&"flee")


func _show_skill_menu() -> void:
	_hide_menu()
	_skill_panel = VBoxContainer.new()
	_skill_panel.position = Vector2(420, 200)
	add_child(_skill_panel)

	for skill: Dictionary in _skills:
		var btn := Button.new()
		btn.text = str(skill.get("display_key", skill["id"]))
		btn.pressed.connect(_on_skill_selected.bind(skill))
		_skill_panel.add_child(btn)


func _on_skill_selected(skill: Dictionary) -> void:
	if _skill_panel != null:
		_skill_panel.queue_free()
		_skill_panel = null
	controller.submit_player_command({
		"type": &"skill",
		"skill": skill,
		"ap": player_combatant.ap,
		"target": _first_alive_enemy(),
	})
	var dmg: int = DamageCalculator.skill_hit(
			int(skill.get("power", 10)), player_combatant.ap,
			StringName(str(skill.get("element", "physical"))),
			[], EnemyManager.rng)
	_spawn_damage_number(dmg, false)
	# 상태이상 부착
	for effect_kind: String in skill.get("status_effects", []):
		enemies[0].attach_effect({"kind": StringName(effect_kind), "turns": 3, "magnitude": 10})
	_shake_screen(5)
	_resolve_turn()


func _resolve_turn() -> void:
	_busy = true
	_hide_menu()

	# 적 턴 처리
	if controller.state == BattleController.TurnState.ENEMY_TURN:
		for e in enemies:
			if not e.is_down():
				var raw := DamageCalculator.enemy_hit(e.ap, EnemyManager.rng)
				var actual: int = player_combatant.take_damage(raw)
				_spawn_damage_number(actual, true)
				_shake_screen(3)
				break
		controller.turn_count += 1
		_tick_effects()

	if controller.state == BattleController.TurnState.FINISHED \
			or player_combatant.is_down() or _all_enemies_down():
		var result: StringName = &"win" if _all_enemies_down() else &"lose"
		_show_result(result)
		return

	_refresh_bars()
	_busy = false
	_show_command_menu()


func _end_player_defend() -> void:
	# 적 턴만 진행
	for e in enemies:
		if not e.is_down():
			var raw := DamageCalculator.enemy_hit(e.ap, EnemyManager.rng)
			player_combatant.take_damage(raw)
			break
	_tick_effects()
	_refresh_bars()

	if player_combatant.is_down():
		_show_result(&"lose")
		return
	_show_command_menu()


func _tick_effects() -> void:
	for c: Combatant in ([player_combatant] as Array[Combatant]) + enemies:
		c.tick_effects()


func _refresh_bars() -> void:
	for i in enemies.size():
		var key = enemies[i]
		if _hp_bars.has(key):
			_hp_bars[key].value = maxi(0, enemies[i].hp)
	if _hp_bars.has(&"player"):
		_hp_bars[&"player"].value = maxi(0, player_combatant.hp)


func _show_damage_number(amount: int, on_player: bool) -> void:
	var lbl := Label.new()
	lbl.text = str(amount)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color",
			Color(1, 0.25, 0.15) if on_player else Color(1.0, 0.9, 0.15))
	lbl.position = Vector2(randf_range(190, 260), randf_range(60, 100)) \
			if not on_player else Vector2(randf_range(20, 60), randf_range(40, 70))
	add_child(lbl)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 28, 0.35)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(lbl.queue_free)


func _shake_screen(power: int) -> void:
	_shake_power = float(power)


func _show_result(result: StringName) -> void:
	_busy = true
	_hide_menu()
	_result_label.text = "WIN!" if result == &"win" else ("FLEE" if result == &"flee" else "LOSE...")
	_result_label.visible = true
	_result_label.add_theme_color_override("font_color",
			Color(0.3, 1.0, 0.5) if result == &"win" else Color(1, 0.3, 0.2))

	await get_tree().create_timer(1.2).timeout
	battle_ended.emit(result, {"exp": 15, "money": 100})
	_exit_battle(result)


func _exit_battle(result: StringName) -> void:
	# 전투 결과를 GameState에 반영
	GameState.player_stats["hp"] = player_combatant.hp
	GameState.player_stats["money"] += 50 if result == &"win" else 0
	get_tree().change_scene_to_file("res://scenes/field.tscn")


func _hide_menu() -> void:
	if _menu_root != null:
		_menu_root.queue_free()
		_menu_root = null


func _all_enemies_down() -> bool:
	for e in enemies:
		if not e.is_down():
			return false
	return true
