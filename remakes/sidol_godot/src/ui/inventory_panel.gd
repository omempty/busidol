class_name InventoryPanel
extends CanvasLayer
## 캐릭터 메뉴(I키) — **탭 4장**(아이템/장비/상태/시스템). 열려 있는 동안 월드 정지.
## 표시 데이터는 전부 data/items.json 경유(콘텐츠 하드코딩 금지).
##
## 2026-08-28 정리: ① 목록이 앞 9줄만 그려 10번째부터는 커서가 안 보이는 곳으로 갔다
## ② 상세에 kind/element 영문 내부값 노출 ③ 창 껍데기를 ModalFrame으로 통일.
##
## 2026-08-30 탭형으로 재구성(04_uiux §1.3) — 이름은 InventoryPanel 그대로 두지만
## 실제로는 캐릭터 메뉴다. 바꾼 이유:
##   * 문서가 정한 4탭 구조가 없었다. 아이템은 여기, 장비는 목록 안 `◆` 표시, 상태는
##     어디에도 없었고(HUD에 LV/HP만), 시스템은 Esc 메뉴에 따로 있었다.
##   * 아이템이 세로 목록이라 한 번에 9칸만 보였다 — **그리드로 바꾸면 24칸이 한눈에** 든다.
##   * 시스템 탭은 **세이브/로드를 다시 구현하지 않는다.** PauseMenu가 이미 갖고 있고
##     두 벌이 되면 한쪽만 고쳐져 갈라진다(이 저장소에서 반복해 잡아 온 결함).
##     탭은 신호만 쏘고 필드가 기존 PauseMenu를 연다.

## 시스템 탭에서 고른 항목 — 필드가 받아 기존 PauseMenu로 넘긴다(중복 구현 금지).
signal system_requested(action: StringName)

enum Tab { ITEMS, GEAR, STATUS, SYSTEM }

const TAB_KEYS := [
	"UI_MENU_TAB_ITEMS", "UI_MENU_TAB_GEAR", "UI_MENU_TAB_STATUS", "UI_MENU_TAB_SYSTEM"
]
## 아이템 그리드 — 6칸 × 4줄이 한 화면. 넘치면 줄 단위로 민다.
const GRID_COLS := 6
const GRID_ROWS := 4
const CELL_PX := 40
## 장비 칸 — data/items.json의 kind 값과 1:1(문서 §1.3 "장비 슬롯 명시화").
const GEAR_SLOTS := [
	{"slot": "weapon", "key": "UI_KIND_WEAPON"},
	{"slot": "armor", "key": "UI_KIND_ARMOR"},
]
## 시스템 탭 항목 — PauseMenu의 같은 기능으로 연결된다.
const SYSTEM_ITEMS = [
	{"id": &"save", "key": "UI_PAUSE_SAVE"},
	{"id": &"load", "key": "UI_PAUSE_LOAD"},
	{"id": &"questlog", "key": "UI_PAUSE_QUESTLOG"},
	{"id": &"settings", "key": "UI_PAUSE_SETTINGS"},
	{"id": &"help", "key": "UI_PAUSE_HELP"},
]

const MAX_ROWS_SHOWN := 9
## 내부 kind/element 값 → 번역 키. 데이터 값을 화면에 그대로 쓰지 않기 위한 표.
const KIND_KEYS := {
	"weapon": "UI_KIND_WEAPON",
	"armor": "UI_KIND_ARMOR",
	"consumable": "UI_KIND_CONSUMABLE",
	"magic_substitute": "UI_KIND_SUBSTITUTE",
	"material": "UI_KIND_MATERIAL",
	"quest": "UI_KIND_QUEST",
	"money": "UI_KIND_MONEY",
}
const ELEMENT_KEYS := {
	"physical": "UI_ELEM_PHYSICAL",
	"electric": "UI_ELEM_ELECTRIC",
	"fire": "UI_ELEM_FIRE",
	"none": "UI_ELEM_NONE",
}

var _tab: Tab = Tab.ITEMS
var _tab_labels: Array[PanelContainer] = []
var _pages: Array[Control] = []
var _grid: GridContainer
var _gear_box: VBoxContainer
var _status_box: VBoxContainer
var _system_box: VBoxContainer
var _sub_index := 0  # 장비·시스템 탭의 커서
var _list_box: VBoxContainer
var _detail_icon: TextureRect
var _detail_glyph: Label
var _detail_name: Label
var _detail_kind: Label
var _detail_stats: VBoxContainer
var _action_hint: Label
var _detail_card: Control
var _frame: ModalFrame
var _rows: Array[Dictionary] = []  # 파생 목록 캐시 [{item_id, count}]
var _index := 0
var _top := 0  # 목록 창의 첫 줄 — 커서를 따라 움직인다


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	GameState.inventory.changed.connect(
		func() -> void:
			if visible:
				_rebuild_list()
	)


