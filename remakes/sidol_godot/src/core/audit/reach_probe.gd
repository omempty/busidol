class_name ReachProbe
extends RefCounted
## 도달성 프루브 — 플레이어의 2×2 몸으로 실제로 갈 수 있는가.
##
## 잡는 것: 고정 NPC가 통로를 막아 진행 불가가 된 층, 영영 못 여는 상자,
## 못 밟는 계단·문. 데이터 참조 검사(validate)로는 절대 보이지 않는 부류 —
## 좌표는 전부 유효하고 파일도 다 있는데 "갈 수가 없는" 상태다.

const CHEST_MIN := 150
const CHEST_MAX := 186
const EMPTY_ATTR := 199  # 원작 EMPTY — 애초에 빈 상자라 매핑이 없는 게 정상
const DOOR_ATTR := 9

## 문 통과 점프 거리 — TransitionGate._try_door와 같은 규약(원작 move_check_gate).
const DOOR_JUMP := 3


## 플레이어 앵커에서 2×2 몸으로 도달 가능한 앵커 집합.
## 걸음뿐 아니라 **문 통과**도 이동 간선이다 — 문(ATT 9)은 통행 불가 셀이라
## 걸음만 모델링하면 문 너머 방이 통째로 "도달 불가"로 잡히는 거짓 양성이 난다.
static func reachable_anchors(rt: MapRuntime, start: Vector2i) -> Dictionary:
	var seen: Dictionary = {}
	if not Placement.body_fits(rt, start):
		return seen
	seen[start] = true
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var a: Vector2i = stack.pop_back()
		for n: Vector2i in neighbors(rt, a):
			if seen.has(n):
				continue
			seen[n] = true
			stack.append(n)
	return seen


