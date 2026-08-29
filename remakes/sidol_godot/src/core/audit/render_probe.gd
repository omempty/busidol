class_name RenderProbe
extends RefCounted
## 렌더 정합 프루브 — "데이터에는 있는데 화면에는 없는 것"을 잡는다.
##
## 실제 회귀 근거(2026-08-26): 오브젝트 레이어의 TileSet이 지면 아틀라스만 실었는데
## set_cell은 소스 1을 지목해 오브젝트 173종이 전부 미렌더였다. 벽 판정만 남아
## "보이지 않는 벽"이 됐지만 validate·smoke·self_check 어디에도 걸리지 않았다.
## 이 프루브는 조립된 TileMapLayer를 직접 읽어 그 간극을 본다.

## 원작 SPR 색0(순검정)은 투명이다. 시트를 구판 파이프라인으로 구우면 검은 사각 배경이 남는다.
const STALE_BLACK_RATIO := 0.15
const ATLASES := [MapRenderer.GROUND_ATLAS, MapRenderer.OBJECT_ATLAS]


## 맵 데이터의 모든 오브젝트/지면 셀이 실제 타일로 찍혔는가.
static func check_layers(rep: AuditReport, renderer: MapRenderer, rt: MapRuntime) -> void:
	var layers := _layers_of(renderer)
	if layers.size() < 3:
		rep.fail("레이어 조립", "TileMapLayer 3층 기대, 실제 %d" % layers.size())
		return
	var def := rt.definition
	var obj_meta: Dictionary = (
		JsonUtil
		. load_dict(MapRenderer.OBJECT_ATLAS.replace(".png", ".json"), "RenderProbe")
		. get("objects", {})
	)
	var out_of_range: Dictionary = {}
	var missing_ground := 0
	var missing_object := 0
	var object_total := 0
	for y in def.height:
		for x in def.width:
			var cell := Vector2i(x, y)
			if layers[0].get_cell_source_id(cell) < 0:
				missing_ground += 1
			var oid := def.object_at(cell)
			if oid > 0:
				object_total += 1
				if layers[1].get_cell_source_id(cell) < 0:
					missing_object += 1
					if obj_meta.has(str(oid)):
						# 아틀라스에 있는데 안 찍혔다 = 코드 결함(과거 소스 ID 오지정과 동종).
						rep.fail("오브젝트 미렌더", "%s obj_id=%d (아틀라스에 존재)" % [cell, oid])
					else:
						out_of_range[oid] = int(out_of_range.get(oid, 0)) + 1
	if missing_ground > 0:
		rep.fail("지면 미렌더", "%d셀" % missing_ground)
	else:
		rep.ok("지면 렌더", "%d셀 전부 배치" % (def.width * def.height))
	for oid: int in out_of_range:
		rep.warn(
			"오브젝트 id 범위 밖",
			"obj_id=%d ×%d셀 — 아틀라스 미수록(원본 OBJ.SPR에 없는 id)" % [oid, out_of_range[oid]]
		)
	if missing_object == 0:
		rep.ok("오브젝트 렌더", "%d셀 전부 배치" % object_total)
	else:
		rep.ok("오브젝트 렌더", "%d셀 중 %d셀 배치" % [object_total, object_total - missing_object])


## 보이지 않는 벽 = 플레이어가 실제로 부딪힐 수 있는데 화면에 아무 근거도 없는 셀.
## 지도 바깥의 미사용 영역까지 세면 수천 건이 되어 신호가 죽는다 —
## 도달 가능한 자리에서 몸이 닿는 셀(facable)로만 한정한다.
static func check_invisible_walls(rep: AuditReport, rt: MapRuntime, facable: Dictionary) -> void:
	var def := rt.definition
	var blind: Array[Vector2i] = []
	for cell: Vector2i in facable:
		if not def.in_bounds(cell):
			continue  # 맵 밖 — 막은 것은 벽 텍스처가 아니라 맵 끝이다
		if rt.is_passable(cell):
			continue
		if def.attr_at(cell) != 1:
			continue  # NPC/상자/방 ID는 별도 의미가 있는 차단
		if def.object_at(cell) > 0:
			continue  # 오브젝트가 서 있으면 눈에 보이는 벽
		# 바닥 타일이 옆 통행 셀과 다르면 벽 텍스처가 깔린 것 = 눈에 보인다.
		# 같은 타일이 그대로 이어지면 플레이어에게는 그냥 바닥인데 막힌 자리다.
		if _same_floor_as_neighbor(rt, cell):
			blind.append(cell)
	if blind.is_empty():
		rep.ok("차단 근거", "부딪힐 수 있는 차단 셀 전부 시각 근거 있음")
		return
	rep.warn("근거 없는 차단", "%d셀 — 지면만 있고 ATT 1 (예: %s)" % [blind.size(), blind.slice(0, 4)])


## 시트가 구판 파이프라인 산출물인지 — 불투명 순검정 비율로 판별.
static func check_atlas_transparency(rep: AuditReport) -> void:
	for path: String in ATLASES:
		var tex: Texture2D = load(path)
		if tex == null:
			rep.fail("아틀라스 로드", path)
			continue
		var img := tex.get_image()
		var total := img.get_width() * img.get_height()
		var black := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.0 and c.r == 0.0 and c.g == 0.0 and c.b == 0.0:
					black += 1
		var ratio := float(black) / float(maxi(total, 1))
		if ratio > STALE_BLACK_RATIO:
			rep.fail(
				"색0 키잉 누락",
				(
					"%s 불투명 순검정 %.1f%% — tools/dev/key_color0_transparent.py 대상"
					% [path.get_file(), ratio * 100.0]
				)
			)
		else:
			rep.ok("아틀라스 투명도", "%s 순검정 %.1f%%" % [path.get_file(), ratio * 100.0])


## 인접한 통행 가능 셀 중 하나라도 같은 지면 타일을 쓰는가.
static func _same_floor_as_neighbor(rt: MapRuntime, cell: Vector2i) -> bool:
	var def := rt.definition
	var here := def.ground_at(cell)
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n := cell + d
		if def.in_bounds(n) and rt.is_passable(n) and def.ground_at(n) == here:
			return true
	return false


static func _layers_of(renderer: MapRenderer) -> Array[TileMapLayer]:
	var out: Array[TileMapLayer] = []
	for child in renderer.get_children():
		if child is TileMapLayer:
			out.append(child)
	return out
