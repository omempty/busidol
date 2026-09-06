class_name ShopUI
extends CanvasLayer
## 상점 UI — 구매로 회복 아이템·장비를 산다. 원작 store()의 현대판.
##
## 재고는 data/shops.json, 이름·가격은 data/items.json이 소유한다.
## 구판은 품목 6종과 가격이 이 소스에 하드코딩돼 있었다(AGENTS.md 콘텐츠 하드코딩 금지 위반).
##
## 2026-08-28 조작성 정리: 구판은 행마다 "구매" 버튼만 있어 **마우스 전용**이었고
## (필드·가방·전투는 전부 키보드) 아이콘·효과·소지금 부족 여부가 보이지 않았다.
## 이제 ↑↓ 선택 · SPACE 구매 · ESC 닫기로 나머지 UI와 조작이 같다.

signal closed

const SHOP_ID := "default"
const ROWS_SHOWN := 8

var _money_label: Label
var _list_box: VBoxContainer
var _detail: Label
var _stock_cache: Array[Dictionary] = []
var _index := 0
var _top := 0
var _open := false


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open() -> void:
	_open = true
	visible = true
	_index = 0
	_top = 0
	_build()


func close() -> void:
	_open = false
	visible = false
	closed.emit()


func is_open() -> bool:
	return _open


func _build() -> void:
	for c in get_children():
		c.queue_free()

	var frame := ModalFrame.new()
	frame.setup("UI_SHOP_TITLE", "UI_SHOP_HINT", Vector2(460, 340))
	frame.dismissed.connect(close)
	add_child(frame)

	_money_label = HudTheme.label("", 13, HudTheme.ACCENT)
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	frame.body.add_child(_money_label)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 2)
	frame.body.add_child(_list_box)

	_detail = HudTheme.label("", 12, HudTheme.TEXT_MUTED)
	frame.body.add_child(_detail)

	_stock_cache = _stock()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_up"):
		_move(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_down"):
		_move(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		_buy_selected()
		get_viewport().set_input_as_handled()


func _move(delta: int) -> void:
	if _stock_cache.is_empty():
		return
	_index = wrapi(_index + delta, 0, _stock_cache.size())
	if _index < _top:
		_top = _index
	elif _index >= _top + ROWS_SHOWN:
		_top = _index - ROWS_SHOWN + 1
	_top = clampi(_top, 0, maxi(_stock_cache.size() - ROWS_SHOWN, 0))
	_refresh()


func _refresh() -> void:
	for child in _list_box.get_children():
		child.queue_free()
	var money: int = GameState.player_stats.get("money", 0)
	_money_label.text = tr("UI_SHOP_MONEY") % HudTheme.money(money)
	if _stock_cache.is_empty():
		_list_box.add_child(HudTheme.label(tr("UI_SHOP_EMPTY"), 13, HudTheme.TEXT_MUTED))
		_detail.text = ""
		return
	for i in range(_top, mini(_stock_cache.size(), _top + ROWS_SHOWN)):
		_list_box.add_child(_make_row(i, money))
	_detail.text = _describe(_stock_cache[_index], money)


func _make_row(i: int, money: int) -> Control:
	var def := _stock_cache[i]
	var price := _price(def)
	var selected := i == _index
	var affordable := money >= price

	var shell := PanelContainer.new()
	shell.mouse_filter = Control.MOUSE_FILTER_STOP
	shell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if selected:
		shell.add_theme_stylebox_override("panel", HudTheme.chip(HudTheme.ROW_SELECTED, 6, 4, 2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	shell.add_child(row)

	var cursor := HudTheme.label("▶" if selected else "", 13, HudTheme.ACCENT)
	cursor.custom_minimum_size = Vector2(14, 0)
	row.add_child(cursor)
	row.add_child(_icon(def))

	# 살 수 없는 물건은 흐리게 — 값을 계산해 보기 전에 눈으로 걸러진다.
	var tint := HudTheme.TEXT if affordable else HudTheme.TEXT_MUTED
	var name_lbl := HudTheme.label(str(def.get("name_ko", def.get("id", ""))), 14, tint)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var price_lbl := HudTheme.label(
		HudTheme.money(price), 13, HudTheme.ACCENT if affordable else HudTheme.HP_LOW
	)
	row.add_child(price_lbl)

	var idx := i
	shell.mouse_entered.connect(
		func() -> void:
			if _index != idx:
				_index = idx
				_refresh()
	)
	shell.gui_input.connect(
		func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed:
				if e.button_index == MOUSE_BUTTON_LEFT:
					_index = idx
					_buy_selected()
				elif e.button_index == MOUSE_BUTTON_RIGHT:
					close()
	)
	return shell


func _icon(def: Dictionary) -> Control:
	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(24, 24)
	icon.add_theme_stylebox_override(
		"panel", HudTheme.fill(ItemIcons.kind_color(StringName(str(def.get("kind", "")))), 5)
	)
	var tex := ItemIcons.texture(def)
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.add_child(rect)
	else:
		var glyph := HudTheme.label(ItemIcons.glyph(def), 13, HudTheme.TEXT)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.add_child(glyph)
	return icon


## 선택 항목 한 줄 요약 — 무엇을 사는지 모르고 사던 것을 없앤다.
func _describe(def: Dictionary, money: int) -> String:
	var parts: Array[String] = []
	if def.has("hp_restore"):
		parts.append("%s %d" % [tr("UI_BAG_HEAL"), int(def["hp_restore"])])
	if def.has("ap"):
		parts.append("%s %d" % [tr("UI_BAG_ATK"), int(def["ap"])])
	if def.has("dp"):
		parts.append("%s %d" % [tr("UI_BAG_DEF"), int(def["dp"])])
	if money < _price(def):
		parts.append(tr("UI_SHOP_NO_MONEY"))
	return "   ".join(parts)


## 재고 목록 — shops.json의 id 순서대로 items.json 정의를 끌어온다.
func _stock() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var shops: Dictionary = JsonUtil.load_dict("res://data/shops.json", "ShopUI").get("shops", {})
	var entry: Dictionary = shops.get(SHOP_ID, {})
	# 해금 플래그 — 아직 안 선 품목은 매대에 오르지 않는다. 방어구를 게이팅하는 자리다
	# (2026-09-06: 시작 소지금 5,000온이 최상급 방어구 값과 같아 5분 만에 전투가 끝났다).
	var gate: Dictionary = entry.get("stock_requires", {})
	for item_id: String in entry.get("stock", []):
		var need := str(gate.get(item_id, ""))
		if not need.is_empty() and not GameState.has_flag(need):
			continue
		var def := Database.get_item(StringName(item_id))
		if def.is_empty():
			push_warning("상점 재고에 없는 아이템: %s" % item_id)
			continue
		out.append(def)
	return out


## 난이도의 item_price_mult 반영 — 쉬움이면 싸게, 도전이면 비싸게.
func _price(item_def: Dictionary) -> int:
	var base := int(item_def.get("price", 0))
	return maxi(1, int(round(float(base) * SettingsManager.difficulty_mult("item_price_mult"))))


func _buy_selected() -> void:
	if _stock_cache.is_empty():
		return
	var def := _stock_cache[clampi(_index, 0, _stock_cache.size() - 1)]
	var price := _price(def)
	var money: int = GameState.player_stats.get("money", 0)
	if money < price:
		AudioManager.play_sfx(&"sfx_menu_move")
		return
	GameState.player_stats["money"] = money - price
	GameState.inventory.add(StringName(str(def["id"])))
	AudioManager.play_sfx(&"sfx_item_get")
	_refresh()
