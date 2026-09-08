extends Node
## 전역 게임 상태 — 원작 전역변수(We/f/v_* 플래그)의 대체 (02_design/01 §2·§6).
## TODO(Phase 4): CharacterStats·Inventory 리소스 연결.

signal state_changed
## 획득 알림 — **얻은 줄 모르면 얻은 것이 아니다.**
## 2026-09-06까지 스킬도 아이템도 조용히 들어왔다(유일한 신호가 콘솔 print였다).
## 그래서 마스터 시나리오 §2.2 성장 트리를 배선해도 플레이어는 몰랐다.
## 화면에 무엇을 띄울지는 HUD가 정한다 — 여기는 "무엇이 들어왔다"만 알린다.
signal acquired(kind: StringName, id: StringName, amount: int)

const BASE_HP := 50  # 원작 We 초기값
const BASE_DP := 10  # 맨몸 방어력 — 구판 Combatant 생성 시 하드코딩돼 있던 값
var current_floor: int = 1  # 원작 f — F1에서 시작
## 한 번이라도 발을 들인 층 — 빠른 이동(Q5)의 해금 조건. 세이브 대상.
var visited_floors: Dictionary = {}
## 장착 중인 장비 — 슬롯명 → 아이템 id. weapon·armor 두 칸.
## 구판은 장착 개념이 아예 없어 items.json의 무기 19종(ap 10~800, element 보유)이
## 획득만 되고 전투에 아무 영향도 주지 않았다.
var equipped: Dictionary = {}
## 습득한 스킬 — id → true. 세이브 대상.
## skills.json의 `starting` 배열이 시작 보유분을 정한다. 그 키가 없으면 **전부 개방**이라
## 기존 동작(6종 즉시 사용)이 그대로 유지된다 — 성장 트리는 데이터만 채우면 켜진다.
var owned_skills: Dictionary = {}
var flags: Dictionary = {}  # 키: quests_v2.json 플래그 ID (Q_F1_START ...)
var chest_overrides: Dictionary = {}  # {층:int -> {Vector2i -> attr}} — 맵 원본 불변 원칙(§3.3)
var player_cell := Vector2i(-1, -1)  # 저장용 실시간 좌표 — field가 매 프레임 갱신(-1이면 미설정)

## 연패 기록 — 패배 자비(같은 층 연속 패배 streak회째부터 소지금 면제)용.
## 승패가 갈릴 때마다 BattleRewards.apply가 갱신한다. 세이브 대상(불러온 뒤에도
## 자비가 이어져야 "봐준다"는 신호가 끊기지 않는다). 구 세이브엔 키가 없어 0/-1로 시작.
var defeat_streak := 0
var defeat_floor := -1

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

## 층별 필드 몬스터 명단 — 층(int) → [{species, pattern, params, cell}].
##
## **전투를 거쳐도 남아 있어야 한다.** 전투는 씬 전환이라 돌아오면 필드가 새로
## 만들어지는데, 그때마다 그 층 몬스터를 통째로 새로 뽑고 있었다 — 잡은 놈이
## 되살아나고 자리·종까지 매번 바뀌어서 「치웠다」가 남지 않고 되돌아 걷는 길이
## 벌이 됐다(2026-08-29). 여기에 명단을 두면 전투를 다녀와도 그 층은 그대로다.
## 세이브에는 싣지 않는다 — 불러오면 그 층은 새로 채워진다.
var field_roster := {}

var inventory := Inventory.new()
## 전장의 안개 — 층별로 "어디를 봤는가". 세이브 대상.
## 여기 두는 이유는 **전투가 씬 전환**이기 때문이다. 필드가 들고 있으면 전투를
## 한 판 하고 돌아올 때마다 층이 통째로 다시 어두워진다(field_roster와 같은 사정).
var fog := FogOfWar.new()
## NPC 대화 횟수 및 시퀀스 청취 기록 — 다회차 대화 밈/반복 대사 및 진행도 연동.
##
## **키는 반드시 String이다**(StringName 아님). 세이브를 거치면 JSON이 키를 String으로
## 되돌려 주는데, 기록은 StringName으로 하고 조회도 StringName으로 하면 불러온 뒤
## 조회가 어긋날 여지가 남는다. 들어오고 나가는 자리에서 한 번에 str()로 눕힌다.
var npc_seen_sequences: Dictionary = {}


