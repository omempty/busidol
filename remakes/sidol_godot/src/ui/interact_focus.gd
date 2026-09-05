class_name InteractFocus
extends Node2D
## 조사 대상 표시 — 지금 SPACE를 누르면 무엇이 반응하는지 칸으로 보여 준다.
##
## 알약(InteractPrompt)만으로는 **어느 칸이 대상인지**가 안 보였다. 2×2 몸으로
## 서는 위치에 따라 상자 두 개가 나란히 있으면 어느 쪽이 열릴지 알 수 없다
## (2026-08-29 유저 지적: "충돌 체크가 애매하다"). 판정은 그대로 두고 **보이게만** 한다.

const Z := 35  # 액터 위, 알약(40) 아래
const PULSE_HZ := 2.2
const INSET := 2.0

var _cells: Array[Vector2i] = []
var _phase := 0.0


func _ready() -> void:
	z_index = Z
	visible = false


## 대상 칸들을 표시한다. 같은 칸 목록이면 위상(깜빡임)을 유지해 끊기지 않는다.
## 개발자 모드가 꺼져 있으면(기본) 표시하지 않는다 — 평시 화면의 디버그感이 지적됐다.
func show_cells(cells: Array[Vector2i]) -> void:
	if not SettingsManager.developer_mode:
		clear()
		return
	if cells.is_empty():
		clear()
		return
	if cells != _cells:
		_cells = cells.duplicate()
		queue_redraw()
	visible = true


func clear() -> void:
	if not visible:
		return
	visible = false
	_cells.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_phase += delta
	queue_redraw()


func _draw() -> void:
	if _cells.is_empty():
		return
	var alpha := 0.35 + 0.25 * sin(_phase * TAU * PULSE_HZ * 0.5)
	var px := float(MapDefinition.TILE_PX)
	# 셀 낱개가 아니라 몸통 전체를 하나의 선택틀로 — 낱개 4칸은 충돌 디버그처럼 보인다.
	var lo := _cells[0]
	var hi := _cells[0]
	for cell: Vector2i in _cells:
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	var r := Rect2(
		Vector2(lo) * px + Vector2(INSET, INSET),
		(Vector2(hi - lo) + Vector2.ONE) * px - Vector2(INSET, INSET) * 2.0
	)
	draw_rect(r, Color(HudTheme.ACCENT, alpha * 0.10), true)
	draw_rect(r, Color(HudTheme.ACCENT, alpha), false, 2.0)
