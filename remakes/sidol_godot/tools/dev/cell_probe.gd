extends Node
## 칸 조회 — **좌표 하나를 놓기 전에 그 자리가 쓸모 있는지 먼저 잰다.**
##
## 실행: godot --headless --path . res://tools/dev/cell_probe.tscn --
##       --floor 1 --cells "100,63;169,60"
##
## 트리거 좌표를 눈대중으로 적으면 「데이터에는 있는데 게임에는 없는」 것이 된다
## (2026-08-29 실측: 8종이 자리표시자라 맵 상단 봉인 띠 안에 있었다). 여기서 답하는 것:
##
##   설 수 있나   zone 트리거는 그 칸에 **올라서야** 발동한다(도달 앵커여야 한다)
##   볼 수 있나   interact 트리거는 **앞에 서서 조사**한다(facable이어야 한다)
##   아니면 어디  가장 가까운 쓸 만한 칸을 함께 준다 — 「안 된다」만으로는 못 고친다
##
## 판정은 감사(ReachProbe)와 **같은 코드**를 부른다. 두 벌을 두면 도구는 된다는데
## 게임은 안 되는 자리가 생긴다.

const FIELD_SCENE := preload("res://scenes/field.tscn")
## 대안을 찾아 볼 반경 — 방 하나를 넘지 않는다.
const SEARCH_RADIUS := 12


func _ready() -> void:
	if get_tree().current_scene == self:
		var runner: Node = (get_script() as GDScript).new()
		runner.name = "CellProbeRunner"
		get_tree().root.add_child.call_deferred(runner)
		return
	await _run()


func _run() -> void:
	var floor_no := int(_arg("--floor", "1"))
	var cells := _cells(_arg("--cells", ""))
	if cells.is_empty():
		push_error('[cell_probe] --cells "x,y;x,y" 가 필요하다')
		get_tree().quit(1)
		return

	GameState.current_floor = floor_no
	GameState.player_cell = Vector2i(-1, -1)
	GameState.flags["q_f1_opening_seen"] = true
	GameState.flags["Q_F1_START"] = true

	var field: Node2D = FIELD_SCENE.instantiate()
	add_child(field)
	await get_tree().process_frame
	await get_tree().process_frame

	var player: PlayerEntity = field.get_player()
	var rt: MapRuntime = field.get_runtime()
	if player == null or rt == null:
		push_error("[cell_probe] f%d 필드를 세우지 못했다" % floor_no)
		get_tree().quit(1)
		return

	var reach := ReachProbe.reachable_anchors(rt, player.mover.grid_pos)
	var facable := ReachProbe.facable_cells(reach)
	print("[cell_probe] f%d — 도달 앵커 %d개 / 조사 가능 %d칸" % [floor_no, reach.size(), facable.size()])
	print("| 칸 | ATT | 설 수 있나(zone) | 조사할 수 있나(interact) | 가장 가까운 대안 |")
	print("|---|---|---|---|---|")
	for cell: Vector2i in cells:
		var att := rt.attr_at(cell)
		var standable: bool = reach.has(cell)
		var seeable: bool = facable.has(cell)
		var alt := "-" if standable and seeable else _nearest(cell, reach, facable)
		print(
			(
				"| %s | %d | %s | %s | %s |"
				% [cell, att, "예" if standable else "아니오", "예" if seeable else "아니오", alt]
			)
		)
	get_tree().quit(0)


## 둘 다 되는 가장 가까운 칸. 없으면 각각 되는 칸이라도 준다.
func _nearest(cell: Vector2i, reach: Dictionary, facable: Dictionary) -> String:
	var best := Vector2i.MAX
	var best_d := 1 << 30
	for r: int in range(1, SEARCH_RADIUS + 1):
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := cell + Vector2i(dx, dy)
				if not reach.has(c) or not facable.has(c):
					continue
				var d := absi(dx) + absi(dy)
				if d < best_d:
					best_d = d
					best = c
		if best_d < 1 << 30:
			break
	return "없음(반경 %d)" % SEARCH_RADIUS if best == Vector2i.MAX else "%s (%d칸)" % [best, best_d]


func _cells(raw: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for piece in raw.split(";", false):
		var xy := piece.split(",", false)
		if xy.size() == 2:
			out.append(Vector2i(int(xy[0].strip_edges()), int(xy[1].strip_edges())))
	return out


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var idx := args.find(name)
	if idx < 0 or idx + 1 >= args.size():
		return fallback
	return args[idx + 1]