func get_sequence_seen_count(seq_id: StringName) -> int:
	return int(npc_seen_sequences.get(str(seq_id), 0))


func record_sequence_seen(seq_id: StringName) -> int:
	var key := str(seq_id)
	var c: int = int(npc_seen_sequences.get(key, 0)) + 1
	npc_seen_sequences[key] = c
	return c


func _ready() -> void:
	init_skills()


func has_flag(flag_id: String) -> bool:
	return bool(flags.get(flag_id, false))


## 플래그 설정 — 처음 켜지는 순간 growth.json의 스토리 보너스 EXP를 지급한다.
##
## 2026-08-28까지 `story_bonus_exp`는 **아무도 읽지 않는 사문화 데이터**였다.
## growth.json은 "스토리 보너스 EXP로 노가다 방지"라고 적어 두었지만 지급 경로가 없어,
## 실제로는 잡몹만으로 레벨을 채워야 했다(계측: 만렙까지 394전투).
## 세이브 로드는 flags 딕셔너리를 통째로 갈아끼우므로 이 경로를 타지 않는다(중복 지급 없음).
func set_flag(flag_id: String, value: Variant = true) -> void:
	var was_on := bool(flags.get(flag_id, false))
	flags[flag_id] = value
	if not was_on and bool(value):
		var bonus := Database.story_bonus_exp(flag_id)
		if bonus > 0:
			var result := grant_exp(bonus)
			print(
				(
					"[growth] 스토리 보너스 %s +%d EXP%s"
					% [
						flag_id,
						bonus,
						(" → Lv%d" % int(result["level"])) if bool(result["level_up"]) else ""
					]
				)
			)
	state_changed.emit()


## 성장 반영 — 경험치 누적 후 growth.json 레벨 테이블로 레벨업 판정.
## 레벨업 시 hp_up/ap_up을 현재치에 가산(최대치 산출식은 HudV0와 동일 기준).
## 반환: {"level_up": bool, "level": int, "levels_gained": int}
## 현재 레벨 최대 HP — 초기값 + 레벨 테이블 hp_up 누적(growth.json).
## HudV0가 갖고 있던 산식을 올린 것 — 아이템 회복도 같은 상한을 봐야 한다.
func max_hp() -> int:
	var total := BASE_HP
	for entry: Dictionary in Database.level_table():
		if int(entry.get("level", 0)) <= int(player_stats.get("level", 1)):
			total += int(entry.get("hp_up", 0))
	return maxi(total, 1)


## 경험치 지급 + 레벨업 처리. 스탯 딕셔너리에 키가 없어도 죽지 않는다 —
## 구판은 `player_stats["exp"]`를 직접 읽어, exp 키가 없는 상태(구 세이브·테스트 설정)에서
## **전투 승리 순간 보상 경로가 통째로 터졌다**(2026-08-28, 턴 버그를 고치자 드러났다).
func grant_exp(amount: int) -> Dictionary:
	player_stats["exp"] = int(player_stats.get("exp", 0)) + amount
	var result := {
		"level_up": false, "level": int(player_stats.get("level", 1)), "levels_gained": 0
	}
	while true:
		var target := _level_entry(result["level"] + 1)
		if target.is_empty():
			break  # 만렙
		if int(player_stats["exp"]) < int(target.get("exp_accum", 0)):
			break
		player_stats["level"] = int(target["level"])
		player_stats["hp"] = int(player_stats.get("hp", 0)) + int(target.get("hp_up", 0))
		player_stats["ap"] = int(player_stats.get("ap", 0)) + int(target.get("ap_up", 0))
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
## 층 진입 시 기록 — 빠른 이동 목적지 목록의 근거.
## kind가 곧 슬롯 이름 — weapon/armor. 같은 것을 다시 고르면 해제.
## 반환: 실제로 장착 상태가 바뀌었는가.
const EQUIP_SLOTS := ["weapon", "armor"]


