class_name WanderAI
extends AIBrain
## 배회 — 현재 방향을 유지하다 막히면 랜덤 전환 + 정찰 회전(Look-around).
## 원작 PATTERN 웨이포인트의 자연스러운 대체.

var dir_persistence := 3  # 같은 방향 유지 틱 수
var look_around_chance := 0.20  # 제자리에서 시선만 돌려 정찰할 확률


func decide(ctx: Dictionary) -> Vector2i:
	var free := free_dirs(ctx, ctx.self_cell)
	if free.is_empty():
		current_dir = Vector2i.ZERO
		return Vector2i.ZERO

	move_cooldown -= 1
	if move_cooldown > 0 and current_dir != Vector2i.ZERO and free.has(current_dir):
		return current_dir

	move_cooldown = dir_persistence

	# 정찰 회전: 이동하지 않고 고개만 돌려 주변을 탐색 (시야각 회전)
	if ctx.rng.randf() < look_around_chance and not free.is_empty():
		current_dir = free[ctx.rng.randi() % free.size()]
		if ctx.has("enemy_entity") and ctx.enemy_entity != null:
			ctx.enemy_entity.face(current_dir)
		return Vector2i.ZERO

	# 직진 확률 높임 (자연스러운 배회)
	if current_dir != Vector2i.ZERO and free.has(current_dir) and ctx.rng.randf() < 0.65:
		return current_dir
	current_dir = free[ctx.rng.randi() % free.size()]
	return current_dir
