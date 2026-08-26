class_name ItemEffects
## 아이템 효과 해석 단일 창구 — 필드/전투가 같은 규칙을 쓰게 한다.
##
## 2026-08-27 실측: items.json 59종 중 게임에 영향을 주는 건 hp_restore 9종뿐이었다.
## 무기 19종은 장착 시스템 부재(별도 해소), 아래 셋은 사용 경로 자체가 없었다:
##   · magic_substitute의 `cures` — 상태이상 해제
##   · consumable의 `ap_buff` — 공격력 임시 상승
##   · money의 `money_value` — 원작 DON(상자에서 돈)
##
## 효과 값은 전부 items.json이 소유한다(소스에 수치 금지, AGENTS.md).

## ap_buff에 지속 턴이 안 적힌 아이템의 기본값. 데이터가 우선한다.
const DEFAULT_AP_BUFF_TURNS := 3
## ap_buff_turns만 있고 상승치가 없는 아이템의 기본 상승치.
const DEFAULT_AP_BUFF := 10


## 획득 시점 처리 — money 계열은 소지품에 넣지 않고 즉시 골드로 바꾼다(원작 DON).
## 반환: 소지품에 넣었으면 false(=이미 소비됨), 아니면 true.
static func on_acquire(item_id: StringName, count: int = 1) -> bool:
	var def := Database.get_item(item_id)
	var value := int(def.get("money_value", 0))
	if str(def.get("kind", "")) != "money" or value <= 0:
		return true
	GameState.player_stats["money"] = int(GameState.player_stats.get("money", 0)) + value * count
	GameState.state_changed.emit()
	return false


## 이 아이템을 지금 쓸 수 있는가. in_battle=false면 전투 전용 효과는 제외한다.
static func is_usable(def: Dictionary, in_battle: bool) -> bool:
	if int(def.get("hp_restore", 0)) > 0:
		return true
	if not in_battle:
		return false  # 상태이상·버프는 전투 중에만 의미가 있다
	if not (def.get("cures", []) as Array).is_empty():
		return true
	if not str(def.get("applies", "")).is_empty():
		return true
	return int(def.get("ap_buff", 0)) > 0 or int(def.get("ap_buff_turns", 0)) > 0


## 필드 사용 — 회복만 가능. 반환: 사람이 읽는 결과 문구(빈 문자열이면 사용 실패).
static func use_on_field(def: Dictionary) -> String:
	var restore := int(def.get("hp_restore", 0))
	if restore <= 0:
		return ""
	var stats: Dictionary = GameState.player_stats
	var max_hp := GameState.max_hp()
	var before := int(stats.get("hp", 0))
	if before >= max_hp:
		return ""  # 만HP — 낭비 방지
	stats["hp"] = mini(before + restore, max_hp)
	GameState.state_changed.emit()
	return "HP %d 회복" % (int(stats["hp"]) - before)


## 전투 사용 — 회복 + 상태이상 해제 + 공격 버프. 반환: 결과 문구 목록.
static func use_in_battle(def: Dictionary, target: Combatant) -> Array[String]:
	var out: Array[String] = []
	var restore := int(def.get("hp_restore", 0))
	if restore > 0:
		var healed := target.heal(restore)
		if healed > 0:
			out.append("HP +%d" % healed)

	var cured := _cure(def, target)
	if not cured.is_empty():
		out.append("%s 해제" % ", ".join(cured))

	var applies := str(def.get("applies", ""))
	if not applies.is_empty():
		var edef: Dictionary = BattleSetup.status_effect_defs().get(applies, {})
		if edef.is_empty():
			push_warning("applies에 정의 없는 효과 id: %s" % applies)
		else:
			var dur := maxi(
				1,
				int(
					round(
						(
							int(edef.get("turns", 3))
							* SettingsManager.difficulty_mult("status_duration_mult")
						)
					)
				)
			)
			(
				target
				. attach_effect(
					{
						"kind": StringName(str(edef.get("kind", ""))),
						"turns": dur,
						"magnitude": int(edef.get("magnitude", 0)),
					}
				)
			)
			out.append("%s (%d턴)" % [str(edef.get("_desc", applies)).split(" —")[0], dur])

	var buff := int(def.get("ap_buff", 0))
	var turns := int(def.get("ap_buff_turns", 0))
	if buff > 0 or turns > 0:
		var amount := buff if buff > 0 else DEFAULT_AP_BUFF
		var dur := turns if turns > 0 else DEFAULT_AP_BUFF_TURNS
		target.attach_effect({"kind": &"buff_attack", "turns": dur, "magnitude": amount})
		out.append("공격력 +%d (%d턴)" % [amount, dur])
	return out


## cures는 status_effect_defs의 **효과 id**(burn 등)를 담는다 — Combatant가 보관하는
## kind로 변환해 지운다. id를 kind로 착각하면 아무것도 안 지워진다(스킬 쪽에서 겪은 함정).
static func _cure(def: Dictionary, target: Combatant) -> Array[String]:
	var ids: Array = def.get("cures", [])
	if ids.is_empty():
		return []
	var defs := BattleSetup.status_effect_defs()
	var removed: Array[String] = []
	for effect_id: String in ids:
		var edef: Dictionary = defs.get(effect_id, {})
		if edef.is_empty():
			push_warning("cures에 정의 없는 효과 id: %s" % effect_id)
			continue
		var kind := StringName(str(edef.get("kind", "")))
		var hit := false
		for i in range(target.active_effects.size() - 1, -1, -1):
			if target.active_effects[i].get("kind", &"") == kind:
				target.active_effects.remove_at(i)
				hit = true
		if hit:
			removed.append(effect_id)
	return removed
