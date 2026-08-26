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
			return {"route_length": 6}
		Kind.PULSE:
			return {"interval_ticks": 6, "radius": 2, "damage": 5, "act_interval": 0.5}
		Kind.TELEPORT:
			return {"interval_ticks": 5, "jump_radius": 4, "act_interval": 0.45}
		Kind.AMBUSHER:
			return {"trigger_range": 1, "burst_cells": 3, "damage": 15, "act_interval": 0.4}
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
