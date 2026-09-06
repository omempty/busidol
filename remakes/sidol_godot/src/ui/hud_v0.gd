class_name HudV0
extends CanvasLayer
## 필드 HUD — 좌상단 스탯 카드(층 배지·LV/AP·HP/EXP 게이지·골드) + 좌하단 아이템 슬롯 +
## 우상단 조작 힌트. 원작 8자리 숫자 스프라이트(Print_Information)의 현대판.
## 수치 상한은 growth.json 레벨 테이블에서 산출(하드코딩 금지, AGENTS.md).
## 배치 근거: docs/02_design/04_uiux_modernization.md §1 — 시야 중앙을 비우고 모서리로.

const BASE_HP := 50  # 원작 We 초기값(game_state 주석 근거)
const CARD_WIDTH := 226.0
const MARGIN := 12.0
const PULSE_ALPHA := 0.45
const PULSE_TIME := 0.55
## 조작 힌트 — InputMap 액션 실제 바인딩과 같은 순서(input_bootstrap.ACTIONS).
const HINTS_KEY := "UI_HUD_HINT"
## 트래커 문구는 **층이 아니라 퀘스트 사슬**이 정한다(QuestState).
## 2026-09-06까지 층 번호로 골랐고, 그래서 `UI_TRACKER_F1`이 "3층 화공과 사고 조사"인
## 채로 F1에서 3층을 가리키고 있었다. 층당 한 줄은 애초에 표현할 수 없는 것을
## 표현하려던 것이다 — 한 층에 퀘스트가 여럿이고 순서도 있다.

var _floor_chip: Label
var _lv_label: Label
var _hp: HudGauge
var _exp: HudGauge
var _money_label: Label
var _slot_bar: HudSlotBar
var _tracker_label: Label
var _first_paint := true
var _pulse: Tween


func _ready() -> void:
	layer = 10
	add_child(_build_card())
	add_child(_build_hints_and_tracker())
	_slot_bar = HudSlotBar.new()
	add_child(_slot_bar)
	_slot_bar.slot_activated.connect(_on_slot_activated)
	refresh()
	GameState.state_changed.connect(refresh)
	EventBus.floor_changed.connect(func(_f: int) -> void: refresh())
	GameState.inventory.changed.connect(_refresh_slots)
	_refresh_slots()


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or not is_inside_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_6:
			var idx: int = event.keycode - KEY_1
			_on_slot_activated(idx)


func _on_slot_activated(idx: int) -> void:
	var slots := GameState.inventory.all_slots()
	if idx < 0 or idx >= slots.size():
		return
	var item_id := StringName(str(slots[idx]["item_id"]))
	var def := Database.get_item(item_id)
	if ItemEffects.is_usable(def, false):
		var note := ItemEffects.use_on_field(def)
		if not note.is_empty():
			GameState.inventory.remove(item_id, 1)
			refresh()
	elif str(def.get("kind", "")) in ["weapon", "armor"]:
		GameState.equip(item_id)
		refresh()


func _build_card() -> Control:
	var card := PanelContainer.new()
	card.name = "StatsPanel"
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.position = Vector2(MARGIN, MARGIN)
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", HudTheme.panel(8, 10))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	card.add_child(vbox)
	vbox.add_child(_build_header())

	_hp = HudGauge.new()
	vbox.add_child(_hp)
	_hp.setup("HP", HudTheme.HP_OK)

	_exp = HudGauge.new()
	vbox.add_child(_exp)
	_exp.setup("EXP", HudTheme.EXP)

	vbox.add_child(_build_money_row())
	return card


