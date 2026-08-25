extends Node
## 전역 게임 상태 — 원작 전역변수(We/f/v_* 플래그)의 대체 (02_design/01 §2·§6).
## TODO(Phase 4): CharacterStats·Inventory 리소스 연결.

signal state_changed

var current_floor: int = 1  # 원작 f — F1에서 시작
var flags: Dictionary = {}  # 키: quests_v2.json 플래그 ID (Q_F1_START ...)
var chest_overrides: Dictionary = {}  # {층:int -> {Vector2i -> attr}} — 맵 원본 불변 원칙(§3.3)
var player_cell := Vector2i(-1, -1)  # 저장용 실시간 좌표 — field가 매 프레임 갱신(-1이면 미설정)

## 원작 We 초기값(level=0은 미구현 레벨업 대신 표기상 1, hp50/ap30/money5000).
var player_stats := {
	"level": 1,
	"exp": 0,
	"hp": 50,
	"ap": 30,
	"money": 5000,
}

## 대기 중 인카운터 데이터 — BattleScene이 소비 후 클리어
var pending_encounter := {}

var inventory := Inventory.new()


func has_flag(flag_id: String) -> bool:
	return bool(flags.get(flag_id, false))


func set_flag(flag_id: String, value: Variant = true) -> void:
	flags[flag_id] = value
	state_changed.emit()


## 성장 반영 — 경험치 누적 후 growth.json 레벨 테이블로 레벨업 판정.
## 레벨업 시 hp_up/ap_up을 현재치에 가산(최대치 산출식은 HudV0와 동일 기준).
## 반환: {"level_up": bool, "level": int, "levels_gained": int}
func grant_exp(amount: int) -> Dictionary:
	player_stats["exp"] = int(player_stats["exp"]) + amount
	var result := {"level_up": false, "level": int(player_stats["level"]), "levels_gained": 0}
	while true:
		var target := _level_entry(result["level"] + 1)
		if target.is_empty():
			break  # 만렙
		if int(player_stats["exp"]) < int(target.get("exp_accum", 0)):
			break
		player_stats["level"] = int(target["level"])
		player_stats["hp"] = int(player_stats["hp"]) + int(target.get("hp_up", 0))
		player_stats["ap"] = int(player_stats["ap"]) + int(target.get("ap_up", 0))
		result["level_up"] = true
		result["level"] = int(target["level"])
		result["levels_gained"] = int(result["levels_gained"]) + 1
	state_changed.emit()
	return result


func _level_entry(level: int) -> Dictionary:
	for entry: Dictionary in Database.level_table():
		if int(entry.get("level", -1)) == level:
			return entry
	return {}


## 상자 개봉 기록 — 층 전환·세이브/로드를 넘어 유지된다.
func set_chest_override(cell: Vector2i, attr_value: int) -> void:
	if not chest_overrides.has(current_floor):
		chest_overrides[current_floor] = {}
	chest_overrides[current_floor][cell] = attr_value


## 해당 층의 상자 오버라이드 반환(읽기 전용 용도 복제 없음 — 호출자가 순회만).
func chest_overrides_for(floor_index: int) -> Dictionary:
	return chest_overrides.get(floor_index, {})


## 새 게임 시작 시 초기화 — SaveManager.load_slot과 대칭.
func reset() -> void:
	current_floor = 1
	flags = {}
	chest_overrides = {}
	player_cell = Vector2i(-1, -1)
	player_stats = {
		"level": 1,
		"exp": 0,
		"hp": 50,
		"ap": 30,
		"money": 5000,
	}
	pending_encounter = {}
	inventory.clear()
	state_changed.emit()
