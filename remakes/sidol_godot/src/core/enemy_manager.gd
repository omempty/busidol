class_name EnemyManager
extends Node
## 층별 몬스터 스폰·AI 틱·점유 레지스트리·인카운터.
## EnemyEntity는 데이터만, 이동 판정과 AI는 여기서 수행(순환 참조 방지).

static var rng := RandomNumberGenerator.new()

var enemies: Array[EnemyEntity] = []
var _occupied := {}
var _brains := {}  # entity -> AIBrain
var _act_accum := {}


func spawn_for_floor(floor_idx: int, rt: MapRuntime, parent: Node2D) -> void:
	despawn_all()
	var table: Dictionary = Database.encounter_table(floor_idx)
	var count: int = int(table.get("count", 0))
	var species_list: Array = table.get("species", [])
	if species_list.is_empty() or count == 0:
		return

	rng.randomize()
	var passable_cells := _collect_passable(rt)

	for i in mini(count, passable_cells.size()):
		var cell: Vector2i = passable_cells[rng.randi() % passable_cells.size()]
		if _occupied.has(cell):
			continue
		var sid := StringName(str(species_list[rng.randi() % species_list.size()]))
		var e := EnemyEntity.new()
		parent.add_child(e)
		e.setup(sid, cell, Color(1, 1, 1))
		enemies.append(e)
		_occupied[cell] = true
		_brains[e] = ChaseAI.new()


func despawn_all() -> void:
	for e in enemies:
		e.queue_free()
	enemies.clear()
	_occupied.clear()
	_brains.clear()


func get_contact(player_cell: Vector2i) -> String:
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var d := e.mover.grid_pos - player_cell
		if absi(d.x) <= 1 and absi(d.y) <= 2:
			return String(e.species_id)
	return ""


func tick(player_cell: Vector2i) -> void:
	for e in enemies:
		if not is_instance_valid(e) or e.mover.moving:
			continue
		var brain: AIBrain = _brains.get(e)
		if brain == null:
			continue
		var ctx := {
			"self_cell": e.mover.grid_pos,
			"player_cell": player_cell,
			"passable": _is_passable,
			"occupied": _occupied,
			"rng": rng,
		}
		var dir := brain.decide(ctx)
		if dir != Vector2i.ZERO and not _occupied.has(e.mover.grid_pos + dir):
			_occupied.erase(e.mover.grid_pos)
			e.mover.grid_pos += dir
			e.position = GridMover.block_center(e.mover.grid_pos)


func _is_passable(cell: Vector2i) -> bool:
	return not _occupied.has(cell)


func get_occupied() -> Dictionary:
	return _occupied


func _collect_passable(rt: MapRuntime) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in rt.definition.height:
		for x in rt.definition.width:
			if rt.is_passable(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out
