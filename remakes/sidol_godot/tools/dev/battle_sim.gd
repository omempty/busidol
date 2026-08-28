extends Node
## 전투 리듬 계측 — 층별로 전투를 N회 굴려 "얼마나 길고 얼마나 아픈가"를 숫자로 낸다.
##
## 전투가 재미있는지는 취향이지만 **몇 턴 걸리는가·몇 대 맞는가**는 취향이 아니다.
## 스모크는 "동작하는가"만 보고, 감사는 화면만 본다. 이 도구는 그 사이의 층 —
## 밸런스가 층을 따라 올라가는지, 어느 층에서 갑자기 길어지는지를 본다.
##
## 연출(안무·타이밍 링·회피 페이즈)은 제외한 **로직 층**만 돌린다.
## 따라서 결과는 "최소 턴 수"에 가깝고, 실제 체감 시간은 여기에 연출 시간이 더해진다.
##
## 실행: godot --headless --path . res://tools/dev/battle_sim.tscn -- [반복수]
## (--script 모드에서는 오토로드가 없어 Database/SettingsManager를 못 쓴다 — 씬으로 돈다.)

const DEFAULT_RUNS := 200
## 층 ↔ 이 층을 도는 시점의 플레이어 레벨.
## 근거: 04_game_systems §2.1이 옮긴 원작 층별 난수 테이블의 Level 칸(1+rnd3 · 4+rnd3 ·
## 7+rnd3 · 10+rnd3 · 13+rnd4)의 중앙값. f0 지하·f5는 리메이크 신설이라 인접 층을 따른다.
const FLOOR_LEVELS := {0: 2, 1: 5, 2: 8, 3: 11, 4: 14, 5: 15}
## 플레이어 정책 — 기본 공격만. 스킬/아이템은 층마다 보유가 달라 비교가 흐려진다.
const BASE_HP := 50  # 원작 We 초기값(HudV0와 같은 근거)
const BASE_AP := 30
const BASE_DP := 10


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := int(args[0]) if args.size() > 0 else DEFAULT_RUNS
	print("[battle_sim] start — 층당 %d회 (난이도=%s)" % [runs, SettingsManager.difficulty_key()])
	print("층  Lv  적종           턴(평균/최대)  승률    받은HP/최대  적1타  내1타  적HP  EXP/체  레벨업까지")
	for f: int in FLOOR_LEVELS:
		_run_floor(f, int(FLOOR_LEVELS[f]), runs)
	_report_pacing()
	print("[battle_sim] done")
	get_tree().quit(0)


func _run_floor(floor_no: int, level: int, runs: int) -> void:
	GameState.current_floor = floor_no
	var species := Database.encounter_species(floor_no)
	if species.is_empty():
		print("f%d  (인카운터 종 없음)" % floor_no)
		return

	var turns_total := 0
	var turns_max := 0
	var wins := 0
	var hp_lost_total := 0
	var hit_total := 0
	var hit_count := 0
	var breaks := 0
	var dealt_total := 0
	var dealt_count := 0
	var enemy_hp_total := 0
	var names: Dictionary = {}

	for i in runs:
		var spec: Dictionary = species[i % species.size()]
		names[str(spec.get("id", ""))] = true
		var result := _simulate(str(spec.get("id", "")), level)
		turns_total += int(result["turns"])
		turns_max = maxi(turns_max, int(result["turns"]))
		wins += 1 if bool(result["win"]) else 0
		hp_lost_total += int(result["hp_lost"])
		hit_total += int(result["hit_sum"])
		hit_count += int(result["hits"])
		breaks += 1 if bool(result["broke"]) else 0
		dealt_total += int(result["dealt_sum"])
		dealt_count += int(result["swings"])
		enemy_hp_total += int(result["enemy_hp"])

	var avg_turns := float(turns_total) / float(runs)
	var avg_hit := float(hit_total) / float(maxi(hit_count, 1))
	var exp_per_kill := _exp_per_kill(floor_no)
	var kills_to_level := _kills_to_level(level, exp_per_kill)
	print(
		(
			"f%-2d %-3d %-14s %5.1f / %-6d %5.1f%%  %5.1f/%-5d %5.1f  %5.1f  %4d  %5.1f   %s"
			% [
				floor_no,
				level,
				",".join(PackedStringArray(names.keys())).substr(0, 14),
				avg_turns,
				turns_max,
				100.0 * float(wins) / float(runs),
				float(hp_lost_total) / float(runs),
				int(_player_at(level)["hp"]),
				avg_hit,
				float(dealt_total) / float(maxi(dealt_count, 1)),
				int(float(enemy_hp_total) / float(runs)),
				exp_per_kill,
				kills_to_level,
			]
		)
	)


