class_name EnemyManager
extends Node
## 층별 몬스터 스폰·AI 틱·점유 레지스트리·인카운터.
## EnemyEntity는 데이터만, 이동 판정과 AI는 여기서 수행(순환 참조 방지).
##
## 몬스터도 플레이어와 같은 2×2 몸을 쓴다 — 그리는 크기와 막는 크기를 일치시킨다.
## 이동은 GridMover 보간을 거치므로 한 걸음이 STEP_TIME 동안 이어진다(순간이동 금지).

## 개체 하나가 세상에 선 직후. 필드가 층 조명을 붙이는 데 쓴다 —
## 여기 없으면 리스폰된 놈이 어두운 층에서 빛 없이 태어난다.
## 조명을 여기서 직접 달지 않는 이유는 순환 참조와 관심사 분리다(이 클래스는 판정만).
signal enemy_spawned(e: EnemyEntity)

static var rng := RandomNumberGenerator.new()

## 스폰 시 플레이어와 띄울 최소 거리(셀, 체비셰프) — 층 진입·전투 복귀 직후
## 눈앞에서 튀어나와 즉시 재전투로 끌려가는 사고를 막는다.
const SAFE_SPAWN_DIST := 10
const SPAWN_TRIES := 12
## 워프 패턴이 한 번에 넘어갈 수 있는 최대 거리(셀). 브레인이 잘못 계산해도
## 맵 반대편에서 순간이동해 오는 사고를 막는 안전망.
const MAX_WARP := 16
## 리스폰이 서는 최소 거리 — 스폰보다 멀다. **화면 밖에서 차오르게** 하려는 것이다.
## 눈앞에서 솟아나면 "치운 길"이라는 감각이 그 자리에서 깨진다.
const RESPAWN_DIST := 16
## 근접 어그로 반경(맨해튼, 앵커 기준) — 특수 패턴·보스가 아니면 이 안에 들어오면
## 탐지 여부와 무관하게 달려든다. F1 몹에 chase가 없어 "앞에 와도 가만히" 보이던 자리.
const PROXIMITY_AGGRO := 2
## 한 마리가 다시 차오르는 데 걸리는 시간(초). monsters.json의 층별
## `respawn_seconds`가 있으면 그쪽이 이긴다.
##
## **왜 즉시도 영구도 아닌가.** 즉시 되살아나면 잡은 보람이 사라지고, 영영 안
## 돌아오면 층이 텅 비어 긴장이 사라진다. 그 사이를 시간으로 메운다 — 맵 한쪽
## 끝에서 반대편까지가 대략 30초(200칸 × 0.16초)이니, 한 번 왕복하는 동안
## 한두 마리가 돌아오는 셈이다.
const RESPAWN_SECONDS := 45.0
## 도달 판정 기준점을 못 세웠을 때 나선으로 찾아보는 반경(셀).
const SEED_SEARCH_RADIUS := 40

var enemies: Array[EnemyEntity] = []
var _occupied := {}  # Vector2i(몸 셀) -> EnemyEntity
var _brains := {}  # entity -> AIBrain
var _act_accum := {}  # entity -> float
var _phasing := {}  # entity -> bool (벽 통과 종)
var _entry := {}  # entity -> 명단 항목(Dictionary) — 잡히면 명단에서 뺄 때 쓴다
var _runtime: MapRuntime
var _parent: Node2D
var _floor := -1
var _cap := 0
var _respawn_seconds := RESPAWN_SECONDS
var _respawn_accum := 0.0
## 이 층의 고정 NPC·배회 워커 **앵커** — 스폰에서 "NPC가 사는 방"을 빼는 데 쓴다.
## 필드가 액터를 먼저 세우고 넘겨준다(scenes/field.gd). 비어 있으면 방 배제를 건너뛴다.
var _actor_anchors: Array[Vector2i] = []


