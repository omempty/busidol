class_name DamageCalculator
extends RefCounted
## 순수 함수 집합 — 기본 공격은 원작 공식 보존((Ap+rnd10)/4, DP 미반영 —
## 원작 밸런스 결함 포함 유지). 기술은 속성 상성 반영.
## DP 반영 옵션은 난이도 프리셋 실착 시 과제(HANDOFF 5차 세션 남은 작업).


## 기본 물리 공격 (원작: (Ap + rnd(10)) / 4)
static func player_hit(ap: int, rng: RandomNumberGenerator) -> int:
	var raw := (ap + rng.randi_range(0, 10)) / 4
	return maxi(1, raw)


## 적 공격 (원작 공식 동일 구조)
static func enemy_hit(power: int, rng: RandomNumberGenerator) -> int:
	var raw := (power + rng.randi_range(0, 10)) / 6
	return maxi(1, raw)


## 스킬 피해 — 속성 상성 배율 적용
static func skill_hit(
	skill_power: int,
	atk_stat: int,
	element: StringName,
	target_weaknesses: Array[StringName],
	rng: RandomNumberGenerator
) -> int:
	var base := (atk_stat + skill_power + rng.randi_range(0, 10)) / 3
	var mult := 1.0
	if element in target_weaknesses:
		mult = 1.5
	return maxi(1, int(base * mult))


## 최종 피해량 클램프
static func clamp_damage(raw: int, target_hp: int) -> int:
	return clampi(raw, 0, target_hp)