func equip(item_id: StringName) -> bool:
	var slot := str(Database.get_item(item_id).get("kind", ""))
	if not EQUIP_SLOTS.has(slot):
		return false
	if str(equipped.get(slot, "")) == String(item_id):
		equipped.erase(slot)
	else:
		equipped[slot] = String(item_id)
	state_changed.emit()
	return true


## 시작 보유 스킬로 초기화 — 새 게임·리셋 시. 이미 보유분이 있으면 건드리지 않는다.
func init_skills(force: bool = false) -> void:
	if not force and not owned_skills.is_empty():
		return
	owned_skills = {}
	for sid: String in Database.starting_skill_ids():
		owned_skills[sid] = true


## 스킬 습득 — 컷신 grant_skill op이 부른다. 반환: 새로 얻었는가.
func grant_skill(skill_id: StringName) -> bool:
	var sid := String(skill_id)
	if sid.is_empty() or owned_skills.has(sid):
		return false
	owned_skills[sid] = true
	acquired.emit(&"skill", skill_id, 1)
	state_changed.emit()
	return true


func has_skill(skill_id: StringName) -> bool:
	return owned_skills.has(String(skill_id))


func owned_skill_ids() -> Array[String]:
	var out: Array[String] = []
	for k: String in owned_skills:
		out.append(k)
	return out


func equipped_in(slot: String) -> Dictionary:
	var eid := str(equipped.get(slot, ""))
	return Database.get_item(StringName(eid)) if not eid.is_empty() else {}


func equipped_weapon() -> Dictionary:
	return equipped_in("weapon")


## 방어력 = 기본 DP + 장착 방어구 dp. 원작은 DP를 저장만 하고 쓰지 않았다(밸런스 결함) —
## 리메이크는 **플레이어 쪽에만** 반영해 방어구에 의미를 준다(백로그 §2 D-FAITH).
## 적 DP까지 켜면 실측으로 맞춘 층별 곡선이 통째로 흔들리므로 데이터로만 남긴다.
func defense_power() -> int:
	return BASE_DP + int(equipped_in("armor").get("dp", 0))


## 전투 공격력 = 기본 AP + 장착 무기 ap.
func attack_power() -> int:
	return int(player_stats.get("ap", 0)) + int(equipped_weapon().get("ap", 0))


## 기본 공격의 속성 — 무기가 정한다. 무기가 없거나 none이면 물리.
## 전기충격기를 들면 기계 계열(electric 약점)에 ×1.5가 붙어 브레이크로 이어진다.
func attack_element() -> StringName:
	var el := str(equipped_weapon().get("element", "physical"))
	return StringName("physical" if el.is_empty() or el == "none" else el)


func mark_visited(floor_index: int) -> void:
	visited_floors[floor_index] = true


## 방문한 층 번호 오름차순.
func visited_list() -> Array[int]:
	var out: Array[int] = []
	for k: int in visited_floors:
		out.append(k)
	out.sort()
	return out


func chest_overrides_for(floor_index: int) -> Dictionary:
	return chest_overrides.get(floor_index, {})


## 새 게임 시작 시 초기화 — SaveManager.load_slot과 대칭.
func reset() -> void:
	current_floor = 1
	visited_floors = {}
	equipped = {}
	init_skills()
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
	field_roster = {}
	defeat_streak = 0
	defeat_floor = -1
	inventory.clear()
	npc_seen_sequences.clear()
	fog.clear()
	state_changed.emit()


## `requires_flag` 규약 — **문자열 하나이거나 목록**이고, 목록이면 전부 서 있어야 한다.
##
## 트리거·전환·NPC 대사 변형이 같은 규약을 쓴다. 세 군데가 각자 해석하기 시작하면
## 「트리거는 열렸는데 대사는 안 바뀐다」 같은 어긋남이 생긴다.
func has_all_flags(req: Variant) -> bool:
	if req == null:
		return true
	if req is Array:
		for r: Variant in req:
			if not has_flag(str(r)):
				return false
		return true
	return has_flag(str(req))