func _build_ui() -> void:
	_frame = ModalFrame.new()
	_frame.setup("UI_CHAR_MENU_TITLE", "UI_CHAR_MENU_HINT", Vector2(620, 360))
	_frame.dismissed.connect(close)
	add_child(_frame)

	_frame.body.add_child(_build_tab_bar())

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	_frame.body.add_child(columns)

	var pages := Control.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.custom_minimum_size = Vector2(300, 236)
	columns.add_child(pages)

	# 아이템 — 그리드. _list_box는 남긴다(그리드 아래 위치 표시줄이 쓴다).
	var items_page := VBoxContainer.new()
	items_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	items_page.add_child(_grid)
	_list_box = VBoxContainer.new()
	items_page.add_child(_list_box)
	pages.add_child(items_page)

	_gear_box = _make_page(pages)
	_status_box = _make_page(pages)
	_system_box = _make_page(pages)
	_pages = [items_page, _gear_box, _status_box, _system_box]

	_detail_card = _build_detail()
	columns.add_child(_detail_card)


func _make_page(parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 6)
	box.visible = false
	parent.add_child(box)
	return box


## 탭 바 — 마우스로도 고를 수 있다(04_uiux §1.3 "삼중 내비").
func _build_tab_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	for i in TAB_KEYS.size():
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var lbl := HudTheme.label(tr(str(TAB_KEYS[i])), 13, HudTheme.TEXT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size = Vector2(74, 0)
		chip.add_child(lbl)
		var idx := i
		chip.gui_input.connect(
			func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					_set_tab(idx as Tab)
		)
		bar.add_child(chip)
		_tab_labels.append(chip)
	return bar


func _set_tab(tab: Tab) -> void:
	_tab = tab
	_sub_index = 0
	_index = 0
	_top = 0
	_refresh_all()


func _cycle_tab(dir: int) -> void:
	_set_tab(wrapi(int(_tab) + dir, 0, TAB_KEYS.size()) as Tab)


## 우측 상세 — 큰 아이콘·이름·종류·수치 목록·행동 힌트.
## 구판은 이름/영문 kind/설명뿐이라 대부분 빈 칸이었다(items.json에 desc가 0건).
func _build_detail() -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(240, 0)
	card.add_theme_stylebox_override("panel", HudTheme.panel(8, 12))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)

	var icon_slot := PanelContainer.new()
	icon_slot.custom_minimum_size = Vector2(44, 44)
	icon_slot.add_theme_stylebox_override("panel", HudTheme.fill(HudTheme.BG_SUNKEN, 8))
	head.add_child(icon_slot)
	_detail_icon = TextureRect.new()
	_detail_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_slot.add_child(_detail_icon)
	_detail_glyph = HudTheme.label("", 20, HudTheme.TEXT)
	_detail_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_slot.add_child(_detail_glyph)

	var titles := VBoxContainer.new()
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(titles)
	_detail_name = HudTheme.label("", 15, HudTheme.TEXT)
	titles.add_child(_detail_name)
	_detail_kind = HudTheme.label("", 11, HudTheme.TEXT_MUTED)
	titles.add_child(_detail_kind)

	_detail_stats = VBoxContainer.new()
	_detail_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_stats.add_theme_constant_override("separation", 3)
	box.add_child(_detail_stats)

	_action_hint = HudTheme.label("", 11, HudTheme.ACCENT)
	box.add_child(_action_hint)
	return card


func open() -> void:
	_index = 0
	_top = 0
	_sub_index = 0
	_tab = Tab.ITEMS
	visible = true
	get_tree().paused = true
	_refresh_all()


func close() -> void:
	visible = false
	get_tree().paused = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_cycle_tab(-1 if event.shift_pressed else 1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"cancel") or event.is_action_pressed(&"inventory"):
		close()
	elif event.is_action_pressed(&"tab_prev"):
		_cycle_tab(-1)
	elif event.is_action_pressed(&"tab_next"):
		_cycle_tab(1)
	elif event.is_action_pressed(&"move_up"):
		_move(-GRID_COLS if _tab == Tab.ITEMS else -1)
	elif event.is_action_pressed(&"move_down"):
		_move(GRID_COLS if _tab == Tab.ITEMS else 1)
	elif event.is_action_pressed(&"move_left"):
		_move(-1)
	elif event.is_action_pressed(&"move_right"):
		_move(1)
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		_confirm()
	else:
		return
	get_viewport().set_input_as_handled()


