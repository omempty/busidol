class_name BattleUI
extends CanvasLayer
## 전투 UI 계층 — HP바·턴 표시·커맨드/스킬 메뉴·결과 라벨.
## 로직(BattleSceneController)과 분리. 커맨드 선택은 시그널로만 통지한다.

signal command_selected(cmd_text: String)
signal skill_selected(skill: Dictionary)
signal item_selected(item_def: Dictionary)

const CMD_TEXTS: Array[String] = ["공격", "기술", "방어", "도구", "도망"]
const MENU_MARGIN := 16.0
const MENU_WIDTH := 132.0
const PLAYER_BAR_COLOR := Color(0.3, 1.0, 0.5)
const ENEMY_BAR_COLOR := Color(1, 0.3, 0.3)

var _hp_bars := {}
var _break_labels := {}  # 적별 브레이크 게이지 라벨 — 약점 보유 종만 생성
var _status_rows := {}  # 전투원별 상태이상 칩 줄(플레이어는 &"player" 키)
var _menu_root: VBoxContainer
var _skill_panel: VBoxContainer
var _item_panel: VBoxContainer
var _turn_label: Label
var _result_label: Label
var _skills: Array[Dictionary] = []
var _player: Combatant
var _enemies: Array[Combatant] = []


func build(p_player: Combatant, p_enemies: Array[Combatant], skills: Array[Dictionary]) -> void:
	layer = 20
	_player = p_player
	_enemies = p_enemies
	_skills = skills
	_build_background()
	_build_enemy_status()
	_build_player_status()
	_build_labels()


func refresh_bars() -> void:
	for i in _enemies.size():
		var e := _enemies[i]
		if _hp_bars.has(e):
			_hp_bars[e].value = maxi(0, e.hp)
		if _break_labels.has(e):
			var lbl: Label = _break_labels[e]
			lbl.text = _break_text(e)
			lbl.add_theme_color_override(
				"font_color", Color(1, 0.45, 0.2) if e.is_broken() else Color(1, 0.92, 0.35)
			)
	if _hp_bars.has(&"player"):
		_hp_bars[&"player"].value = maxi(0, _player.hp)
	_refresh_status()


## 상태이상 칩 갱신 — HP바와 같은 시점에 돈다(부착·해제·턴 감소가 여기서 보인다).
func _refresh_status() -> void:
	for e in _enemies:
		if _status_rows.has(e):
			StatusChips.refresh(_status_rows[e], e.active_effects)
	if _status_rows.has(&"player"):
		StatusChips.refresh(_status_rows[&"player"], _player.active_effects)


## 브레이크 게이지 표기 — DOS 감성 ASCII. 약점 없는 종은 항상 빈 문자열.
func _break_text(e: Combatant) -> String:
	if e.weaknesses.is_empty():
		return ""
	if e.is_broken():
		return "BREAK!"
	var pips := "["
	for p in e.break_threshold:
		pips += "#" if p < e.break_gauge else "-"
	return pips + "]"


func set_turn_text(text: String) -> void:
	_turn_label.text = text


func show_result(result: StringName) -> void:
	hide_menu()
	_result_label.text = (
		"WIN!" if result == &"win" else ("FLEE" if result == &"flee" else "LOSE...")
	)
	_result_label.visible = true
	_result_label.add_theme_color_override(
		"font_color", Color(0.3, 1.0, 0.5) if result == &"win" else Color(1, 0.3, 0.2)
	)


func show_command_menu() -> void:
	hide_menu()
	_menu_root = _new_menu_box()
	for cmd_text: String in CMD_TEXTS:
		var btn := Button.new()
		btn.text = cmd_text
		btn.pressed.connect(func() -> void: command_selected.emit(cmd_text))
		_menu_root.add_child(btn)


func show_skill_menu() -> void:
	hide_menu()
	_skill_panel = _new_menu_box()
	for skill: Dictionary in _skills:
		var btn := Button.new()
		btn.text = str(skill.get("display_key", skill["id"]))
		btn.pressed.connect(
			func() -> void:
				_close_skill_panel()
				skill_selected.emit(skill)
		)
		_skill_panel.add_child(btn)


func show_item_menu() -> void:
	hide_menu()
	_item_panel = _new_menu_box()
	var usable := 0
	for slot: Dictionary in GameState.inventory.all_slots():
		var def: Dictionary = Database.get_item(StringName(str(slot.get("item_id", ""))))
		if not ItemEffects.is_usable(def, true):
			continue  # 회복·해제·버프 — 판정은 ItemEffects 단일 창구
		usable += 1
		var btn := Button.new()
		btn.text = "%s ×%d" % [str(def.get("name_ko", def["id"])), int(slot.get("count", 1))]
		btn.pressed.connect(
			func() -> void:
				_close_item_panel()
				item_selected.emit(def)
		)
		_item_panel.add_child(btn)
	if usable == 0:
		var none := Button.new()
		none.text = "사용 가능한 도구 없음"
		none.disabled = true
		_item_panel.add_child(none)


