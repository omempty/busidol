class_name Combatant
extends RefCounted
## 전투 참여자 래퍼 — hp/ap/dp 직접 보유 + 활성 상태이상.
## TODO(Phase 4): CharacterStats Resource와 연동.

var display_name := ""
var max_hp := 50
var hp := 50
var ap := 30
var dp := 10
var active_effects: Array[Dictionary] = []
## 방어력 나눗수 — dp 8이면 -2, dp 110이면 -27. 층별 적 1타(3~44)에 대응해 정한 값.
const DP_DIVISOR := 4
var skills: Array[StringName] = []
var weaknesses: Array[StringName] = []  # 약점 속성 — 약점 히트 시 브레이크 게이지 상승
var break_gauge := 0  # 약점 히트 누적 — threshold 도달 시 브레이크
var break_threshold := 2
var broken_turns := 0  # 브레이크 지속 턴 — 행동 불가 + 받는 피해 ×1.5


func _init(p_name: String, p_hp: int, p_ap: int, p_dp: int) -> void:
	display_name = p_name
	max_hp = p_hp
	hp = p_hp
	ap = p_ap
	dp = p_dp


func take_damage(raw: int) -> int:
	var final_dmg := raw
	# 방어 버프 적용 (피해 경감 %)
	for fx in active_effects:
		if fx["kind"] == &"buff_damage_taken":
			final_dmg = maxi(1, int(final_dmg * (1.0 - float(fx["magnitude"]) / 100.0)))
	# 방어력 경감 — dp/DP_DIVISOR 만큼 깎는다(최소 1은 들어간다).
	# 버프 경감(%) 다음, 브레이크 증폭 앞에 온다: 브레이크는 "방어 무시"가 취지다.
	final_dmg = maxi(1, final_dmg - int(dp / DP_DIVISOR))
	# 브레이크 — 방어 무시 급 피해 증폭
	if broken_turns > 0:
		final_dmg = maxi(1, int(final_dmg * 1.5))
	final_dmg = mini(final_dmg, hp)
	hp -= final_dmg
	return final_dmg


func heal(amount: int) -> int:
	var healed := mini(amount, max_hp - hp)
	hp += healed
	return healed


## 공격 버프(buff_attack) 합산 — 도구로 올린 공격력이 실제 피해에 반영되게.
func attack_stat() -> int:
	var total := ap
	for fx in active_effects:
		if fx["kind"] == &"buff_attack":
			total += int(fx["magnitude"])
	return total


## 상태 저항(buff_status_resist)이 걸려 있으면 새 상태이상은 붙지 않는다.
## 저항·버프 자체는 통과시킨다 — 아군 효과까지 막으면 저항이 스스로를 못 건다.
func attach_effect(effect: Dictionary) -> void:
	var kind: StringName = effect.get("kind", &"")
	if kind in [&"dot", &"paralysis"] and has_status_resist():
		return
	active_effects.append(effect)


func has_status_resist() -> bool:
	for fx in active_effects:
		if fx["kind"] == &"buff_status_resist":
			return true
	return false


func tick_effects() -> Array[int]:
	"""턴 종료 시 호출. 반환: 각 DoT의 피해량 목록."""
	var dot_damages: Array[int] = []
	for i in range(active_effects.size() - 1, -1, -1):
		var fx: Dictionary = active_effects[i]
		match fx["kind"]:
			&"dot":
				var dmg: int = int(fx["magnitude"])
				hp = maxi(0, hp - dmg)
				dot_damages.append(dmg)
		fx["turns"] = int(fx["turns"]) - 1
		if int(fx["turns"]) <= 0:
			active_effects.remove_at(i)
	return dot_damages


func has_paralysis() -> bool:
	for fx in active_effects:
		if fx["kind"] == &"paralysis":
			return true
	return false


func is_broken() -> bool:
	return broken_turns > 0


## 약점 히트 1회 처리 — 게이지 상승, 임계 도달 시 브레이크. 반환: 브레이크 발동 여부.
func register_weak_hit() -> bool:
	if is_broken():
		return false
	break_gauge += 1
	if break_gauge >= break_threshold:
		break_gauge = 0
		broken_turns = 1
		return true
	return false


func is_down() -> bool:
	return hp <= 0
