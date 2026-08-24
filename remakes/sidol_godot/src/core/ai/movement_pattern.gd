class_name MovementPattern
extends RefCounted
## 종별 특화 이동 패턴 — 데이터 주도(monsters.json의 pattern 필드로 설정).
## 각 패턴은 "텔레그래프(예고 동작)"을 가진다 → 플레이어 학습 유도.

enum Kind {
	WANDER,       # 기본 배회 (Vulgar 등)
	CHASE,        # 직접 추적 (HellCop 등)
	DASH,         # 정지(텔레그래프 깜빡임) → 3셀 돌진 (Mad Eye)
	BURROW,       # 지하 잠복 2초 → 플레이어 인접 셀에서 출현 (DWorm)
	ZIGZAG,       # 좌우 급격 교대 + 직진 버스트 (Ozzy)
	PATROL,       # 고정 경로 순찰, 공격받으면 추적으로 전환 (Iron-Voc)
	PULSE,        # 정지 + N초마다 반경 데미지 펄스 (O-Ray)
	TELEPORT,     # N초마다 반경 내 랜덤 위치로 점프 (Sparker)
	AMBUSHER,     # 정지 위장 → 플레이어 인접 시 폭발적 3셀 공격 (Rogue Vending)
	PHASER,       # 벽 통과(충돌 무시), 느린 직진 (Null Pointer)
	RANGED,       # 거리 유지 + 발사체 (CRT Golem)
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


## 패턴별 파라미터 기본값 — monsters.json에서 오버라이드 가능
static func get_defaults(kind: int) -> Dictionary:
	match kind:
		Kind.DASH:
			return {"pause_ticks": 4, "dash_cells": 3, "cooldown_ticks": 3}
		Kind.BURROW:
			return {"hidden_ticks": 8, "emerge_radius": 3}
		Kind.ZIGZAG:
			return {"switch_interval": 2}
		Kind.PATROL:
			return {"route_length": 6}
		Kind.PULSE:
			return {"interval_ticks": 6, "radius": 2, "damage": 5}
		Kind.TELEPORT:
			return {"interval_ticks": 5, "jump_radius": 4}
		Kind.AMBUSHER:
			return {"trigger_range": 1, "burst_cells": 3, "damage": 15}
		Kind.PHASER:
			return {"speed_divisor": 3}   # 3틱마다 1셀 (느림)
		Kind.RANGED:
			return {"preferred_distance": 4, "projectile_interval": 5}
		_:
			return {}
