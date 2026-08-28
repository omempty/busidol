class_name BatteryCircuitMinigame
extends CanvasLayer
## 배터리 회로 퍼즐 — 슬롯에 건전지를 넣어 직렬 합계 × 과충전 배율 = 목표 전압.
## 입력: ←→ 커서, ↑↓ 전압 순환(빈칸→denominations), SPACE(interact) 레버 단수 증가.
## 회로가 정확히 일치하는 순간 자동 통과. 설정은 전부 data/minigames/*.json.

signal finished(passed: bool)

const PANEL_POS := Vector2(230, 190)  ## 960×540 중앙 정렬
const PANEL_SIZE := Vector2(500, 160)

var _cfg: Dictionary = {}
var _vals: Array[int] = []  # 각 슬롯 전압 (0 = 빈칸)
var _cursor := 0
var _lever := 1
var _active := false

var _slots_lbl: Label
var _info_lbl: Label


func _ready() -> void:
	layer = 45
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.08, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.position = PANEL_POS
	panel.custom_minimum_size = PANEL_SIZE
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var title := Label.new()
	title.text = tr("UI_BATTERY_TITLE")
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(title)
	_slots_lbl = Label.new()
	_slots_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_slots_lbl)
	_info_lbl = Label.new()
	_info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_info_lbl)


func start(config: Dictionary) -> void:
	_cfg = config
	_vals.clear()
	for i in int(config.get("slots", 6)):
		_vals.append(0)
	_cursor = 0
	_lever = 1
	_active = true
	visible = true
	_refresh()


func is_active() -> bool:
	return _active


func total_voltage() -> int:
	var s := 0
	for v in _vals:
		s += v
	return s * _lever


func _input(event: InputEvent) -> void:
	if not _active:
		return
	var dens: Array = _cfg.get("denominations", [10, 100])
	if event.is_action_pressed(&"move_left"):
		_cursor = (_cursor - 1 + _vals.size()) % _vals.size()
	elif event.is_action_pressed(&"move_right"):
		_cursor = (_cursor + 1) % _vals.size()
	elif event.is_action_pressed(&"move_up"):
		_cycle_slot(dens, -1)
	elif event.is_action_pressed(&"move_down"):
		_cycle_slot(dens, 1)
	elif event.is_action_pressed(&"interact"):
		var lmax := maxi(int(_cfg.get("lever_max", 10)), 1)
		_lever = _lever % lmax + 1
	else:
		return
	_refresh()


func _cycle_slot(dens: Array, dir: int) -> void:
	# 순환 계열: 0 → den[0] → ... → den[n-1] → 0
	var series := [0]
	for d: Variant in dens:
		series.append(int(d))
	var idx := series.find(_vals[_cursor])
	idx = (idx + dir + series.size()) % series.size()
	_vals[_cursor] = series[idx]


func _refresh() -> void:
	var parts: Array[String] = []
	for i in _vals.size():
		var txt := "[ ]" if _vals[i] == 0 else "[%dV]" % _vals[i]
		parts.append("> " + txt if i == _cursor else "  " + txt)
	_slots_lbl.text = " ".join(parts)
	_info_lbl.text = (
		(tr("UI_BATTERY_HINT") + "\n" + tr("UI_BATTERY_HINT2"))
		% [
			total_voltage() / _lever if _lever > 0 else 0,
			_lever,
			total_voltage(),
			int(_cfg.get("target_voltage", 0))
		]
	)
	if total_voltage() == int(_cfg.get("target_voltage", 0)):
		_active = false
		visible = false
		finished.emit(true)
