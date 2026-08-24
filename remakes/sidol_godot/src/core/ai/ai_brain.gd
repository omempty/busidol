class_name AIBrain
extends RefCounted
## 몬스터 AI 베이스 — 원작 PATTERN표를 대체하는 데이터 주도 브레인.
## docs/02_design/01_oop_redesign.md §5 참조.

var move_cooldown := 0.0
var current_dir := Vector2i.ZERO


## ctx: { self_cell, player_cell, passable: Callable, occupied: Dictionary, rng: RandomNumberGenerator }
## 반환: 이동 방향(Vector2i) 또는 Vector2i.ZERO(정지)
func decide(_ctx: Dictionary) -> Vector2i:
	return Vector2i.ZERO


## 헬퍼: 4방향 중 통행 가능하고 점유되지 않은 방향 목록
static func free_dirs(ctx: Dictionary, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var target := cell + d
		if ctx.passable.call(target) and not ctx.occupied.has(target):
			out.append(d)
	return out