## 탭마다 확인키가 하는 일이 다르다 — 아이템은 사용/장착, 장비는 해제, 시스템은 위임.
func _confirm() -> void:
	match _tab:
		Tab.ITEMS:
			_use_selected()
		Tab.GEAR:
			var slot := str(GEAR_SLOTS[_sub_index]["slot"])
			var equipped := str(GameState.equipped.get(slot, ""))
			if not equipped.is_empty():
				GameState.equip(StringName(equipped))  # 같은 것을 다시 = 해제
				AudioManager.play_sfx(&"sfx_menu_cancel")
				_refresh_all()
		Tab.SYSTEM:
			system_requested.emit(StringName(str(SYSTEM_ITEMS[_sub_index]["id"])))
			close()
		_:
			pass


## 선택 항목에 SPACE — 무기/방어구면 장착·해제, 회복 아이템이면 사용.
## 구판은 인벤토리가 표시 전용이라 무기 19종과 회복 아이템이 여기서 아무것도 못 했다.
func _use_selected() -> void:
	if _rows.is_empty():
		return
	var slot: Dictionary = _rows[clampi(_index, 0, _rows.size() - 1)]
	var item_id := StringName(str(slot["item_id"]))
	var kind := str(Database.get_item(item_id).get("kind", ""))
	var was := str(GameState.equipped.get(kind, ""))
	if GameState.equip(item_id):
		# 장착은 부위별 효과음(무기 휘두름·방어구 전개), 해제는 취소음.
		if was == String(item_id):
			AudioManager.play_sfx(&"sfx_menu_cancel")
		elif kind == "armor":
			AudioManager.play_sfx(&"cast_shield")
		else:
			AudioManager.play_sfx(&"atk_swish")
		_refresh_all()
		return
	var def := Database.get_item(item_id)
	var note := ItemEffects.use_on_field(def)
	if note.is_empty():
		return  # 필드에서 못 쓰는 것(전투 전용·만HP)은 조용히 무시
	GameState.inventory.remove(item_id, 1)
	_refresh_all()


func _move(delta: int) -> void:
	match _tab:
		Tab.ITEMS:
			if _rows.is_empty():
				return
			_index = clampi(_index + delta, 0, _rows.size() - 1)
			_scroll_to_cursor()
			_rebuild_list()
		Tab.GEAR:
			_sub_index = wrapi(_sub_index + signi(delta), 0, GEAR_SLOTS.size())
			_refresh_gear()
		Tab.SYSTEM:
			_sub_index = wrapi(_sub_index + signi(delta), 0, SYSTEM_ITEMS.size())
			_refresh_system()
		_:
			pass


## 커서가 창 밖으로 나가면 창을 민다 — 커서가 안 보이는 줄로 사라지지 않게.
func _scroll_to_cursor() -> void:
	# 그리드는 **줄 단위**로 민다 — 칸 단위로 밀면 같은 아이템이 다른 열로 튄다.
	var page := GRID_COLS * GRID_ROWS
	var row := _index / GRID_COLS
	var top_row := _top / GRID_COLS
	if row < top_row:
		top_row = row
	elif row >= top_row + GRID_ROWS:
		top_row = row - GRID_ROWS + 1
	_top = maxi(top_row, 0) * GRID_COLS
	_top = clampi(_top, 0, maxi(_rows.size() - page, 0))


## 탭 전부를 다시 그린다 — 한 창구로 묶어 두면 어느 탭에서 무엇이 바뀌든 어긋나지 않는다.
## 자식 비우기 — **트리에서 먼저 떼고** 지운다. queue_free만 하면 그 프레임 동안
## 옛 행이 그대로 남아(자식 수도 그대로다) 새 행과 겹쳐 그려진다.
func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _refresh_all() -> void:
	for i in _pages.size():
		_pages[i].visible = i == int(_tab)
	# 상세 카드는 아이템 탭의 것이다 — 다른 탭에서 켜 두면 지금 보는 것과 무관한
	# 아이템 정보가 옆에 남아 그 탭의 내용인 것처럼 읽힌다.
	if _detail_card != null:
		_detail_card.visible = _tab == Tab.ITEMS
	for i in _tab_labels.size():
		var on := i == int(_tab)
		var chip := _tab_labels[i]
		chip.add_theme_stylebox_override(
			"panel", HudTheme.chip(HudTheme.ROW_SELECTED if on else HudTheme.BG_SUNKEN, 6, 6, 3)
		)
		(chip.get_child(0) as Label).add_theme_color_override(
			"font_color", HudTheme.ACCENT if on else HudTheme.TEXT_MUTED
		)
	_rebuild_list()
	_refresh_gear()
	_refresh_status()
	_refresh_system()


