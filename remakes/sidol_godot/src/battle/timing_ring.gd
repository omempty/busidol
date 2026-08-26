class_name TimingRing
extends Node2D
## 타이밍 버튼 링(timed hit) — 수축하는 링이 sweet zone(후반 40%)에 들 때
## ui_accept(Enter/Space) 또는 마우스 좌클릭하면 성공.
## 윈도우·배율 데이터: data/skills.json timing 섹션.

signal resolved(success: bool)

const RADIUS_MAX := 46.0
const RADIUS_MIN := 10.0
const SWEET_FROM := 0.6  ## 경과율 60% 이상 = sweet zone

var window := 0.45
var _elapsed := 0.0
var _done := false


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	queue_redraw()
	if Input.is_action_just_pressed(&"ui_accept") or Input.is_mouse_button_pressed(
		MOUSE_BUTTON_LEFT
	):
		_finish(_elapsed / window >= SWEET_FROM)
	elif _elapsed >= window:
		_finish(false)


func _finish(success: bool) -> void:
	_done = true
	resolved.emit(success)
	queue_free()


func _draw() -> void:
	var t := clampf(_elapsed / window, 0.0, 1.0)
	var radius := lerpf(RADIUS_MAX, RADIUS_MIN, t)
	var col := Color(1.0, 0.92, 0.35) if t >= SWEET_FROM else Color(0.8, 0.85, 1.0, 0.7)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, col, 3.0)
	draw_arc(Vector2.ZERO, RADIUS_MIN, 0.0, TAU, 24, Color(1, 1, 1, 0.5), 1.5)