## 전투 1회 — 플레이어는 기본 공격만, 적은 통상 공격만.
## 판정은 실제 전투와 같은 BattleController를 쓴다(약점·브레이크·방어 규칙까지 포함).
func _simulate(enemy_id: String, level: int) -> Dictionary:
	var built_player := _player_at(level)
	var player := Combatant.new(
		"부싯돌", int(built_player["hp"]), int(built_player["ap"]), int(built_player["dp"])
	)
	var built := BattleSetup.build_enemies({"enemies": [enemy_id]})
	var enemies: Array[Combatant] = []
	enemies.assign(built["combatants"])
	if enemies.is_empty():
		return {"turns": 0, "win": false, "hp_lost": 0, "hit_sum": 0, "hits": 0, "broke": false}

	var ctrl := BattleController.new()
	add_child(ctrl)
	ctrl.start(player, enemies)

	var start_hp := player.hp
	var enemy_start_hp := enemies[0].hp
	var dealt_sum := 0
	var swings := 0
	var turns := 0
	var hits := 0
	var hit_sum := 0
	var broke := false
	var win := false
	ctrl.battle_finished.connect(func(result: StringName) -> void: win = result == &"win")

	# 무한 루프 방지 — 30턴이면 이미 "긴 전투"라 판정에 충분하다.
	while turns < 30 and not player.is_down() and ctrl.state != BattleController.TurnState.FINISHED:
		turns += 1
		var enemy_before := enemies[0].hp
		ctrl.submit_player_command(
			{"type": &"attack", "ap": player.attack_stat(), "target": enemies[0]}
		)
		dealt_sum += enemy_before - enemies[0].hp
		swings += 1
		if enemies[0].is_broken():
			broke = true
		if ctrl.state == BattleController.TurnState.FINISHED:
			break
		var before := player.hp
		ctrl.enemy_turn()
		# 씬 흐름과 같은 규약 — 적 페이즈가 끝나면 판정 상태를 플레이어 차례로 되돌린다.
		ctrl.begin_player_phase()
		var taken := before - player.hp
		if taken > 0:
			hits += 1
			hit_sum += taken
	ctrl.queue_free()
	return {
		"turns": turns,
		"dealt_sum": dealt_sum,
		"swings": swings,
		"enemy_hp": enemy_start_hp,
		"win": win or enemies[0].is_down(),
		"hp_lost": start_hp - player.hp,
		"hit_sum": hit_sum,
		"hits": hits,
		"broke": broke,
	}


## growth.json 레벨 테이블로 그 레벨의 플레이어 스탯을 만든다(하드코딩 금지).
## 무기·방어구는 층마다 보유가 달라 비교가 흐려지므로 맨몸 기준이다 —
## 즉 이 수치는 **하한**이고, 장비를 갖추면 전투는 이보다 짧아진다.
func _player_at(level: int) -> Dictionary:
	var hp := BASE_HP
	var ap := BASE_AP
	for entry: Dictionary in Database.level_table():
		if int(entry.get("level", 0)) <= level:
			hp += int(entry.get("hp_up", 0))
			ap += int(entry.get("ap_up", 0))
	return {"hp": hp, "ap": ap, "dp": BASE_DP}