func _rebuild_list() -> void:
	_rows = GameState.inventory.all_slots()
	_clear(_grid)
	_clear(_list_box)
	var page := GRID_COLS * GRID_ROWS
	if _rows.is_empty():
		for i in page:
			_grid.add_child(_make_empty_cell(i))
		_list_box.add_child(HudTheme.label(tr("UI_BAG_EMPTY"), 13, HudTheme.TEXT_MUTED))
		_refresh_detail()
		return
	_index = clampi(_index, 0, _rows.size() - 1)
	_scroll_to_cursor()
	var shown_count := 0
	for i in range(_top, mini(_rows.size(), _top + page)):
		_grid.add_child(_make_cell(i))
		shown_count += 1
	for i in range(shown_count, page):
		_grid.add_child(_make_empty_cell(i))
	if _rows.size() > page:
		var pos := HudTheme.label(
			tr("UI_BAG_POSITION") % [_index + 1, _rows.size()], 11, HudTheme.TEXT_MUTED
		)
		pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_list_box.add_child(pos)
	_refresh_detail()


func _make_empty_cell(_i: int) -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(CELL_PX, CELL_PX)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.18, 0.4)
	sb.border_color = Color(0.24, 0.28, 0.36, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	cell.add_theme_stylebox_override("panel", sb)
	var dot := Label.new()
	dot.text = "·"
	dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dot.add_theme_color_override("font_color", Color(0.35, 0.40, 0.50, 0.4))
	dot.add_theme_font_size_override("font_size", 14)
	cell.add_child(dot)
	return cell


## 그리드 한 칸 — 아이콘 + 개수. **마우스를 올리면 그 칸이 선택된다**(호버 툴팁 자리는
## 우측 상세가 맡는다 — 툴팁 창을 따로 띄우면 같은 정보가 두 벌이 된다).
func _make_cell(i: int) -> Control:
	var slot: Dictionary = _rows[i]
	var def := Database.get_item(StringName(str(slot["item_id"])))
	var selected := i == _index
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(CELL_PX, CELL_PX)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cell.add_theme_stylebox_override(
		"panel", HudTheme.chip(HudTheme.ROW_SELECTED if selected else HudTheme.BG_SUNKEN, 6, 3, 3)
	)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	cell.add_child(box)
	box.add_child(_icon_slot(def, 24))
	var equipped_here := (
		str(GameState.equipped.get(str(def.get("kind", "")), "")) == str(slot["item_id"])
	)
	var tag := HudTheme.label(
		("◆" if equipped_here else "") + "×%d" % int(slot["count"]),
		9,
		HudTheme.EQUIPPED if equipped_here else HudTheme.TEXT_MUTED
	)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)

	var idx := i
	cell.mouse_entered.connect(
		func() -> void:
			if _index != idx:
				_index = idx
				_rebuild_list()
	)
	cell.gui_input.connect(
		func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_index = idx
				_use_selected()
	)
	return cell