func spawn_for_floor(
	floor_idx: int,
	rt: MapRuntime,
	parent: Node2D,
	player_cell: Vector2i,
	actor_anchors: Array[Vector2i] = []
) -> void:
	despawn_all()
	_actor_anchors = actor_anchors
	_runtime = rt
	_parent = parent
	_floor = floor_idx
	_respawn_accum = 0.0
	var table := Database.encounter_table(floor_idx)
	# 밀도 설정(Q6) 반영 — NONE이면 0마리, 즉 몬스터 없는 탐험 모드.
	_cap = SettingsManager.encounter_count(int(table.get("count", 0)))
	_respawn_seconds = float(table.get("respawn_seconds", RESPAWN_SECONDS))
	var species_list := Database.encounter_species(floor_idx)
	if species_list.is_empty() or _cap == 0:
		GameState.field_roster.erase(floor_idx)
		return

	rng.randomize()
	# **명단이 이미 있으면 그것을 되세운다.** 전투를 다녀오는 것은 씬 전환이라
	# 여기가 다시 불리는데, 그때마다 새로 뽑으면 잡은 놈이 되살아나고 자리도 바뀐다.
	var roster: Array = GameState.field_roster.get(floor_idx, [])
	if roster.is_empty():
		roster = _roll_roster(rt, player_cell, species_list, _cap)
		GameState.field_roster[floor_idx] = roster
	_keep_landing_clear(rt, player_cell, roster)
	for entry: Dictionary in roster:
		_make_enemy(entry)


## **도착하자마자 전투는 없다.** 명단을 되세우면 몬스터는 지난번에 서 있던
## 자리에 그대로 돌아오는데, 그게 계단 앞이면 내려서는 순간 붙는다. 착지점
## 근처에 있던 놈만 먼 자리로 옮긴다 — 층은 그대로 두고 첫 걸음만 지켜 준다.
func _keep_landing_clear(rt: MapRuntime, player_cell: Vector2i, roster: Array) -> void:
	var spots: Array[Vector2i] = []
	var taken := {}
	for entry: Dictionary in roster:
		var cell: Vector2i = entry["cell"]
		var d := cell - player_cell
		if maxi(absi(d.x), absi(d.y)) >= SAFE_SPAWN_DIST:
			for c in Placement.body_cells(cell):
				taken[c] = true
			continue
		if spots.is_empty():
			spots = _collect_spawn_anchors(rt, player_cell, SAFE_SPAWN_DIST)
			if spots.is_empty():
				return
		var moved := _pick_free_anchor(spots, taken)
		if moved.x < 0:
			continue
		entry["cell"] = moved
		for c in Placement.body_cells(moved):
			taken[c] = true


## 새 명단을 뽑는다 — 그 층에 처음 들어섰을 때 한 번.
func _roll_roster(rt: MapRuntime, player_cell: Vector2i, species_list: Array, count: int) -> Array:
	var out: Array = []
	var spots := _collect_spawn_anchors(rt, player_cell, SAFE_SPAWN_DIST)
	if spots.is_empty():
		push_warning("EnemyManager: f%d 스폰 가능 앵커 없음" % _floor)
		return out
	var taken := {}
	for _i in count:
		var cell := _pick_free_anchor(spots, taken)
		if cell.x < 0:
			break
		for c in Placement.body_cells(cell):
			taken[c] = true
		var spec: Dictionary = species_list[rng.randi() % species_list.size()]
		(
			out
			. append(
				{
					"id": str(spec["id"]),
					"pattern": str(spec["pattern"]),
					"params": spec.get("params", {}),
					"cell": cell,
				}
			)
		)
	return out


## 명단 항목 하나를 실제 개체로 세운다.
func _make_enemy(entry: Dictionary) -> void:
	if _parent == null or not _parent.is_inside_tree():
		return
	var cell: Vector2i = entry["cell"]
	var e := EnemyEntity.new()
	_parent.add_child(e)
	e.setup(StringName(str(entry["id"])), cell, Color(1, 1, 1))
	var params: Dictionary = entry.get("params", {})
	var kind := MovementPattern.kind_from_name(str(entry["pattern"]))
	e.act_interval = MovementPattern.act_interval(kind, params)
	# 몬스터도 맵 통행 규칙을 탄다. 구판은 점유 사전만 봐서 벽과 맵 밖을 자유로이 통과했다.
	# PHASER(벽 통과 설계 종)만 지형 검사를 건너뛴다.
	var phases := MovementPattern.ignores_walls(kind)
	e.mover.is_passable = func(c: Vector2i) -> bool: return _cell_free_for(e, c, phases)
	enemies.append(e)
	_brains[e] = MovementPattern.make_brain(str(entry["pattern"]), params)
	_phasing[e] = phases
	_act_accum[e] = 0.0
	_entry[e] = entry
	_occupy(e, cell)
	enemy_spawned.emit(e)


