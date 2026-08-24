class_name SpeciesBrain
extends AIBrain
## 종별 특화 패턴 브레인 — monsters.json의 pattern 필드로 동작 결정.
## 각 패턴은 텔레그래프(예고 동작)를 가져 플레이어가 학습 가능하게 한다.
## docs/03_plan/03_content_backlog.md §1 및 ASSET_AGENT_BRIEF §3.6 참조.

var pattern_kind: int = MovementPattern.Kind.WANDER
var params: Dictionary = {}
var _state := {}   # 인스턴스별 임시 상태


func configure(p_kind: int, p_params: Dictionary = {}) -> void:
	pattern_kind = p_kind
	var defaults := MovementPattern.get_defaults(p_kind)
	for key in defaults:
		if not params.has(key):
			params[key] = defaults[key]
	for key in p_params:
		params[key] = p_params[key]


func decide(ctx: Dictionary) -> Vector2i:
	match pattern_kind:
		MovementPattern.Kind.DASH:
			return _decide_dash(ctx)
		MovementPattern.Kind.BURROW:
			return _decide_burrow(ctx)
		MovementPattern.Kind.ZIGZAG:
			return _decide_zigzag(ctx)
		MovementPattern.Kind.TELEPORT:
			return _decide_teleport(ctx)
		MovementPattern.Kind.AMBUSHER:
			return _decide_ambusher(ctx)
		MovementPattern.Kind.PHASER:
			return _decide_phaser(ctx)
		_:
			return fallback_brain.decide(ctx)


## DASH — N틱 정지(빨강 깜빡임 텔레그래프) → 지정 셀 수 돌진 → 쿨다운
func _decide_dash(ctx: Dictionary) -> Vector2i:
	var self_cell: Vector2i = ctx.self_cell
	var player_cell: Vector2i = ctx.player_cell
	if not _state.has("phase"):
		_state["phase"] = &"idle"
		_state["tick"] = 0

	match _state["phase"]:
		&"idle":
			var dist: int = absi(self_cell.x - player_cell.x) + absi(self_cell.y - player_cell.y)
			if dist <= 4:
				_state["phase"] = &"telegraph"
				_state["tick"] = int(params["pause_ticks"])
				_state["dash_dir"] = _dir_toward(self_cell, player_cell)
			return fallback_brain.decide(ctx)
		&"telegraph":
			_state["tick"] -= 1
			if _state["tick"] <= 0:
				_state["phase"] = &"dashing"
				_state["remaining"] = int(params["dash_cells"])
			return Vector2i.ZERO   # 정지 = 텔레그래프
		&"dashing":
			var d: Vector2i = _state["dash_dir"]
			var free := free_dirs(ctx, self_cell)
			if free.has(d):
				_state["remaining"] -= 1
				if _state["remaining"] <= 0:
					_state["phase"] = &"idle"
					_state["tick"] = int(params["cooldown_ticks"])
				return d
			else:
				_state["phase"] = &"idle"
				return Vector2i.ZERO
		&"cooldown_tick":
			_state["tick"] -= 1
			if _state["tick"] <= 0:
				_state["phase"] = &"idle"
			return Vector2i.ZERO
	return Vector2i.ZERO


## BURROW — 사라짐(먼지 파티클) → 플레이어 인접 셀에서 출현
func _decide_burrow(ctx: Dictionary) -> Vector2i:
	var self_cell: Vector2i = ctx.self_cell
	var player_cell: Vector2i = ctx.player_cell
	if not _state.has("phase"):
		_state["phase"] = &"surface"

	match _state["phase"]:
		&"surface":
			_state["tick"] = (_state.get("tick", 0) as int) + 1
			if _state["tick"] >= int(params.get("hidden_ticks", 8)):
				# 플레이어 인접 셀로 점프
				var candidates: Array[Vector2i] = []
				for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					var target := player_cell + d
					if ctx.passable.call(target) and not ctx.occupied.has(target):
						candidates.append(target)
				if not candidates.is_empty():
					_state["phase"] = &"hidden"
					_state["emerge_at"] = candidates[ctx.rng.randi() % candidates.size()]
					return _state["emerge_at"] - self_cell   # 순간이동
				return Vector2i.ZERO
			return fallback_brain.decide(ctx)
		&"hidden":
			_state["phase"] = &"surface"
			_state["tick"] = 0
			return Vector2i.ZERO
	return Vector2i.ZERO


## ZIGZAG — 좌우 급격 교대 + 직진 버스트
func _decide_zigzag(ctx: Dictionary) -> Vector2i:
	var self_cell: Vector2i = ctx.self_cell
	var player_cell: Vector2i = ctx.player_cell
	if not _state.has("side"):
		_state["side"] = 1
	_state["side"] *= -1 if ctx.rng.randf() < 0.4 else 1
	var to_player := player_cell - self_cell
	var primary := Vector2i(sign(to_player.x), 0) if absi(to_player.x) > absi(to_player.y) else Vector2i(0, sign(to_player.y))
	var perpendicular := Vector2i(-primary.y * _state["side"], primary.x * _state["side"])
	var free := free_dirs(ctx, self_cell)
	if free.has(perpendicular):
		return perpendicular
	elif free.has(primary):
		return primary
	elif not free.is_empty():
		return free[0]
	return Vector2i.ZERO


## TELEPORT — N틱마다 반경 내 랜덤 유효 셀로 점프
func _decide_teleport(ctx: Dictionary) -> Vector2i:
	var self_cell: Vector2i = ctx.self_cell
	if not _state.has("tick"):
		_state["tick"] = int(params.get("interval_ticks", 5))
	_state["tick"] -= 1
	if _state["tick"] <= 0:
		_state["tick"] = int(params.get("interval_ticks", 5))
		var radius := int(params.get("jump_radius", 4))
		var player_cell: Vector2i = ctx.player_cell
		for attempt in range(10):
			var dx := ctx.rng.randi_range(-radius, radius)
			var dy := ctx.rng.randi_range(-radius, radius)
			var target := Vector2i(player_cell.x + dx, player_cell.y + dy)
			if ctx.passable.call(target) and target != self_cell:
				return target - self_cell   # 순간이동 벡터
	return Vector2i.ZERO


## AMBUSHER — 정지 위장 → 플레이어 인접 시 폭발적 공격
func _decide_ambusher(ctx: Dictionary) -> Vector2i:
	var self_cell: Vector2i = ctx.self_cell
	var player_cell: Vector2i = ctx.player_cell
	if self_cell.manhattan_distance_to(player_cell) <= 1:
		return Vector2i.ZERO   # 공격 트리거 (BattleController에서 처리)
	return Vector2i.ZERO   # 위장 상태 — 이동하지 않음


## PHASER — 벽 통과, 느린 직진
func _decide_phaser(ctx: Dictionary) -> Vector2i:
	var self_cell: Vector2i = ctx.self_cell
	var player_cell: Vector2i = ctx.player_cell
	var to_p := player_cell - self_cell
	var d := Vector2i.ZERO
	if absi(to_p.x) > absi(to_p.y):
		d = Vector2i(signi(to_p.x), 0)
	else:
		d = Vector2i(0, signi(to_p.y))
	return d


func _dir_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var diff := to - from
	if absi(diff.x) > absi(diff.y):
		return Vector2i(signi(diff.x), 0)
	return Vector2i(0, signi(diff.y))
