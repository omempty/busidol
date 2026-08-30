class_name BattleUI
extends CanvasLayer
## 전투 UI 계층 — 상태 카드(플레이어·적)·턴 칩·커맨드/기술/도구 메뉴·결과 배지.
## 로직(BattleSceneController)과 분리. 선택은 시그널로만 통지한다.
##
## 2026-08-28 재작성(캡처 실측 근거):
## - **커맨드를 키보드로 고를 수 없었다.** Button만 있고 포커스를 주는 코드가 0곳이라
##   필드·가방·상점이 전부 키보드인데 전투만 마우스를 요구했다 → 커서 목록으로 교체.
## - **번역된 문자열로 분기하고 있었다**(`match cmd_text: "공격"`). 영어로 바꾸면
##   전투 커맨드가 통째로 먹통이 된다 → 시그널이 번역 불변 id를 넘긴다.
## - 상태 표기가 이름 라벨 + 벌거벗은 ProgressBar였다 → HUD와 같은 카드 규격으로.

signal command_selected(cmd_id: StringName)
signal skill_selected(skill: Dictionary)
signal item_selected(item_def: Dictionary)
## 단축키 — 대상 전환(Q/E)과 직전 행동 반복(R). 컨트롤러가 처리한다.
signal target_cycled(direction: int)
signal repeat_requested

## 커맨드 id ↔ 표시 키. id는 번역과 무관한 계약값(컨트롤러가 이걸로 분기한다).
const COMMANDS: Array[Dictionary] = [
	{"id": &"attack", "key": "UI_BATTLE_CMD_ATTACK"},
	{"id": &"skill", "key": "UI_BATTLE_CMD_SKILL"},
	{"id": &"guard", "key": "UI_BATTLE_CMD_GUARD"},
	{"id": &"item", "key": "UI_BATTLE_CMD_ITEM"},
	{"id": &"flee", "key": "UI_BATTLE_CMD_FLEE"},
]
## 숫자 단축키로 바로 고를 수 있는 항목 수(1~9). 그 뒤 항목은 커서로 간다.
const SLOT_KEYS := 9
const MENU_MARGIN := 16.0
const MENU_WIDTH := 168.0
## 적 카드 폭은 슬롯 간격(100px)보다 좁아야 한다 — 넓게 잡았더니 2체 이상일 때
## 카드끼리 겹쳐 뒤쪽 적의 HP가 가려졌다(2026-08-28 캡처).
const ENEMY_CARD_WIDTH := 94.0
const ENEMY_SLOT_X := 600.0  # BattlePresenter의 적 스프라이트 x 기준
const ENEMY_SLOT_STEP := 100.0
const PLAYER_CARD := Vector2(220, 0)

var _hp_gauges := {}  # Combatant | &"player" -> HudGauge
var _break_bars := {}  # 적별 브레이크 게이지 — 약점 보유 종만 생성
var _status_rows := {}  # 전투원별 상태이상 칩 줄(플레이어는 &"player" 키)
var _turn_label: Label
var _result_label: Label
var _result_panel: PanelContainer
var _player_ap: Label
var _menu_panel: PanelContainer
var _menu_rows: Array[Control] = []
var _menu_cursors: Array[Label] = []
var _menu_entries: Array[Dictionary] = []
var _menu_index := 0
var _menu_kind := &""
var _disabled_commands: Dictionary = {}  # 커맨드 id → true면 흐리게 + 선택 불가
var _skills: Array[Dictionary] = []
var _player: Combatant
var _enemies: Array[Combatant] = []
var _enemy_cards: Array[PanelContainer] = []  # 대상 강조용
var _target_index := 0


func build(p_player: Combatant, p_enemies: Array[Combatant], skills: Array[Dictionary]) -> void:
	layer = 20
	_player = p_player
	_enemies = p_enemies
	_skills = skills
	_build_background()
	_build_enemy_status()
	_build_player_status()
	_build_labels()
	refresh_bars()


func refresh_bars() -> void:
	for e in _enemies:
		if _hp_gauges.has(e):
			_set_gauge(_hp_gauges[e], e.hp, e.max_hp)
		if _break_bars.has(e):
			_refresh_break(e)
	if _hp_gauges.has(&"player"):
		_set_gauge(_hp_gauges[&"player"], _player.hp, _player.max_hp)
	if _player_ap != null:
		_player_ap.text = "AP %d   DP %d" % [_player.attack_stat(), _player.dp]
	_refresh_status()


## 현재 대상 강조 — Q/E로 바뀐 대상을 화면이 즉시 보여 준다.
func set_target(index: int) -> void:
	_target_index = index
	for i in _enemy_cards.size():
		var card := _enemy_cards[i]
		if not is_instance_valid(card):
			continue
		if i == index:
			card.add_theme_stylebox_override("panel", HudTheme.chip(HudTheme.ROW_SELECTED, 8, 7, 3))
		else:
			card.add_theme_stylebox_override("panel", HudTheme.panel(8, 7))