## 장비 탭 — 2분할 레이아웃(좌측: 착용 슬롯 / 우측: 후보 장비 목록 & 스탯 증감 비교 프리뷰).
func _refresh_gear() -> void:
	if _gear_box == null:
		return
	_clear(_gear_box)

	# 1) 상단 헤더: 종합 스탯 요약 배지
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.add_child(HudTheme.label(tr("UI_GEAR_SLOTS_TITLE"), 13, HudTheme.TEXT))
	var stat_summary := HudTheme.label(
		"AP %d · DP %d" % [GameState.attack_power(), GameState.defense_power()], 12, HudTheme.ACCENT
	)
	stat_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(stat_summary)
	_gear_box.add_child(header)

	# 2) 2분할 컨테이너 (좌측 슬롯 목록 / 우측 후보 장비 & 스탯 비교)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_gear_box.add_child(split)

	# 2-A) 좌측 슬롯 컬럼
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(240, 0)
	left_col.add_theme_constant_override("separation", 6)
	split.add_child(left_col)

	for i in GEAR_SLOTS.size():
		var slot := str(GEAR_SLOTS[i]["slot"])
		var def := GameState.equipped_in(slot)
		var row := PanelContainer.new()
		var selected := _tab == Tab.GEAR and i == _sub_index
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.add_theme_stylebox_override(
			"panel",
			HudTheme.chip(HudTheme.ROW_SELECTED if selected else HudTheme.BG_SUNKEN, 6, 8, 6)
		)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		row.add_child(line)
		line.add_child(_icon_slot(def, 28))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(col)
		col.add_child(HudTheme.label(tr(str(GEAR_SLOTS[i]["key"])), 10, HudTheme.TEXT_MUTED))
		var empty := def.is_empty()
		col.add_child(
			HudTheme.label(
				tr("UI_GEAR_EMPTY") if empty else str(def.get("name_ko", "")),
				13,
				HudTheme.TEXT_MUTED if empty else HudTheme.EQUIPPED
			)
		)
		var num := 0
		if def.has("ap"):
			num = int(def["ap"])
		elif def.has("dp"):
			num = int(def["dp"])
		line.add_child(
			HudTheme.label(
				"+%d" % num if num > 0 else "",
				12,
				HudTheme.ACCENT if num > 0 else HudTheme.TEXT_MUTED
			)
		)
		var idx := i
		row.gui_input.connect(
			func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					_sub_index = idx
					_refresh_gear()
		)
		left_col.add_child(row)

	# 2-B) 우측 후보 장비 목록 & 스탯 증감 비교
	var right_card := PanelContainer.new()
	right_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_card.add_theme_stylebox_override("panel", HudTheme.panel(6, 8))
	split.add_child(right_card)

	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 6)
	right_card.add_child(right_box)

	var target_slot := str(GEAR_SLOTS[_sub_index]["slot"])
	var cur_equipped := GameState.equipped_in(target_slot)
	var title_text := (
		"%s · %s (%s)"
		% [
			tr("UI_GEAR_INV_TITLE"),
			tr("UI_GEAR_COMPARE_TITLE"),
			tr(str(GEAR_SLOTS[_sub_index]["key"]))
		]
	)
	right_box.add_child(HudTheme.label(title_text, 11, HudTheme.TEXT_MUTED))

	# 인벤토리에서 해당 슬롯에 착용 가능한 장비 추출
	var candidates: Array[Dictionary] = []
	for slot_info in GameState.inventory.all_slots():
		var item_def := Database.get_item(StringName(str(slot_info["item_id"])))
		if str(item_def.get("kind", "")) == target_slot:
			candidates.append(slot_info)

	if candidates.is_empty() and cur_equipped.is_empty():
		right_box.add_child(HudTheme.label(tr("UI_GEAR_NO_EQUIPABLE"), 12, HudTheme.TEXT_MUTED))
	else:
		# 현재 장착 중이면 해제 옵션 표시
		if not cur_equipped.is_empty():
			var unequip_btn := PanelContainer.new()
			unequip_btn.mouse_filter = Control.MOUSE_FILTER_STOP
			unequip_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			unequip_btn.add_theme_stylebox_override(
				"panel", HudTheme.chip(HudTheme.BG_SUNKEN, 4, 6, 3)
			)
			var unequip_lbl := HudTheme.label("✖ " + tr("UI_GEAR_UNEQUIP"), 11, HudTheme.TEXT_MUTED)
			unequip_btn.add_child(unequip_lbl)
			var unequip_id := StringName(str(GameState.equipped.get(target_slot, "")))
			unequip_btn.gui_input.connect(
				func(e: InputEvent) -> void:
					if (
						e is InputEventMouseButton
						and e.pressed
						and e.button_index == MOUSE_BUTTON_LEFT
					):
						GameState.equip(unequip_id)
						AudioManager.play_sfx(&"sfx_menu_cancel")
						_refresh_all()
			)
			right_box.add_child(unequip_btn)

		# 후보 장비들 표시
		var cand_scroll := ScrollContainer.new()
		cand_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cand_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		right_box.add_child(cand_scroll)

		var cand_list := VBoxContainer.new()
		cand_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cand_list.add_theme_constant_override("separation", 4)
		cand_scroll.add_child(cand_list)

		for c in candidates:
			var cand_id := StringName(str(c["item_id"]))
			var cand_def := Database.get_item(cand_id)
			var is_equipped := str(GameState.equipped.get(target_slot, "")) == str(cand_id)

			var c_row := PanelContainer.new()
			c_row.mouse_filter = Control.MOUSE_FILTER_STOP
			c_row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			c_row.add_theme_stylebox_override(
				"panel",
				HudTheme.chip(HudTheme.ROW_SELECTED if is_equipped else HudTheme.BG_SUNKEN, 4, 6, 4)
			)

			var c_line := HBoxContainer.new()
			c_line.add_theme_constant_override("separation", 6)
			c_row.add_child(c_line)

			c_line.add_child(_icon_slot(cand_def, 22))
			var c_name := HudTheme.label(
				str(cand_def.get("name_ko", cand_id)),
				12,
				HudTheme.EQUIPPED if is_equipped else HudTheme.TEXT
			)
			c_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c_line.add_child(c_name)

			# 스탯 증감 비교
			var cur_stat: int = int(cur_equipped.get("ap" if target_slot == "weapon" else "dp", 0))
			var new_stat: int = int(cand_def.get("ap" if target_slot == "weapon" else "dp", 0))
			var diff := new_stat - cur_stat
			var diff_text := ""
			var diff_color := HudTheme.TEXT_MUTED
			if is_equipped:
				diff_text = tr("UI_BAG_ACT_UNEQUIP")
			elif diff > 0:
				diff_text = "+%d ▲" % diff
				diff_color = Color(0.3, 0.9, 0.4)
			elif diff < 0:
				diff_text = "%d ▼" % diff
				diff_color = Color(0.9, 0.35, 0.35)
			else:
				diff_text = "±0"

			var diff_lbl := HudTheme.label(diff_text, 11, diff_color)
			c_line.add_child(diff_lbl)

			c_row.gui_input.connect(
				func(e: InputEvent) -> void:
					if (
						e is InputEventMouseButton
						and e.pressed
						and e.button_index == MOUSE_BUTTON_LEFT
					):
						GameState.equip(cand_id)
						_refresh_all()
			)
			cand_list.add_child(c_row)

	# 3) 하단 조작 힌트
	_gear_box.add_child(HudTheme.label(tr("UI_GEAR_HINT"), 11, HudTheme.TEXT_MUTED))


