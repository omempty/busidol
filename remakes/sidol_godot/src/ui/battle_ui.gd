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
signal cancel_requested

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
## 배틀 로그 사이드패널(04_uiux §1.4) — 좌하단, 커맨드 메뉴(우하단)와 겹치지 않는다.
const LOG_WIDTH := 250.0
const LOG_ROWS := 7
const LOG_MARGIN := 12.0
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
var _target_markers: Array[Label] = []  # 타겟 마커 표시
var _log_panel: PanelContainer
var _log_box: VBoxContainer
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
	_build_log()
	refresh_bars()


## 커맨드 id → 표시 이름(로그가 쓴다). 번역 불변 id로 오가므로 여기서만 문자열이 된다.
func command_label(cmd_id: StringName) -> String:
	for cmd: Dictionary in COMMANDS:
		if StringName(str(cmd["id"])) == cmd_id:
			return tr(str(cmd["key"]))
	return String(cmd_id)


func refresh_bars() -> void:
	# 적 턴은 컨트롤러 밖(BattleEnemyPhase)에서 로그를 적는다 — 게이지를 새로 그리는
	# 이 자리에서 함께 갱신하면 적는 쪽이 화면 갱신을 몰라도 된다.
	refresh_log()
	for e in _enemies:
		if _hp_gauges.has(e):
			_set_gauge(_hp_gauges[e], e.hp, e.max_hp)
		if _break_bars.has(e):
			_refresh_break(e)
	if _hp_gauges.has(&"player"):
		_set_gauge(_hp_gauges[&"player"], _player.hp, _player.max_hp)
	if _player_ap != null:
		# 기력은 **매 턴 보이는 자리에** 있어야 한다 — 안 보이면 "지금 쓸까 모을까"를
		# 판단할 근거가 없어 자원이 있으나 마나가 된다.
		var line := "AP %d   DP %d" % [_player.attack_stat(), _player.dp]
		if _player.max_stamina > 0:
			line += "   %s %d/%d" % [tr("UI_BATTLE_STAMINA"), _player.stamina, _player.max_stamina]
		_player_ap.text = line
	_refresh_status()


## 현재 대상 강조 — Q/E로 바뀐 대상을 화면이 즉시 보여 준다.
func set_target(index: int) -> void:
	_target_index = index
	for i in _enemy_cards.size():
		var card := _enemy_cards[i]
		if not is_instance_valid(card):
			continue
		var is_sel := i == index
		if is_sel:
			card.add_theme_stylebox_override("panel", HudTheme.chip(HudTheme.ROW_SELECTED, 8, 7, 3))
		else:
			card.add_theme_stylebox_override("panel", HudTheme.panel(8, 7))
		if i < _target_markers.size() and is_instance_valid(_target_markers[i]):
			_target_markers[i].visible = is_sel
	if _menu_kind == &"skill":
		show_skill_menu()


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
		var child := row.get_child(i)
		var pip := child as PanelContainer
		if pip != null:
			var filled := i < e.break_gauge
			var color := (
				HudTheme.BREAK_ON if broken else (HudTheme.ACCENT if filled else HudTheme.TRACK)
			)
			pip.add_theme_stylebox_override("panel", HudTheme.fill(color, 2))
		var lbl := child as Label
		if lbl != null:
			if broken:
				lbl.text = "BREAK!"
				lbl.add_theme_color_override("font_color", HudTheme.BREAK_ON)
			else:
				lbl.text = _format_weaknesses(e.weaknesses)
				lbl.add_theme_color_override("font_color", HudTheme.ACCENT)


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
	var target_enemy: Combatant = null
	if _target_index >= 0 and _target_index < _enemies.size():
		target_enemy = _enemies[_target_index]
	for skill: Dictionary in _skills:
		var el := str(skill.get("element", ""))
		var note := _element_note(skill)
		var is_weak := false
		if target_enemy != null and not target_enemy.is_down():
			if StringName(el) in target_enemy.weaknesses:
				is_weak = true
		elif str(skill.get("targeting", "")) == "all_enemies":
			for e in _enemies:
				if not e.is_down() and StringName(el) in e.weaknesses:
					is_weak = true
					break
		if is_weak:
			note = (note + " " if not note.is_empty() else "") + "WEAK!"
		# 코스트를 이름 옆에 적고, 못 쓰면 회색으로 잠근다 — 고르고 나서 "모자란다"를
		# 듣는 것보다 고르기 전에 보이는 편이 낫다.
		var cost := int(skill.get("cost", 0))
		var label := str(skill.get("display_key", skill["id"]))
		if cost > 0:
			label += "  (%d)" % cost
		var affordable := _player == null or _player.can_spend_stamina(cost)
		var entry := {
			"text": label,
			"skill": skill,
			"note": note,
			"disabled": not affordable,
		}
		entries.append(entry)
	if entries.is_empty():
		# 빈 상자만 뜨면 "고장"으로 읽힌다 — 도구 메뉴와 같은 규약으로 이유를 적는다.
		# (스킬은 GameState.owned_skills 게이팅이라 미습득이면 실제로 0개일 수 있다.)
		entries.append({"text": tr("UI_BATTLE_NO_SKILL"), "disabled": true})
	entries.append({"text": tr("UI_BATTLE_BACK"), "id": &"back"})
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
	entries.append({"text": tr("UI_BATTLE_BACK"), "id": &"back"})
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
		var back_lbl := HudTheme.label(tr("UI_BATTLE_MENU_BACK"), 10, HudTheme.TEXT_MUTED)
		back_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		back_lbl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		back_lbl.gui_input.connect(
			func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					AudioManager.play_sfx(&"sfx_menu_cancel")
					show_command_menu()
		)
		box.add_child(back_lbl)
	# 단축키 안내 — 메뉴 아래 한 줄. 번역 키는 data/l10n/ui.csv.
	var hint := HudTheme.label(tr("UI_BATTLE_HOTKEYS"), 10, HudTheme.TEXT_MUTED)
	hint.name = "Hotkeys"
	box.add_child(hint)
	_refresh_menu()


