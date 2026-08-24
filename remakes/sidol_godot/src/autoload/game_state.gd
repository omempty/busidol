extends Node
## 전역 게임 상태 — 원작 전역변수(We/f/v_* 플래그)의 대체 (02_design/01 §2·§6).
## TODO(Phase 4): CharacterStats·Inventory 리소스 연결.

signal state_changed

var current_floor: int = 1                # 원작 f — F1에서 시작
var flags: Dictionary = {}                # 키: quests_v2.json 플래그 ID (Q_F1_START ...)
var chest_overrides: Dictionary = {}      # 셀 오버라이드 기록 — 맵 원본 불변 원칙(§3.3)

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