func hide_menu() -> void:
	if _menu_root != null:
		_free_menu(_menu_root)
		_menu_root = null
	_close_skill_panel()
	_close_item_panel()


func _close_item_panel() -> void:
	if _item_panel != null:
		_free_menu(_item_panel)
		_item_panel = null


func _close_skill_panel() -> void:
	if _skill_panel != null:
		_free_menu(_skill_panel)
		_skill_panel = null


## 커맨드·기술·도구 세 메뉴가 공유하는 박스.
## 절대 좌표로 두면 항목 수가 늘 때마다 화면 밖으로 밀린다 —
## 커맨드 5종일 때 "도망"이 잘렸고, 도구 메뉴는 회복 아이템 최대 9종이라 더 심했다.
## 우하단에 앵커를 박고 **위로** 자라게 해서 항목 수와 무관하게 하단이 고정된다.
func _new_menu_box() -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_right = -MENU_MARGIN
	panel.offset_bottom = -MENU_MARGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", HudTheme.panel(8, 6))
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	return box


## 메뉴 박스는 패널로 감싸여 있다 — VBox만 지우면 빈 패널이 남는다.
func _free_menu(box: Node) -> void:
	if box == null or not is_instance_valid(box):
		return
	var top: Node = box
	while top.get_parent() != null and top.get_parent() != self:
		top = top.get_parent()
	top.queue_free()


func _build_background() -> void:
	# 단색 근검정이던 자리 — 벽/지평선/바닥을 가진 배경으로 교체(층별 색조).
	# 하위 CanvasLayer(-1)라 월드 스프라이트(BattlePresenter, layer 0)를 덮지 않는다.
	var backdrop := BattleBackdrop.new()
	add_child(backdrop)
	backdrop.build(GameState.current_floor)


func _build_enemy_status() -> void:
	for i in _enemies.size():
		var e := _enemies[i]
		var name_lbl := Label.new()
		name_lbl.text = e.display_name
		name_lbl.position = Vector2(560 + i * 100, 60)
		name_lbl.add_theme_font_size_override("font_size", 10)
		add_child(name_lbl)

		var bar := ProgressBar.new()
		bar.max_value = e.max_hp
		bar.value = e.hp
		bar.position = Vector2(560 + i * 100, 76)
		bar.size = Vector2(64, 8)
		bar.show_percentage = false
		bar.modulate = ENEMY_BAR_COLOR
		add_child(bar)
		_hp_bars[e] = bar

		# 브레이크 게이지 — 약점 보유 종만 (refresh_bars에서 갱신)
		if not e.weaknesses.is_empty():
			var bl := Label.new()
			bl.position = Vector2(560 + i * 100, 86)
			bl.add_theme_font_size_override("font_size", 9)
			bl.add_theme_color_override("font_color", Color(1, 0.92, 0.35))
			bl.text = _break_text(e)
			add_child(bl)
			_break_labels[e] = bl

		var srow := StatusChips.make_row()
		srow.position = Vector2(560 + i * 100, 98)
		add_child(srow)
		_status_rows[e] = srow


func _build_player_status() -> void:
	var pname := Label.new()
	pname.text = "부싯돌"
	pname.position = Vector2(16, 14)
	add_child(pname)

	var php := ProgressBar.new()
	php.max_value = _player.max_hp
	php.value = _player.hp
	php.position = Vector2(16, 32)
	php.size = Vector2(140, 10)
	php.show_percentage = false
	php.modulate = PLAYER_BAR_COLOR
	add_child(php)
	_hp_bars[&"player"] = php

	var pap := Label.new()
	pap.text = "AP %d" % _player.ap
	pap.position = Vector2(16, 48)
	add_child(pap)

	var srow := StatusChips.make_row()
	srow.position = Vector2(16, 68)
	add_child(srow)
	_status_rows[&"player"] = srow


func _build_labels() -> void:
	_turn_label = Label.new()
	_turn_label.text = "TURN 1"
	_turn_label.position = Vector2(450, 14)
	_turn_label.add_theme_font_size_override("font_size", 14)
	add_child(_turn_label)

	_result_label = Label.new()
	_result_label.text = ""
	_result_label.position = Vector2(450, 150)
	_result_label.add_theme_font_size_override("font_size", 28)
	_result_label.visible = false
	add_child(_result_label)
