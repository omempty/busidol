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
## 방어력 연화 상수 — 경감률 = dp / (dp + DP_SOFTCAP). dp 10 → 10%, 34 → 27%,
## 58 → 39%, 88 → 49%, 110 → 55%. **상한이 있어 절대 0에 수렴하지 않는다.**
##
## 구판은 `피해 - dp/4` 정액 감산이었다. 그런데 층별 적 1타가 3~21이고 방어구 dp가
## 8~110이라, **시작 소지금 5,000온으로 살 수 있는 화학 보호복(dp 88)** 하나면
## 22를 깎아 최종보스까지 모든 적의 1타가 최소값 1로 눌렸다(2026-09-06 실측).
## 정액 감산은 적 화력이 커질수록 약해져야 하는데 거꾸로 강해진다 — 비율로 바꾼다.
const DP_SOFTCAP := 90
var skills: Array[StringName] = []
## 기력(氣力) — 스킬 자원. **평타로 모으고 방어로 크게 모아 스킬로 쓴다.**
##
## 왜 넣었나(2026-09-06 유저 지적 "4F까지 공격만 연속하면 무조건 이김"): 스킬이
## 공격의 1.37~1.62배인데 코스트가 없어 늘 스킬이 정답이었고, 그마저 승패를 안 바꿔
## 커맨드 5개 중 실질 선택지가 1개였다. 자원을 두면 "지금 쓸까 모을까"가 매 턴 생긴다.
## MP·마나가 아니라 「기력」인 것은 배경이 1995년 공대이기 때문이다 — 마법이 없다.
##
## 0이면 이 전투원은 기력을 쓰지 않는다(적). 적에게도 주려면 여기만 세우면 된다.
var max_stamina := 0
var stamina := 0
var weaknesses: Array[StringName] = []  # 약점 속성 — 약점 히트 시 브레이크 게이지 상승
var break_gauge := 0  # 약점 히트 누적 — threshold 도달 시 브레이크
var break_threshold := 2
var broken_turns := 0  # 브레이크 지속 턴 — 행동 불가 + 받는 피해 ×1.5
## DP 경감을 받는가 — 방어구는 리메이크 추가분이라 **플레이어에게만** 적용된다.
## 원작 공식은 양쪽 다 DP 미반영이다(WARMODE.C: DeadEnemy/EnemyAttack).
## 공용 take_damage가 적에게도 dp/4를 깎던 탓에 f3 적(dp 165~195)이 플레이어 공격을
## 거의 전부 상쇄해 1~2 피해만 들어갔다(2026-08-28 실측).
var dp_reduces_damage := true


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
	# 방어력 경감 — 비율(dp/(dp+DP_SOFTCAP))로 깎는다(최소 1은 들어간다).
	# 버프 경감(%) 다음, 브레이크 증폭 앞에 온다: 브레이크는 "방어 무시"가 취지다.
	if dp_reduces_damage and dp > 0:
		var cut := float(dp) / float(dp + DP_SOFTCAP)
		final_dmg = maxi(1, int(round(float(final_dmg) * (1.0 - cut))))
	# 브레이크 — 방어 무시 급 피해 증폭
	if broken_turns > 0:
		final_dmg = maxi(1, int(final_dmg * 1.5))
	final_dmg = mini(final_dmg, hp)
	hp -= final_dmg
	return final_dmg


## 기력을 쓸 수 있는가 — 최대치가 0인 전투원(적)은 언제나 쓸 수 있다고 본다.
func can_spend_stamina(cost: int) -> bool:
	return max_stamina <= 0 or stamina >= cost


func spend_stamina(cost: int) -> void:
	if max_stamina > 0:
		stamina = maxi(0, stamina - cost)


func gain_stamina(amount: int) -> int:
	if max_stamina <= 0:
		return 0
	var before := stamina
	stamina = mini(max_stamina, stamina + amount)
	return stamina - before


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
