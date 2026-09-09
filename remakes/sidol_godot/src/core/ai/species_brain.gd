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
	MovementPattern.Kind.PHASER,
]
## **AMBUSHER를 HOMING_KINDS에서 뺀 이유 (2026-09-09 실측).** 여기 들어 있으면 거리만
## 보고 경고를 띄운다 — 200틱 시뮬레이션에서 6칸 밖에 가만히 선 위장 상태인데도
## **200틱 내내 경고 표식이 떠 있었다.** 그러면 매복이 성립하지 않는다(플레이어가 미리
## 안다). 매복은 아래 phase 판정으로만 경고한다: 위장 중엔 조용하고 터질 때만 뜬다.
## 경고가 뜨는 거리(맨해튼). 접촉 판정(2칸 안팎)보다 넉넉해야 피할 시간이 생긴다.
const ALERT_RADIUS := 8
const PerceptionProbe := preload("res://src/core/ai/perception_probe.gd")
## PATROL — 순찰 중 플레이어를 알아채는 거리(맨해튼)와, 놓친 뒤 순찰로 돌아가기까지의 틱.
## 추적 전용 종(CHASE aggro 6)보다 좁게 잡는다: 순찰병은 "제 길을 도는" 것이 본업이고,
## 시야가 넓으면 결국 CHASE와 구별이 안 된다.
const PATROL_AGGRO := 5
const PATROL_HEARING := 2
const PATROL_LOST_TICKS := 6
## PULSE — 데이터의 radius는 피해 반경으로 적힌 값이라 그대로 쓰면 2칸이라 너무 좁다
## (몸이 2×2라 사실상 붙어야 반응한다). 접근 사정권은 그보다 넉넉해야 박자가 읽힌다.
const PULSE_REACH := 4


## 돌진 예비·잠복 같은 "곧 덤빈다" 단계이거나, 추적형이 사정거리에 들어오면 경고.
func is_alerted() -> bool:
	var phase: StringName = _state.get("phase", &"")
	# &"hiding"은 없다 — 위장 중에는 경고를 띄우지 않는다(그게 매복이다).
	# &"burst"는 넣는다 — 이미 달려드는 중이므로 피할 기회는 줘야 한다.
	if phase in [&"telegraph", &"dashing", &"hidden", &"chase", &"pulse", &"burst"]:
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
		MovementPattern.Kind.PATROL:
			return _decide_patrol(ctx)
		MovementPattern.Kind.PULSE:
			return _decide_pulse(ctx)
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


## AMBUSHER — 위장하고 서 있다가 사정권에 들어오면 **터지듯 달려든다.**
##
## 왜 고쳤나 (2026-09-09): 예전 구현은 두 분기가 **모두 `Vector2i.ZERO`**였다. 주석에는
## "공격 트리거(BattleController에서 처리)"라고 적혀 있었지만 그것을 받는 코드가 저장소
## 어디에도 없었다(전수 검색 결과 0곳). 그래서 rogue_vending은 플레이어가 제 발로
## 부딪히기 전까지 **영원히 서 있는 장식**이었다 — 매복이 아니라 가구였다.
##
## 매복의 재미는 "안전해 보이던 것이 갑자기 움직인다"이므로, 위장 중에는 경고 표식도
## 띄우지 않고(is_alerted가 hidden 단계를 안 본다) 사정권 진입 순간에만 터뜨린다.
func _decide_ambusher(ctx: Dictionary) -> Vector2i:
	var self_cell: Vector2i = ctx.self_cell
	var player_cell: Vector2i = ctx.player_cell
	if not _state.has("phase"):
		_state["phase"] = &"hiding"
		_state["burst"] = 0
		_state["cool"] = 0

	match _state["phase"]:
		&"hiding":
			if int(_state["cool"]) > 0:
				_state["cool"] = int(_state["cool"]) - 1
				return Vector2i.ZERO
			var range_cells := maxi(int(params.get("trigger_range", 3)), 1)
			if _distance(self_cell, player_cell) > range_cells:
				return Vector2i.ZERO
			# 벽 너머는 못 본다 — 옆방 사람에게 달려들면 매복이 아니라 투시다.
			var los: Callable = ctx.get("is_passable_cell", ctx.passable)
			if not PerceptionProbe.has_line_of_sight(self_cell, player_cell, los):
				return Vector2i.ZERO
			_state["phase"] = &"burst"
			_state["burst"] = maxi(int(params.get("burst_cells", 3)), 1)
			return Vector2i.ZERO  # 터지기 직전 한 틱 — 예고
		&"burst":
			_state["burst"] = int(_state["burst"]) - 1
			if int(_state["burst"]) <= 0:
				_state["phase"] = &"hiding"
				_state["cool"] = int(params.get("cooldown_ticks", 6))
			var toward := _dir_toward(self_cell, player_cell)
			if free_dirs(ctx, self_cell).has(toward):
				return toward
			return Vector2i.ZERO
	return Vector2i.ZERO


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


