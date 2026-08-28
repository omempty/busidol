class_name FleeRule
## 도망 판정 — 확률 계산만 하는 순수 함수 묶음(난수도 호출자가 넘긴다).
##
## 원작은 도망이 **항상 성공**이었다(WARMODE.C `MeMove` case 4: `return(0)`,
## 04_game_systems §2.2). 원작 코드에는 `ME.Hp-=random(10)` 페널티를 넣으려다
## 주석 처리한 흔적이 남아 있다 — 저자도 "공짜 도망"을 문제로 봤다는 뜻이다.
##
## 2026-08-28 현대 편의 결정: 확률제 + 실패 시 턴 소모.
## 다만 **실패할수록 확률이 오른다** — 도망이 막혀 같은 전투에 갇히는 것이
## 현대 RPG에서 가장 나쁜 경험이라, 위험은 주되 출구는 남긴다.
## 수치는 전부 data/battle_rules.json이 소유한다(AGENTS.md 콘텐츠 하드코딩 금지).

const DEFAULTS := {
	"base_chance": 0.5,
	"per_failure_bonus": 0.25,
	"low_hp_bonus": 0.2,
	"low_hp_at": 0.3,
	"floor_penalty": 0.03,
	"min_chance": 0.15,
	"max_chance": 0.95,
	"boss_allowed": false,
}


## 이 전투에서 도망을 시도할 수 있는가. 보스전은 규칙으로 막는다.
static func allowed(rules: Dictionary, is_boss: bool) -> bool:
	if not is_boss:
		return true
	return bool(_v(rules, "boss_allowed"))


## 성공 확률(0~1). failures = 이 전투에서 이미 실패한 횟수.
static func chance(rules: Dictionary, failures: int, hp_ratio: float, floor_no: int) -> float:
	var p := float(_v(rules, "base_chance"))
	p += float(_v(rules, "per_failure_bonus")) * float(maxi(failures, 0))
	if hp_ratio <= float(_v(rules, "low_hp_at")):
		p += float(_v(rules, "low_hp_bonus"))  # 빈사일수록 놓아 준다 — 전멸 반복 방지
	p -= float(_v(rules, "floor_penalty")) * float(maxi(floor_no, 0))
	return clampf(p, float(_v(rules, "min_chance")), float(_v(rules, "max_chance")))


static func _v(rules: Dictionary, key: String) -> Variant:
	return rules.get(key, DEFAULTS[key])
