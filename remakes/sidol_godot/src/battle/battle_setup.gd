class_name BattleSetup
extends RefCounted
## 전투 셋업 데이터 구성 — 스킬·타이밍 로드, 적 전투원 생성(약점 포함).


## skills.json 로드 — {"skills": [...], "timing": {...}}
static func load_skills() -> Dictionary:
	var out := {"skills": [], "timing": {}}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/skills.json"))
	if typeof(raw) == TYPE_DICTIONARY:
		# 습득한 스킬만 전투 메뉴에 오른다(GameState.owned_skills).
		# 구판은 skills.json 전량을 그대로 넘겨 6종이 처음부터 열려 있었다.
		var owned: Array[Dictionary] = []
		for sk: Dictionary in raw.get("skills", []):
			if GameState.has_skill(StringName(str(sk.get("id", "")))):
				owned.append(sk)
		out["skills"] = owned
		out["timing"] = raw.get("timing", {})
	return out


## 기력 설정 {max, start, gain_on_attack, gain_on_guard, gain_on_turn}. skills.json이 값의 출처.
static func stamina_config() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/skills.json"))
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return (raw as Dictionary).get("stamina", {})


## 상태이상 id → {kind, turns, magnitude}. skills.json이 값의 출처.
static func status_effect_defs() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/skills.json"))
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return (raw as Dictionary).get("status_effect_defs", {})


## pending_encounter def의 enemies → Combatant 목록 생성.
## 반환: {"combatants": Array[Combatant], "ids": Array[String]}
static func build_enemies(def: Dictionary) -> Dictionary:
	var combatants: Array[Combatant] = []
	var ids: Array[String] = []
	for eid in def.get("enemies", ["mad_eye"]):
		# field/cutscene은 species 원본 딕셔너리를 넘길 수 있다 — id만 추출
		var eid_str := str(eid.get("id", eid)) if eid is Dictionary else str(eid)
		var edef: Dictionary = Database.get_enemy_def(StringName(eid_str))
		# 필드 종은 전투가 벌어지는 층의 스탯을 입는다(보스는 자기 정의를 쓴다).
		if bool(edef.get("from_floor_stats", false)):
			var fs := Database.floor_stats(GameState.current_floor)
			if not fs.is_empty():
				edef = edef.duplicate()
				edef["hp_range"] = fs.get("hp_range", [20, 40])
				var ar: Array = fs.get("ap_range", [15, 15])
				edef["ap"] = randi_range(int(ar[0]), int(ar[-1]))
				var dr: Array = fs.get("dp_range", [5, 5])
				edef["dp"] = randi_range(int(dr[0]), int(dr[-1]))
				edef["exp"] = fs.get("exp", [5, 10])
				edef["money"] = fs.get("money", [50, 100])
		var hp_r: Array = edef.get("hp_range", [20, 40])
		var hp_val: int = randi_range(int(hp_r[0]), int(hp_r[1]))
		# 난이도 배율(growth.json difficulty_presets) — 구판은 정의만 있고 곱하는 곳이 없었다.
		hp_val = maxi(1, int(round(hp_val * SettingsManager.difficulty_mult("enemy_hp_mult"))))
		var ap_val := maxi(
			1,
			int(round(int(edef.get("ap", 15)) * SettingsManager.difficulty_mult("enemy_ap_mult")))
		)
		var c := Combatant.new(
			str(edef.get("display_name", eid_str)), hp_val, ap_val, int(edef.get("dp", 5))
		)
		# 적 DP는 데이터로만 보존한다(원작 미반영) — 표시·설계 근거로 남기되 피해 계산에는 안 쓴다.
		c.dp_reduces_damage = false
		for w in edef.get("weaknesses", []):
			c.weaknesses.append(StringName(str(w)))
		combatants.append(c)
		ids.append(eid_str)
	return {"combatants": combatants, "ids": ids}
