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
	elif event.is_action_pressed(&"interact"):
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
	if GameState.equip(item_id):
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
	if _rows.is_empty():
		_list_box.add_child(HudTheme.label(tr("UI_BAG_EMPTY"), 13, HudTheme.TEXT_MUTED))
		_refresh_detail()
		return
	_index = clampi(_index, 0, _rows.size() - 1)
	_scroll_to_cursor()
	var page := GRID_COLS * GRID_ROWS
	for i in range(_top, mini(_rows.size(), _top + page)):
		_grid.add_child(_make_cell(i))
	if _rows.size() > page:
		var pos := HudTheme.label(
			tr("UI_BAG_POSITION") % [_index + 1, _rows.size()], 11, HudTheme.TEXT_MUTED
		)
		pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_list_box.add_child(pos)
	_refresh_detail()


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


## 장비 탭 — 칸마다 무엇이 끼워져 있고 그것이 무슨 수치를 주는지.
## 구판은 이 화면이 없어 목록의 `◆` 표시가 전부였다(04_uiux §1.3 "장비 슬롯 명시화").
func _refresh_gear() -> void:
	if _gear_box == null:
		return
	_clear(_gear_box)
	for i in GEAR_SLOTS.size():
		var slot := str(GEAR_SLOTS[i]["slot"])
		var def := GameState.equipped_in(slot)
		var row := PanelContainer.new()
		var selected := _tab == Tab.GEAR and i == _sub_index
		row.add_theme_stylebox_override(
			"panel",
			HudTheme.chip(HudTheme.ROW_SELECTED if selected else HudTheme.BG_SUNKEN, 6, 8, 5)
		)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		row.add_child(line)
		line.add_child(_icon_slot(def, 26))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(col)
		col.add_child(HudTheme.label(tr(str(GEAR_SLOTS[i]["key"])), 11, HudTheme.TEXT_MUTED))
		var empty := def.is_empty()
		col.add_child(
			HudTheme.label(
				tr("UI_GEAR_EMPTY") if empty else str(def.get("name_ko", "")),
				14,
				HudTheme.TEXT_MUTED if empty else HudTheme.EQUIPPED
			)
		)
		var num := 0
		if def.has("ap"):
			num = int(def["ap"])
		elif def.has("dp"):
			num = int(def["dp"])
		line.add_child(HudTheme.label("+%d" % num if num > 0 else "", 13, HudTheme.TEXT))
		_gear_box.add_child(row)
	_gear_box.add_child(HudTheme.label(tr("UI_GEAR_HINT"), 11, HudTheme.TEXT_MUTED))


## 상태 탭 — HUD가 좁아 못 싣는 수치를 한자리에(LV·EXP·HP·AP·DP·골드·스킬).
func _refresh_status() -> void:
	if _status_box == null:
		return
	_clear(_status_box)
	var rows := [
		["UI_STAT_LEVEL", str(int(GameState.player_stats.get("level", 1)))],
		["UI_STAT_HP", "%d / %d" % [int(GameState.player_stats.get("hp", 0)), GameState.max_hp()]],
		["UI_STAT_AP", str(GameState.attack_power())],
		["UI_STAT_DP", str(GameState.defense_power())],
		["UI_STAT_EXP", str(int(GameState.player_stats.get("exp", 0)))],
		["UI_STAT_MONEY", HudTheme.money(int(GameState.player_stats.get("money", 0)))],
	]
	for r: Array in rows:
		var line := HBoxContainer.new()
		line.add_child(HudTheme.label(tr(str(r[0])), 13, HudTheme.TEXT_MUTED))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(sp)
		line.add_child(HudTheme.label(str(r[1]), 13, HudTheme.TEXT))
		_status_box.add_child(line)


## 시스템 탭 — **기능을 다시 만들지 않는다.** 신호만 쏘고 필드가 기존 PauseMenu를 연다.
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
			HudTheme.chip(HudTheme.ROW_SELECTED if selected else HudTheme.BG_SUNKEN, 6, 8, 5)
		)
		row.add_child(
			HudTheme.label(
				tr(str(SYSTEM_ITEMS[i]["key"])), 14, HudTheme.ACCENT if selected else HudTheme.TEXT
			)
		)
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
