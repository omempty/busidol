extends RefCounted
## 자동 주행의 길찾기 — **게임의 실제 이동 그래프**에 그대로 묻는다.
##
## 공용 `_godot_shared/godot/autoplay/grid_navigator.gd` 를 쓰지 않는 이유: 이 게임의
## 이동에는 걸음 말고 **문 통과**가 있다(발밑/머리 위 ATT 9 두 셀 → 3칸 점프,
## TransitionGate._try_door). 걸음만 모델링하면 문 너머 방이 통째로 "도달 불가"로
## 잡힌다 — 실제로 첫 시험 주행에서 지하(f0)가 그렇게 보였다.
##
## 그 규칙을 아는 판정기는 이미 저장소에 있다(`ReachProbe.neighbors`). 판정을 두 벌
## 두면 "도구는 갈 수 있다는데 게임은 못 간다"가 쏟아지므로 그것을 그대로 쓴다.

## 한 목표를 향해 이만큼 넘게 헤매면 포기한다(무한 탐색 방지).
const MAX_PATH := 400

var rt: MapRuntime

var _fits: Dictionary = {}
## 되짚어 경로를 만들기 위한 부모 포인터 — 마지막 `reachable_from` 기준.
var _parent: Dictionary = {}


func _init(runtime: MapRuntime) -> void:
	rt = runtime


## 2×2 몸이 통째로 들어가는가. 칸 하나에 통행 판정 4번이라 결과를 쌓아 둔다 —
## 1만 3천 칸 × 목표 수백 개면 캐시 없이는 도구가 끝나지 않는다.
func fits(anchor: Vector2i) -> bool:
	if _fits.has(anchor):
		return bool(_fits[anchor])
	var value := Placement.body_fits(rt, anchor)
	_fits[anchor] = value
	return value


## `start` 에서 걸어 닿는 앵커 전부. 값은 **걸음 수**다.
##
## 경로 자체는 넣지 않는다 — 앵커마다 경로 배열을 통째로 복제하면 앵커 6천 개 × 경로
## 수십 칸이라 조회 한 번에 수십만 원소를 베낀다(1200초 주행에서 그 조회가 수백 번이다).
## 대신 부모 포인터만 남기고 `path_to`에서 되짚는다.
##
## 경로 한 칸이 걸음 하나지만 **문 통과는 3칸을 건너뛴다** — 부르는 쪽이 칸 사이
## 거리를 보고 걸음인지 문인지 가린다.
func reachable_from(start: Vector2i) -> Dictionary:
	_parent = {start: start}
	var distance: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var here: Vector2i = queue[head]
		head += 1
		var step := int(distance[here])
		if step >= MAX_PATH:
			continue
		for next: Vector2i in ReachProbe.neighbors(rt, here):
			if distance.has(next) or not fits(next):
				continue
			_parent[next] = here
			distance[next] = step + 1
			queue.append(next)
	return distance


## 그 앵커까지의 경로(시작 앵커 제외). 못 가면 빈 배열.
func path_to(reachable: Dictionary, anchor: Vector2i) -> Array:
	if not reachable.has(anchor):
		return []
	var path: Array = []
	var here := anchor
	while _parent.has(here) and _parent[here] != here:
		path.append(here)
		here = _parent[here]
	path.reverse()
	return path
