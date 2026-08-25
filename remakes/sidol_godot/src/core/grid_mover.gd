class_name GridMover
extends Node
## 격자 이동 컴포넌트 — 원작의 2x2 발판 판정 유지 + 보간 이동 + 입력 버퍼.
## docs/03_plan/01_roadmap.md Phase 1 품질 기준: 이징 보간, 방향 즉시 반응, 버퍼 체인.

signal step_started(dir: Vector2i)
signal step_finished(pos: Vector2i)
signal step_blocked(dir: Vector2i)

const STEP_TIME := 0.16

var grid_pos := Vector2i.ZERO
var footprint := Vector2i(2, 2)  # 원작: 캐릭터 몸이 2x2 셀 점유
var moving := false
var enabled := true  # 문 통과/층 전환 등 특수 이동 중 잠금
var buffered_dir := Vector2i.ZERO
var body: Node2D  # 실제 이동할 노드(스프라이트 부모)
var is_passable: Callable  # func(cell: Vector2i) -> bool


## 2x2 블록의 중심 픽셀 좌표(스프라이트 centered 기준).
static func block_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 1, cell.y + 1) * float(MapDefinition.TILE_PX)


func setup(p_body: Node2D, start_cell: Vector2i, passable_cb: Callable) -> void:
	body = p_body
	is_passable = passable_cb
	grid_pos = start_cell
	body.position = block_center(grid_pos)


func try_step(dir: Vector2i) -> bool:
	if moving:
		buffered_dir = dir
		return false
	if not enabled:
		return false
	if not _edge_passable(grid_pos, dir):
		step_blocked.emit(dir)
		return false
	moving = true
	grid_pos += dir
	step_started.emit(dir)
	# self는 씬 트리 밖 멤버 노드라 create_tween()이 실패한다 —
	# 트리에 있는 body 기준으로 생성(보간·_on_arrived 체인의 생명선).
	var tween := body.create_tween()
	tween.tween_property(body, "position", block_center(grid_pos), STEP_TIME)
	tween.finished.connect(_on_arrived)
	return true


func teleport(cell: Vector2i) -> void:
	grid_pos = cell
	moving = false
	buffered_dir = Vector2i.ZERO
	if body != null:
		body.position = block_center(cell)


func _on_arrived() -> void:
	moving = false
	step_finished.emit(grid_pos)
	if buffered_dir != Vector2i.ZERO:
		var d := buffered_dir
		buffered_dir = Vector2i.ZERO
		try_step(d)


## 진행 방향 선행 열/행의 셀들이 전부 통행 가능한지 — 원작 2셀 폭 판정 재현.
func _edge_passable(origin: Vector2i, dir: Vector2i) -> bool:
	var start := origin + dir
	var span := maxi(footprint.x, footprint.y)
	for i in span:
		var cell := start
		if dir.x != 0:
			cell.x += (footprint.x - 1) if dir.x > 0 else 0
			cell.y += i
		else:
			cell.y += (footprint.y - 1) if dir.y > 0 else 0
			cell.x += i
		if not is_passable.call(cell):
			return false
	return true