## 이 층 적 1체가 주는 평균 EXP — monsters.json floor_stats의 범위 중앙값 × 난이도 배율.
func _exp_per_kill(floor_no: int) -> float:
	var fs := Database.floor_stats(floor_no)
	var rng_exp: Array = fs.get("exp", [5, 10])
	var mid := (float(rng_exp[0]) + float(rng_exp[-1])) * 0.5
	return mid * SettingsManager.difficulty_mult("exp_mult")


## 다음 레벨까지 몇 체를 잡아야 하는가 — growth.json의 설계 의도
## "각 층에서 자연히 1~2레벨업"이 성립하는지 보는 잣대다(층 하나가 대략 10~20전투).
func _kills_to_level(level: int, exp_per_kill: float) -> String:
	if exp_per_kill <= 0.0:
		return "-"
	var here := -1
	var next := -1
	for entry: Dictionary in Database.level_table():
		if int(entry.get("level", 0)) == level:
			here = int(entry.get("exp_accum", 0))
		if int(entry.get("level", 0)) == level + 1:
			next = int(entry.get("exp_accum", 0))
	if here < 0 or next < 0:
		return "MAX"
	return "%d체" % int(ceil(float(next - here) / exp_per_kill))


## 성장 페이싱 — "다음 층 권장 레벨에 닿으려면 몇 전투가 필요한가".
##
## 층당 20~25회면 현대 RPG의 자연 진행, 40회를 넘으면 노가다다.
## 성장 경로는 본편 층(f1~f5)만 잡는다 — f0(지하)는 f1에서 조건 없이 내려갈 수 있는
## **초반 탐험 층**이라(transitions: stairs_east_down guard 1~5, flag 없음) 진행 순서에
## 넣을 수 없다. 원작 수치(적 HP 11~21·EXP 2~5)도 그 위치에 맞는다.
func _report_pacing() -> void:
	var story := Database.story_bonus_table()
	var plan := [
		{"floor": 1, "level": 5, "quests": ["Q_F1_START", "Q_F1_SOPO", "Q_F1_GAS", "Q_F1_BLAST"]},
		{"floor": 2, "level": 8, "quests": ["Q_F2_HP", "Q_F2_FIGHTER", "Q_F2_POSTER"]},
		{
			"floor": 3,
			"level": 11,
			"quests": ["Q_F3_CURE_REQ", "Q_F3_DRAG", "Q_F3_ALLIN", "Q_F3_PALIN", "Q_F3_CURE_DONE"]
		},
		{"floor": 4, "level": 14, "quests": ["Q_F0_DISK", "Q_F4_BATTERY", "Q_F4_SACRIFICE"]},
		{"floor": 5, "level": 15, "quests": ["Q_F5_BOSS_CURE", "Q_F5_AI_BATTLE"]},
	]
	print("")
	print("성장 페이싱 — 층  목표Lv  필요EXP  스토리  전투몫  EXP/체  필요 전투수")
	var prev_level := 1
	var total := 0.0
	for row: Dictionary in plan:
		var floor_no := int(row["floor"])
		var level := int(row["level"])
		var need := _exp_accum(level) - _exp_accum(prev_level)
		var bonus := 0
		for q: String in row["quests"]:
			bonus += int(story.get(q, 0))
		var by_battle := maxi(need - bonus, 0)
		var per := _exp_per_kill(floor_no)
		var battles := float(by_battle) / maxf(per, 0.001)
		total += battles
		print(
			(
				"                f%-2d %5d %8d %7d %7d %6.1f %8.0f회"
				% [floor_no, level, need, bonus, by_battle, per, battles]
			)
		)
		prev_level = level
	print("                → 만렙까지 총 %.0f전투 (스토리 보너스 합 %d)" % [total, _sum(story)])


func _exp_accum(level: int) -> int:
	for entry: Dictionary in Database.level_table():
		if int(entry.get("level", 0)) == level:
			return int(entry.get("exp_accum", 0))
	return 0


func _sum(table: Dictionary) -> int:
	var out := 0
	for k: String in table:
		out += int(table[k])
	return out
