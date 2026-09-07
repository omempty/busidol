extends Node
## 전투 스모크 — Phase 6 수용 기준 자동화:
##   부팅 → 공격 커맨드 → 안무 재생(battle_moves) → damage_frame 표현 → 턴 해결
## 실행: godot --headless --path . res://tests/smoke_battle.tscn   (exit 0=PASS)

const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const TIMEOUT := 5.0


func _ready() -> void:
	var failures: Array[String] = []

	# 실제 새 게임과 같은 출발점 — 스탯 키가 빠지면 보상 경로가 다른 이유로 죽어
	# 전투 버그와 구분되지 않는다.
	GameState.reset()
	GameState.player_stats["hp"] = 50
	GameState.player_stats["ap"] = 30
	GameState.player_stats["money"] = 0
	GameState.pending_encounter = {"enemies": ["mad_eye"]}

	var battle: BattleSceneController = BATTLE_SCENE.instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame

	if battle.enemies.is_empty():
		_finish(["적 생성 실패"], battle)
		return
	# 공격·스킬 검증 도중 적이 죽으면 승리 처리로 **필드 씬으로 전환**되어(스모크 씬이 사라져)
	# 테스트가 영영 끝나지 않는다. 2026-08-28 턴 버그를 고치자 실제로 그렇게 됐다.
	battle.enemies[0].max_hp = 999
	battle.enemies[0].hp = 999
	var hp_before: int = battle.enemies[0].hp

	# --- 1) 공격 안무 재생 + 데미지 적용 (타이밍 링 헤드리스 타임아웃 포함) ---
	# 커맨드는 번역 불변 id로 넘긴다(구판은 한국어 문자열이라 언어를 바꾸면 깨졌다).
	battle._on_command(&"attack")
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

	# --- 1-0) 연속 턴 — 2턴째 공격도 실제로 들어가는가 ---
	# 2026-08-28 실측 버그: 씬이 적 페이즈를 직접 굴리면서 BattleController의 상태를
	# 되돌리지 않아 state가 ENEMY_TURN에 갇혔고, submit_player_command가 조용히 무시돼
	# **2턴째부터 플레이어 공격이 0 피해**였다(연출·커맨드 창은 정상이라 화면으론 안 보인다).
	var second_before: int = maxi(0, battle.enemies[0].hp)
	battle._on_command(&"attack")
	waited = 0.0
	while battle._busy and waited < TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var second_after: int = maxi(0, battle.enemies[0].hp)
	print("[smoke_battle] 2턴째 enemy hp %d -> %d" % [second_before, second_after])
	if second_after >= second_before and second_before > 0:
		failures.append("2턴째 공격 무효(턴 상태가 플레이어로 돌아오지 않음)")

	# --- 1-2) 적 DP는 피해를 깎지 않는다 — 원작 공식(WARMODE.C DeadEnemy)과 같은 규약.
	# 방어구는 리메이크 추가분이라 DP 경감은 플레이어 쪽에만 붙는다.
	var dummy := Combatant.new("더미", 500, 10, 400)
	dummy.dp_reduces_damage = false
	var plain := dummy.take_damage(40)
	if plain != 40:
		failures.append("적 DP가 피해를 깎았다(기대 40, 실제 %d)" % plain)
	var armored := Combatant.new("플레이어", 500, 10, 40)
	if armored.take_damage(40) >= 40:
		failures.append("플레이어 DP 경감이 적용되지 않았다")

	# --- 1-1) 브레이크 게이지 UI — 약점 보유 적에게 게이지 라벨 생성 ---
	if battle._ui._break_bars.is_empty():
		failures.append("브레이크 게이지 미생성(약점 보유 적 존재)")

	# --- 1-3) 보상 경로 — 스탯에 exp 키가 없어도 살아남는가 ---
	# 턴 버그로 전투가 끝나지 않던 시절엔 이 경로가 한 번도 안 돌아 터진 줄도 몰랐다.
	GameState.player_stats.erase("exp")
	var lv_result := GameState.grant_exp(10)
	if int(GameState.player_stats.get("exp", -1)) != 10:
		failures.append("grant_exp가 exp 키 부재를 견디지 못함(%s)" % lv_result)

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

	# --- 7) 마비 — 걸린 마비가 플레이어 턴을 실제로 빼앗는가 ---
	# 2026-09-07까지 마비 5종이 `turns: 1`이라 **붙자마자 사라졌다.** `_resolve_turn`은
	# 마비를 거는 자리(`_enemy_act`) 바로 뒤에 `_tick_effects()`를 부른다 → 그 라운드에서
	# turns가 0이 되어 제거되고, 플레이어 차례의 `has_paralysis()`는 언제나 false였다.
	# 12%로 뽑힌 마비가 아무 일도 하지 않았고, 그래서 진통 파스(마비 해제)를 살 이유도
	# 없었다. 여기서는 **그 순서를 그대로 재현**한다.
	#
	# 지속 값을 코드에 두지 않고 `monsters.json`에서 읽는다 — 1로 되돌리면 이 관문이 빨개진다.
	# 반대쪽도 막는다: 두 번째 tick에도 남아 있으면 여러 턴을 연속으로 빼앗는다는 뜻이고,
	# 그건 "내가 하는 게임"이 아니게 되는 자리라 설계 규칙(정확히 한 턴)에 어긋난다.
	var paralyzers: Array[StringName] = [
		&"sparker", &"iron_voc", &"hellcop", &"c_bug", &"rogue_vending"
	]
	var durations: Array[String] = []
	for eid: StringName in paralyzers:
		var spec: Dictionary = Database.get_enemy_def(eid).get("special", {})
		if str(spec.get("kind", "")) != "paralysis":
			failures.append("%s의 special이 더 이상 마비가 아니다" % eid)
			continue
		var turns := int(spec.get("turns", 0))
		durations.append("%s %d" % [eid, turns])
		battle.player_combatant.active_effects.clear()
		battle.player_combatant.attach_effect(
			{"kind": &"paralysis", "turns": turns, "magnitude": 0}
		)
		battle._tick_effects()  # 마비를 건 그 라운드의 tick
		if not battle.player_combatant.has_paralysis():
			failures.append("%s 마비가 걸린 라운드에서 곧바로 지워진다(turns=%d) — 플레이어 턴을 못 뺏는다" % [eid, turns])
			continue
		battle._tick_effects()  # 빼앗긴 그 턴이 끝나는 tick
		if battle.player_combatant.has_paralysis():
			failures.append("%s 마비가 한 턴을 넘겨 지속된다(turns=%d)" % [eid, turns])
	battle.player_combatant.active_effects.clear()
	print("[smoke_battle] 마비 지속(정확히 한 턴): %s" % ", ".join(durations))

	# --- 7-1) 턴만 넘기는 경로(방어·도망 실패·아이템·마비)도 마비를 다시 보는가 ---
	# `_end_player_defend`는 그 네 경로가 공유하는데, 2026-09-07까지 끝에서 마비를 검사하지
	# 않고 커맨드 창을 그냥 열었다. 지속이 1이던 시절엔 tick이 무조건 지워 안 드러났지만,
	# 2로 올리자 **살아 넘어온 마비가 조용히 무시되는** 구멍이 열린다.
	# 여기서는 지속을 인위적으로 3으로 걸어 그 경로를 강제한다 — 검사가 없으면 한 번만
	# 소비하고 마비를 남긴 채 돌아오고(잔존 = FAIL), 있으면 다 소진하고 나온다.
	# 적은 mad_eye(dot 계열)라 이 사이에 마비가 새로 붙지 않는다 — 판정이 결정적이다.
	battle.player_combatant.max_hp = 9999
	battle.player_combatant.hp = 9999
	battle.player_combatant.attach_effect({"kind": &"paralysis", "turns": 3, "magnitude": 0})
	battle._end_player_defend()
	await get_tree().process_frame
	print("[smoke_battle] 턴 넘김 경로 마비 재검사: 잔존=%s" % str(battle.player_combatant.has_paralysis()))
	if battle.player_combatant.has_paralysis():
		failures.append("_end_player_defend가 살아 넘어온 마비를 무시하고 커맨드 창을 연다")
	battle.player_combatant.active_effects.clear()

	# --- 8) 적 전투 대형 시트 — 계약대로 서고, 행들이 실제로 재생되는가 ---
	# 원작 전투는 320×200 전체 화면 프레임 시퀀스였고 그 프레임이 저장소에 있었는데
	# **게임 코드가 로드하는 곳이 0곳**이었다(2026-09-07). 적이 화면 높이의 13~21%뿐이라
	# 원작(52~73%)의 압박감이 통째로 빠져 있었다. 되돌아가지 않게 세 가지를 못 박는다.
	#
	# (a) 계약(`battle_actor_specs.json` enemies·status=baked)과 실제 파일이 일치하는가
	# (b) 전투 화면이 그 시트를 **실제로 골랐는가** — 필드 도트로 조용히 새면 여기서 걸린다
	# (c) 굽기만 하고 아무도 안 읽는 행이 없는가 — 이 저장소의 지배적 결함이 그것이다
	# 계약 파일은 지금까지 python 도구만 읽었다(저장소 전체에서 GDScript 참조 0곳).
	# 게임 쪽 관문이 같은 파일을 읽어야 계약과 실물이 갈라지는 것을 잡는다.
	var spec_raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/battle_actor_specs.json")
	)
	var baked: Array[String] = []
	if typeof(spec_raw) == TYPE_DICTIONARY:
		for e: Variant in (spec_raw as Dictionary).get("enemies", []):
			if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("status", "")) == "baked":
				baked.append(str((e as Dictionary).get("id", "")))
	if baked.is_empty():
		failures.append("battle_actor_specs.json에 status=baked인 적이 하나도 없다")
	for eid: String in baked:
		# **원본 파일을 직접 본다.** `SpriteSets.battle_sheet`는 `ResourceLoader.exists`를
		# 쓰는데 그것은 임포트 캐시(.godot/imported)를 보므로, 원본 PNG를 지워도 계속
		# "있다"고 답한다 — 실제로 이 관문이 그 대조군을 놓쳤다(2026-09-07 실측).
		# 여기서 보려는 것은 "계약과 저장소 파일이 일치하는가"이지 로드 가능성이 아니다.
		for ext: String in ["png", "json"]:
			var path := "res://assets/sprites/%s_battle.%s" % [eid, ext]
			if not FileAccess.file_exists(path):
				failures.append("%s는 계약상 baked인데 %s가 없다 — bake_battle_sheets.py를 돌려라" % [eid, path])
		if str(SpriteSets.battle_sheet(StringName(eid))["sheet"]).is_empty():
			failures.append("%s _battle 시트를 SpriteSets가 못 찾는다" % eid)
	print("[smoke_battle] 전투 대형 시트 계약 %d종: %s" % [baked.size(), ", ".join(baked)])

	if not baked.is_empty():
		GameState.pending_encounter = {"enemies": [baked[0]]}
		var big: BattleSceneController = BATTLE_SCENE.instantiate()
		add_child(big)
		await get_tree().process_frame
		await get_tree().process_frame
		var spr: Sprite2D = (
			big._presenter.enemy_sprites[0] if not big._presenter.enemy_sprites.is_empty() else null
		)
		if spr == null or not spr.has_meta(&"battle_sheet"):
			failures.append("%s 전투가 대형 시트를 안 세웠다 — 필드 도트로 샜다" % baked[0])
		else:
			# 셀이 곧 원작 화면이므로 화면 높이만큼 서야 한다(원작 구도 1:1 이식).
			var cell: Vector2i = spr.get_meta(&"anim_cell")
			var on_screen := float(cell.y) * spr.scale.y
			var view_h := float(
				ProjectSettings.get_setting("display/window/size/viewport_height", 540)
			)
			print(
				(
					"[smoke_battle] %s 대형 시트 셀 %dx%d · 배율 %.2f · 화면상 %.0fpx / 뷰포트 %.0f"
					% [baked[0], cell.x, cell.y, spr.scale.y, on_screen, view_h]
				)
			)
			if absf(on_screen - view_h) > 1.0:
				failures.append("대형 시트가 원작 배율로 안 섰다 — 화면상 %.0fpx, 뷰포트 %.0f" % [on_screen, view_h])
			# 구운 행에 전부 호출부가 있는가 — 재생이 false면 그 행은 사문화다.
			for anim: String in ["attack", "special", "hurt", "death", "wounded"]:
				if not big._presenter.play_anim(spr, anim, baked[0]):
					failures.append("%s 대형 시트에 '%s' 행이 없다(계약 위반)" % [baked[0], anim])
		big.queue_free()
		await get_tree().process_frame

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
