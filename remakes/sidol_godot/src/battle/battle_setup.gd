class_name BattleSetup
extends RefCounted
## 전투 셋업 데이터 구성 — 스킬·타이밍 로드, 적 전투원 생성(약점 포함).


## skills.json 로드 — {"skills": [...], "timing": {...}}
static func load_skills() -> Dictionary:
	var out := {"skills": [], "timing": {}}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/skills.json"))
	if typeof(raw) == TYPE_DICTIONARY:
		out["skills"] = raw.get("skills", [])
		out["timing"] = raw.get("timing", {})
	return out


## pending_encounter def의 enemies → Combatant 목록 생성.
## 반환: {"combatants": Array[Combatant], "ids": Array[String]}
static func build_enemies(def: Dictionary) -> Dictionary:
	var combatants: Array[Combatant] = []
	var ids: Array[String] = []
	for eid in def.get("enemies", ["mad_eye"]):
		# field/cutscene은 species 원본 딕셔너리를 넘길 수 있다 — id만 추출
		var eid_str := str(eid.get("id", eid)) if eid is Dictionary else str(eid)
		var edef: Dictionary = Database.get_enemy_def(StringName(eid_str))
		var hp_r: Array = edef.get("hp_range", [20, 40])
		var hp_val: int = randi_range(int(hp_r[0]), int(hp_r[1]))
		var c := Combatant.new(
			str(edef.get("display_name", eid_str)), hp_val,
			int(edef.get("ap", 15)), int(edef.get("dp", 5))
		)
		for w in edef.get("weaknesses", []):
			c.weaknesses.append(StringName(str(w)))
		combatants.append(c)
		ids.append(eid_str)
	return {"combatants": combatants, "ids": ids}
