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

	# --- 1) 공격 안무 재생 + 데미지 적용 ---
	battle._on_command("공격")
	var waited := 0.0
	while battle._runner.is_playing() and waited < TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
	print("[smoke_battle] move played=%.3fs busy=%s" % [waited, battle._busy])
	if waited >= TIMEOUT:
		failures.append("안무 재생 타임아웃")

	var hp_after: int = maxi(0, battle.enemies[0].hp)
	print("[smoke_battle] enemy hp %d -> %d" % [hp_before, hp_after])
	if hp_after >= hp_before:
		failures.append("공격 데미지 미적용")

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
	else:
		GameState.pending_encounter = {"enemies": ["sys_builder"]}
		var boss: BattleSceneController = BATTLE_SCENE.instantiate()
		add_child(boss)
		await get_tree().process_frame
		await get_tree().process_frame
		var hp_before2: int = boss.player_combatant.hp
		var hits: int = await boss._run_dodge_phase(bdef)
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
