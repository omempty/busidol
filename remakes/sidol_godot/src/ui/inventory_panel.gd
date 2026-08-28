class_name InventoryPanel
extends CanvasLayer
## 인벤토리 창(I키) — 좌측 목록(커서)+우측 상세. 열려 있는 동안 월드 정지(PauseMenu와 동일 규약).
## 표시 데이터는 전부 data/items.json 경유(콘텐츠 하드코딩 금지).
##
## 2026-08-28 정리: ① 목록이 앞 9줄만 그려 10번째부터는 **커서가 안 보이는 곳으로 갔다**
## (창 스크롤로 해결) ② 상세에 kind/element 영문 내부값이 그대로 노출됐다(번역 키로 교체)
## ③ 창 껍데기를 ModalFrame으로 통일.

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

var _list_box: VBoxContainer
var _detail_icon: TextureRect
var _detail_glyph: Label
var _detail_name: Label
var _detail_kind: Label
var _detail_stats: VBoxContainer
var _action_hint: Label
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
	_frame.setup("UI_BAG_TITLE", "UI_BAG_HINT", Vector2(620, 360))
	add_child(_frame)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	_frame.body.add_child(columns)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 2)
	columns.add_child(_list_box)

	columns.add_child(_build_detail())


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
	visible = true
	get_tree().paused = true
	_rebuild_list()


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
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_up"):
		_move(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_down"):
		_move(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact"):
		_use_selected()
		get_viewport().set_input_as_handled()


## 선택 항목에 SPACE — 무기/방어구면 장착·해제, 회복 아이템이면 사용.
## 구판은 인벤토리가 표시 전용이라 무기 19종과 회복 아이템이 여기서 아무것도 못 했다.
func _use_selected() -> void:
	if _rows.is_empty():
		return
	var slot: Dictionary = _rows[clampi(_index, 0, _rows.size() - 1)]
	var item_id := StringName(str(slot["item_id"]))
	if GameState.equip(item_id):
		_rebuild_list()
		return
	var def := Database.get_item(item_id)
	var note := ItemEffects.use_on_field(def)
	if note.is_empty():
		return  # 필드에서 못 쓰는 것(전투 전용·만HP)은 조용히 무시
	GameState.inventory.remove(item_id, 1)
	_rebuild_list()


func _move(delta: int) -> void:
	if _rows.is_empty():
		return
	_index = wrapi(_index + delta, 0, _rows.size())
	_scroll_to_cursor()
	_rebuild_list()


## 커서가 창 밖으로 나가면 창을 민다 — 커서가 안 보이는 줄로 사라지지 않게.
func _scroll_to_cursor() -> void:
	if _index < _top:
		_top = _index
	elif _index >= _top + MAX_ROWS_SHOWN:
		_top = _index - MAX_ROWS_SHOWN + 1
	_top = clampi(_top, 0, maxi(_rows.size() - MAX_ROWS_SHOWN, 0))


func _rebuild_list() -> void:
	_rows = GameState.inventory.all_slots()
	for child in _list_box.get_children():
		child.queue_free()
	if _rows.is_empty():
		_list_box.add_child(HudTheme.label(tr("UI_BAG_EMPTY"), 13, HudTheme.TEXT_MUTED))
		_refresh_detail()
		return
	_index = clampi(_index, 0, _rows.size() - 1)
	_scroll_to_cursor()
	for i in range(_top, mini(_rows.size(), _top + MAX_ROWS_SHOWN)):
		_list_box.add_child(_make_row(i))
	if _rows.size() > MAX_ROWS_SHOWN:
		var pos := HudTheme.label(
			tr("UI_BAG_POSITION") % [_index + 1, _rows.size()], 11, HudTheme.TEXT_MUTED
		)
		pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_list_box.add_child(pos)
	_refresh_detail()


func _make_row(i: int) -> Control:
	var slot: Dictionary = _rows[i]
	var item_def := Database.get_item(StringName(str(slot["item_id"])))
	var selected := i == _index

	var shell := PanelContainer.new()
	if selected:
		shell.add_theme_stylebox_override("panel", HudTheme.chip(HudTheme.ROW_SELECTED, 6, 4, 2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	shell.add_child(row)

	# 커서는 고정 폭 칸에 둔다 — 글자 앞에 붙이면 선택이 옮겨질 때마다 행이 좌우로 튄다.
	var cursor := HudTheme.label("▶" if selected else "", 13, HudTheme.ACCENT)
	cursor.custom_minimum_size = Vector2(14, 0)
	row.add_child(cursor)
	row.add_child(_icon_slot(item_def, 26))

	var slot_name := str(item_def.get("kind", ""))
	var equipped_here := str(GameState.equipped.get(slot_name, "")) == str(slot["item_id"])
	var name_label := HudTheme.label(
		("◆ " if equipped_here else "") + str(item_def.get("name_ko", str(slot["item_id"]))),
		14,
		HudTheme.EQUIPPED if equipped_here else HudTheme.TEXT
	)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	row.add_child(HudTheme.label("×%d" % int(slot["count"]), 12, HudTheme.TEXT_MUTED))
	return shell


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
	for child in _detail_stats.get_children():
		child.queue_free()
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
