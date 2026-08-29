extends RefCounted
## 자동 주행이 이 층에서 가 볼 곳 — 계단·트리거·NPC·상자.
##
## 좌표는 전부 `data/**` 에서 읽는다(AGENTS.md 콘텐츠 하드코딩 금지). 상자 판정도
## 필드 씬의 `_is_chest` 를 그대로 물어본다 — 여기서 따로 판단하기 시작하면
## "도구는 상자라는데 게임은 아니라고 한다"가 생긴다.
##
## `mode` 는 그 칸을 **밟는가(stand)** 조사하는가(face)를 가른다. 게임이 그 칸을 어떻게
## 보느냐로 정한다 — zone 트리거·계단은 올라서야 발동하고, interact 트리거·NPC·상자는
## **전방 2셀**에 들어와야 발동한다(field.front_cells). 통행 여부로 정하지 않는다:
## 통행 가능한 칸도 그쪽으로 걸어와 멈추면 앞에 둘 수 있다(부르는 쪽이 그렇게 붙는다).

const TRANSITIONS_PATH := "res://data/maps/transitions.json"

## 우선순위 띠. 작을수록 먼저 간다. 거리를 더해 쓰므로 띠 간격은 맵 지름보다 넓다.
## **새 층으로 나가는 계단이 맨 앞이다** — 한 층을 훑고 넘어가면 예산이 앞에서 닳는다.
const RANK_NEW_FLOOR := 0
const RANK_TRIGGER := 2000
const RANK_NPC := 4000
const RANK_CHEST := 6000
const RANK_FLOOR_SEEN := 9000

## 이 층에서 못 낸 목표의 사유 — 부르는 쪽이 보고서에 싣는다.
var notes: Array[String] = []


func collect(field: Node2D, floor_no: int, visited: Dictionary) -> Array:
	notes.clear()
	var out: Array = []
	out.append_array(_stairs(floor_no, visited))
	out.append_array(_triggers(field, floor_no))
	out.append_array(_npcs(field))
	out.append_array(_chests(field))
	return out


## 계단 — 앵커에 올라서서 아래키를 누르면 층이 바뀐다(TransitionGate._try_stairs).
## 플래그가 잠근 계단도 목표로 낸다: **잠겨 있다는 사실을 재는 것**이 이 도구의 일이다.
func _stairs(floor_no: int, visited: Dictionary) -> Array:
	var out: Array = []
	for t: Dictionary in JsonUtil.load_dict(TRANSITIONS_PATH, "autoplay").get("transitions", []):
		if floor_no < int(t["guard_min_floor"]) or floor_no > int(t["guard_max_floor"]):
			continue
		var to_floor := floor_no + int(t["floor_delta"])
		var reqs := flags_of(t.get("requires_flag"))
		var locked := false
		for r: String in reqs:
			if not GameState.has_flag(r):
				locked = true
		var label := "f%d → f%d" % [floor_no, to_floor]
		if locked:
			label += "  (%s 필요)" % ", ".join(reqs)
		var goal := {
			"id": str(t["id"]),
			"kind": "계단",
			"label": label,
			"cell": Vector2i(int(t["anchor"][0]), int(t["anchor"][1])),
			"mode": "stand",
			"passable": true,
			"rank": RANK_NEW_FLOOR if not visited.has(to_floor) else RANK_FLOOR_SEEN,
			"expect": {"floor": to_floor},
		}
		out.append(goal)
	return out


