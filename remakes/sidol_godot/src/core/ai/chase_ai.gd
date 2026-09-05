class_name ChaseAI
extends AIBrain
## 플레이어 추적 — BFS 경로 탐색 + 시야각/청각 인지 + 포위 슬롯 + 공격 전조 멈칫.

const PerceptionProbe := preload("res://src/core/ai/perception_probe.gd")

var aggro_radius := 6
var hearing_radius := 2
var deaggro_radius := 12
var recompute_interval := 3
var lose_sight_ticks := 4

var _path_step := Vector2i.ZERO
var _recompute_tick := 0
var _chasing := false
var _lost_sight_count := 0
var _hesitating := false
var fallback_brain: AIBrain


func _init() -> void:
	fallback_brain = WanderAI.new()


func is_alerted() -> bool:
	return _chasing


func decide(ctx: Dictionary) -> Vector2i:
	var self_cell: Vector2i = ctx.self_cell
	var player_cell: Vector2i = ctx.player_cell
	var target_cell: Vector2i = ctx.get("target_cell", player_cell)
	var facing: Vector2i = ctx.get("facing", current_dir)
	var is_passable_cell: Callable = ctx.get("is_passable_cell", ctx.passable)
	var dist: int = absi(self_cell.x - player_cell.x) + absi(self_cell.y - player_cell.y)

	# 1. 시야각(전방 120도) 및 청각(2칸 이내) 인지 검사
	if not _chasing:
		if PerceptionProbe.can_perceive(
			self_cell, facing, player_cell, aggro_radius, hearing_radius, is_passable_cell
		):
			_chasing = true
			_lost_sight_count = 0
	else:
		if dist > deaggro_radius:
			_chasing = false
			_hesitating = false
		else:
			# 추적 중에는 시선 차폐(벽 뒤로 숨음)를 검사하여 일정 시간 놓치면 어그로 해제
			var has_los := PerceptionProbe.has_line_of_sight(
				self_cell, player_cell, is_passable_cell
			)
			if has_los:
				_lost_sight_count = 0
			else:
				_lost_sight_count += 1
				if _lost_sight_count >= lose_sight_ticks:
					_chasing = false
					_hesitating = false

	if not _chasing:
		_hesitating = false
		return fallback_brain.decide(ctx)

	# 2. 공격 전조 및 완급 조절(Hesitation): 플레이어 2칸 이내 진입 시 1틱 멈칫 + 위협 펄스
	if dist <= 2:
		if not _hesitating:
			_hesitating = true
			if ctx.has("enemy_entity") and ctx.enemy_entity != null:
				ctx.enemy_entity.trigger_threat_pulse()
			return Vector2i.ZERO
		else:
			_hesitating = false

	# 3. 목표 슬롯(Flanking Slot) 또는 플레이어 셀 선택
	var goal := player_cell
	if dist > 1 and target_cell != player_cell:
		goal = target_cell

	_recompute_tick -= 1
	if _recompute_tick <= 0 or _path_step == Vector2i.ZERO:
		_path_step = _bfs_first_step(self_cell, goal, ctx, 24)
		if _path_step == Vector2i.ZERO and goal != player_cell:
			_path_step = _bfs_first_step(self_cell, player_cell, ctx, 24)
		_recompute_tick = recompute_interval

	if _path_step != Vector2i.ZERO:
		var d: Vector2i = _path_step - self_cell
		var occupied: Dictionary = ctx.occupied
		if not occupied.has(self_cell + d):
			current_dir = d
			return d

	var free := free_dirs(ctx, self_cell)
	if free.is_empty():
		return Vector2i.ZERO
	free.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var da: int = absi((self_cell + a).x - goal.x) + absi((self_cell + a).y - goal.y)
			var db: int = absi((self_cell + b).x - goal.x) + absi((self_cell + b).y - goal.y)
			return da < db
	)
	current_dir = free[0]
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
