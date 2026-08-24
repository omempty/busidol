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
var skills: Array[StringName] = []


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
	final_dmg = mini(final_dmg, hp)
	hp -= final_dmg
	return final_dmg


func heal(amount: int) -> int:
	var healed := mini(amount, max_hp - hp)
	hp += healed
	return healed


func attach_effect(effect: Dictionary) -> void:
	active_effects.append(effect)


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


func is_down() -> bool:
	return hp <= 0
