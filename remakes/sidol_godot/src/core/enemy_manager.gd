class_name EnemyManager
extends Node
## 층별 몬스터 스폰·AI 틱·점유 레지스트리·인카운터.
## EnemyEntity는 데이터만, 이동 판정과 AI는 여기서 수행(순환 참조 방지).
##
## 몬스터도 플레이어와 같은 2×2 몸을 쓴다 — 그리는 크기와 막는 크기를 일치시킨다.
## 이동은 GridMover 보간을 거치므로 한 걸음이 STEP_TIME 동안 이어진다(순간이동 금지).

static var rng := RandomNumberGenerator.new()

## 스폰 시 플레이어와 띄울 최소 거리(셀, 체비셰프) — 층 진입·전투 복귀 직후
## 눈앞에서 튀어나와 즉시 재전투로 끌려가는 사고를 막는다.
const SAFE_SPAWN_DIST := 10
const SPAWN_TRIES := 12
## 워프 패턴이 한 번에 넘어갈 수 있는 최대 거리(셀). 브레인이 잘못 계산해도
## 맵 반대편에서 순간이동해 오는 사고를 막는 안전망.
const MAX_WARP := 16

var enemies: Array[EnemyEntity] = []
var _occupied := {}  # Vector2i(몸 셀) -> EnemyEntity
var _brains := {}  # entity -> AIBrain
var _act_accum := {}  # entity -> float
var _phasing := {}  # entity -> bool (벽 통과 종)
var _runtime: MapRuntime


func spawn_for_floor(floor_idx: int, rt: MapRuntime, parent: Node2D, player_cell: Vector2i) -> void:
	despawn_all()
	_runtime = rt
	# 밀도 설정(Q6) 반영 — NONE이면 0마리, 즉 몬스터 없는 탐험 모드.
	var count := SettingsManager.encounter_count(
		int(Database.encounter_table(floor_idx).get("count", 0))
	)
	var species_list := Database.encounter_species(floor_idx)
	if species_list.is_empty() or count == 0:
		return

	rng.randomize()
	var spots := _collect_spawn_anchors(rt, player_cell)
	if spots.is_empty():
		push_warning("EnemyManager: f%d 스폰 가능 앵커 없음" % floor_idx)
		return

	for i in count:
		var cell := _pick_free_anchor(spots)
		if cell.x < 0:
			break
		var spec: Dictionary = species_list[rng.randi() % species_list.size()]
		var e := EnemyEntity.new()
		parent.add_child(e)
		e.setup(StringName(str(spec["id"])), cell, Color(1, 1, 1))
		var params: Dictionary = spec.get("params", {})
		var kind := MovementPattern.kind_from_name(str(spec["pattern"]))
		e.act_interval = MovementPattern.act_interval(kind, params)
		# 몬스터도 맵 통행 규칙을 탄다. 구판은 점유 사전만 봐서 벽과 맵 밖을 자유로이 통과했다.
		# PHASER(벽 통과 설계 종)만 지형 검사를 건너뛴다.
		var phases := MovementPattern.ignores_walls(kind)
		e.mover.is_passable = func(c: Vector2i) -> bool: return _cell_free_for(e, c, phases)
		enemies.append(e)
		_brains[e] = MovementPattern.make_brain(str(spec["pattern"]), params)
		_phasing[e] = phases
		_act_accum[e] = 0.0
		_occupy(e, cell)


func despawn_all() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	_occupied.clear()
	_brains.clear()
	_act_accum.clear()
	_phasing.clear()


## 플레이어 몸과 몬스터 몸이 겹치거나 변을 맞대면 전투. 판정은 Placement 단일 출처.
func get_contact(player_cell: Vector2i) -> String:
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if Placement.bodies_touch(player_cell, e.mover.grid_pos):
			return String(e.species_id)
	return ""


