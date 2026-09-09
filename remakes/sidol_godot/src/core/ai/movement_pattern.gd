class_name MovementPattern
extends RefCounted
## 종별 특화 이동 패턴 — 데이터 주도(monsters.json의 pattern 필드로 설정).
## 각 패턴은 "텔레그래프(예고 동작)"을 가진다 → 플레이어 학습 유도.

enum Kind {
	WANDER,  # 기본 배회 (Vulgar 등)
	CHASE,  # 직접 추적 (HellCop 등)
	DASH,  # 정지(텔레그래프 깜빡임) → 3셀 돌진 (Mad Eye)
	BURROW,  # 지하 잠복 2초 → 플레이어 인접 셀에서 출현 (DWorm)
	ZIGZAG,  # 좌우 급격 교대 + 직진 버스트 (Ozzy)
	PATROL,  # 고정 경로 순찰, 공격받으면 추적으로 전환 (Iron-Voc)
	PULSE,  # 정지 + N초마다 반경 데미지 펄스 (O-Ray)
	TELEPORT,  # N초마다 반경 내 랜덤 위치로 점프 (Sparker)
	AMBUSHER,  # 정지 위장 → 플레이어 인접 시 폭발적 3셀 공격 (Rogue Vending)
	PHASER,  # 벽 통과(충돌 무시), 느린 직진 (Null Pointer)
	RANGED,  # 거리 유지 + 발사체 (CRT Golem)
}


## 패턴별 텔레그래프 정보 — UI/이펙트 표시용
static func get_telegraph(kind: int) -> Dictionary:
	match kind:
		Kind.DASH:
			return {"visual": "flash_red", "duration": 0.8, "hint": "돌진 준비"}
		Kind.BURROW:
			return {"visual": "dust_particles", "duration": 2.0, "hint": "잠복 중"}
		Kind.PULSE:
			return {"visual": "expanding_ring", "duration": 0.5, "hint": "펄스 발사"}
		Kind.TELEPORT:
			return {"visual": "glitch_flicker", "duration": 0.3, "hint": "점프 준비"}
		Kind.AMBUSHER:
			return {"visual": "slight_shake", "duration": 0.4, "hint": "위장 해제"}
		_:
			return {}


## 패턴 이름(monsters.json pattern 필드) → Kind. 데이터와 코드를 잇는 유일한 표.
const NAME_TO_KIND := {
	"wander": Kind.WANDER,
	"chase": Kind.CHASE,
	"dash": Kind.DASH,
	"burrow": Kind.BURROW,
	"zigzag": Kind.ZIGZAG,
	"patrol": Kind.PATROL,
	"pulse": Kind.PULSE,
	"teleport": Kind.TELEPORT,
	"ambusher": Kind.AMBUSHER,
	"phaser": Kind.PHASER,
	"ranged": Kind.RANGED,
}
## 행동 주기 기본값(초) — 한 걸음 사이 간격. 패턴 성격에 맞춘 엔진측 튜닝값이며
## monsters.json의 params.act_interval로 종별 오버라이드할 수 있다.
const BASE_ACT_INTERVAL := 0.34

## **실제로 decide()에 분기가 있는 패턴.** 여기 없는 것은 wander로 조용히 떨어진다.
##
## 왜 이 목록이 필요한가 (2026-09-09 실측): PATROL·PULSE는 enum에도, NAME_TO_KIND에도,
## get_defaults에도, get_telegraph에도 있었고 **데이터에서 실제로 배정까지 돼 있었는데**
## (f3 iron_voc 순찰 · f4 o_ray 펄스) SpeciesBrain에 분기가 없어 둘 다 배회만 했다.
## 게임은 정상으로 보이고 관문도 초록이었다 — 아무도 "선언한 패턴이 실제로 도는가"를
## 재지 않았기 때문이다. 이 목록과 AiProbe.check_pattern_coverage가 그 자리다.
const IMPLEMENTED_KINDS := [
	Kind.WANDER,
	Kind.CHASE,
	Kind.DASH,
	Kind.BURROW,
	Kind.ZIGZAG,
	Kind.PATROL,
	Kind.PULSE,
	Kind.TELEPORT,
	Kind.AMBUSHER,
	Kind.PHASER,
]


static func is_implemented(pattern: String) -> bool:
	return NAME_TO_KIND.has(pattern) and IMPLEMENTED_KINDS.has(NAME_TO_KIND[pattern])


static func kind_from_name(pattern: String) -> int:
	return int(NAME_TO_KIND.get(pattern, Kind.WANDER))


## 벽을 통과하는 패턴인가 — PHASER(Null Pointer)만 해당.
static func ignores_walls(kind: int) -> bool:
	return kind == Kind.PHASER


static func act_interval(kind: int, params: Dictionary = {}) -> float:
	if params.has("act_interval"):
		return maxf(float(params["act_interval"]), 0.05)
	return float(get_defaults(kind).get("act_interval", BASE_ACT_INTERVAL))


## 패턴별 파라미터 기본값 — monsters.json에서 오버라이드 가능
static func get_defaults(kind: int) -> Dictionary:
	match kind:
		Kind.CHASE:
			return {"act_interval": 0.28}
		Kind.DASH:
			return {"pause_ticks": 4, "dash_cells": 3, "cooldown_ticks": 3, "act_interval": 0.18}
		Kind.BURROW:
			return {"hidden_ticks": 8, "emerge_radius": 3, "act_interval": 0.30}
		Kind.ZIGZAG:
			return {"switch_interval": 2, "act_interval": 0.26}
		Kind.PATROL:
			# 한 변 6칸이면 32px 타일에서 화면 한 폭 안이라 순찰선이 눈에 들어온다.
			return {"route_length": 6, "aggro_radius": 5, "act_interval": 0.34}
		Kind.PULSE:
			return {"interval_ticks": 6, "radius": 2, "damage": 5, "act_interval": 0.5}
		Kind.TELEPORT:
			return {"interval_ticks": 5, "jump_radius": 4, "act_interval": 0.45}
		Kind.AMBUSHER:
			# trigger_range가 1이었다 — 몸이 2×2라 사실상 이미 닿은 뒤에야 걸린다.
			# 3칸이면 "지나가려는 순간" 터져서 매복으로 읽힌다.
			return {
				"trigger_range": 3,
				"burst_cells": 3,
				"cooldown_ticks": 6,
				"damage": 15,
				"act_interval": 0.4
			}
		Kind.PHASER:
			return {"speed_divisor": 3, "act_interval": 0.55}  # 느린 직진
		Kind.RANGED:
			return {"preferred_distance": 4, "projectile_interval": 5}
		_:
			return {}


## pattern 이름 → 브레인 인스턴스. CHASE/WANDER는 전용 브레인, 나머지는 SpeciesBrain.
static func make_brain(pattern: String, params: Dictionary = {}) -> AIBrain:
	var kind := kind_from_name(pattern)
	if kind == Kind.CHASE:
		return ChaseAI.new()
	if kind == Kind.WANDER:
		return WanderAI.new()
	var brain := SpeciesBrain.new()
	brain.configure(kind, params)
	return brain
