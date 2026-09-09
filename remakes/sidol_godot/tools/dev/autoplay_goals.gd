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
## **아직 못 가 본 층이 남아 있을 때** 이미 가 본 층으로 되돌아가는 계단.
## 상자보다 앞이다 — 근거는 _stairs()의 rank 주석.
const RANK_BACKTRACK := 5000
const RANK_FLOOR_SEEN := 9000

## 이 층에서 못 낸 목표의 사유 — 부르는 쪽이 보고서에 싣는다.
var notes: Array[String] = []


## 이 게임에 층이 몇 개인가 — **데이터에서 뽑는다.** transitions.json의 guard 범위가
## "그 층에 이 계단이 있다"는 뜻이므로, 범위의 합집합이 곧 걸어 다닐 수 있는 층 목록이다.
## 도착 층(floor_delta를 더한 값)은 쓰지 않는다 — 범위 끝에서 존재하지 않는 층이 섞인다.
static func _all_floors_visited(visited: Dictionary) -> bool:
	for t: Dictionary in JsonUtil.load_dict(TRANSITIONS_PATH, "autoplay").get("transitions", []):
		for f in range(int(t["guard_min_floor"]), int(t["guard_max_floor"]) + 1):
			if not visited.has(f):
				return false
	return true


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
		# 잠긴 계단은 **맨 뒤로 미룬다.** 새 층으로 나가는 계단이라 rank 0이었는데, 층에
		# 들어서자마자 거기부터 갔다가 안 열리고 그 한 번으로 소진됐다. 정작 그 뒤에
		# 게이트 플래그가 서도 다시는 안 갔다 — F3~F5가 걸어서 영영 안 열린 진짜
		# 이유다(2026-08-29 주행 보고서 대조: f2에 닿자마자 stairs_center_up_f2를 밟고
		# 실패했고, Q_F2_POSTER는 그 뒤에야 HP실→포스터로 섰다).
		# 잠겼다는 사실 자체는 여전히 잰다 — 목표에서 빼지 않고 순서만 뒤로 놓는다.
		# 이미 가 본 층으로 되돌아가는 계단의 순위는 **아직 못 가 본 층이 남았는가**로 갈린다.
		#
		# 실측(2026-09-09, 120초 예산 2회): 새 판은 예외 없이 f1에서 f0로 먼저 내려간다
		# (f0가 미방문이라 rank 0). 그런데 돌아오는 계단이 RANK_FLOOR_SEEN(9000)이라
		# 상자(6000)보다 뒤로 밀려 **f0 상자 45·46개를 다 줍고서야** f1로 돌아왔다
		# (그 사이 목표 48·49개). 예산의 절반 가까이가 본편과 무관한 지하 청소에 고정
		# 지출되고, 주행이 조금만 느려지면 그대로 관문이 빨개진다(실패 회차 gate_6은
		# 목표 61개 중 55개가 f0 상자였고 층 2에서 끝났다).
		#
		# 그래서 못 가 본 층이 남아 있는 동안에는 되돌아가는 계단을 상자보다 앞에 둔다.
		# 전 층을 다 밟은 뒤에는 예전대로 맨 뒤다 — 그때는 상자·트리거를 마저 훑는 것이 맞다.
		# 잠긴 계단은 여전히 맨 뒤다(위 주석의 2026-08-29 사고).
		var rank := RANK_NEW_FLOOR
		if visited.has(to_floor):
			rank = RANK_FLOOR_SEEN if _all_floors_visited(visited) else RANK_BACKTRACK
		if locked:
			rank = RANK_FLOOR_SEEN
		var goal := {
			"id": str(t["id"]),
			"kind": "계단",
			"label": label,
			"cell": Vector2i(int(t["anchor"][0]), int(t["anchor"][1])),
			"mode": "stand",
			"passable": true,
			"rank": rank,
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
		var guard := str(t.get("guard_flag", ""))
		if not guard.is_empty() and GameState.has_flag(guard):
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
			# **몸 전체를 낸다.** NPC는 2×2인데 앵커 한 칸만 보면, 아랫줄로는 말을 걸 수
			# 있는데도 「걸어서 닿을 수 없다」로 적힌다 — 게임은 `npc.occupies()`로 몸을
			# 통째로 보므로 도구만 못 간다고 하는 자리가 생긴다(2026-08-29 f3 화공과 교수).
			"cells": npc.body_cells(),
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
