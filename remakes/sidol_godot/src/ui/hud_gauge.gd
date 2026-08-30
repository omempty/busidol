class_name HudGauge
extends Control
## HUD 게이지 한 줄 — 바 위에 캡션(좌)·수치(우)를 겹쳐 얹는다.
## 캡션·수치·바를 각각 한 줄씩 쓰던 구판 대비 세로 공간 ⅓, 시선 이동 없음.
## 값 변화는 트윈으로 흘려 준다(피격/획득이 눈에 남는다).

const HEIGHT := 18.0
const FILL_TRANSITION := 0.28
const SIDE_PAD := 7.0
## 색각 무늬(Q9) — 단계마다 **모양이 다르다.** 색만 바꾸면 적록색약에서 경고가 안 읽힌다.
## 0=없음(안전) · 1=사선(주의) · 2=교차(위험). 채워진 구간에만 그린다.
enum Pattern { NONE, DIAGONAL, CROSS }
const PATTERN_GAP := 6.0
const PATTERN_WIDTH := 1.6
const PATTERN_ALPHA := 0.5

var _bar: ProgressBar
var _pattern_layer: Control
var _pattern: Pattern = Pattern.NONE
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

	# 무늬 판은 바 위·글자 아래. 글자를 가리면 수치가 안 읽힌다.
	_pattern_layer = Control.new()
	_pattern_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pattern_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pattern_layer.draw.connect(_draw_pattern)
	add_child(_pattern_layer)
	move_child(_pattern_layer, 1)  # _bar 바로 위


## HP 게이지 한 번에 세우기 — 색과 무늬가 **같은 곳에서** 정해져야 둘이 어긋나지 않는다.
func set_hp(ratio: float, animate: bool = true) -> void:
	set_fill(HudTheme.hp_color(ratio))
	_pattern = HudTheme.hp_pattern(ratio) as Pattern
	set_ratio(ratio, animate)
	_pattern_layer.queue_redraw()


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
	# 채워진 폭이 트윈으로 움직이는 동안 무늬도 같이 따라와야 한다.
	_tween.parallel().tween_method(
		func(_v: float) -> void: _pattern_layer.queue_redraw(), 0.0, 1.0, FILL_TRANSITION
	)


## 채워진 구간 위에 무늬를 긋는다. 설정이 꺼져 있거나 안전 단계면 아무것도 안 그린다.
func _draw_pattern() -> void:
	if _pattern == Pattern.NONE or not SettingsManager.colorblind_patterns:
		return
	var w := _pattern_layer.size.x * float(_bar.value)
	var h := _pattern_layer.size.y
	if w <= 1.0 or h <= 1.0:
		return
	var ink := Color(0, 0, 0, PATTERN_ALPHA)
	# 사선(↘) — 위험 단계에서는 반대 사선을 겹쳐 교차 무늬가 된다.
	var x := -h
	while x < w:
		_line_clipped(Vector2(x, 0), Vector2(x + h, h), w, ink)
		if _pattern == Pattern.CROSS:
			_line_clipped(Vector2(x + h, 0), Vector2(x, h), w, ink)
		x += PATTERN_GAP


## 채워진 폭(w)을 넘는 부분은 그리지 않는다 — 빈 구간까지 무늬가 나가면 게이지가 안 읽힌다.
func _line_clipped(from: Vector2, to: Vector2, w: float, ink: Color) -> void:
	if maxf(from.x, to.x) <= 0.0 or minf(from.x, to.x) >= w:
		return
	_pattern_layer.draw_line(
		Vector2(clampf(from.x, 0.0, w), from.y),
		Vector2(clampf(to.x, 0.0, w), to.y),
		ink,
		PATTERN_WIDTH
	)