## 이 개체를 세상에서 지운다 — **명단에서도 뺀다.** 전투가 붙은 개체에 쓴다:
## 이겼으면 잡은 것이고, 도망쳤어도 그 자리에 그대로 서 있으면 도망이 아니다.
func remove_entity(e: EnemyEntity) -> void:
	var entry: Variant = _entry.get(e)
	if entry != null:
		var roster: Array = GameState.field_roster.get(_floor, [])
		roster.erase(entry)
	if is_instance_valid(e):
		_release(e, e.mover.grid_pos)
		e.queue_free()
	enemies.erase(e)
	_brains.erase(e)
	_act_accum.erase(e)
	_phasing.erase(e)
	_entry.erase(e)


func despawn_all() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	_occupied.clear()
	_brains.clear()
	_act_accum.clear()
	_phasing.clear()
	_entry.clear()


## 플레이어 몸과 몬스터 몸이 겹치거나 변을 맞대면 전투. 판정은 Placement 단일 출처.
## **개체를 돌려준다** — 부르는 쪽이 그 개체를 명단에서 뺄 수 있어야 한다.
func contact_entity(player_cell: Vector2i) -> EnemyEntity:
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if Placement.bodies_touch(player_cell, e.mover.grid_pos):
			return e
	return null


## 종별 행동 주기마다 한 걸음. 구판은 매 물리 프레임 순간이동해 초당 60칸을 갔다.
func tick(player_cell: Vector2i, delta: float) -> void:
	_respawn_tick(player_cell, delta)

	# 다중 추적 시 플랭킹(Flanking) 슬롯 계산: 단일 행렬(Conga line)을 방지하고 좌우/배후로 포위
	var alerted_chasers: Array[EnemyEntity] = []
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var b: AIBrain = _brains.get(e)
		if b != null and b.is_alerted():
			alerted_chasers.append(e)

	var flank_targets: Dictionary = {}
	if alerted_chasers.size() >= 2:
		alerted_chasers.sort_custom(
			func(a: EnemyEntity, b: EnemyEntity) -> bool:
				var da := (
					absi(a.mover.grid_pos.x - player_cell.x)
					+ absi(a.mover.grid_pos.y - player_cell.y)
				)
				var db := (
					absi(b.mover.grid_pos.x - player_cell.x)
					+ absi(b.mover.grid_pos.y - player_cell.y)
				)
				return da < db
		)
		var slots: Array[Vector2i] = [
			player_cell + Vector2i(-2, 0),
			player_cell + Vector2i(2, 0),
			player_cell + Vector2i(0, -2),
			player_cell + Vector2i(0, 2),
		]
		for i in range(1, alerted_chasers.size()):
			var chaser: EnemyEntity = alerted_chasers[i]
			var slot_cand: Vector2i = slots[(i - 1) % slots.size()]
			if _runtime != null and _runtime.is_passable(slot_cand):
				flank_targets[chaser] = slot_cand
			else:
				flank_targets[chaser] = player_cell

	for e in enemies:
		if not is_instance_valid(e) or e.mover.moving:
			continue
		var accum := float(_act_accum.get(e, 0.0)) + delta
		if accum < e.act_interval:
			_act_accum[e] = accum
			continue
		_act_accum[e] = 0.0
		# 근접 어그로가 먼저 — 옆에 와놓고 배회만 하면 "가만히" 보인다.
		if _try_proximity_lunge(e, player_cell):
			continue
		var brain: AIBrain = _brains.get(e)
		if brain == null:
			continue
		var phasing := bool(_phasing.get(e, false))
		var anchor_free := func(c: Vector2i) -> bool: return _anchor_free_for(e, c, phasing)
		var is_passable_cell := func(c: Vector2i) -> bool:
			return phasing or (_runtime != null and _runtime.is_passable(c))
		var assigned_target: Vector2i = flank_targets.get(e, player_cell)
		var ctx := {
			"self_cell": e.mover.grid_pos,
			"player_cell": player_cell,
			"target_cell": assigned_target,
			"facing": e.facing_vector(),
			"is_passable_cell": is_passable_cell,
			"passable": anchor_free,
			"occupied": {},  # 점유는 passable 안에서 이미 반영된다
			"rng": rng,
			"enemy_entity": e,
		}
		var dir: Vector2i = brain.decide(ctx)
		e.set_alerted(brain.is_alerted())
		if dir == Vector2i.ZERO:
			continue
		_apply_move(e, dir)