func _set_gauge(gauge: HudGauge, hp: int, max_hp: int) -> void:
	var ratio := float(maxi(hp, 0)) / float(maxi(max_hp, 1))
	gauge.set_value_text("%d / %d" % [maxi(hp, 0), max_hp])
	gauge.set_hp(ratio)


## 상태이상 칩 갱신 — HP와 같은 시점에 돈다(부착·해제·턴 감소가 여기서 보인다).
func _refresh_status() -> void:
	for e in _enemies:
		if _status_rows.has(e):
			StatusChips.refresh(_status_rows[e], e.active_effects)
	if _status_rows.has(&"player"):
		StatusChips.refresh(_status_rows[&"player"], _player.active_effects)


## 브레이크 게이지 — ASCII 핍("[#-]")이던 것을 칸 게이지로. 브레이크 중에는 색과 문구로 알린다.
func _refresh_break(e: Combatant) -> void:
	var row: HBoxContainer = _break_bars[e]
	var broken := e.is_broken()
	for i in row.get_child_count():
		var pip := row.get_child(i) as PanelContainer
		var filled := i < e.break_gauge
		# 빈 칸도 보여야 "게이지가 있다"는 것이 읽힌다 — 검정으로 두면 카드 배경에 묻힌다.
		var color := (
			HudTheme.BREAK_ON if broken else (HudTheme.ACCENT if filled else HudTheme.TRACK)
		)
		pip.add_theme_stylebox_override("panel", HudTheme.fill(color, 2))


func set_turn_text(text: String) -> void:
	_turn_label.text = text


func show_result(result: StringName) -> void:
	hide_menu()
	var key := "UI_BATTLE_RESULT_LOSE"
	var color := HudTheme.HP_LOW
	if result == &"win":
		key = "UI_BATTLE_RESULT_WIN"
		color = HudTheme.HP_OK
	elif result == &"flee":
		key = "UI_BATTLE_RESULT_FLEE"
		color = HudTheme.TEXT
	_result_label.text = tr(key)
	_result_label.add_theme_color_override("font_color", color)
	_result_panel.visible = true


## 쓸 수 없는 커맨드를 미리 알린다 — 눌러 보고 나서 안 되는 것보다 낫다(보스전 도망 등).
func set_command_enabled(cmd_id: StringName, enabled: bool) -> void:
	if enabled:
		_disabled_commands.erase(cmd_id)
	else:
		_disabled_commands[cmd_id] = true


func show_command_menu() -> void:
	var entries: Array[Dictionary] = []
	for cmd: Dictionary in COMMANDS:
		var entry := {"text": tr(str(cmd["key"])), "id": cmd["id"]}
		if _disabled_commands.has(cmd["id"]):
			entry["disabled"] = true
		entries.append(entry)
	_open_menu(&"command", entries)


func show_skill_menu() -> void:
	var entries: Array[Dictionary] = []
	for skill: Dictionary in _skills:
		var entry := {
			"text": str(skill.get("display_key", skill["id"])),
			"skill": skill,
			"note": _element_note(skill),
		}
		entries.append(entry)
	if entries.is_empty():
		# 빈 상자만 뜨면 "고장"으로 읽힌다 — 도구 메뉴와 같은 규약으로 이유를 적는다.
		# (스킬은 GameState.owned_skills 게이팅이라 미습득이면 실제로 0개일 수 있다.)
		entries.append({"text": tr("UI_BATTLE_NO_SKILL"), "disabled": true})
	_open_menu(&"skill", entries)


func show_item_menu() -> void:
	var entries: Array[Dictionary] = []
	for slot: Dictionary in GameState.inventory.all_slots():
		var def: Dictionary = Database.get_item(StringName(str(slot.get("item_id", ""))))
		if not ItemEffects.is_usable(def, true):
			continue  # 회복·해제·버프 — 판정은 ItemEffects 단일 창구
		var entry := {
			"text": str(def.get("name_ko", def["id"])),
			"note": "×%d" % int(slot.get("count", 1)),
			"item": def,
		}
		entries.append(entry)
	if entries.is_empty():
		entries.append({"text": tr("UI_BATTLE_NO_ITEM"), "disabled": true})
	_open_menu(&"item", entries)


func hide_menu() -> void:
	if _menu_panel != null and is_instance_valid(_menu_panel):
		_menu_panel.queue_free()
	_menu_panel = null
	_menu_rows.clear()
	_menu_cursors.clear()
	_menu_entries.clear()
	_menu_kind = &""


