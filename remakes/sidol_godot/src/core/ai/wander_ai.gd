class_name WanderAI
extends AIBrain
## 배회 — 현재 방향을 유지하다 막히면 랜덤 전환.
## 원작 PATTERN 웨이포인트의 자연스러운 대체.

var dir_persistence := 3  # 같은 방향 유지 틱 수


func decide(ctx: Dictionary) -> Vector2i:
	var free := free_dirs(ctx, ctx.self_cell)
	if free.is_empty():
		current_dir = Vector2i.ZERO
		return Vector2i.ZERO

	move_cooldown -= 1
	if move_cooldown > 0 and current_dir != Vector2i.ZERO and free.has(current_dir):
		return current_dir

	move_cooldown = dir_persistence
	# 직진 확률 높임 (자연스러운 배회)
	if current_dir != Vector2i.ZERO and free.has(current_dir) and ctx.rng.randf() < 0.65:
		return current_dir
	return free[ctx.rng.randi() % free.size()]
