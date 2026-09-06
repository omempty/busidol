class_name DamageCalculator
extends RefCounted
## 순수 함수 집합 — 기본 공격은 원작 공식 보존((Ap+rnd10)/4, DP 미반영 —
## 원작 밸런스 결함 포함 유지). 기술은 속성 상성 반영.
## DP 반영 옵션은 난이도 프리셋 실착 시 과제(HANDOFF 5차 세션 남은 작업).


## 난수 폭 — **위력에 비례한다.**
##
## 원작은 rnd(10) 고정이었고 Ap가 30~830이라 피해 분산이 ±23%까지 났다. 리메이크는
## 레벨업을 더해 Ap가 1000대까지 가는데 난수만 10으로 두어, Lv14에서 **94%의 턴이
## 260~263 네 값 중 하나**가 됐다(분산 1.2% · 2026-09-06 실측). 적 HP가 310이면
## 언제나 정확히 2타 — 결과가 굴리기 전에 정해져 있으면 굴릴 이유가 없다.
## 폭을 위력의 1/5로 두면 어느 구간에서나 원작과 같은 체감 분산(±18% 안팎)이 된다.
## 하한 10은 원작 값 그대로다(저레벨 구간의 체감을 바꾸지 않는다).
static func spread(power: int, rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, maxi(10, power / 5))


## 기본 물리 공격 (원작: (Ap + rnd(10)) / 4 — 나눗수는 그대로, 폭만 위력 비례)
static func player_hit(ap: int, rng: RandomNumberGenerator) -> int:
	var raw := (ap + spread(ap, rng)) / 4
	return maxi(1, raw)


## 적 공격 (원작 공식 동일 구조)
static func enemy_hit(power: int, rng: RandomNumberGenerator) -> int:
	var raw := (power + spread(power, rng)) / 6
	return maxi(1, raw)


## 스킬 피해 — 속성 상성 배율 적용
static func skill_hit(
	skill_power: int,
	atk_stat: int,
	element: StringName,
	target_weaknesses: Array[StringName],
	rng: RandomNumberGenerator
) -> int:
	var pw := atk_stat + skill_power
	var base := (pw + spread(pw, rng)) / 3
	var mult := 1.0
	if element in target_weaknesses:
		mult = 1.5
	return maxi(1, int(base * mult))


## 최종 피해량 클램프
static func clamp_damage(raw: int, target_hp: int) -> int:
	return clampi(raw, 0, target_hp)
