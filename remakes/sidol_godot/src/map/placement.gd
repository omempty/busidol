class_name Placement
## 2×2 몸을 가진 액터의 배치 기하 — NPC·몬스터 스폰과 감사 도구의 공용 판정.
## 원작 캐릭터는 논리적으로 2×2 타일을 점유한다(docs/01_analysis/04_game_systems.md §1.1).
## 몸 기준 기하를 여기 한 곳에 두어 "그려지는 크기"와 "막는 크기"가 어긋나지 않게 한다.

const BODY := Vector2i(2, 2)
const DOOR_ATTR := 9
## 통로 차단 검사 창 반경(앵커 기준 체비셰프). 문·복도 폭을 넉넉히 덮는 크기.
const CHOKE_RADIUS := 5
## find_spot 나선 탐색 기본 반경.
const SEARCH_RADIUS := 6


static func body_cells(anchor: Vector2i, body: Vector2i = BODY) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in body.y:
		for dx in body.x:
			out.append(anchor + Vector2i(dx, dy))
	return out


## 몸이 통째로 들어가는가 — 한 셀만 보면 2×2 액터가 벽에 박힌 채 배치된다.
static func body_fits(rt: MapRuntime, anchor: Vector2i, body: Vector2i = BODY) -> bool:
	for c in body_cells(anchor, body):
		if not rt.is_passable(c):
			return false
	return true


## 두 몸이 겹치거나 변을 맞대면 접촉(모서리만 스치는 경우는 제외).
## 원작 Check_Quang은 x±1·y±2 — 세로만 한 칸 넓어, 옆에서는 겹쳐야 하고
## 위아래는 떨어져 있어도 전투가 시작되는 비대칭이었다. 가로 절을 대칭으로 더한다.
static func bodies_touch(a: Vector2i, b: Vector2i, body: Vector2i = BODY) -> bool:
	var d := b - a
	var overlap_x := absi(d.x) < body.x
	var overlap_y := absi(d.y) < body.y
	var adjacent_x := absi(d.x) <= body.x
	var adjacent_y := absi(d.y) <= body.y
	return (overlap_x and adjacent_y) or (overlap_y and adjacent_x)


static func bodies_intersect(a: Vector2i, b: Vector2i, body: Vector2i = BODY) -> bool:
	var d := b - a
	return absi(d.x) < body.x and absi(d.y) < body.y


## 문(ATT 9)이 가까운가 — 정지 액터가 문간을 막지 않게 한다.
static func near_door(rt: MapRuntime, anchor: Vector2i, radius: int, body: Vector2i = BODY) -> bool:
	for y in range(anchor.y - radius, anchor.y + body.y + radius):
		for x in range(anchor.x - radius, anchor.x + body.x + radius):
			if rt.definition.attr_at(Vector2i(x, y)) == DOOR_ATTR:
				return true
	return false


## 이 자리를 막으면 주변 통로가 끊기는가 — 앵커 주변 창에서
## 2×2 통행 가능 앵커의 연결 성분 수가 늘면 "쪼갰다" = 길목이다.
static func blocks_passage(rt: MapRuntime, anchor: Vector2i, body: Vector2i = BODY) -> bool:
	var window := _window_anchors(rt, anchor, body)
	var blocked := body_cells(anchor, body)
	var after: Dictionary = {}
	for a: Vector2i in window:
		if not _body_hits(a, blocked, body):
			after[a] = true
	if after.is_empty():
		return not window.is_empty()
	return _components(after) > _components(window)


## desired에서 나선으로 퍼지며 조건을 만족하는 첫 앵커. 못 찾으면 제약을 단계적으로 완화한다
## (길목 회피 → 문 회피 순으로 포기) — 배치 실패로 NPC가 사라지는 편보다 낫다.
## taken: 이미 점유된 셀 Dictionary(Vector2i -> anything).
## 반환: {"anchor": Vector2i, "relaxed": int} · relaxed 0=완전만족 1=길목허용 2=문근처허용 3=실패
static func find_spot(
	rt: MapRuntime,
	desired: Vector2i,
	taken: Dictionary,
	radius: int = SEARCH_RADIUS,
	door_margin: int = 2
) -> Dictionary:
	for relaxed in 3:
		for r in range(0, radius + 1):
			for a: Vector2i in ring(desired, r):
				if not body_fits(rt, a, BODY):
					continue
				if _body_taken(a, taken):
					continue
				if relaxed < 2 and near_door(rt, a, door_margin):
					continue
				if relaxed < 1 and blocks_passage(rt, a):
					continue
				return {"anchor": a, "relaxed": relaxed}
	return {"anchor": desired, "relaxed": 3}


static func _body_taken(anchor: Vector2i, taken: Dictionary) -> bool:
	for c in body_cells(anchor):
		if taken.has(c):
			return true
	return false


static func _body_hits(anchor: Vector2i, cells: Array[Vector2i], body: Vector2i) -> bool:
	for c in body_cells(anchor, body):
		if cells.has(c):
			return true
	return false


## 체비셰프 거리 r인 정사각 링(r=0이면 중심 한 점).
static func ring(center: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if r == 0:
		out.append(center)
		return out
	for d in range(-r, r + 1):
		out.append(center + Vector2i(d, -r))
		out.append(center + Vector2i(d, r))
	for d in range(-r + 1, r):
		out.append(center + Vector2i(-r, d))
		out.append(center + Vector2i(r, d))
	return out


static func _window_anchors(rt: MapRuntime, anchor: Vector2i, body: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	for y in range(anchor.y - CHOKE_RADIUS, anchor.y + CHOKE_RADIUS + 1):
		for x in range(anchor.x - CHOKE_RADIUS, anchor.x + CHOKE_RADIUS + 1):
			var a := Vector2i(x, y)
			if body_fits(rt, a, body):
				out[a] = true
	return out


## 4방향 인접으로 이어진 앵커 덩어리 수.
static func _components(anchors: Dictionary) -> int:
	var seen: Dictionary = {}
	var count := 0
	for start: Vector2i in anchors:
		if seen.has(start):
			continue
		count += 1
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var n := c + d
				if anchors.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
	return count