## 커맨드·기술·도구가 공유하는 커서 목록.
## 우하단 앵커 + 위로 성장 — 항목 수가 늘어도 하단이 고정된다(도구 메뉴가 가장 길다).
func _open_menu(kind: StringName, entries: Array[Dictionary]) -> void:
	hide_menu()
	_menu_kind = kind
	_menu_entries = entries
	_menu_index = 0

	_menu_panel = PanelContainer.new()
	_menu_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_menu_panel.offset_right = -MENU_MARGIN
	_menu_panel.offset_bottom = -MENU_MARGIN
	_menu_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_menu_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_menu_panel.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	_menu_panel.add_theme_stylebox_override("panel", HudTheme.panel(10, 8))
	add_child(_menu_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_menu_panel.add_child(box)

	for i in entries.size():
		var row := _make_menu_row(i, entries[i])
		box.add_child(row)
		_menu_rows.append(row)
	if kind != &"command":
		box.add_child(HudTheme.label(tr("UI_BATTLE_MENU_BACK"), 10, HudTheme.TEXT_MUTED))
	# 단축키 안내 — 메뉴 아래 한 줄. 번역 키는 data/l10n/ui.csv.
	var hint := HudTheme.label(tr("UI_BATTLE_HOTKEYS"), 10, HudTheme.TEXT_MUTED)
	hint.name = "Hotkeys"
	box.add_child(hint)
	_refresh_menu()


func _make_menu_row(index: int, entry: Dictionary) -> Control:
	var shell := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	shell.add_child(row)

	var cursor := HudTheme.label("", 13, HudTheme.ACCENT)
	cursor.custom_minimum_size = Vector2(13, 0)
	row.add_child(cursor)

	# 숫자 배지 — 단축키가 있다는 사실 자체를 화면이 알려 준다(설명서를 읽게 만들지 않는다).
	if index < SLOT_KEYS:
		var slot := HudTheme.label("%d" % (index + 1), 11, HudTheme.TEXT_MUTED)
		slot.custom_minimum_size = Vector2(11, 0)
		row.add_child(slot)
	# 노드 경로가 아니라 참조로 들고 있는다 — 컨테이너 이름은 엔진이 자동으로 붙여 바뀐다.
	_menu_cursors.append(cursor)

	var muted := bool(entry.get("disabled", false))
	var label := HudTheme.label(
		str(entry.get("text", "")), 14, HudTheme.TEXT_MUTED if muted else HudTheme.TEXT
	)
	label.name = "Text"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var note := str(entry.get("note", ""))
	if not note.is_empty():
		row.add_child(HudTheme.label(note, 11, HudTheme.TEXT_MUTED))

	# 마우스로도 고를 수 있게 유지한다 — 키보드가 주, 마우스는 보조.
	shell.mouse_filter = Control.MOUSE_FILTER_STOP
	shell.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed:
				_menu_index = index
				_refresh_menu()
				_confirm_menu()
	)
	return shell


func _refresh_menu() -> void:
	for i in _menu_rows.size():
		var shell := _menu_rows[i] as PanelContainer
		var selected := i == _menu_index
		_menu_cursors[i].text = "▶" if selected else ""
		if selected:
			shell.add_theme_stylebox_override(
				"panel", HudTheme.chip(HudTheme.ROW_SELECTED, 6, 4, 2)
			)
		else:
			shell.remove_theme_stylebox_override("panel")


func _unhandled_input(event: InputEvent) -> void:
	# 대상 전환·반복은 메뉴가 열려 있지 않아도(연출 중이 아니면) 받는다.
	if event.is_action_pressed(&"battle_target_prev"):
		target_cycled.emit(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"battle_target_next"):
		target_cycled.emit(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"battle_repeat"):
		repeat_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if _menu_panel == null or _menu_entries.is_empty():
		return
	# 숫자 단축키 — 커서를 옮기고 곧바로 결정한다(두 번 누르지 않게).
	for i in mini(_menu_entries.size(), SLOT_KEYS):
		if not event.is_action_pressed(StringName("battle_slot_%d" % (i + 1))):
			continue
		if bool(_menu_entries[i].get("disabled", false)):
			get_viewport().set_input_as_handled()
			return
		_menu_index = i
		_refresh_menu()
		_confirm_menu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"move_up"):
		_move_menu(-1)
	elif event.is_action_pressed(&"move_down"):
		_move_menu(1)
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		_confirm_menu()
	elif event.is_action_pressed(&"cancel"):
		if _menu_kind == &"command":
			return  # 전투 중 커맨드는 물러설 곳이 없다
		show_command_menu()
	else:
		return
	get_viewport().set_input_as_handled()


func _move_menu(delta: int) -> void:
	_menu_index = wrapi(_menu_index + delta, 0, _menu_entries.size())
	AudioManager.play_sfx(&"sfx_menu_move")
	_refresh_menu()


