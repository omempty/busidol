class_name PerceptionProbe
extends RefCounted
## 현대 Action RPG 스타일 시야각 및 시선 차폐(Line-of-Sight) 인지 검증 프루브.
##
## 1. 전방 120도 부채꼴 시야각(Vision Cone)
## 2. Bresenham 기반 격자 시선 차폐(Line-of-Sight, 벽 가림 판정)
## 3. 근접 청각(Hearing Radius: 360도 2칸 이내)


## 목표 좌표가 시선 전방 cone_angle_deg (기본 120도 = ±60도) 부채꼴 안에 들어오는가.
static func in_vision_cone(
	self_cell: Vector2i, facing_dir: Vector2i, target_cell: Vector2i, cone_angle_deg: float = 120.0
) -> bool:
	if facing_dir == Vector2i.ZERO:
		return true
	var diff := target_cell - self_cell
	if diff == Vector2i.ZERO:
		return true
	var v_diff := Vector2(diff).normalized()
	var v_face := Vector2(facing_dir).normalized()
	var dot := v_diff.dot(v_face)
	var threshold := cos(deg_to_rad(cone_angle_deg * 0.5))
	return dot >= threshold


## Bresenham 2D 격자 광선 검사 — 시작점에서 목표점 사이 벽(통행 불가 타일)이 없는가.
static func has_line_of_sight(from: Vector2i, to: Vector2i, is_passable: Callable) -> bool:
	if from == to:
		return true
	var dx := absi(to.x - from.x)
	var dy := absi(to.y - from.y)
	var sx := 1 if to.x > from.x else -1
	var sy := 1 if to.y > from.y else -1
	var err := dx - dy
	var curr := from

	while curr != to:
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			curr.x += sx
		if e2 < dx:
			err += dx
			curr.y += sy
		if curr != to and is_passable != null and not is_passable.call(curr):
			return false
	return true


## 종합 인지 판정: 거리 + 청각 반경 + 시야각 + 벽 차폐
static func can_perceive(
	self_cell: Vector2i,
	facing_dir: Vector2i,
	target_cell: Vector2i,
	aggro_radius: int,
	hearing_radius: int,
	is_passable: Callable
) -> bool:
	var dist := absi(self_cell.x - target_cell.x) + absi(self_cell.y - target_cell.y)
	if dist > aggro_radius:
		return false
	# 근접 청각: 등 뒤라도 2칸 이내 초근접은 발소리로 인지 (단, 두꺼운 벽 너머는 차단)
	if dist <= hearing_radius:
		return has_line_of_sight(self_cell, target_cell, is_passable)
	# 시야 범위: 전방 120도 시야각 및 시선 차폐 검사
	return (
		in_vision_cone(self_cell, facing_dir, target_cell, 120.0)
		and has_line_of_sight(self_cell, target_cell, is_passable)
	)