const SYSTEM_ICONS := ["💾", "📂", "📜", "⚙️", "❓"]
const SYSTEM_SUB_KEYS := [
	"UI_SYSTEM_SUB_SAVE",
	"UI_SYSTEM_SUB_LOAD",
	"UI_SYSTEM_SUB_QUESTLOG",
	"UI_SYSTEM_SUB_SETTINGS",
	"UI_SYSTEM_SUB_HELP",
]


## 상태 탭 — 리치 프로필 레이아웃(기본 스탯/게이지 + 습득 스킬 목록 시각화).
func _refresh_status() -> void:
	if _status_box == null:
		return
	_clear(_status_box)

	# 1) 캐릭터 프로필 헤더
	var profile := HBoxContainer.new()
	profile.add_theme_constant_override("separation", 10)
	var name_lbl := HudTheme.label(tr("UI_STAT_PROFILE_TITLE"), 14, HudTheme.ACCENT)
	profile.add_child(name_lbl)
	var sp0 := Control.new()
	sp0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile.add_child(sp0)
	var lv_badge := PanelContainer.new()
	lv_badge.add_theme_stylebox_override("panel", HudTheme.chip(HudTheme.ACCENT, 4, 8, 2))
	var lv_lbl := HudTheme.label(
		"%s %d" % [tr("UI_STAT_LEVEL"), int(GameState.player_stats.get("level", 1))],
		11,
		HudTheme.TEXT_ON_ACCENT
	)
	lv_badge.add_child(lv_lbl)
	profile.add_child(lv_badge)
	_status_box.add_child(profile)

	# 2) HP 행
	var hp_line := HBoxContainer.new()
	hp_line.add_theme_constant_override("separation", 8)
	hp_line.add_child(HudTheme.label(tr("UI_STAT_HP"), 12, HudTheme.TEXT_MUTED))
	var hp_bar := ProgressBar.new()
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.custom_minimum_size = Vector2(120, 14)
	hp_bar.max_value = float(GameState.max_hp())
	hp_bar.value = float(GameState.player_stats.get("hp", 0))
	hp_bar.show_percentage = false
	var hp_sb := StyleBoxFlat.new()
	hp_sb.bg_color = HudTheme.HP_OK
	hp_sb.set_corner_radius_all(3)
	hp_bar.add_theme_stylebox_override("fill", hp_sb)
	hp_line.add_child(hp_bar)
	var hp_val := HudTheme.label(
		"%d / %d" % [int(GameState.player_stats.get("hp", 0)), GameState.max_hp()],
		11,
		HudTheme.TEXT
	)
	hp_line.add_child(hp_val)
	_status_box.add_child(hp_line)

	# 3) EXP 행
	var exp_line := HBoxContainer.new()
	exp_line.add_theme_constant_override("separation", 8)
	exp_line.add_child(HudTheme.label(tr("UI_STAT_EXP"), 12, HudTheme.TEXT_MUTED))
	var exp_val_cur: int = int(GameState.player_stats.get("exp", 0))
	var exp_bar := ProgressBar.new()
	exp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exp_bar.custom_minimum_size = Vector2(120, 14)
	exp_bar.max_value = float(maxi(exp_val_cur + 100, 1000))
	exp_bar.value = float(exp_val_cur)
	exp_bar.show_percentage = false
	var exp_sb := StyleBoxFlat.new()
	exp_sb.bg_color = HudTheme.EXP
	exp_sb.set_corner_radius_all(3)
	exp_bar.add_theme_stylebox_override("fill", exp_sb)
	exp_line.add_child(exp_bar)
	var exp_val := HudTheme.label(
		"%s: %d" % [tr("UI_STAT_NEXT_EXP"), exp_val_cur], 11, HudTheme.TEXT
	)
	exp_line.add_child(exp_val)
	_status_box.add_child(exp_line)

	# 4) 전투 수치 행 (공격력 / 방어력 / 소지금)
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 16)
	stats_row.add_child(
		HudTheme.label("%s: %d" % [tr("UI_STAT_AP"), GameState.attack_power()], 12, HudTheme.TEXT)
	)
	stats_row.add_child(
		HudTheme.label("%s: %d" % [tr("UI_STAT_DP"), GameState.defense_power()], 12, HudTheme.TEXT)
	)
	var sp_stat := Control.new()
	sp_stat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_row.add_child(sp_stat)
	stats_row.add_child(
		HudTheme.label(
			(
				"%s: %s"
				% [tr("UI_STAT_MONEY"), HudTheme.money(int(GameState.player_stats.get("money", 0)))]
			),
			12,
			HudTheme.ACCENT
		)
	)
	_status_box.add_child(stats_row)

	# 5) 보유 스킬 목록 카드
	var skill_card := PanelContainer.new()
	skill_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_card.add_theme_stylebox_override("panel", HudTheme.panel(6, 8))
	_status_box.add_child(skill_card)

	var skill_vbox := VBoxContainer.new()
	skill_vbox.add_theme_constant_override("separation", 4)
	skill_card.add_child(skill_vbox)
	skill_vbox.add_child(HudTheme.label(tr("UI_STAT_SKILLS_TITLE"), 11, HudTheme.TEXT_MUTED))

	var raw_skills: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/skills.json")
	)
	var owned_skills_list: Array[Dictionary] = []
	if typeof(raw_skills) == TYPE_DICTIONARY:
		for sk: Dictionary in (raw_skills as Dictionary).get("skills", []):
			if GameState.has_skill(StringName(str(sk.get("id", "")))):
				owned_skills_list.append(sk)

	if owned_skills_list.is_empty():
		skill_vbox.add_child(HudTheme.label(tr("UI_STAT_NO_SKILLS"), 12, HudTheme.TEXT_MUTED))
	else:
		var skill_scroll := ScrollContainer.new()
		skill_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		skill_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		skill_vbox.add_child(skill_scroll)

		var skill_grid := GridContainer.new()
		skill_grid.columns = 2
		skill_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skill_grid.add_theme_constant_override("h_separation", 8)
		skill_grid.add_theme_constant_override("v_separation", 4)
		skill_scroll.add_child(skill_grid)

		for sk in owned_skills_list:
			var s_chip := PanelContainer.new()
			s_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s_chip.add_theme_stylebox_override("panel", HudTheme.chip(HudTheme.BG_SUNKEN, 4, 6, 3))
			var s_box := HBoxContainer.new()
			s_box.add_theme_constant_override("separation", 6)
			s_chip.add_child(s_box)

			var elem := str(sk.get("element", "none"))
			var elem_lbl := HudTheme.label(
				"[%s]" % tr(str(ELEMENT_KEYS.get(elem, elem))), 10, HudTheme.TEXT_MUTED
			)
			s_box.add_child(elem_lbl)

			var s_name := HudTheme.label(
				str(sk.get("display_key", sk.get("id", ""))), 12, HudTheme.TEXT
			)
			s_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s_box.add_child(s_name)

			var pow_val: int = int(sk.get("power", 0))
			if pow_val > 0:
				s_box.add_child(HudTheme.label("P.%d" % pow_val, 10, HudTheme.ACCENT))
			skill_grid.add_child(s_chip)


