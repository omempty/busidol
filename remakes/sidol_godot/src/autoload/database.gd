extends Node
## 데이터 조회 단일 창구 — dialogue.json / dialogue_sequences.json 로딩 담당.
## 원칙: 콘텐츠는 소스 하드코딩 금지, 전부 data 파일 경유 (AGENTS.md).

const DATA_DIR := "res://data/"

var _dialogue: Dictionary = {}
var _sequences: Dictionary = {}
var _encounters: Dictionary = {}
var _enemies: Dictionary = {}
var _items: Dictionary = {}
var _legacy_ref: Dictionary = {}  # 원작 상자 ATT(문자열) → 아이템 id
var _floor_stats: Dictionary = {}  # 층 키(f0..) → 필드 몬스터 스탯 범위
var _growth: Dictionary = {}

## 난이도 — "easy"/"normal"/"hard" (SettingsManager에서 변경)
## 현재 난이도 프리셋 키 — SettingsManager가 설정 변경 시 갱신한다.
## (구판은 이 값이 "normal"에 고정돼 있었고 get_difficulty_mult 호출부도 0건이었다.)
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


## 원작 상자 ATT(150~184) → 신규 아이템 id. items.json legacy_ref가 출처.
## 표에 없으면 빈 StringName.
## 층별 필드 몬스터 스탯 — monsters.json floor_stats. 없으면 빈 Dictionary.
## 시작 보유 스킬 id — skills.json의 `starting`. 없으면 **전 스킬**(현행 동작 보존).
func starting_skill_ids() -> Array[String]:
	var raw := JsonUtil.load_dict(DATA_DIR + "skills.json", "Database")
	var out: Array[String] = []
	var starting: Array = raw.get("starting", [])
	if not starting.is_empty():
		for sid: Variant in starting:
			out.append(str(sid))
		return out
	for sk: Dictionary in raw.get("skills", []):
		out.append(str(sk.get("id", "")))
	return out


func floor_stats(floor_idx: int) -> Dictionary:
	return _floor_stats.get("f%d" % floor_idx, {})


func legacy_item(attr: int) -> StringName:
	var mapped := str(_legacy_ref.get(str(attr), ""))
	return StringName(mapped)


func get_item(id: StringName) -> Dictionary:
	return _items.get(String(id), {})


func load_enemies() -> void:
	var raw := JsonUtil.load_dict(DATA_DIR + "monsters.json", "Database")
	if raw.is_empty():
		push_error("monsters.json 파싱 실패")
		return
	# floors 의 species 배열에서 고유 id 수집 + 기본 스탯 부여
	var seen := {}
	for floor_key: String in raw.get("floors", {}):
		var floor_data: Dictionary = raw["floors"][floor_key]
		for s: Variant in floor_data.get("species", []):
			var sid: String = ""
			if s is Dictionary:
				sid = str(s.get("id", ""))
			elif s is String:
				sid = str(s)
			if sid.is_empty() or seen.has(sid):
				continue
			seen[sid] = true
			# 필드 종은 **정체성만** 여기서 갖는다(이름·약점·플래그).
			# 강도는 전투가 벌어지는 **층**이 정한다 — 같은 종이 f1과 f2에 다 나오므로
			# 종 정의에 스탯을 굳히면 층별 난이도가 무너진다. BattleSetup이 floor_stats를 입힌다.
			_enemies[sid] = {
				"id": sid,
				"display_name": sid.replace("_", " ").capitalize(),
				"from_floor_stats": true,
			}
			# 시나리오 연계 필드 패스스루 — 처음 격파 시 세팅 플래그
			if s is Dictionary and s.has("first_win_flag"):
				_enemies[sid]["first_win_flag"] = str(s["first_win_flag"])
	_floor_stats = raw.get("floor_stats", {})
	_load_bosses(raw)
	_apply_species_meta(raw)


## species 섹션 — 종별 약점(브레이크 시스템) 및 display_name. 보스는 자기 정의 우선.
func _apply_species_meta(raw: Dictionary) -> void:
	var table: Dictionary = raw.get("species", {})
	for sid: String in table:
		var entry: Dictionary = table[sid]
		if not _enemies.has(sid):
			_enemies[sid] = {
				"id": sid,
				"display_name": sid.replace("_", " ").capitalize(),
				"ap": 15,
				"dp": 5,
				"hp_range": [20, 40],
				"exp": [5, 10],
				"money": [50, 100],
			}
		_enemies[sid]["weaknesses"] = entry.get("weaknesses", [])
		if entry.has("display_name"):
			_enemies[sid]["display_name"] = str(entry["display_name"])
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
	_legacy_ref = raw.get("legacy_ref", {})


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


## 층 인카운터 종 목록을 한 모양으로 펴서 돌려준다.
## monsters.json의 species 원소는 문자열(f0)과 객체(f1~)가 섞여 있다 —
## 그대로 str()로 찍으면 종 id가 `{ "id": "dworm", ... }` 통문자열이 돼
## 시트 조회·적 정의 조회가 전부 폴백으로 떨어진다.
func encounter_species(floor_idx: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in encounter_table(floor_idx).get("species", []):
		if typeof(entry) == TYPE_DICTIONARY:
			var d: Dictionary = entry
			(
				out
				. append(
					{
						"id": str(d.get("id", "")),
						"pattern": str(d.get("pattern", "wander")),
						"params": d.get("params", {}),
						"first_win_flag": str(d.get("first_win_flag", "")),
					}
				)
			)
		else:
			out.append({"id": str(entry), "pattern": "wander", "params": {}, "first_win_flag": ""})
	return out


func load_encounters() -> void:
	var raw := JsonUtil.load_dict(DATA_DIR + "monsters.json", "Database")
	_encounters = raw.get("floors", {})
	if _encounters.is_empty():
		push_error("monsters.json 파싱 실패")