## 이벤트 트리거 — zone(밟으면)/interact(앞에서 조사하면). auto는 층에 들어서면
## 저절로 도니 목표가 아니다. 게임이 안 볼 것(플래그 미충족·이미 소비)은 여기서도 뺀다.
func _triggers(field: Node2D, floor_no: int) -> Array:
	var out: Array = []
	var path := "res://data/maps/triggers_f%d.json" % floor_no
	if not FileAccess.file_exists(path):
		return out
	var rt: MapRuntime = field.get_runtime()
	for t: Dictionary in JsonUtil.load_dict(path, "autoplay").get("triggers", []):
		var kind := str(t.get("type", ""))
		if kind == "auto":
			continue
		var blocked := false
		for r: String in flags_of(t.get("requires_flag")):
			if not GameState.has_flag(r):
				blocked = true
		if blocked:
			continue
		var done := str(t.get("done_flag", ""))
		if not done.is_empty() and GameState.has_flag(done):
			continue
		for cell: Vector2i in _trigger_cells(t):
			var trigger_id := str(t.get("id", ""))
			if not rt.definition.in_bounds(cell):
				var why := "좌표가 맵(%d×%d) 밖" % [rt.definition.width, rt.definition.height]
				notes.append("| f%d | %s | %s | %s |" % [floor_no, trigger_id, str(cell), why])
				continue
			var goal := {
				"id": "%s@%d,%d" % [trigger_id, cell.x, cell.y],
				"kind": "트리거(%s)" % kind,
				"label": trigger_id,
				"cell": cell,
				# zone은 밟아야, interact는 앞에 둬야 발동한다(TriggerSystem).
				"mode": "stand" if kind == "zone" else "face",
				"passable": rt.is_passable(cell),
				"rank": RANK_TRIGGER,
				"expect": {"flag": done},
			}
			out.append(goal)
	return out


## `cells` 가 정본이다(TriggerSystem._trigger_cells). `pos` 만 있는 트리거는 게임이
## 못 읽지만 **의도한 자리는 거기**이므로 목표로는 낸다 — 가서 안 되는 것을 재려는 것이다.
func _trigger_cells(t: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for a: Variant in t.get("cells", []):
		out.append(Vector2i(int(a[0]), int(a[1])))
	if out.is_empty() and t.has("pos"):
		var p: Array = t["pos"]
		out.append(Vector2i(int(p[0]), int(p[1])))
	return out


## NPC — 배치된 실좌표를 쓴다. npcs_f*.json의 희망 좌표는 Placement가 옮길 수 있다.
func _npcs(field: Node2D) -> Array:
	var out: Array = []
	for npc: NpcEntity in field.npcs:
		if not is_instance_valid(npc):
			continue
		var goal := {
			"id": String(npc.npc_id),
			"kind": "NPC",
			"label": npc.display_name,
			"cell": npc.cell,
			"mode": "face",
			"passable": false,  # NPC 몸 셀은 통행 오버라이드로 막혀 있다
			"rank": RANK_NPC,
			"expect": {"dialogue": true},
		}
		out.append(goal)
	return out


## 상자 — 같은 ATT로 붙어 있는 덩어리가 상자 하나(field._chest_group과 같은 규약).
func _chests(field: Node2D) -> Array:
	var out: Array = []
	var rt: MapRuntime = field.get_runtime()
	var def: MapDefinition = rt.definition
	var seen: Dictionary = {}
	for y in def.height:
		for x in def.width:
			var cell := Vector2i(x, y)
			if seen.has(cell):
				continue
			# 런타임 ATT로 묻는다 — 이미 연 상자는 오버라이드가 벽(1)이라 걸러진다.
			var attr := rt.attr_at(cell)
			if not bool(field.call("_is_chest", attr)):
				continue
			for c: Vector2i in field.call("_chest_group", cell, attr):
				seen[c] = true
			var goal := {
				"id": "chest@%d,%d" % [x, y],
				"kind": "상자",
				"label": "ATT %d" % attr,
				"cell": cell,
				"mode": "face",
				"passable": false,  # 상자 ATT는 통행 불가
				"rank": RANK_CHEST,
				"expect": {"chest": cell},
			}
			out.append(goal)
	return out


## requires_flag는 문자열 하나이거나 목록이다(TriggerSystem._consumed와 같은 규약).
static func flags_of(v: Variant) -> Array:
	if v == null:
		return []
	if v is Array:
		var out: Array = []
		for e: Variant in v:
			out.append(str(e))
		return out
	return [str(v)]