## 시스템 탭 — 카드형 레이아웃 + 서브 캡션. 신호만 쏘고 필드가 기존 PauseMenu를 연다.
func _refresh_system() -> void:
	if _system_box == null:
		return
	_clear(_system_box)
	for i in SYSTEM_ITEMS.size():
		var selected := _tab == Tab.SYSTEM and i == _sub_index
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.add_theme_stylebox_override(
			"panel",
			HudTheme.chip(HudTheme.ROW_SELECTED if selected else HudTheme.BG_SUNKEN, 6, 10, 6)
		)
		var h_line := HBoxContainer.new()
		h_line.add_theme_constant_override("separation", 10)
		row.add_child(h_line)

		var icon_lbl := HudTheme.label(
			SYSTEM_ICONS[i] if i < SYSTEM_ICONS.size() else "▶", 16, HudTheme.TEXT
		)
		h_line.add_child(icon_lbl)

		var text_col := VBoxContainer.new()
		text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_col.add_theme_constant_override("separation", 2)
		h_line.add_child(text_col)

		var title_lbl := HudTheme.label(
			tr(str(SYSTEM_ITEMS[i]["key"])), 13, HudTheme.ACCENT if selected else HudTheme.TEXT
		)
		text_col.add_child(title_lbl)

		var sub_key: String = SYSTEM_SUB_KEYS[i] if i < SYSTEM_SUB_KEYS.size() else ""
		if not sub_key.is_empty():
			var sub_lbl := HudTheme.label(tr(sub_key), 10, HudTheme.TEXT_MUTED)
			text_col.add_child(sub_lbl)

		var arr := HudTheme.label("›", 14, HudTheme.ACCENT if selected else HudTheme.TEXT_MUTED)
		h_line.add_child(arr)

		var idx := i
		row.mouse_entered.connect(
			func() -> void:
				_sub_index = idx
				_refresh_system()
		)
		row.gui_input.connect(
			func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					_sub_index = idx
					_confirm()
		)
		_system_box.add_child(row)