## 한 앵커에서 갈 수 있는 이웃 앵커 — **이동 그래프의 단일 출처**다.
## 감사(ReachProbe)와 자동 주행(tools/dev/autoplay_map.gd)이 같은 것을 쓴다.
## 판정을 두 벌 두면 "도구는 갈 수 있다는데 게임은 못 간다"가 생긴다.
##
## **갈 수 있는 곳만 돌려준다** — 부르는 쪽에서 다시 거르지 말 것. 걸음과 문 통과는
## 규칙이 다르기 때문이다:
##
##   걸음     2×2 몸이 통째로 들어가야 한다(통행 가능 4칸)
##   문 통과  **착지 칸을 검사하지 않는다.** 원본 move_check_gate(GOODITEM.C L1396)가
##            문(ATT 9) 위/아래 2셀만 보고 3칸을 옮기고, 우리 TransitionGate._try_door도
##            같다. 그래서 방 ID로 채워진 통행 불가 구역(교수실·HP방 = ATT 25·51·110…)에
##            **들어설 수 있고**, 원본은 거기 선 것을 What_Bang()으로 읽어 이벤트를 연다.
##            착지에 통행 판정을 걸면 그 방들이 통째로 「도달 불가」가 된다 —
##            층마다 2,600여 앵커가 그렇게 잘려 나가고 있었다(2026-08-29).
##
## 통행 불가 칸에 선 뒤에는 걸어 나올 수 없다. 문으로 들어갔으면 문으로 나온다.
static func neighbors(rt: MapRuntime, a: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if Placement.body_fits(rt, a):
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if Placement.body_fits(rt, a + d):
				out.append(a + d)
	# 발밑(몸 아래 행) 2셀이 문이면 아래로, 머리 위 행이 문이면 위로 점프한다.
	if _door_row(rt, a.x, a.y + Placement.BODY.y):
		out.append(a + Vector2i(0, DOOR_JUMP))
	if _door_row(rt, a.x, a.y - 1):
		out.append(a - Vector2i(0, DOOR_JUMP))
	return out


static func _door_row(rt: MapRuntime, x: int, y: int) -> bool:
	for dx in Placement.BODY.x:
		if rt.definition.attr_at(Vector2i(x + dx, y)) != DOOR_ATTR:
			return false
	return true


## 도달 가능한 앵커에서 "전방 2셀"로 닿을 수 있는 모든 셀 — 한 번만 펼쳐 두고 O(1) 조회한다
## (대상마다 앵커 전체를 훑으면 수백만 비교가 된다).
static func facable_cells(reach: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for anchor: Vector2i in reach:
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			for c in _edge(anchor, d):
				out[c] = true
	return out


## 상호작용 대상이 전방 2셀에 들어올 수 있는 앵커가 실제로 도달 가능한가.
static func check_interactables(rep: AuditReport, rt: MapRuntime, facable: Dictionary) -> void:
	var def := rt.definition
	# 상자는 여러 셀에 같은 ATT로 깔린다 — 덩어리 하나가 상자 하나다.
	# 셀 단위로 보면 벽에 붙은 반대쪽 셀이 늘 "도달 불가"로 잡히는 거짓 양성이 난다.
	var groups := _chest_groups(rt)
	var unreachable_chests := 0
	for g: Array in groups:
		var ok := false
		for c: Vector2i in g:
			if facable.has(c):
				ok = true
				break
		if not ok:
			unreachable_chests += 1
			rep.fail("상자 도달 불가", "%s attr=%d" % [g[0], def.attr_at(g[0])])
	# 매핑되지 않은 상자 — 열려도 "비어 있다"만 나온다. obj_id 173과 같은 부류의
	# 원본 데이터 공백이라 조용히 넘기지 말고 드러낸다.
	var unmapped: Dictionary = {}
	for g: Array in groups:
		var a := def.attr_at(g[0])
		if a != DOOR_ATTR and Database.legacy_item(a).is_empty() and a != EMPTY_ATTR:
			unmapped[a] = int(unmapped.get(a, 0)) + 1
	for a: int in unmapped:
		rep.warn("상자 매핑 없음", "ATT=%d ×%d덩어리 — items.json legacy_ref 미수록" % [a, unmapped[a]])
	var chests := groups.size()
	var doors := 0
	var unreachable_doors := 0
	for y in def.height:
		for x in def.width:
			var cell := Vector2i(x, y)
			var a := def.attr_at(cell)
			if a == DOOR_ATTR:
				doors += 1
				if not facable.has(cell):
					unreachable_doors += 1
					rep.warn("문 도달 불가", str(cell))
	rep.ok("상자 도달", "%d덩어리 중 %d개 접근 가능" % [chests, chests - unreachable_chests])
	rep.ok("문 도달", "%d개 중 %d개 접근 가능" % [doors, doors - unreachable_doors])


## 맵 전체에서 걸을 수 있는 앵커 중 실제로 도달하는 비율.
## 고립된 영역이 있으면 그 안의 상자·NPC가 통째로 도달 불가로 잡힌다 —
## 개별 실패를 나열하기 전에 "구역이 끊겼다"는 원인을 먼저 보여 준다.
static func check_connectivity(rep: AuditReport, rt: MapRuntime, reach: Dictionary) -> void:
	var def := rt.definition
	var walkable: Dictionary = {}
	for y in def.height - 1:
		for x in def.width - 1:
			var a := Vector2i(x, y)
			if Placement.body_fits(rt, a):
				walkable[a] = true
	var orphan_total := walkable.size() - reach.size()
	if orphan_total <= 0:
		rep.ok("연결성", "걸을 수 있는 앵커 %d개 전부 도달" % walkable.size())
		return
	var biggest := _biggest_orphan(walkable, reach)
	rep.warn(
		"고립 구역",
		(
			"걸을 수 있는 앵커 %d개 중 %d개 미도달 · 최대 고립 %d개 @%s"
			% [walkable.size(), orphan_total, biggest["size"], biggest["sample"]]
		)
	)


static func _biggest_orphan(walkable: Dictionary, reach: Dictionary) -> Dictionary:
	var seen: Dictionary = {}
	var best := {"size": 0, "sample": Vector2i.ZERO}
	for start: Vector2i in walkable:
		if reach.has(start) or seen.has(start):
			continue
		var size := 0
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			size += 1
			for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var n := c + d
				if walkable.has(n) and not reach.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		if size > int(best["size"]):
			best = {"size": size, "sample": start}
	return best


## 같은 ATT 값으로 인접한 상자 셀 덩어리 목록.
static func _chest_groups(rt: MapRuntime) -> Array:
	var def := rt.definition
	var seen: Dictionary = {}
	var out: Array = []
	for y in def.height:
		for x in def.width:
			var cell := Vector2i(x, y)
			var a := def.attr_at(cell)
			if a < CHEST_MIN or a > CHEST_MAX or seen.has(cell):
				continue
			var group: Array[Vector2i] = [cell]
			seen[cell] = true
			var stack: Array[Vector2i] = [cell]
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					var n := c + d
					if seen.has(n) or def.attr_at(n) != a:
						continue
					seen[n] = true
					group.append(n)
					stack.append(n)
			out.append(group)
	return out


## NPC에게 말을 걸 수 있는 자리가 있는가 — 배치가 벽에 처박히면 대화 자체가 죽는다.
static func check_npcs(rep: AuditReport, facable: Dictionary, npcs: Array) -> void:
	for npc: NpcEntity in npcs:
		var ok := false
		for c in npc.body_cells():
			if facable.has(c):
				ok = true
				break
		if not ok:
			rep.fail("NPC 대화 불가", "%s @%s — 전방에 설 자리 없음" % [npc.npc_id, npc.cell])
	rep.ok("NPC 접근", "%d명 검사" % npcs.size())


## 층 전환 앵커에 서서 아래키를 누를 수 있는가.
## 이벤트 트리거를 **발동시킬 수 있는가.** zone은 그 칸에 올라설 수 있어야 하고,
## interact는 전방 2셀에 들어와야 한다(TriggerSystem·field.front_cells와 같은 규약).
##
## 좌표가 유효하고 파일이 다 있어도 **갈 수 없으면 그 이벤트는 게임에 없는 것**이다.
## validate는 파일만 보므로 이 부류를 원리적으로 못 잡는다 — 2026-08-29 자동 주행이
## 「F2 포스터 퀘스트가 영영 발동하지 않아 F3~F5에 못 간다」를 실측하고서야 드러났다.
static func check_triggers(
	rep: AuditReport, reach: Dictionary, facable: Dictionary, floor_no: int
) -> void:
	var path := "res://data/maps/triggers_f%d.json" % floor_no
	if not FileAccess.file_exists(path):
		return
	var checked := 0
	for t: Dictionary in JsonUtil.load_dict(path, "ReachProbe").get("triggers", []):
		var kind := str(t.get("type", ""))
		if kind == "auto":
			continue  # 층에 들어서면 저절로 돈다 — 밟을 좌표가 없다
		var id := str(t.get("id", "?"))
		var cells: Array = t.get("cells", [])
		if cells.is_empty():
			rep.fail("트리거 좌표 없음", "%s (type=%s)" % [id, kind])
			continue
		checked += 1
		var ok := false
		for c: Variant in cells:
			var cell := Vector2i(int(c[0]), int(c[1]))
			if reach.has(cell) if kind == "zone" else facable.has(cell):
				ok = true
				break
		if not ok:
			var first := Vector2i(int(cells[0][0]), int(cells[0][1]))
			rep.fail("트리거 도달 불가", "%s @%s (type=%s)" % [id, first, kind])
	rep.ok("트리거 도달", "이 층 좌표 트리거 %d개" % checked)


static func check_transitions(rep: AuditReport, reach: Dictionary, floor_no: int) -> void:
	var raw := JsonUtil.load_dict("res://data/maps/transitions.json", "ReachProbe")
	var checked := 0
	for t: Dictionary in raw.get("transitions", []):
		if floor_no < int(t["guard_min_floor"]) or floor_no > int(t["guard_max_floor"]):
			continue
		checked += 1
		var anchor := Vector2i(int(t["anchor"][0]), int(t["anchor"][1]))
		if not reach.has(anchor):
			rep.fail("계단 도달 불가", "%s @%s" % [t.get("id", "?"), anchor])
	rep.ok("계단 도달", "이 층 유효 전환 %d개" % checked)


static func _edge(anchor: Vector2i, dir: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var body := Placement.BODY
	var start := anchor + dir
	for i in maxi(body.x, body.y):
		var cell := start
		if dir.x != 0:
			cell.x += (body.x - 1) if dir.x > 0 else 0
			cell.y += i
		else:
			cell.y += (body.y - 1) if dir.y > 0 else 0
			cell.x += i
		out.append(cell)
	return out