## 종별 행동 주기마다 한 걸음. 구판은 매 물리 프레임 순간이동해 초당 60칸을 갔다.
func tick(player_cell: Vector2i, delta: float) -> void:
	for e in enemies:
		if not is_instance_valid(e) or e.mover.moving:
			continue
		var accum := float(_act_accum.get(e, 0.0)) + delta
		if accum < e.act_interval:
			_act_accum[e] = accum
			continue
		_act_accum[e] = 0.0
		var brain: AIBrain = _brains.get(e)
		if brain == null:
			continue
		var phasing := bool(_phasing.get(e, false))
		var anchor_free := func(c: Vector2i) -> bool: return _anchor_free_for(e, c, phasing)
		var ctx := {
			"self_cell": e.mover.grid_pos,
			"player_cell": player_cell,
			"passable": anchor_free,
			"occupied": {},  # 점유는 passable 안에서 이미 반영된다
			"rng": rng,
		}
		var dir: Vector2i = brain.decide(ctx)
		e.set_alerted(brain.is_alerted())
		if dir == Vector2i.ZERO:
			continue
		_apply_move(e, dir)


## 브레인이 낸 방향을 적용한다. BURROW/TELEPORT는 한 칸이 아니라
## 목적지까지의 벡터를 돌려주므로(설계된 순간이동) 걸음이 아니라 워프로 처리한다.
func _apply_move(e: EnemyEntity, dir: Vector2i) -> void:
	var from := e.mover.grid_pos
	if absi(dir.x) + absi(dir.y) == 1:
		if not e.mover.try_step(dir):
			return
		_release(e, from)
		_occupy(e, e.mover.grid_pos)
		e.face(dir)
		return
	var target := from + dir
	if absi(dir.x) + absi(dir.y) > MAX_WARP:
		push_warning("EnemyManager: 워프 거리 초과 %s %s -> %s" % [e.species_id, from, target])
		return
	if not _anchor_free_for(e, target, bool(_phasing.get(e, false))):
		return
	_release(e, from)
	e.mover.teleport(target)
	_occupy(e, target)
	e.face(dir)


func get_occupied() -> Dictionary:
	return _occupied


## 몸 셀 단위 점유 — 한 칸만 잡으면 2×2 몬스터끼리 반쯤 겹친다.
func _occupy(e: EnemyEntity, anchor: Vector2i) -> void:
	for c in Placement.body_cells(anchor):
		_occupied[c] = e


func _release(e: EnemyEntity, anchor: Vector2i) -> void:
	for c in Placement.body_cells(anchor):
		if _occupied.get(c) == e:
			_occupied.erase(c)


## 한 셀이 이 몬스터에게 비어 있는가 — 맵 통행 + 남의 몸 아님.
## phasing 종은 지형을 무시하되 맵 경계와 다른 몬스터는 지킨다.
func _cell_free_for(e: EnemyEntity, cell: Vector2i, phasing: bool = false) -> bool:
	if _runtime == null:
		return false
	if phasing:
		if not _runtime.definition.in_bounds(cell):
			return false
	elif not _runtime.is_passable(cell):
		return false
	var owner: Variant = _occupied.get(cell)
	return owner == null or owner == e


## AI 탐색용 — 앵커에 몸이 통째로 들어가는가.
func _anchor_free_for(e: EnemyEntity, anchor: Vector2i, phasing: bool = false) -> bool:
	for c in Placement.body_cells(anchor):
		if not _cell_free_for(e, c, phasing):
			return false
	return true


## 몸이 들어가고 플레이어에게서 충분히 떨어진 앵커만 후보로 모은다.
func _collect_spawn_anchors(rt: MapRuntime, player_cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in rt.definition.height - 1:
		for x in rt.definition.width - 1:
			var a := Vector2i(x, y)
			var d := a - player_cell
			if maxi(absi(d.x), absi(d.y)) < SAFE_SPAWN_DIST:
				continue
			if Placement.body_fits(rt, a):
				out.append(a)
	return out


func _pick_free_anchor(spots: Array[Vector2i]) -> Vector2i:
	for _try in SPAWN_TRIES:
		var a: Vector2i = spots[rng.randi() % spots.size()]
		var clear := true
		for c in Placement.body_cells(a):
			if _occupied.has(c):
				clear = false
				break
		if clear:
			return a
	return Vector2i(-1, -1)
