class_name HudGauge
extends Control
## HUD 게이지 한 줄 — 바 위에 캡션(좌)·수치(우)를 겹쳐 얹는다.
## 캡션·수치·바를 각각 한 줄씩 쓰던 구판 대비 세로 공간 ⅓, 시선 이동 없음.
## 값 변화는 트윈으로 흘려 준다(피격/획득이 눈에 남는다).

const HEIGHT := 18.0
const FILL_TRANSITION := 0.28
const SIDE_PAD := 7.0

var _bar: ProgressBar
var _caption: Label
var _value: Label
var _fill_color := Color.WHITE
var _tween: Tween


func setup(caption: String, fill_color: Color) -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_theme_stylebox_override("background", HudTheme.sunken())
	add_child(_bar)
	set_fill(fill_color)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = SIDE_PAD
	row.offset_right = -SIDE_PAD
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	_caption = HudTheme.outlined_label(caption, 10, Color(HudTheme.TEXT, 0.85))
	row.add_child(_caption)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_value = HudTheme.outlined_label("", 11, HudTheme.TEXT)
	row.add_child(_value)


func set_fill(color: Color) -> void:
	if _fill_color.is_equal_approx(color):
		return
	_fill_color = color
	_bar.add_theme_stylebox_override("fill", HudTheme.fill(color))


func set_value_text(text: String) -> void:
	_value.text = text


## ratio 0~1. animate=false는 씬 진입 첫 표시용(빈 게이지가 차오르는 연출 방지).
func set_ratio(ratio: float, animate: bool = true) -> void:
	var target := clampf(ratio, 0.0, 1.0)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not animate:
		_bar.value = target
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_bar, "value", target, FILL_TRANSITION)
