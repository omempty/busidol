class_name BattleRewards
extends RefCounted
## 전투 보상 산출·반영 — monsters.json 종별 범위 보상(하드코딩 금지).


## 승리 보상 산출 — 종별 exp/money 범위에서 난수 합산.
static func compute(enemy_ids: Array[String]) -> Dictionary:
	var exp_total := 0
	var money_total := 0
	for eid in enemy_ids:
		var edef := Database.get_enemy_def(StringName(eid))
		# 필드 종의 보상도 층이 정한다(BattleSetup의 스탯 부여와 같은 규약).
		if bool(edef.get("from_floor_stats", false)):
			var fs := Database.floor_stats(GameState.current_floor)
			if not fs.is_empty():
				edef = edef.duplicate()
				edef["exp"] = fs.get("exp", [5, 10])
				edef["money"] = fs.get("money", [50, 100])
		var exp_range: Array = edef.get("exp", [5, 10])
		var money_range: Array = edef.get("money", [50, 100])
		exp_total += randi_range(int(exp_range[0]), int(exp_range[1]))
		money_total += randi_range(int(money_range[0]), int(money_range[1]))
	# 난이도 exp 배율 — 쉬움은 빨리 크고, 도전은 더 싸운다.
	exp_total = maxi(1, int(round(exp_total * SettingsManager.difficulty_mult("exp_mult"))))
	return {"exp": exp_total, "money": money_total}


## 결과 반영 — HP·보상·시나리오 플래그·오토세이브. 반환: grant_exp 성장 결과.
static func apply(
	result: StringName, rewards: Dictionary, player_hp: int, on_win_flag: String
) -> Dictionary:
	# 패배해도 **HP 0으로 필드에 돌려보내지 않는다.** 0으로 돌아가면 다음 접촉이
	# 곧바로 다시 패배라 그 자리에서 무한 패배가 된다 — 자동 주행 한 판에 17회
	# 관측(2026-08-29, docs/05_status/01_autoplay.md). 원작에 게임오버 처리가 없어
	# 최소 복구("정신을 차린다")만 한다. 패널티 설계는 별도 결정 사항이다.
	if result == &"lose":
		# **패배에 대가가 있다.** 구판은 풀 HP로 되돌려 보내 지는 것이 공짜였고,
		# 그래서 "질 수 있다"는 긴장이 성립하지 않았다(2026-09-06 유저 지적).
		# 그렇다고 HP 0으로 돌려보내면 다음 접촉이 곧바로 다시 패배라 무한 패배가
		# 된다(2026-08-29 자동 주행 한 판에 17회 관측). 그 사이를 데이터로 정한다 —
		# 절반 남짓 회복하고 소지금 일부를 잃는다. 되돌아갈 수는 있되 공짜는 아니다.
		# 2026-09-08 확장: 난이도별 차등 + 연패 자비. 세이브 복귀형이 아니라
		# 소지금 손실형을 쓰는 이유(탐험 처벌 방지·전진 운동량)는 로드맵 §6 결정.
		var rules: Dictionary = Database.defeat_rules()
		var hp_ratio := float(rules.get("hp_ratio", 0.5))
		var money_loss := float(rules.get("money_loss", 0.25))
		var preset: Dictionary = (rules.get("by_difficulty", {}) as Dictionary).get(
			SettingsManager.difficulty_key(), {}
		)
		hp_ratio = float(preset.get("hp_ratio", hp_ratio))
		money_loss = float(preset.get("money_loss", money_loss))
		# 연패 집계 — 같은 층에서 진 것만 잇는다. 층을 옮기면 1부터 다시 센다.
		if GameState.defeat_floor == GameState.current_floor:
			GameState.defeat_streak += 1
		else:
			GameState.defeat_streak = 1
			GameState.defeat_floor = GameState.current_floor
		# 연패 자비 — streak회째부터 소지금은 안 깎는다(HP는 깎인다).
		# 빈곤 나선(연패→빈털터리)을 막는 "봐준다"는 신호다.
		var mercy: Dictionary = rules.get("mercy", {})
		var spared: bool = (
			bool(mercy.get("waive_money", false))
			and GameState.defeat_streak >= int(mercy.get("streak", 2))
		)
		GameState.player_stats["hp"] = maxi(1, int(round(GameState.max_hp() * hp_ratio)))
		var lost := 0
		if not spared:
			lost = int(round(float(GameState.player_stats["money"]) * money_loss))
			GameState.player_stats["money"] = maxi(0, int(GameState.player_stats["money"]) - lost)
		if lost > 0:
			print("[battle] 패배 — 소지금 %d 손실" % lost)
			BattleLog.push(
				TranslationServer.translate("UI_BLOG_DEFEAT_TOLL") % lost, BattleLog.Kind.DAMAGE
			)
		elif spared:
			BattleLog.push(
				TranslationServer.translate("UI_BLOG_DEFEAT_MERCY"), BattleLog.Kind.ACCENT
			)
	else:
		GameState.player_stats["hp"] = player_hp
	var growth := {}
	if result == &"win":
		# 승리하면 연패가 끊긴다 — 자비 카운터 리셋(도망은 유지, 승도 패도 아니라서).
		GameState.defeat_streak = 0
		GameState.defeat_floor = -1
		GameState.player_stats["money"] = (
			int(GameState.player_stats["money"]) + int(rewards["money"])
		)
		growth = GameState.grant_exp(int(rewards["exp"]))
		if bool(growth.get("level_up", false)):
			print("[battle] level up → %d" % int(growth.get("level", 0)))
		if not on_win_flag.is_empty():
			GameState.set_flag(on_win_flag, true)
		SaveManager.request_autosave("전투 승리")  # 필드 복귀 후 consume
	return growth
