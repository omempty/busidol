class_name FogOfWar
extends RefCounted
## 전장의 안개 — 미니맵을 **전지 지도에서 탐험 기록으로** 바꾼다.
##
## 왜 필드가 아니라 미니맵인가: 필드는 이미 안개다. 뷰포트 960×540 · 타일 32px이므로
## 화면에 서는 것은 30×17 = 510칸, 맵은 200×65 = 13,000칸이다(3.9%). 반면 미니맵은 층에
## 들어서는 순간 13,000칸을 통째로 구워 놓았고 **상자 자리까지** 노란색으로 칠했다.
## 이 게임에서 전지(全知)인 표면은 거기 하나뿐이었다.
##
## 그래서 이것은 새 재미 요소라기보다 **이미 적립된 맵 항목들의 전제조건**이다.
## 백로그 1.1의 "시크릿 룸"과 "은닉 보상"(눈에 띄지 않는 구석의 상자)은 M 한 번에
## 구석 상자가 다 보이는 상태에서는 만들어도 작동하지 않는다.
##
## **가리는 설계가 아니라 뒤집는 설계다.** 지금 미니맵은 "어디에 뭐가 있나"는 알려줘도
## "내가 어디를 안 가봤나"는 못 알려준다. 길찾기의 실제 어려움은 후자다. 그래서 안개와
## 함께 프론티어(미탐색 경계)와 탐험률이 들어간다 — 발견은 어렵게, 재방문은 쉽게.
##
## ## 기록하는 것은 **화면에 비친 칸**이다 — 시야 차폐가 아니다
##
## 첫 판(2026-09-07 오전)은 반경 10칸에 Bresenham 시선을 쏴서 벽에 가린 칸을 빼는
## 로그라이크식이었다. **틀린 이식이었다.** 이 게임은 탑다운 타일뷰라 카메라가 비추는
## 사각형 안은 벽 너머 방까지 전부 화면에 그려진다(MapRenderer가 뷰포트 타일을 통째로
## 깐다). 즉 시선 차폐를 걸면 **화면에 뻔히 보이는 방이 지도에는 안 가본 곳으로 남는다** —
## 실측으로 화면 510칸 중 240칸만 기록됐다. 1인칭도 아닌데 시야를 막은 셈이다.
##
## 덤으로 비용도 그때 붙었다. 걸음마다 441칸 × Bresenham이고 광선 한 걸음마다
## `is_passable`을 Callable로 불러 연속 주행 관문이 물리 240틱/초 → 72틱/초로 주저앉았다
## (A/B 실측: 안개 ON 층 2 FAIL / OFF 층 6 PASS). 사각형 기록으로 바꾸니 광선도 Callable도
## 통째로 사라졌다 — **맞는 모델이 더 싸다.**

## 층별 탐색 비트맵 — 칸 하나에 1비트. 200×65 = 13,000비트 = 1,625바이트/층.
## 6층 전부 밝혀도 9.75KB다(base64로 세이브에 실으면 13KB 안팎).
var _seen := {}

## 층별 "도달 가능한 통행칸 수" — 탐험률의 분모. **지연 계산**이다.
##
## 원작 맵에는 걸어 닿을 수 없는 지대가 넓게 남아 있다(world_audit 실측: f1은 걸을 수
## 있는 앵커 9,124개 중 2,609개가 미도달). 통행 가능 칸 전체를 분모로 삼으면 아무리
## 다 돌아도 76%에서 멈춰 "내가 뭘 놓쳤나"를 만든다. 그래서 분모는 **도달 가능한** 칸이다.
##
## 층에 들어설 때 계산하면 로딩이 늘어난다 — 지도를 처음 열 때 한 번 계산해 캐시한다.
var _reach_total := {}


func clear() -> void:
	_seen.clear()
	_reach_total.clear()


## 이 층의 비트맵. 없으면 만든다.
func bits(floor_index: int, def: MapDefinition) -> PackedByteArray:
	if not _seen.has(floor_index):
		var buf := PackedByteArray()
		buf.resize((def.width * def.height + 7) / 8)
		buf.fill(0)
		_seen[floor_index] = buf
	return _seen[floor_index]


func is_seen(floor_index: int, def: MapDefinition, cell: Vector2i) -> bool:
	if not def.in_bounds(cell):
		return false
	var idx := cell.y * def.width + cell.x
	return (bits(floor_index, def)[idx >> 3] & (1 << (idx & 7))) != 0


## 밝힌다. **새로 밝혔을 때만** true — 미니맵이 고칠 픽셀만 고치게 하기 위해서다.
func mark(floor_index: int, def: MapDefinition, cell: Vector2i) -> bool:
	if not def.in_bounds(cell):
		return false
	var buf := bits(floor_index, def)
	var idx := cell.y * def.width + cell.x
	var byte := idx >> 3
	var mask := 1 << (idx & 7)
	if (buf[byte] & mask) != 0:
		return false
	buf[byte] = buf[byte] | mask
	return true