## 근접 돌진 — 반경 안 + 일반 패턴 + 비보스면 탐지 여부와 무관하게 한 걸음 접근.
## burrow/ambusher/teleport/pulse/ranged와 보스는 각자 룰이 있어 제외한다.
## 달려든 놈은 alerted로 찍는다 — 기습(Advantage)은 "못 본" 상태가 조건이라,
## 정면에서 달려들었는데 선제 보너스가 들어가면 앞뒤가 안 맞는다.
func _try_proximity_lunge(e: EnemyEntity, player_cell: Vector2i) -> bool:
	var d: Vector2i = e.mover.grid_pos - player_cell
	var dist := absi(d.x) + absi(d.y)
	if dist == 0 or dist > PROXIMITY_AGGRO:
		return false
	var entry: Dictionary = _entry.get(e, {})
	var kind := MovementPattern.kind_from_name(str(entry.get("pattern", "wander")))
	if (
		kind != MovementPattern.Kind.WANDER
		and kind != MovementPattern.Kind.DASH
		and kind != MovementPattern.Kind.ZIGZAG
		and kind != MovementPattern.Kind.PATROL
	):
		return false
	if bool(Database.get_enemy_def(StringName(e.species_id)).get("is_boss", false)):
		return false
	var phasing := bool(_phasing.get(e, false))
	var best := Vector2i.ZERO
	var best_d := dist
	for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if not _anchor_free_for(e, e.mover.grid_pos + step, phasing):
			continue
		var dd: Vector2i = e.mover.grid_pos + step - player_cell
		if absi(dd.x) + absi(dd.y) < best_d:
			best_d = absi(dd.x) + absi(dd.y)
			best = step
	if best == Vector2i.ZERO:
		return false
	e.set_alerted(true)
	_apply_move(e, best)
	return true


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
## 스폰 앵커 — **걸어 닿을 수 있는 복도와 빈 방만.**
##
## 구판은 맵 전체에서 2×2가 들어가는 칸을 전부 후보로 삼았다. 그래서 둘이 났다
## (2026-09-06 유저 실플레이 지적):
##   ① **건물 밖·고립 구역에 선다.** 원작 맵에는 걸어 닿을 수 없는 지대가 넓게 남아
##      있다(world_audit 실측: f5 앵커 10,989개 중 2,250개 미도달, 최대 덩어리
##      1,170칸 @(0,49) · f3 7,971개 중 2,928개). 거기 선 몬스터는 만날 수 없고,
##      미니맵과 소리로만 존재해 세계가 가짜로 보인다.
##   ② **NPC가 사는 방 안에 선다.** 교수실·동아리방에 말을 걸러 들어갔더니 전투방이다.
##
## 두 그래프를 쓴다 — 묻는 것이 다르기 때문이다.
##   도달 판정  `ReachProbe.reachable_anchors` (문 통과 포함) — "플레이어가 갈 수 있는가"
##   방 구분    걸음 인접만, **문은 벽으로 취급**            — "여기가 복도인가 방인가"
## 문(ATT 9)은 통행 가능이 아니라 걸음 인접만으로 성분을 뜨면 방이 복도에서 저절로
## 끊긴다. 착지점이 든 성분이 복도이고 나머지가 방이다.
func _collect_spawn_anchors(
	rt: MapRuntime, player_cell: Vector2i, min_dist: int
) -> Array[Vector2i]:
	var seed_anchor := _reach_seed(rt, player_cell)
	if seed_anchor.x < 0:
		# 기준점을 못 잡으면 도달 판정 자체가 성립하지 않는다 — 층을 텅 비우느니
		# 옛 방식(맵 전체)으로 되돌린다. 실제 게임에서는 플레이어가 선 칸을 넘기므로
		# 여기 오지 않지만, 프루브·도구가 임의 좌표로 부를 수 있다.
		push_warning("EnemyManager: f%d 기준 앵커 없음 — 맵 전체에서 뽑는다" % _floor)
		return _all_anchors(rt, player_cell, min_dist)

	var reach := ReachProbe.reachable_anchors(rt, seed_anchor)
	var banned := _banned_room_anchors(rt)
	var out: Array[Vector2i] = []
	var without_rooms: Array[Vector2i] = []
	for anchor: Variant in reach:
		var a: Vector2i = anchor
		var d := a - player_cell
		if maxi(absi(d.x), absi(d.y)) < min_dist:
			continue
		# reachable_anchors는 문 점프 착지도 돌려준다(통행 판정을 안 한다) —
		# 설 수 있는 자리만 남긴다.
		if not Placement.body_fits(rt, a):
			continue
		without_rooms.append(a)
		if not banned.has(a):
			out.append(a)
	if not out.is_empty():
		return out
	if not without_rooms.is_empty():
		# 빈 방이 하나도 없는 층 — ①(건물 밖)이 ②(NPC 방)보다 심한 결함이므로
		# 도달 판정만 남기고 방 배제를 포기한다.
		push_warning("EnemyManager: f%d 빈 방이 없어 NPC 방 배제를 생략" % _floor)
		return without_rooms
	push_warning("EnemyManager: f%d 도달 가능 앵커 없음 — 맵 전체에서 뽑는다" % _floor)
	return _all_anchors(rt, player_cell, min_dist)


