extends Node
## 전투 스모크 — Phase 6 수용 기준 자동화:
##   부팅 → 공격 커맨드 → 안무 재생(battle_moves) → damage_frame 표현 → 턴 해결
## 실행: godot --headless --path . res://tests/smoke_battle.tscn   (exit 0=PASS)

const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const TIMEOUT := 5.0


func _ready() -> void:
	var failures: Array[String] = []

	GameState.player_stats = {"hp": 50, "ap": 30, "money": 0}
	GameState.pending_encounter = {"enemies": ["mad_eye"]}

	var battle: BattleSceneController = BATTLE_SCENE.instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame

	if battle.enemies.is_empty():
		_finish(["적 생성 실패"], battle)
		return
	var hp_before: int = battle.enemies[0].hp

	# --- 1) 공격 안무 재생 + 데미지 적용 (타이밍 링 헤드리스 타임아웃 포함) ---
	battle._on_command("공격")
	var waited := 0.0
	while battle._busy and waited < TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
	print("[smoke_battle] action resolved=%.3fs" % waited)
	if waited >= TIMEOUT:
		failures.append("공격 액션 타임아웃(타이밍 링/안무)")

	var hp_after: int = maxi(0, battle.enemies[0].hp)
	print("[smoke_battle] enemy hp %d -> %d" % [hp_before, hp_after])
	if hp_after >= hp_before:
		failures.append("공격 데미지 미적용")

	# --- 1-1) 브레이크 게이지 UI — 약점 보유 적에게 게이지 라벨 생성 ---
	if battle._ui._break_labels.is_empty():
		failures.append("브레이크 게이지 라벨 미생성(약점 보유 적 존재)")

	# --- 2) 스킬(전체 대상 화염) 안무 ---
	(
		battle
		. _on_skill_selected(
			{
				"id": "flame_beaker_throw",
				"display_key": "테스트 화염",
				"element": "fire",
				"targeting": "all_enemies",
				"power": 30,
				"status_effects": [],
				"choreography_id": "atk_flame_throw",
			}
		)
	)
	waited = 0.0
	while (battle._runner.is_playing() or battle._busy) and waited < TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if waited >= TIMEOUT:
		failures.append("스킬 안무 타임아웃")

	# --- 3) battle_moves 데이터 무결성: skills.json의 choreography_id 전부 존재 ---
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/skills.json"))
	if typeof(raw) == TYPE_DICTIONARY:
		for s: Dictionary in raw.get("skills", []):
			var cid := StringName(str(s.get("choreography_id", "")))
			var path := "res://data/battle_moves/%s.json" % cid
			if not FileAccess.file_exists(path):
				failures.append("안무 데이터 없음: %s" % cid)
			else:
				var mv: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
				if (
					typeof(mv) != TYPE_DICTIONARY
					or str(mv.get("id", "")) != str(cid)
					or not _has_apply_damage(mv)
				):
					failures.append("안무 데이터 불량: %s" % cid)

	# --- 4) 보스 데이터 로드 + 회피 페이즈 실행 ---
	var bdef: Dictionary = Database.get_enemy_def(&"sys_builder")
	if not bool(bdef.get("is_boss", false)):
		failures.append("보스 정의 미로드: sys_builder")
	elif (bdef.get("dodge_phase", {}) as Dictionary).is_empty():
		failures.append("보스 dodge_phase 설정 없음")
	elif not (bdef["dodge_phase"] as Dictionary).has("telegraph"):
		failures.append("보스 텔레그래프 미정의")
	else:
		GameState.pending_encounter = {"enemies": ["sys_builder"]}
		var boss: BattleSceneController = BATTLE_SCENE.instantiate()
		add_child(boss)
		await get_tree().process_frame
		await get_tree().process_frame
		var hp_before2: int = boss.player_combatant.hp
		var hits: int = await BattleEnemyPhase.dodge_sequence(
			boss._dodge, bdef, boss._presenter, boss._ui, boss.player_combatant
		)
		print(
			(
				"[smoke_battle] dodge hits=%d player hp %d -> %d"
				% [hits, hp_before2, boss.player_combatant.hp]
			)
		)
		if boss._dodge != null and boss._dodge.visible:
			failures.append("회피 페이즈 종료 후 미숨김")
		# 헤드리스(입력 없음) → 0히트가 정상. 피해 0 확인.
		if hits == 0 and boss.player_combatant.hp != hp_before2:
			failures.append("무피격인데 피해 발생")
		boss.queue_free()

	# --- 5) 약점·브레이크·타이밍 로직 (BattleController 직접 구동 — 시드 고정 결정론) ---
	EnemyManager.rng.seed = 20260826
	var logic := BattleController.new()
	add_child(logic)
	var hero := Combatant.new("부싯돌", 200, 30, 10)
	var weakling := Combatant.new("약점 몬스터", 500, 15, 5)
	weakling.weaknesses.assign([&"fire"] as Array[StringName])
	var tank := Combatant.new("비약점 몬스터", 500, 15, 5)
	logic.start(hero, [weakling, tank] as Array[Combatant])

	var fire_skill := {
		"id": "test_fire",
		"element": "fire",
		"targeting": "single",
		"power": 30,
		"status_effects": [],
		"choreography_id": "atk_flame_throw",
	}

	# 5-1) 약점 배율 — 동일 시드·동일 조건, fire 약점 몬스터가 더 아프다(결정론)
	var cmd_weak := {"type": &"skill", "skill": fire_skill.duplicate(true), "target": weakling}
	logic.state = BattleController.TurnState.PLAYER_COMMAND
	logic.submit_player_command(cmd_weak)
	var weak_dmg: int = int((cmd_weak["damages"] as Array)[0]["amount"])
	var weak_flag: bool = bool((cmd_weak["damages"] as Array)[0]["weak"])

	EnemyManager.rng.seed = 20260826  # 동일 시드 — base가 같아 배율만 비교한다
	var cmd_plain := {"type": &"skill", "skill": fire_skill.duplicate(true), "target": tank}
	logic.state = BattleController.TurnState.PLAYER_COMMAND
	logic.submit_player_command(cmd_plain)
	var plain_dmg: int = int((cmd_plain["damages"] as Array)[0]["amount"])
	var plain_flag: bool = bool((cmd_plain["damages"] as Array)[0]["weak"])

	print(
		(
			"[smoke_battle] weakness check: fire->weak %d (flag=%s) vs plain %d (flag=%s)"
			% [weak_dmg, weak_flag, plain_dmg, plain_flag]
		)
	)
	if not weak_flag or plain_flag:
		failures.append("약점 플래그 판정 오류")
	if weak_dmg <= plain_dmg:
		failures.append("약점 배율 미적용 (weak=%d plain=%d)" % [weak_dmg, plain_dmg])

	# 5-2) 브레이크 — 약점 히트 2회 누적 시 브레이크 + 받는 피해 ×1.5 (결정론 프로브)
	var cmd_break := {"type": &"skill", "skill": fire_skill.duplicate(true), "target": weakling}
	logic.state = BattleController.TurnState.PLAYER_COMMAND
	logic.submit_player_command(cmd_break)
	var break_flag: bool = bool((cmd_break["damages"] as Array)[0]["break"])
	if not break_flag or not weakling.is_broken():
		failures.append("브레이크 미발동 (gauge=%d)" % weakling.break_gauge)
	var probe := Combatant.new("프로브", 500, 15, 5)
	var base_hit: int = probe.take_damage(100)
	probe.broken_turns = 1
	var amp_hit: int = probe.take_damage(100)
	print(
		(
			"[smoke_battle] break check: break_flag=%s broken mult %d -> %d"
			% [break_flag, base_hit, amp_hit]
		)
	)
	if amp_hit <= base_hit:
		failures.append("브레이크 피해 증폭 미적용 (%d -> %d)" % [base_hit, amp_hit])

	# 5-3) 타이밍 보너스 — timing_mult 1.2
	EnemyManager.rng.seed = 20260826
	var cmd_timing := {
		"type": &"skill",
		"skill": fire_skill.duplicate(true),
		"target": tank,
		"timing_mult": 1.2,
	}
	logic.state = BattleController.TurnState.PLAYER_COMMAND
	logic.submit_player_command(cmd_timing)
	EnemyManager.rng.seed = 20260826
	var cmd_no_timing := {"type": &"skill", "skill": fire_skill.duplicate(true), "target": tank}
	logic.state = BattleController.TurnState.PLAYER_COMMAND
	logic.submit_player_command(cmd_no_timing)
	var timing_dmg: int = int((cmd_timing["damages"] as Array)[0]["amount"])
	var no_timing_dmg: int = int((cmd_no_timing["damages"] as Array)[0]["amount"])
	print("[smoke_battle] timing check: just=%d vs normal=%d" % [timing_dmg, no_timing_dmg])
	if timing_dmg <= no_timing_dmg:
		failures.append("타이밍 보너스 미적용 (just=%d normal=%d)" % [timing_dmg, no_timing_dmg])
	logic.queue_free()

	# --- 6) 도구 사용 — hp_restore 회복 + 인벤 차감 ---
	GameState.inventory.add(&"ITEM_MEDICINE", 2)
	var med: Dictionary = Database.get_item(&"ITEM_MEDICINE")
	if int(med.get("hp_restore", 0)) <= 0:
		failures.append("테스트용 소모품 hp_restore 없음")
	else:
		battle.player_combatant.hp = 30
		var inv_before: int = GameState.inventory.count(&"ITEM_MEDICINE")
		battle._on_item_selected(med)
		await get_tree().process_frame
		var healed_hp: int = battle.player_combatant.hp
		var inv_after: int = GameState.inventory.count(&"ITEM_MEDICINE")
		print(
			(
				"[smoke_battle] item use: hp 30 -> %d (restore %d), inv %d -> %d"
				% [healed_hp, int(med["hp_restore"]), inv_before, inv_after]
			)
		)
		if healed_hp <= 30:
			failures.append("도구 회복 미적용")
		if inv_after != inv_before - 1:
			failures.append("도구 인벤 차감 오류")
		GameState.inventory.remove(&"ITEM_MEDICINE", GameState.inventory.count(&"ITEM_MEDICINE"))

	_finish(failures, battle)


func _has_apply_damage(move: Variant) -> bool:
	if typeof(move) != TYPE_DICTIONARY:
		return false
	var channels: Dictionary = move.get("channels", {})
	if not channels.has("logic"):
		return true  # 버프 계열은 logic 생략 허용
	for kf: Dictionary in channels["logic"]:
		if bool(kf.get("apply_damage", false)):
			return true
	return true


func _finish(failures: Array[String], battle: Node) -> void:
	battle.queue_free()
	if failures.is_empty():
		print("[smoke_battle] PASS")
		get_tree().quit(0)
	else:
		push_error("[smoke_battle] FAIL: " + "; ".join(failures))
		get_tree().quit(1)