## **화면이 비추고 있는 사각형을 그대로 기록한다** — 새로 밝힌 칸 목록을 돌려준다.
##
## 범위는 카메라가 정한다(`Field.visible_cell_rect`). 맵 가장자리에서는 카메라 limit이
## 걸려 주인공이 화면 복판에 없으므로, 주인공 기준 사각형으로 잡으면 그쪽이 덜 기록된다.
##
## 걸음당 비용은 510칸 비트 검사이고 그중 거의 전부가 "이미 봤다"로 즉시 걸러진다
## (한 칸 옮기면 새로 들어오는 것은 한 줄뿐이다). 광선도 Callable도 없다.
func reveal_rect(floor_index: int, def: MapDefinition, rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var buf := bits(floor_index, def)
	var y0 := maxi(rect.position.y, 0)
	var y1 := mini(rect.end.y, def.height)
	var x0 := maxi(rect.position.x, 0)
	var x1 := mini(rect.end.x, def.width)
	for y in range(y0, y1):
		var row := y * def.width
		for x in range(x0, x1):
			var idx := row + x
			var byte := idx >> 3
			var mask := 1 << (idx & 7)
			if (buf[byte] & mask) != 0:
				continue
			buf[byte] = buf[byte] | mask
			out.append(Vector2i(x, y))
	return out


## 복구 보상 — 그 층 통행칸을 전부 밝힌다(백로그 §1.3 "안개가 걷힌다").
## 새로 밝힌 칸 수를 돌려준다. 분전반 스위치를 올리면 field.set_blackout이 부른다.
func reveal_all(floor_index: int, rt: MapRuntime) -> int:
	var def := rt.definition
	var n := 0
	for y in def.height:
		for x in def.width:
			var cell := Vector2i(x, y)
			if rt.is_passable(cell) and mark(floor_index, def, cell):
				n += 1
	return n


## 밝힌 통행칸 수 — 탐험률의 분자. 벽은 세지 않는다(걸을 수 있는 곳을 얼마나 봤나).
func seen_passable(floor_index: int, rt: MapRuntime) -> int:
	var def := rt.definition
	var n := 0
	for y in def.height:
		for x in def.width:
			var cell := Vector2i(x, y)
			if rt.is_passable(cell) and is_seen(floor_index, def, cell):
				n += 1
	return n


## 탐험률 분모 — 착지점에서 실제로 걸어 닿는 통행칸. 층당 한 번만 센다.
func reach_total(floor_index: int, rt: MapRuntime, start_anchor: Vector2i) -> int:
	if _reach_total.has(floor_index):
		return int(_reach_total[floor_index])
	var cells := {}
	for anchor: Vector2i in ReachProbe.reachable_anchors(rt, start_anchor):
		for c: Vector2i in Placement.body_cells(anchor):
			cells[c] = true
	_reach_total[floor_index] = cells.size()
	return cells.size()


## 0.0~1.0. 분모를 못 구하면(도달 판정 실패) -1.0 — 부르는 쪽이 숨긴다.
func explored_ratio(floor_index: int, rt: MapRuntime, start_anchor: Vector2i) -> float:
	var total := reach_total(floor_index, rt, start_anchor)
	if total <= 0:
		return -1.0
	return clampf(float(seen_passable(floor_index, rt)) / float(total), 0.0, 1.0)


## 이 층에서 밝힌 칸 수 — **MapDefinition 없이** 센다.
## 연속 주행(autoplay)이 층을 떠난 뒤에도 보고할 수 있어야 하기 때문이다.
## 배선이 끊기면 0, 안개가 죽으면 13,000에 붙는다 — 어느 쪽이든 보고서에 드러난다.
func seen_cells(floor_index: int) -> int:
	if not _seen.has(floor_index):
		return 0
	var n := 0
	for b: int in _seen[floor_index]:
		while b != 0:
			n += b & 1
			b >>= 1
	return n


## 안개를 가진 층 목록(오름차순).
func floors_with_fog() -> Array[int]:
	var out: Array[int] = []
	for f: int in _seen:
		out.append(f)
	out.sort()
	return out


## 세이브용 — 층 → base64. 비트맵을 그대로 싣는다(층당 2,167자 안팎).
func to_data() -> Dictionary:
	var out := {}
	for floor_index: int in _seen:
		out[str(floor_index)] = Marshalls.raw_to_base64(_seen[floor_index])
	return out


## 불러오기 — 형식이 어긋난 칸은 조용히 버린다(세이브 호환: 이 키가 없으면 안개가 가득).
func restore(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for key: Variant in data:
		var buf := Marshalls.base64_to_raw(str(data[key]))
		if buf.is_empty():
			continue
		_seen[int(str(key))] = buf