## PATROL — 스폰 자리 둘레를 도는 순찰. 플레이어를 **인지하면** 추적으로 바뀌고,
## 놓치면 순찰로 돌아온다.
##
## 왜 이렇게 만들었나 (2026-09-09): 이 패턴은 enum·NAME_TO_KIND·기본값·데이터(f3 iron_voc)에
## 전부 선언돼 있었는데 `decide()`에 분기가 없어 **wander로 조용히 떨어져 있었다.** 순찰의
## 재미는 "리듬이 예측 가능하다"는 것이다 — 언제 어디를 보는지 읽히면 몰래 지나가는
## 선택지가 생긴다. 그래서 경로를 무작위로 굴리지 않고 **막힐 때까지 직진 → 시계 방향 전환**
## 이라는 규칙 하나로 돈다(길찾기 없이 벽을 따라 도는 순찰선이 나온다).
func _decide_patrol(ctx: Dictionary) -> Vector2i:
	var self_cell: Vector2i = ctx.self_cell
	var player_cell: Vector2i = ctx.player_cell
	if not _state.has("anchor"):
		_state["anchor"] = self_cell
		_state["dir"] = Vector2i.RIGHT
		_state["leg"] = 0
		_state["phase"] = &"patrol"
		_state["lost"] = 0

	var facing: Vector2i = ctx.get("facing", Vector2i.DOWN)
	var seen := PerceptionProbe.can_perceive(
		self_cell,
		facing,
		player_cell,
		int(params.get("aggro_radius", PATROL_AGGRO)),
		PATROL_HEARING,
		ctx.get("is_passable_cell", ctx.passable)
	)
	if seen:
		_state["phase"] = &"chase"
		_state["lost"] = 0
	elif _state["phase"] == &"chase":
		# 놓쳐도 바로 포기하지 않는다 — 모퉁이를 돌자마자 멈춰 서면 추격이 싱겁다.
		_state["lost"] = int(_state["lost"]) + 1
		if int(_state["lost"]) > PATROL_LOST_TICKS:
			_state["phase"] = &"patrol"

	var free := free_dirs(ctx, self_cell)
	if _state["phase"] == &"chase":
		var toward := _dir_toward(self_cell, player_cell)
		if free.has(toward):
			return toward
		# 막히면 순찰선으로 흘려 보낸다(멈춰 서지 않는다).
	elif int(_state["lost"]) == 0 and _state["anchor"] != self_cell:
		pass

	if free.is_empty():
		return Vector2i.ZERO
	var route_length := maxi(int(params.get("route_length", 6)), 2)
	var dir: Vector2i = _state["dir"]
	_state["leg"] = int(_state["leg"]) + 1
	# 순찰 반경을 벗어났으면 앵커 쪽을 우선한다 — 층을 가로질러 흘러가지 않게.
	var anchor: Vector2i = _state["anchor"]
	var away := absi(self_cell.x - anchor.x) + absi(self_cell.y - anchor.y)
	if away > route_length * 2:
		var home := _dir_toward(self_cell, anchor)
		if free.has(home):
			_state["dir"] = home
			_state["leg"] = 0
			return home
	if int(_state["leg"]) >= route_length or not free.has(dir):
		# 시계 방향으로 한 번 꺾는다. 네 방향을 다 막혔으면 갈 수 있는 아무 쪽.
		for _turn in 4:
			dir = Vector2i(-dir.y, dir.x)
			if free.has(dir):
				break
		_state["leg"] = 0
	if not free.has(dir):
		dir = free[ctx.rng.randi() % free.size()]
	_state["dir"] = dir
	return dir


## PULSE — **박자를 가진 포탑.** 평소엔 한 칸도 안 움직이고, interval_ticks마다 한 번
## "펄스"를 친다. 펄스 직전 한 틱은 예고(telegraph)이고, 펄스가 터질 때 반경 안에
## 플레이어가 있으면 그쪽으로 **한 칸** 다가온다.
##
## 왜 이 모양인가 (2026-09-09): 이 패턴도 데이터(f4 o_ray)에 배정돼 있었지만 구현이 없어
## wander로 떨어져 있었다. 그리고 필드에는 **원거리 피해라는 기구가 없다**(접촉이 곧 전투다).
## 그래서 "반경 피해"를 억지로 새로 만들지 않고, 대신 **접근의 리듬**으로 옮겼다 —
## 쉬지 않고 쫓아오는 CHASE와 달리 멈춤·예고·한 걸음이 반복되므로 박자를 세어 피할 수 있다.
## 반경 밖으로 나가면 즉시 멈춘다: "그 자리는 위험하다"는 공간 학습이 이 패턴의 값이다.
func _decide_pulse(ctx: Dictionary) -> Vector2i:
	var self_cell: Vector2i = ctx.self_cell
	var player_cell: Vector2i = ctx.player_cell
	if not _state.has("tick"):
		_state["tick"] = int(params.get("interval_ticks", 6))
		_state["anchor"] = self_cell
		_state["phase"] = &"idle"

	var radius := int(params.get("radius", 2)) + PULSE_REACH
	var dist := _distance(self_cell, player_cell)
	if dist > radius:
		# 사정권 밖 — 박자를 처음으로 되돌리고 제자리를 지킨다.
		_state["tick"] = int(params.get("interval_ticks", 6))
		_state["phase"] = &"idle"
		var anchor: Vector2i = _state["anchor"]
		if self_cell != anchor:
			var back := _dir_toward(self_cell, anchor)
			if free_dirs(ctx, self_cell).has(back):
				return back
		return Vector2i.ZERO

	_state["tick"] = int(_state["tick"]) - 1
	if int(_state["tick"]) == 1:
		_state["phase"] = &"telegraph"  # 예고 — 경고 표식이 뜬다
		return Vector2i.ZERO
	if int(_state["tick"]) > 0:
		_state["phase"] = &"idle"
		return Vector2i.ZERO

	_state["tick"] = int(params.get("interval_ticks", 6))
	_state["phase"] = &"pulse"
	var toward := _dir_toward(self_cell, player_cell)
	if free_dirs(ctx, self_cell).has(toward):
		return toward
	return Vector2i.ZERO