## 도달 판정의 기준점 — 플레이어가 선 앵커. 착지 보정 전이거나 도구가 임의 좌표를
## 넘기면 설 수 없는 칸일 수 있어, 그때는 나선으로 가장 가까운 설 수 있는 칸을 찾는다.
func _reach_seed(rt: MapRuntime, player_cell: Vector2i) -> Vector2i:
	if Placement.body_fits(rt, player_cell):
		return player_cell
	for r in range(1, SEED_SEARCH_RADIUS + 1):
		for a: Vector2i in Placement.ring(player_cell, r):
			if Placement.body_fits(rt, a):
				return a
	return Vector2i(-1, -1)


## 옛 방식 — 맵 전체에서 2×2가 들어가는 칸. 위 두 폴백에서만 쓴다.
func _all_anchors(rt: MapRuntime, player_cell: Vector2i, min_dist: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in rt.definition.height - 1:
		for x in rt.definition.width - 1:
			var a := Vector2i(x, y)
			var d := a - player_cell
			if maxi(absi(d.x), absi(d.y)) < min_dist:
				continue
			if Placement.body_fits(rt, a):
				out.append(a)
	return out


## 액터(고정 NPC·배회 워커)가 **사는 방**의 앵커들. 복도는 넣지 않는다.
##
## 워커는 원래 복도를 걷는 존재라, 복도까지 막으면 스폰할 곳이 사라진다.
## 막는 것은 "문으로만 드나드는 닫힌 구역에 액터가 있는 경우"뿐이다.
func _banned_room_anchors(rt: MapRuntime) -> Dictionary:
	if _actor_anchors.is_empty():
		return {}
	var room := _room_ids(rt)
	var corridor := _main_room(room)
	var banned_rooms := {}
	for a: Vector2i in _actor_anchors:
		var rid := _room_near(room, a)
		if rid >= 0 and rid != corridor:
			banned_rooms[rid] = true
	if banned_rooms.is_empty():
		return {}
	var out := {}
	for anchor: Variant in room:
		if banned_rooms.has(int(room[anchor])):
			out[anchor] = true
	return out


## 방 번호 매기기 — **앵커(2×2 몸) 인접**으로 성분을 뜬다. 문(ATT 9)은 몸이 들어가지
## 않으므로 방이 복도에서 저절로 끊긴다.
##
## 셀 단위 인접으로 하면 안 된다. 처음에 그렇게 썼더니 F3의 교수실 알코브가 복도와
## 한 덩어리(9,865칸)로 잡혀 아무것도 배제되지 않았다 — 한 칸 폭 틈은 셀로는
## 이어져 있어도 2×2 몸은 못 지나간다. 실제 이동 규칙으로 재야 실제 방이 나온다
## (2×2로 다시 재니 F3에서 교수실 35칸·랩실 57칸이 제대로 떨어져 나왔다).
##
## **런타임 오버라이드가 아니라 원본 ATT를 본다.** `_spawn_npcs()`가 NPC 몸 셀을
## ATT 1로 덮으므로, 오버라이드로 성분을 뜨면 NPC 자신이 선 자리가 방에서 떨어져
## 나와 정작 그 방을 못 찾는다.
func _room_ids(rt: MapRuntime) -> Dictionary:
	var out := {}
	var next_id := 0
	for y in rt.definition.height - 1:
		for x in rt.definition.width - 1:
			var start := Vector2i(x, y)
			if out.has(start) or not _raw_fits(rt, start):
				continue
			var stack: Array[Vector2i] = [start]
			out[start] = next_id
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					var n := c + d
					if out.has(n) or not _raw_fits(rt, n):
						continue
					out[n] = next_id
					stack.append(n)
			next_id += 1
	return out


## 2×2 몸이 들어가는가 — 원본 ATT 기준(0·2만 통행). Placement.body_fits는 오버라이드를
## 보므로 방 분해에는 쓸 수 없다.
func _raw_fits(rt: MapRuntime, a: Vector2i) -> bool:
	if a.x < 0 or a.y < 0:
		return false
	if a.x + Placement.BODY.x > rt.definition.width:
		return false
	if a.y + Placement.BODY.y > rt.definition.height:
		return false
	for c in Placement.body_cells(a):
		var v := rt.definition.attr_at(c)
		if v != 0 and v != 2:
			return false
	return true


## 액터 앵커가 속한 방. 액터는 Placement.find_spot으로 자리를 옮겨 앉을 수 있어
## 앵커가 성분에 없을 수 있다 — 그럴 땐 두 칸 안에서 찾는다.
func _room_near(room: Dictionary, a: Vector2i) -> int:
	if room.has(a):
		return int(room[a])
	for r in range(1, 3):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := a + Vector2i(dx, dy)
				if room.has(n):
					return int(room[n])
	return -1


## 복도 = **가장 넓은 성분**.
##
## 처음에는 "플레이어 착지점이 든 성분"으로 잡았는데 F0에서 뒤집혔다 — 동쪽 계단
## 앵커(169,58)가 NPC 셋이 있는 방(296칸) **안**이라 그 방이 복도로 잡히고 본
## 구역 4,171칸이 통째로 배제됐다. 층의 주 통행 공간은 언제나 가장 넓은 성분이다.
func _main_room(room: Dictionary) -> int:
	var size := {}
	var best := -1
	var best_n := 0
	for anchor: Variant in room:
		var rid: int = int(room[anchor])
		var n: int = int(size.get(rid, 0)) + 1
		size[rid] = n
		if n > best_n:
			best_n = n
			best = rid
	return best


func _pick_free_anchor(spots: Array[Vector2i], taken: Dictionary) -> Vector2i:
	for _try in SPAWN_TRIES:
		var a: Vector2i = spots[rng.randi() % spots.size()]
		var clear := true
		for c in Placement.body_cells(a):
			if _occupied.has(c) or taken.has(c):
				clear = false
				break
		if clear:
			return a
	return Vector2i(-1, -1)


## **천천히 차오른다.** 잡은 자리가 곧바로 다시 채워지면 잡은 보람이 없고,
## 영영 비어 있으면 층이 안전지대가 돼 긴장이 사라진다. 정원까지 시간을 두고
## 한 마리씩, 그것도 플레이어에게서 멀리(RESPAWN_DIST) 되돌린다.
func _respawn_tick(player_cell: Vector2i, delta: float) -> void:
	if _runtime == null or _cap <= 0 or enemies.size() >= _cap:
		_respawn_accum = 0.0
		return
	_respawn_accum += delta
	if _respawn_accum < _respawn_seconds:
		return
	_respawn_accum = 0.0
	var species_list := Database.encounter_species(_floor)
	if species_list.is_empty():
		return
	var spots := _collect_spawn_anchors(_runtime, player_cell, RESPAWN_DIST)
	if spots.is_empty():
		return
	var cell := _pick_free_anchor(spots, {})
	if cell.x < 0:
		return
	var spec: Dictionary = species_list[rng.randi() % species_list.size()]
	var entry := {
		"id": str(spec["id"]),
		"pattern": str(spec["pattern"]),
		"params": spec.get("params", {}),
		"cell": cell,
	}
	var roster: Array = GameState.field_roster.get(_floor, [])
	roster.append(entry)
	GameState.field_roster[_floor] = roster
	_make_enemy(entry)
