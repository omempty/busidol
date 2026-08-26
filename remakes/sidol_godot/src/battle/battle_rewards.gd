class_name BattleRewards
extends RefCounted
## 전투 보상 산출·반영 — monsters.json 종별 범위 보상(하드코딩 금지).


## 승리 보상 산출 — 종별 exp/money 범위에서 난수 합산.
static func compute(enemy_ids: Array[String]) -> Dictionary:
	var exp_total := 0
	var money_total := 0
	for eid in enemy_ids:
		var edef := Database.get_enemy_def(StringName(eid))
		var exp_range: Array = edef.get("exp", [5, 10])
		var money_range: Array = edef.get("money", [50, 100])
		exp_total += randi_range(int(exp_range[0]), int(exp_range[1]))
		money_total += randi_range(int(money_range[0]), int(money_range[1]))
	return {"exp": exp_total, "money": money_total}


## 결과 반영 — HP·보상·시나리오 플래그·오토세이브. 반환: grant_exp 성장 결과.
static func apply(
	result: StringName, rewards: Dictionary, player_hp: int, on_win_flag: String
) -> Dictionary:
	GameState.player_stats["hp"] = player_hp
	var growth := {}
	if result == &"win":
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
