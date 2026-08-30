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

var _floor_chip: Label
var _lv_label: Label
var _hp: HudGauge
var _exp: HudGauge
var _money_label: Label
var _slot_bar: HudSlotBar
var _first_paint := true
var _pulse: Tween


func _ready() -> void:
	layer = 10
	add_child(_build_card())
	add_child(_build_hints())
	_slot_bar = HudSlotBar.new()
	add_child(_slot_bar)
	refresh()
	GameState.state_changed.connect(refresh)
	EventBus.floor_changed.connect(func(_f: int) -> void: refresh())
	GameState.inventory.changed.connect(_refresh_slots)
	_refresh_slots()


func _build_card() -> Control:
	var card := PanelContainer.new()
	card.name = "StatsPanel"
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.position = Vector2(MARGIN, MARGIN)
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", HudTheme.panel())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
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


## 층 배지 + LV/AP — 한 줄에 좌우로 붙인다.
func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)

	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", HudTheme.chip(HudTheme.ACCENT))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_floor_chip = HudTheme.label("", 12, HudTheme.TEXT_ON_ACCENT)
	chip.add_child(_floor_chip)
	header.add_child(chip)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_lv_label = HudTheme.label("", 12, HudTheme.TEXT)
	header.add_child(_lv_label)
	return header


func _build_money_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(HudTheme.label(tr("UI_HUD_MONEY"), 10, HudTheme.TEXT_MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_money_label = HudTheme.label("", 13, HudTheme.ACCENT)
	row.add_child(_money_label)
	return row


## 우상단 조작 힌트 — 항상 보이되 존재감은 낮게(초보 이탈 방지, 숙련자 방해 없음).
func _build_hints() -> Control:
	var chip := PanelContainer.new()
	chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# position이 아니라 offset으로 잡는다 — 우측 앵커에서 position은 왼쪽 변을 옮겨
	# 칩이 화면 밖으로 밀려 나간다. 폭은 내용대로 왼쪽으로 자란다.
	chip.offset_right = -MARGIN
	chip.offset_top = MARGIN
	chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	chip.grow_vertical = Control.GROW_DIRECTION_END
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 구판은 칩 전체를 0.55로 죽여 맵 무늬 위에서 글자가 읽히지 않았다.
	# 배경은 그대로 두고 글자만 낮춘다 — 존재감은 낮게, 가독성은 확보.
	chip.add_theme_stylebox_override("panel", HudTheme.panel(8, 7))
	chip.add_child(HudTheme.outlined_label(tr(HINTS_KEY), 10, HudTheme.TEXT_MUTED))
	return chip


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