## 마우스 — 항목에 올리면 선택, 누르면 결정(04_uiux §1.3 삼중 내비).
## 전투 UI는 2026-08-28에 마우스 전용에서 키보드로 되돌린 이력이 있다 —
## **되돌리는 게 아니라 얹는다.** 키보드·패드 경로는 그대로 둔다.
func _bind_menu_mouse(shell: Control, index: int) -> void:
	shell.mouse_filter = Control.MOUSE_FILTER_STOP
	shell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	shell.mouse_entered.connect(
		func() -> void:
			if index == _menu_index or index >= _menu_entries.size():
				return
			if bool(_menu_entries[index].get("disabled", false)):
				return
			_menu_index = index
			_refresh_menu()
	)
	shell.gui_input.connect(
		func(e: InputEvent) -> void:
			if not (e is InputEventMouseButton and e.pressed):
				return
			if e.button_index == MOUSE_BUTTON_LEFT and index < _menu_entries.size():
				_menu_index = index
				_refresh_menu()
				_confirm_menu()
			elif e.button_index == MOUSE_BUTTON_RIGHT and _menu_kind != &"command":
				show_command_menu()
	)


func _make_menu_row(index: int, entry: Dictionary) -> Control:
	var shell := PanelContainer.new()
	_bind_menu_mouse(shell, index)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	shell.add_child(row)

	var cursor := HudTheme.label("", 13, HudTheme.ACCENT)
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor.custom_minimum_size = Vector2(13, 0)
	row.add_child(cursor)

	# 숫자 배지 — 단축키가 있다는 사실 자체를 화면이 알려 준다(설명서를 읽게 만들지 않는다).
	if index < SLOT_KEYS:
		var slot := HudTheme.label("%d" % (index + 1), 11, HudTheme.TEXT_MUTED)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.custom_minimum_size = Vector2(11, 0)
		row.add_child(slot)
	# 노드 경로가 아니라 참조로 들고 있는다 — 컨테이너 이름은 엔진이 자동으로 붙여 바뀐다.
	_menu_cursors.append(cursor)

	var muted := bool(entry.get("disabled", false))
	var label := HudTheme.label(
		str(entry.get("text", "")), 14, HudTheme.TEXT_MUTED if muted else HudTheme.TEXT
	)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.name = "Text"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var note := str(entry.get("note", ""))
	if not note.is_empty():
		var note_lbl := HudTheme.label(note, 11, HudTheme.TEXT_MUTED)
		note_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(note_lbl)

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
	# 우클릭으로 서브메뉴(스킬/아이템) 취소
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		if _menu_kind != &"command":
			show_command_menu()
			get_viewport().set_input_as_handled()
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
	elif (
		event.is_action_pressed(&"interact")
		or event.is_action_pressed(&"ui_accept")
		or event.is_action_pressed(&"menu")
		or (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and (
				event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_Z]
				or event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_Z]
			)
		)
	):
		_confirm_menu()
	elif (
		event.is_action_pressed(&"cancel")
		or (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)
		)
	):
		if _menu_kind == &"command":
			cancel_requested.emit()
			get_viewport().set_input_as_handled()
			return
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
		AudioManager.play_sfx(&"sfx_menu_cancel")
		return
	if entry.get("id") == &"back":
		AudioManager.play_sfx(&"sfx_menu_cancel")
		show_command_menu()
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