## 층 배지 + 캐릭터명 + LV/AP — 현대적 레이아웃
func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)

	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", HudTheme.chip(HudTheme.ACCENT, 4, 6, 2))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_floor_chip = HudTheme.label("", 11, HudTheme.TEXT_ON_ACCENT)
	chip.add_child(_floor_chip)
	header.add_child(chip)

	var name_lbl := HudTheme.label("시돌", 12, HudTheme.ACCENT)
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(name_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_lv_label = HudTheme.label("", 11, HudTheme.TEXT)
	header.add_child(_lv_label)
	return header


func _build_money_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(HudTheme.label(tr("UI_HUD_MONEY"), 10, HudTheme.TEXT_MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_money_label = HudTheme.label("", 12, HudTheme.ACCENT)
	row.add_child(_money_label)
	return row


## 우상단 조작 힌트 + 스마트 퀘스트 트래커
func _build_hints_and_tracker() -> Control:
	var top_right := VBoxContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.offset_right = -MARGIN
	top_right.offset_top = MARGIN
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.grow_vertical = Control.GROW_DIRECTION_END
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.add_theme_constant_override("separation", 6)

	# 1) 조작 힌트 칩
	var hint_chip := PanelContainer.new()
	hint_chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	hint_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_chip.add_theme_stylebox_override("panel", HudTheme.panel(6, 6))
	hint_chip.add_child(HudTheme.outlined_label(tr(HINTS_KEY), 10, HudTheme.TEXT_MUTED))
	top_right.add_child(hint_chip)

	# 2) 스마트 퀘스트 트래커 카드
	var tracker_card := PanelContainer.new()
	tracker_card.size_flags_horizontal = Control.SIZE_SHRINK_END
	tracker_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracker_card.add_theme_stylebox_override("panel", HudTheme.panel(6, 8))
	var tr_box := VBoxContainer.new()
	tr_box.add_theme_constant_override("separation", 2)
	tracker_card.add_child(tr_box)

	var tr_head := HBoxContainer.new()
	tr_head.add_theme_constant_override("separation", 4)
	tr_head.add_child(HudTheme.label("⚔️ " + tr("UI_HUD_TRACKER_TITLE"), 10, HudTheme.ACCENT))
	tr_box.add_child(tr_head)

	_tracker_label = HudTheme.label("", 11, HudTheme.TEXT)
	tr_box.add_child(_tracker_label)
	top_right.add_child(tracker_card)

	return top_right


func _refresh_slots() -> void:
	if _slot_bar != null:
		_slot_bar.refresh(GameState.inventory.all_slots())


func refresh() -> void:
	var stats: Dictionary = GameState.player_stats
	var level := int(stats.get("level", 1))
	var animate := not _first_paint
	_first_paint = false

	_floor_chip.text = "F%d" % GameState.current_floor
	_lv_label.text = "LV %d   AP %d" % [level, int(stats.get("ap", 0))]

	var max_hp := _max_hp(level)
	var hp := clampi(int(stats.get("hp", 0)), 0, max_hp)
	var hp_ratio := float(hp) / float(max_hp)
	_hp.set_value_text("%d / %d" % [hp, max_hp])
	_hp.set_hp(hp_ratio, animate)
	_set_low_hp_pulse(hp_ratio < HudTheme.HP_LOW_AT and hp > 0)

	var span := _exp_span(level, int(stats.get("exp", 0)))
	_exp.set_value_text(str(span["text"]))
	_exp.set_ratio(float(span["ratio"]), animate)

	_money_label.text = HudTheme.money(int(stats.get("money", 0)))

	if _tracker_label != null:
		_tracker_label.text = QuestState.tracker_line()


## 현재 레벨 최대 HP — 초기값 + 레벨 테이블 hp_up 누적(growth.json).
func _max_hp(level: int) -> int:
	var total := BASE_HP
	for entry: Dictionary in Database.level_table():
		if int(entry.get("level", 0)) <= level:
			total += int(entry.get("hp_up", 0))
	return maxi(total, 1)


## 현재 레벨 구간 내 경험치 진척도. 구판은 0 또는 1만 찍어 게이지가 늘 비어 있었다.
func _exp_span(level: int, cur_exp: int) -> Dictionary:
	var floor_exp := _exp_accum(level)
	var next_exp := _exp_accum(level + 1)
	if next_exp < 0:
		return {"ratio": 1.0, "text": "MAX"}
	var span := maxi(next_exp - floor_exp, 1)
	var gained := clampi(cur_exp - floor_exp, 0, span)
	return {"ratio": float(gained) / float(span), "text": tr("UI_HUD_NEXT_LEVEL") % (span - gained)}


## 레벨 진입 누적 경험치 — 테이블에 없는 레벨(만렙 초과)은 -1.
func _exp_accum(level: int) -> int:
	for entry: Dictionary in Database.level_table():
		if int(entry.get("level", 0)) == level:
			return int(entry.get("exp_accum", 0))
	return -1


## 빈사 상태에서 HP 게이지가 천천히 명멸한다 — 수치를 안 읽어도 위험이 보인다.
func _set_low_hp_pulse(on: bool) -> void:
	var running := _pulse != null and _pulse.is_valid()
	if on == running:
		return
	if not on:
		_pulse.kill()
		_hp.modulate.a = 1.0
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_hp, "modulate:a", PULSE_ALPHA, PULSE_TIME)
	_pulse.tween_property(_hp, "modulate:a", 1.0, PULSE_TIME)
