class_name InteractProbe
extends RefCounted
## 조사 판정의 **단일 소스** — SPACE를 눌렀을 때 어느 칸이 반응하는가.
##
## 게임(field)과 도구(autoplay·sweep·world_audit)가 **같은 함수를 물어봐야** 한다.
## 한쪽이 따로 계산하기 시작하면 "도구는 닿는다는데 게임은 아니라고 한다"가 생기고,
## 그 순간 자동 보고서를 믿을 수 없게 된다.
##
## 판정 모양 — 2×2 몸이 바라보는 변 앞의 **정면 2칸이 먼저, 그 다음 어깨 2칸**이다.
## 전에는 정면 2칸만 봤다. 그래서 상자·NPC와 반 칸 어긋나 서면 바로 앞에 두고도
## 아무 반응이 없었고, "충돌 체크가 애매하다"는 인상이 여기서 났다(2026-08-29 유저
## 지적). 어깨를 더하면 요즘 게임처럼 "대충 그쪽을 보고 누르면 잡힌다"가 된다.
## 우선순위가 있으므로 넓혀도 엉뚱한 것이 먼저 잡히지는 않는다 — 정면이 늘 이긴다.
##
##       ↑ 바라보는 방향
##     ┌───┬───┬───┬───┐
##     │ 어│ 정│ 정│ 어│   정 = 정면 2칸(1순위)
##     └───┴───┴───┴───┘   어 = 어깨 2칸(2순위)
##       ┌───┬───┐
##       │ 몸│ 몸│
##       └───┴───┘


## 조사 후보 셀 — **우선순위 순서대로** 돌려준다. 부르는 쪽은 앞에서부터 확인하고
## 첫 번째로 걸리는 것을 대상으로 삼으면 된다.
static func probe_cells(mover: GridMover, anchor: Vector2i, facing: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = mover.edge_cells(anchor, facing)
	if out.is_empty():
		return out
	# 어깨 — 정면 줄의 양옆 한 칸씩. 바라보는 축과 직각 방향으로 벌린다.
	var side := Vector2i(facing.y, facing.x)
	if side == Vector2i.ZERO:
		return out
	out.append(out[0] - side)
	out.append(out[out.size() - 2] + side)
	return out
