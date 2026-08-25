class_name HudV0
extends CanvasLayer
## HUD — 우측 상단 패널(층/LV/AP + HP·EXP 게이지 + GOLD). 원작 8자리 숫자 스프라이트의 현대판.
## 수치 상한은 growth.json 레벨 테이블에서 산출(하드코딩 금지, AGENTS.md).
## 품질 기준(docs/03_plan Phase 1): 처음부터 Control 포커스 내비 구조를 전제로 설계.

const BASE_HP := 50   # 원작 We 초기값(game_state 주석 근거)
const SLOT_COUNT := 6
const SLOT_SIZE := 40.0

var _floor_label: Label
var _lv_label: Label
var _hp_value: Label
var _exp_value: Label
var _money_label: Label
var _hp_bar: ProgressBar
var _exp_bar: ProgressBar
var _slot_bar: HBoxContainer


func _ready() -> void:
	layer = 10
	add_child(_build_panel())
	add_child(_build_slot_bar())
	refresh()
	GameState.state_changed.connect(refresh)
	EventBus.floor_changed.connect(func(_f: int) -> void: refresh())
	GameState.inventory.changed.connect(_refresh_slots)
	_refresh_slots()


func _build_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "StatsPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-196, 10)
	panel.custom_minimum_size = Vector2(186, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# 헤더 — 층 배지 / LV·AP
	var header := HBoxContainer.new()
	vbox.add_child(header)
	_floor_label = _label("", 15, Color(1.0, 0.8, 0.35))
	header.add_child(_floor_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_lv_label = _label("", 13, Color(1, 1, 1, 0.9))
	header.add_child(_lv_label)

	# HP 게이지
	vbox.add_child(_caption_row("HP"))
	_hp_value = _label("", 12, Color(1, 1, 1, 0.75))
	_hp_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_hp_value)
	_hp_bar = _bar(Color(0.36, 0.82, 0.45))
	vbox.add_child(_hp_bar)

	# EXP 게이지
	vbox.add_child(_caption_row("EXP"))
	_exp_value = _label("", 11, Color(1, 1, 1, 0.55))
	_exp_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_exp_value)
	_exp_bar = _bar(Color(0.5, 0.7, 0.98))
	vbox.add_child(_exp_bar)

	# 골드
	vbox.add_child(_caption_row("GOLD"))
	_money_label = _label("", 14, Color(1.0, 0.87, 0.4))
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_money_label)
	return panel


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.82)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	return sb


func _caption_row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_label(text, 11, Color(1, 1, 1, 0.45)))
	return row


## 좌하단 상시 아이템 슬롯 — 소지품 앞 6칸(kind 색 플레이스홀더 아이콘+수량).
func _build_slot_bar() -> Control:
	_slot_bar = HBoxContainer.new()
	_slot_bar.add_theme_constant_override("separation", 6)
	_slot_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_slot_bar.offset_left = 12
	_slot_bar.offset_top = -12.0 - SLOT_SIZE
	return _slot_bar


func _refresh_slots() -> void:
	if _slot_bar == null:
		return
	for child in _slot_bar.get_children():
		child.queue_free()
	var slots := GameState.inventory.all_slots()
	for i in SLOT_COUNT:
		if i < slots.size():
			_slot_bar.add_child(_make_slot(slots[i]))
		else:
			_slot_bar.add_child(_make_empty_slot())
	if slots.size() > SLOT_COUNT:
		var more := Label.new()
		more.text = "+%d" % (slots.size() - SLOT_COUNT)
		more.add_theme_font_size_override("font_size", 11)
		more.modulate = Color(1, 1, 1, 0.55)
		_slot_bar.add_child(more)


func _make_slot(slot: Dictionary) -> PanelContainer:
	var item_def := Database.get_item(StringName(str(slot["item_id"])))
	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	icon.tooltip_text = str(item_def.get("name_ko", slot["item_id"]))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(ItemIcons.kind_color(
			StringName(str(item_def.get("kind", "")))), 0.9)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)
	icon.add_theme_stylebox_override("panel", sb)
	var glyph := Label.new()
	glyph.text = ItemIcons.glyph(item_def)
	glyph.add_theme_font_size_override("font_size", 18)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_child(glyph)
	var count := Label.new()
	count.text = "×%d" % int(slot["count"])
	count.add_theme_font_size_override("font_size", 10)
	count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -22
	count.offset_top = -14
	count.modulate = Color(1, 1, 1, 0.85)
	icon.add_child(count)
	return icon


func _make_empty_slot() -> PanelContainer:
	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.35)
	sb.border_color = Color(1, 1, 1, 0.1)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)
	icon.add_theme_stylebox_override("panel", sb)
	return icon


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _bar(fill_color: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 7)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fill)
	return pb


## 현재 레벨 최대 HP — 초기값 + 레벨 테이블 hp_up 누적(growth.json).
func _max_hp(level: int) -> int:
	var total := BASE_HP
	for entry: Dictionary in Database.level_table():
		if int(entry.get("level", 0)) <= level:
			total += int(entry.get("hp_up", 0))
	return maxi(total, 1)


## 다음 레벨 요구 경험치 — 만렙이면 -1.
func _next_exp(level: int, cur_exp: int) -> int:
	for entry: Dictionary in Database.level_table():
		if int(entry.get("level", 0)) == level + 1:
			return maxi(int(entry.get("exp_accum", 0)) - cur_exp, 0)
	return -1


func refresh() -> void:
	var stats: Dictionary = GameState.player_stats
	var level := int(stats.get("level", 1))

	_floor_label.text = "F%d" % GameState.current_floor
	_lv_label.text = "LV %d  ·  AP %d" % [level, int(stats.get("ap", 0))]

	var max_hp := _max_hp(level)
	var hp := clampi(int(stats.get("hp", 0)), 0, max_hp)
	_hp_value.text = "%d/%d" % [hp, max_hp]
	_hp_bar.value = float(hp) / float(max_hp)
	# 위험 구간(30% 미만) 게이지 색 전환
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.88, 0.32, 0.3) if _hp_bar.value < 0.3 \
			else Color(0.36, 0.82, 0.45)
	fill.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("fill", fill)

	var need := _next_exp(level, int(stats.get("exp", 0)))
	if need < 0:
		_exp_value.text = "MAX"
		_exp_bar.value = 1.0
	else:
		_exp_value.text = "다음 레벨까지 %d" % need
		_exp_bar.value = 1.0 if need == 0 else 0.0

	_money_label.text = "%d G" % int(stats.get("money", 0))