## 배틀 로그 — 지나간 턴을 읽는 자리. 데미지 팝은 그 순간에만 뜨고, 연출 ×2·스킵에서는
## 읽을 새가 없다. 갱신은 BattleLog.push를 부른 쪽이 refresh_log()로 알린다.
func _build_log() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", HudTheme.panel(8, 8))
	panel.custom_minimum_size = Vector2(LOG_WIDTH, 0)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = LOG_MARGIN
	panel.offset_bottom = -(MENU_MARGIN + 62.0)
	add_child(panel)
	_log_box = VBoxContainer.new()
	_log_box.add_theme_constant_override("separation", 2)
	panel.add_child(_log_box)
	_log_panel = panel
	refresh_log()


## 최근 LOG_ROWS줄만 다시 그린다 — 전투 중 갱신이 잦아 통째로 다시 만드는 편이 싸다.
func refresh_log() -> void:
	if _log_box == null:
		return
	for child in _log_box.get_children():
		child.queue_free()
	var rows := BattleLog.tail(LOG_ROWS)
	if rows.is_empty():
		_log_panel.visible = false
		return
	_log_panel.visible = true
	for row: Dictionary in rows:
		var kind := int(row.get("kind", 0))
		var lbl := HudTheme.label(
			"%s %s" % [BattleLog.mark_of(kind), str(row.get("text", ""))],
			11,
			BattleLog.color_of(kind)
		)
		lbl.clip_text = true
		_log_box.add_child(lbl)


func _build_background() -> void:
	# 단색 근검정이던 자리 — 벽/지평선/바닥을 가진 배경으로 교체(층별 색조).
	# 하위 CanvasLayer(-1)라 월드 스프라이트(BattlePresenter, layer 0)를 덮지 않는다.
	var backdrop := BattleBackdrop.new()
	add_child(backdrop)
	backdrop.build(GameState.current_floor)


## 적 카드 — 스프라이트 머리 위 플로팅. 타겟마커·이름·HP·브레이크·상태이상을 한 덩어리로 묶는다.
func _build_enemy_status() -> void:
	_target_markers.clear()
	for i in _enemies.size():
		var e := _enemies[i]
		var card := PanelContainer.new()
		card.position = Vector2(ENEMY_SLOT_X + i * ENEMY_SLOT_STEP - ENEMY_CARD_WIDTH * 0.5, 84.0)
		card.custom_minimum_size = Vector2(ENEMY_CARD_WIDTH, 0)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_theme_stylebox_override("panel", HudTheme.panel(8, 7))
		add_child(card)
		_enemy_cards.append(card)

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		card.add_child(box)

		var marker := HudTheme.label("▼ TARGET", 9, HudTheme.ACCENT)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.visible = (i == _target_index)
		box.add_child(marker)
		_target_markers.append(marker)

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
	row.custom_minimum_size = Vector2(0, 8)
	for i in maxi(e.break_threshold, 1):
		var pip := PanelContainer.new()
		pip.custom_minimum_size = Vector2(0, 5)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.add_theme_stylebox_override("panel", HudTheme.fill(HudTheme.TRACK, 2))
		row.add_child(pip)
	var weak_lbl := HudTheme.label(_format_weaknesses(e.weaknesses), 9, HudTheme.ACCENT)
	row.add_child(weak_lbl)
	_break_bars[e] = row
	return row


func _format_weaknesses(weaknesses: Array[StringName]) -> String:
	var icons: Array[String] = []
	for w in weaknesses:
		match str(w):
			"fire":
				icons.append("🔥")
			"electric":
				icons.append("⚡")
			"physical":
				icons.append("⚔")
			_:
				icons.append(str(w))
	return " ".join(icons)


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
	var lv_val := int(GameState.player_stats.get("level", 1))
	var lv_badge := HudTheme.label("Lv.%d" % lv_val, 11, HudTheme.ACCENT)
	head.add_child(lv_badge)
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
