class_name ChaseAI
extends AIBrain
## 플레이어 추적 — BFS 경로 탐색 + 어그로 반경 + 리시(탈출 거리).

var aggro_radius := 6
var deaggro_radius := 12
var recompute_interval := 3

var _path_step := Vector2i.ZERO
var _recompute_tick := 0
var _chasing := false
var fallback_brain: AIBrain


func _init() -> void:
	fallback_brain = WanderAI.new()


func is_alerted() -> bool:
	return _chasing


func decide(ctx: Dictionary) -> Vector2i:
	var self_cell: Vector2i = ctx.self_cell
	var player_cell: Vector2i = ctx.player_cell
	var dist: int = absi(self_cell.x - player_cell.x) + absi(self_cell.y - player_cell.y)

	if dist <= aggro_radius:
		_chasing = true
	elif dist > deaggro_radius:
		_chasing = false

	if not _chasing:
		return fallback_brain.decide(ctx)

	_recompute_tick -= 1
	if _recompute_tick <= 0 or _path_step == Vector2i.ZERO:
		_path_step = _bfs_first_step(self_cell, player_cell, ctx, 24)
		_recompute_tick = recompute_interval

	if _path_step != Vector2i.ZERO:
		var d: Vector2i = _path_step - self_cell
		var occupied: Dictionary = ctx.occupied
		if not occupied.has(self_cell + d):
			return d

	var free := free_dirs(ctx, self_cell)
	if free.is_empty():
		return Vector2i.ZERO
	free.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var da: int = (
				absi((self_cell + a).x - player_cell.x) + absi((self_cell + a).y - player_cell.y)
			)
			var db: int = (
				absi((self_cell + b).x - player_cell.x) + absi((self_cell + b).y - player_cell.y)
			)
			return da < db
	)
	return free[0]


static func _key(c: Vector2i) -> String:
	return "%d:%d" % [c.x, c.y]


func _bfs_first_step(start: Vector2i, goal: Vector2i, ctx: Dictionary, max_depth: int) -> Vector2i:
	if start == goal:
		return Vector2i.ZERO
	var passable: Callable = ctx.passable
	var occupied: Dictionary = ctx.occupied
	var parent := {}
	parent[_key(start)] = ""
	var frontier: Array[Vector2i] = [start]
	var depth := 0
	while not frontier.is_empty() and depth < max_depth:
		var next: Array[Vector2i] = []
		for c in frontier:
			for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var nc := c + d
				var nk := _key(nc)
				if parent.has(nk):
					continue
				if not passable.call(nc):
					continue
				if occupied.has(nc):
					continue
				parent[nk] = _key(c)
				if nc == goal:
					return _reconstruct(parent, nk, start)
				next.append(nc)
		frontier = next
		depth += 1
	return Vector2i.ZERO


func _reconstruct(parent: Dictionary, goal_key: String, start: Vector2i) -> Vector2i:
	var cur := goal_key
	var start_key := _key(start)
	while parent.get(cur, "") != start_key and parent[cur] != "":
		cur = parent[cur]
	var parts := cur.split(":")
	return Vector2i(int(parts[0]), int(parts[1]))
