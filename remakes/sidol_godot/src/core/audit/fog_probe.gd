class_name FogProbe
extends RefCounted
## 전장의 안개 프루브 — 안개가 **가리되 가두지 않는가**.
##
## 안개는 앞의 관문 넷이 구조적으로 못 보는 부류다. validate는 데이터 참조만, self_check는
## 로직 규약만, 스모크는 "동작하는가"만, check_scripts는 파싱만 본다. 안개의 결함은
## "층을 세워 놓고 실제로 얼마나 밝혀졌는가"라서 조립 관문(world_audit)의 층이다.
##
## 이 프루브가 잡으려는 두 가지 사고:
##   ① **안 가려짐** — 배선이 끊겨 예전처럼 전지 지도로 돌아가는 것. 조용히 퇴행하고
##	  아무도 모른다(안개는 없어도 게임이 돌아간다 — 이 저장소의 지배적 결함 모양 그대로).
##   ② **가둠** — 반대로 너무 가려 갈 곳을 못 찾게 되는 것. 갈 수 있는 데가 남아 있는데
##	  **프론티어가 0개**면 지도에 "여기서 더 갈 수 있다"는 단서가 한 개도 없다는 뜻이다.


## 층 하나를 세운 직후의 안개 상태.
## `reach`는 이미 구한 도달 가능 앵커 집합(다시 BFS 돌리지 않는다).
static func check_reveal(
	rep: AuditReport, rt: MapRuntime, floor_index: int, view_px: Vector2, reach: Dictionary
) -> void:
	var def := rt.definition
	var fog: FogOfWar = GameState.fog

	var reach_cells := {}
	for anchor: Vector2i in reach:
		for c: Vector2i in Placement.body_cells(anchor):
			reach_cells[c] = true

	var seen := 0
	var frontier := 0
	var unseen_reach := 0
	for y in def.height:
		for x in def.width:
			var cell := Vector2i(x, y)
			if fog.is_seen(floor_index, def, cell):
				seen += 1
				continue
			if reach_cells.has(cell):
				unseen_reach += 1
			if _touches_seen_passable(rt, fog, floor_index, cell):
				frontier += 1

	var total := def.width * def.height

	# ⓪ 규약: **어두운 층만 안개가 낀다**(FloorLighting.is_dark). 밝은 층에서 안개가
	#    돌면 지도가 이유 없이 검어지고, 어두운 층에서 안 돌면 규약이 죽은 것이다.
	if not FloorLighting.is_dark(floor_index):
		if seen > 0:
			rep.fail("안개 적용 층", "밝은 층인데 안개가 %d칸 기록됐다 — is_dark 판정이 갈렸다" % seen)
		else:
			rep.ok("안개 적용 층", "밝은 층 — 안개 없음(지도 전체 공개)")
		return
	rep.ok("안개 적용 층", "어두운 층 — 안개 적용")

	# ① 가리는가 — 밝혀진 칸이 0이면 지도가 새까맣고, 전부면 안개가 죽은 것이다.
	if seen <= 0:
		rep.fail("안개 초기 시야", "층에 들어섰는데 밝혀진 칸이 0 — 지도가 새까맣다")
	elif seen >= total:
		rep.fail("안개 초기 시야", "%d칸 전부 밝혀짐 — 안개가 걸리지 않았다(전지 지도로 퇴행)" % total)
	else:
		rep.ok("안개 초기 시야", "%d/%d칸 (%.1f%%) — 화면에 비친 칸만 기록" % [seen, total, 100.0 * seen / total])

	# ② 가두지 않는가 — 갈 데가 남았으면 지도에 그 방향이 한 칸이라도 찍혀야 한다.
	if unseen_reach > 0 and frontier <= 0:
		rep.fail("안개 프론티어", "아직 못 본 도달 가능 칸이 %d개인데 프론티어가 0개 — 어디로 가야 하는지 지도에 단서가 없다" % unseen_reach)
	else:
		rep.ok("안개 프론티어", "미탐색 도달칸 %d개 · 프론티어 %d칸" % [unseen_reach, frontier])

	# ③ 화면만큼만 밝히는가.
	#
	#    **기준을 필드에서 받아오지 않는다.** 처음엔 `Field.visible_cell_rect()`를 그대로
	#    받아 그것과 비교했는데, 그러면 범위 계산이 틀려도 프루브가 같은 틀린 값을 보고
	#    "맞다"고 한다(음성 테스트로 확인: 사각형을 70×58로 부풀렸더니 그대로 통과했다).
	#    그래서 여기서는 **뷰포트 픽셀**이라는 독립된 출처에서 상한을 다시 구한다.
	#    +2는 칸 경계에 걸친 줄·열 몫이다.
	var t := float(MapDefinition.TILE_PX)
	var bound_cells := (floori(view_px.x / t) + 2) * (floori(view_px.y / t) + 2)
	if seen > bound_cells:
		rep.fail(
			"안개 화면 범위",
			(
				"밝힌 칸 %d > 화면 상한 %d(뷰포트 %dx%d / 타일 %d) — 화면 밖까지 열렸다"
				% [seen, bound_cells, int(view_px.x), int(view_px.y), MapDefinition.TILE_PX]
			)
		)
	else:
		rep.ok("안개 화면 범위", "밝힌 칸 %d ≤ 화면 상한 %d" % [seen, bound_cells])


static func _touches_seen_passable(
	rt: MapRuntime, fog: FogOfWar, floor_index: int, cell: Vector2i
) -> bool:
	var def := rt.definition
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n := cell + d
		if not def.in_bounds(n):
			continue
		if rt.is_passable(n) and fog.is_seen(floor_index, def, n):
			return true
	return false