## 아이콘 칸 — 텍스처가 있으면 그림, 없으면 종류 색 + 글리프.
func _icon_slot(item_def: Dictionary, px: int) -> Control:
	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(px, px)
	icon.add_theme_stylebox_override(
		"panel", HudTheme.fill(ItemIcons.kind_color(StringName(str(item_def.get("kind", "")))), 5)
	)
	var tex := ItemIcons.texture(item_def)
	if tex != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = tex
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.add_child(tex_rect)
	else:
		var glyph := HudTheme.label(ItemIcons.glyph(item_def), int(px * 0.55), HudTheme.TEXT)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.add_child(glyph)
	return icon


func _refresh_detail() -> void:
	_clear(_detail_stats)
	if _rows.is_empty():
		_detail_name.text = ""
		_detail_kind.text = ""
		_detail_icon.texture = null
		_detail_glyph.text = ""
		_action_hint.text = ""
		return

	var slot: Dictionary = _rows[clampi(_index, 0, _rows.size() - 1)]
	var def := Database.get_item(StringName(str(slot["item_id"])))
	var kind := str(def.get("kind", ""))
	_detail_name.text = str(def.get("name_ko", str(slot["item_id"])))
	_detail_kind.text = tr(str(KIND_KEYS.get(kind, kind)))
	_detail_icon.texture = ItemIcons.texture(def)
	_detail_glyph.text = "" if _detail_icon.texture != null else ItemIcons.glyph(def)

	var desc := str(def.get("desc", ""))
	if not desc.is_empty():
		var body := HudTheme.label(desc, 12, HudTheme.TEXT_MUTED)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(200, 0)
		_detail_stats.add_child(body)
	if def.has("ap"):
		_add_stat("UI_BAG_ATK", str(int(def["ap"])))
	if def.has("dp"):
		_add_stat("UI_BAG_DEF", str(int(def["dp"])))
	if def.has("element") and str(def["element"]) != "physical":
		var el := str(def["element"])
		_add_stat("UI_BAG_ELEMENT", tr(str(ELEMENT_KEYS.get(el, el))))
	if def.has("hp_restore"):
		_add_stat("UI_BAG_HEAL", str(int(def["hp_restore"])))
	if def.has("price"):
		_add_stat("UI_BAG_PRICE", HudTheme.money(int(def["price"])))
	_action_hint.text = _hint_for(def, kind, str(slot["item_id"]))


## 수치 한 줄 — 이름(좌)·값(우)로 붙여 눈이 값만 훑을 수 있게 한다.
func _add_stat(label_key: String, value: String) -> void:
	var line := HBoxContainer.new()
	line.add_child(HudTheme.label(tr(label_key), 12, HudTheme.TEXT_MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(spacer)
	line.add_child(HudTheme.label(value, 12, HudTheme.TEXT))
	_detail_stats.add_child(line)


## 이 아이템에 SPACE를 누르면 무엇이 일어나는가 — 눌러 보기 전에 알려 준다.
func _hint_for(def: Dictionary, kind: String, item_id: String) -> String:
	if kind == "weapon" or kind == "armor":
		var equipped := str(GameState.equipped.get(kind, "")) == item_id
		return tr("UI_BAG_ACT_UNEQUIP") if equipped else tr("UI_BAG_ACT_EQUIP")
	if ItemEffects.is_usable(def, false):
		return tr("UI_BAG_ACT_USE")
	return tr("UI_BAG_ACT_NONE")