func _confirm_menu() -> void:
	if _menu_entries.is_empty():
		return
	var entry: Dictionary = _menu_entries[clampi(_menu_index, 0, _menu_entries.size() - 1)]
	if bool(entry.get("disabled", false)):
		return
	match _menu_kind:
		&"command":
			command_selected.emit(StringName(str(entry["id"])))
		&"skill":
			hide_menu()
			skill_selected.emit(entry["skill"])
		&"item":
			hide_menu()
			item_selected.emit(entry["item"])


## 스킬 목록 우측 꼬리표 — 속성을 알아야 약점·브레이크를 노릴 수 있다.
func _element_note(skill: Dictionary) -> String:
	var el := str(skill.get("element", ""))
	if el.is_empty() or el == "physical":
		return ""
	return tr(str(InventoryPanel.ELEMENT_KEYS.get(el, el)))


func _build_background() -> void:
	# 단색 근검정이던 자리 — 벽/지평선/바닥을 가진 배경으로 교체(층별 색조).
	# 하위 CanvasLayer(-1)라 월드 스프라이트(BattlePresenter, layer 0)를 덮지 않는다.
	var backdrop := BattleBackdrop.new()
	add_child(backdrop)
	backdrop.build(GameState.current_floor)


## 적 카드 — 스프라이트 머리 위. 이름·HP·브레이크·상태이상을 한 덩어리로 묶는다.
func _build_enemy_status() -> void:
	for i in _enemies.size():
		var e := _enemies[i]
		var card := PanelContainer.new()
		card.position = Vector2(ENEMY_SLOT_X + i * ENEMY_SLOT_STEP - ENEMY_CARD_WIDTH * 0.5, 44)
		card.custom_minimum_size = Vector2(ENEMY_CARD_WIDTH, 0)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_theme_stylebox_override("panel", HudTheme.panel(8, 7))
		add_child(card)
		_enemy_cards.append(card)

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		card.add_child(box)
		var name_lbl := HudTheme.label(e.display_name, 11, HudTheme.TEXT)
		name_lbl.clip_text = true
		box.add_child(name_lbl)

		var gauge := HudGauge.new()
		box.add_child(gauge)
		gauge.setup("HP", HudTheme.HP_OK)
		_hp_gauges[e] = gauge

		if not e.weaknesses.is_empty():
			box.add_child(_make_break_row(e))

		var srow := StatusChips.make_row()
		box.add_child(srow)
		_status_rows[e] = srow


## 브레이크 칸 게이지 — threshold 수만큼 칸을 만들고 채움 색으로 진행을 보인다.
func _make_break_row(e: Combatant) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.custom_minimum_size = Vector2(0, 6)
	for i in maxi(e.break_threshold, 1):
		var pip := PanelContainer.new()
		pip.custom_minimum_size = Vector2(0, 5)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.add_theme_stylebox_override("panel", HudTheme.fill(HudTheme.TRACK, 2))
		row.add_child(pip)
	_break_bars[e] = row
	return row


## 플레이어 카드 — 좌하단(커맨드 메뉴가 우하단이라 시선이 아래 한 줄에 모인다).
func _build_player_status() -> void:
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	card.offset_left = MENU_MARGIN
	card.offset_bottom = -MENU_MARGIN
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.custom_minimum_size = PLAYER_CARD
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", HudTheme.panel(10, 10))
	add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	card.add_child(box)

	var head := HBoxContainer.new()
	head.add_child(HudTheme.label(tr("UI_BATTLE_PLAYER_NAME"), 14, HudTheme.TEXT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_player_ap = HudTheme.label("", 11, HudTheme.TEXT_MUTED)
	head.add_child(_player_ap)
	box.add_child(head)

	var gauge := HudGauge.new()
	box.add_child(gauge)
	gauge.setup("HP", HudTheme.HP_OK)
	_hp_gauges[&"player"] = gauge

	var srow := StatusChips.make_row()
	box.add_child(srow)
	_status_rows[&"player"] = srow


func _build_labels() -> void:
	var turn_chip := PanelContainer.new()
	turn_chip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	turn_chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	turn_chip.offset_top = 12
	turn_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_chip.add_theme_stylebox_override("panel", HudTheme.chip(HudTheme.BG_SUNKEN, 8, 12, 4))
	add_child(turn_chip)
	_turn_label = HudTheme.label("TURN 1", 13, HudTheme.TEXT)
	turn_chip.add_child(_turn_label)

	_result_panel = PanelContainer.new()
	_result_panel.set_anchors_preset(Control.PRESET_CENTER)
	_result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result_panel.visible = false
	_result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.add_theme_stylebox_override("panel", HudTheme.panel(12, 20))
	add_child(_result_panel)
	_result_label = HudTheme.label("", 30, HudTheme.TEXT)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_panel.add_child(_result_label)
