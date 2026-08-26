class_name SpeciesBrain
extends AIBrain
## 종별 특화 패턴 브레인 — monsters.json의 pattern 필드로 동작 결정.
## 각 패턴은 텔레그래프(예고 동작)를 가져 플레이어가 학습 가능하게 한다.
## docs/03_plan/03_content_backlog.md §1 및 ASSET_AGENT_BRIEF §3.6 참조.

var pattern_kind: int = MovementPattern.Kind.WANDER
var params: Dictionary = {}
var _state := {}  # 인스턴스별 임시 상태
var _last_dist := 9999  # 마지막 decide 시점의 플레이어 거리 — 경고 표식 판정용
var fallback_brain: AIBrain


func _init() -> void:
	fallback_brain = WanderAI.new()


func configure(p_kind: int, p_params: Dictionary = {}) -> void:
	pattern_kind = p_kind
	var defaults := MovementPattern.get_defaults(p_kind)
	for key in defaults:
		if not params.has(key):
			params[key] = defaults[key]
	for key in p_params:
		params[key] = p_params[key]


## 플레이어를 향해 오는 패턴들 — 이 종들은 가까워지면 경고를 띄운다.
## WANDER/PATROL/PULSE는 플레이어를 쫓지 않으므로 제외(거짓 경고 방지).
const HOMING_KINDS := [
	MovementPattern.Kind.CHASE,
	MovementPattern.Kind.DASH,
	MovementPattern.Kind.BURROW,
	MovementPattern.Kind.ZIGZAG,
	MovementPattern.Kind.TELEPORT,
	MovementPattern.Kind.AMBUSHER,
	MovementPattern.Kind.PHASER,
]
## 경고가 뜨는 거리(맨해튼). 접촉 판정(2칸 안팎)보다 넉넉해야 피할 시간이 생긴다.
const ALERT_RADIUS := 8


## 돌진 예비·잠복 같은 "곧 덤빈다" 단계이거나, 추적형이 사정거리에 들어오면 경고.
func is_alerted() -> bool:
	var phase: StringName = _state.get("phase", &"")
	if phase in [&"telegraph", &"dashing", &"hidden"]:
		return true
	if HOMING_KINDS.has(pattern_kind):
		return _last_dist <= int(params.get("alert_radius", ALERT_RADIUS))
	return fallback_brain != null and fallback_brain.is_alerted()


func decide(ctx: Dictionary) -> Vector2i:
	_last_dist = _distance(ctx.self_cell, ctx.player_cell)
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
			return Vector2i.ZERO  # 정지 = 텔레그래프
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

	# 맵 반대편에서도 잠복이 돌면 플레이어가 본 적 없는 몬스터가 코앞에 튀어나온다 —
	# 어그로 반경 안에서만 잠복 사이클을 돌린다.
	if _distance(self_cell, player_cell) > int(params.get("engage_radius", 12)):
		_state["phase"] = &"surface"
		_state["tick"] = 0
		return fallback_brain.decide(ctx)

	match _state["phase"]:
		&"surface":
			_state["tick"] = (_state.get("tick", 0) as int) + 1
			if _state["tick"] >= int(params.get("hidden_ticks", 8)):
				# 플레이어 주변 emerge_radius 링에서 출현 — 바로 옆에 뜨면
				# 회피 불가 전투가 된다. 한 박자 볼 거리를 남긴다.
				var target := _pick_emerge(ctx, player_cell, int(params.get("emerge_radius", 3)))
				if target.x >= 0:
					_state["phase"] = &"hidden"
					_state["emerge_at"] = target
					return target - self_cell  # 순간이동
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
	var primary := (
		Vector2i(sign(to_player.x), 0)
		if absi(to_player.x) > absi(to_player.y)
		else Vector2i(0, sign(to_player.y))
	)
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
		if _distance(self_cell, player_cell) > int(params.get("engage_radius", 12)):
			return fallback_brain.decide(ctx)
		for attempt in range(10):
			var dx: int = ctx.rng.randi_range(-radius, radius)
			var dy: int = ctx.rng.randi_range(-radius, radius)
			var target := Vector2i(player_cell.x + dx, player_cell.y + dy)
			# 플레이어 몸에 맞닿는 자리는 제외 — 착지 즉시 전투는 회피 수단이 없다.
			if Placement.bodies_touch(player_cell, target):
				continue
			if ctx.passable.call(target) and target != self_cell:
				return target - self_cell  # 순간이동 벡터
	return Vector2i.ZERO


## AMBUSHER — 정지 위장 → 플레이어 인접 시 폭발적 공격
func _decide_ambusher(ctx: Dictionary) -> Vector2i:
	var self_cell: Vector2i = ctx.self_cell
	var player_cell: Vector2i = ctx.player_cell
	if absi(self_cell.x - player_cell.x) + absi(self_cell.y - player_cell.y) <= 1:
		return Vector2i.ZERO  # 공격 트리거 (BattleController에서 처리)
	return Vector2i.ZERO  # 위장 상태 — 이동하지 않음


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


## 플레이어 주변 radius 링에서 설 수 있는 자리 하나. 없으면 (-1,-1).
func _pick_emerge(ctx: Dictionary, player_cell: Vector2i, radius: int) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for c: Vector2i in Placement.ring(player_cell, maxi(radius, Placement.BODY.x + 1)):
		if Placement.bodies_touch(player_cell, c):
			continue
		if ctx.passable.call(c):
			candidates.append(c)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[ctx.rng.randi() % candidates.size()]


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _dir_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var diff := to - from
	if absi(diff.x) > absi(diff.y):
		return Vector2i(signi(diff.x), 0)
	return Vector2i(0, signi(diff.y))
