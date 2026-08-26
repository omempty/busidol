extends Node
## 데이터 조회 단일 창구 — dialogue.json / dialogue_sequences.json 로딩 담당.
## 원칙: 콘텐츠는 소스 하드코딩 금지, 전부 data 파일 경유 (AGENTS.md).

const DATA_DIR := "res://data/"

var _dialogue: Dictionary = {}
var _sequences: Dictionary = {}
var _encounters: Dictionary = {}
var _enemies: Dictionary = {}
var _items: Dictionary = {}
var _growth: Dictionary = {}

## 난이도 — "easy"/"normal"/"hard" (SettingsManager에서 변경)
static var difficulty := "normal"


func get_difficulty_mult(key: String) -> float:
	var presets: Dictionary = _growth.get("difficulty_presets", {})
	var preset: Dictionary = presets.get(difficulty, {})
	return float(preset.get(key, 1.0))


func level_table() -> Array:
	return _growth.get("levels", [])


func get_enemy_def(id: StringName) -> Dictionary:
	return _enemies.get(
		String(id),
		{
			"display_name": String(id),
			"ap": 15,
			"dp": 5,
			"hp_range": [20, 40],
			"exp": [5, 10],
			"money": [50, 100]
		}
	)


func get_item(id: StringName) -> Dictionary:
	return _items.get(String(id), {})


func load_enemies() -> void:
	var raw := JsonUtil.load_dict(DATA_DIR + "monsters.json", "Database")
	if raw.is_empty():
		push_error("monsters.json 파싱 실패")
		return
	# floors 의 species 배열에서 고유 id 수집 + 기본 스탯 부여
	var seen := {}
	for floor_data: Dictionary in raw.get("floors", {}).values():
		for s: Variant in floor_data.get("species", []):
			var sid: String = ""
			if s is Dictionary:
				sid = str(s.get("id", ""))
			elif s is String:
				sid = str(s)
			if sid.is_empty() or seen.has(sid):
				continue
			seen[sid] = true
			_enemies[sid] = {
				"id": sid,
				"display_name": sid.replace("_", " ").capitalize(),
				"ap": 15,
				"dp": 5,
				"hp_range": [20, 40],
				"exp": [5, 10],
				"money": [50, 100],
			}
			# 시나리오 연계 필드 패스스루 — 처음 격파 시 세팅 플래그
			if s is Dictionary and s.has("first_win_flag"):
				_enemies[sid]["first_win_flag"] = str(s["first_win_flag"])
	_load_bosses(raw)
	_apply_weaknesses(raw)


## species 섹션 — 종별 약점(브레이크 시스템). 보스는 자기 정의의 weaknesses 우선.
func _apply_weaknesses(raw: Dictionary) -> void:
	var table: Dictionary = raw.get("species", {})
	for sid: String in table:
		if not _enemies.has(sid):
			continue
		_enemies[sid]["weaknesses"] = table[sid].get("weaknesses", [])
	for bid: String in raw.get("bosses", {}):
		if _enemies.has(bid):
			_enemies[bid]["weaknesses"] = raw["bosses"][bid].get("weaknesses", [])


## bosses 섹션 — dodge_phase(회피 페이즈) 설정 포함 보스 정의
func _load_bosses(raw: Dictionary) -> void:
	for bid: String in raw.get("bosses", {}):
		var bdef: Dictionary = raw["bosses"][bid]
		_enemies[bid] = {
			"id": bid,
			"display_name": str(bdef.get("display_name", bid.replace("_", " ").capitalize())),
			"ap": int(bdef.get("ap", 20)),
			"dp": int(bdef.get("dp", 8)),
			"hp_range": bdef.get("hp_range", [100, 140]),
			"exp": bdef.get("exp", [80, 120]),
			"money": bdef.get("money", [400, 600]),
			"is_boss": true,
			"dodge_phase": bdef.get("dodge_phase", {}),
			"dodge_damage_per_hit": int(bdef.get("dodge_damage_per_hit", 3)),
			"weaknesses": bdef.get("weaknesses", []),
		}


func load_items() -> void:
	# items.json은 {items: [...]} 객체 래핑 — load_array(최상위 배열 전용)가 아닌
	# load_dict로 읽는다. 기존 load_array 사용 시 빈 DB로 로드되는 침묵 버그(8/26 자동 테스트 적발).
	var raw := JsonUtil.load_dict(DATA_DIR + "items.json", "Database")
	for item: Dictionary in raw.get("items", []):
		_items[str(item["id"])] = item


func _ready() -> void:
	load_dialogue()
	load_sequences()
	load_encounters()
	load_enemies()
	load_items()
	_load_growth()


func _load_growth() -> void:
	_growth = JsonUtil.load_dict(DATA_DIR + "growth.json", "Database")


func load_dialogue() -> void:
	_dialogue = JsonUtil.load_dict(DATA_DIR + "dialogue.json", "Database")
	if _dialogue.is_empty():
		push_error("dialogue.json 파싱 실패")


func load_sequences() -> void:
	var raw := JsonUtil.load_dict(DATA_DIR + "dialogue_sequences.json", "Database")
	_sequences = raw.get("sequences", {})
	if _sequences.is_empty():
		push_error("dialogue_sequences.json 파싱 실패")


## 대사 본문 조회 — 키 형식 "@t17" / "@c101" (마스터 시나리오 §4.1 체계)
func text(key: String) -> String:
	return str(_dialogue.get(key, ""))


func has_text(key: String) -> bool:
	return _dialogue.has(key)


func sequence(id: StringName) -> Array:
	var v: Variant = _sequences.get(String(id))
	if typeof(v) == TYPE_DICTIONARY:
		var steps: Variant = v.get("steps", [])
		return steps if typeof(steps) == TYPE_ARRAY else []
	if typeof(v) == TYPE_ARRAY:
		return v
	return []


## 층별 인카운터 테이블 조회 — data/monsters.json
func encounter_table(floor_idx: int) -> Dictionary:
	var key := "f%d" % floor_idx
	return _encounters.get(key, {"count": 0, "species": []})


func load_encounters() -> void:
	var raw := JsonUtil.load_dict(DATA_DIR + "monsters.json", "Database")
	_encounters = raw.get("floors", {})
	if _encounters.is_empty():
		push_error("monsters.json 파싱 실패")
