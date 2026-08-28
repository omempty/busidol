class_name ShopUI
extends CanvasLayer
## 상점 UI — 음식 구매로 HP 회복. 원작 store()의 현대판.
##
## 재고는 data/shops.json, 이름·가격은 data/items.json이 소유한다.
## 구판은 품목 6종과 가격이 이 소스에 하드코딩돼 있었다(AGENTS.md 콘텐츠 하드코딩 금지 위반) —
## 난이도의 item_price_mult를 곱하려 해도 곱할 데이터가 없었다.

signal closed

const SHOP_ID := "default"
const PANEL_SIZE := Vector2(400, 420)

var _money_label: Label
var _open := false


func _ready() -> void:
	layer = 40
	visible = false


func open() -> void:
	_open = true
	visible = true
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

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	# 중앙 정렬은 양방향 성장으로 — PRESET_CENTER만으로는 좌상단이 화면 중앙에 놓인다.
	# 내용에 맡기면 재고 22종이 세로 766px로 자라 화면을 넘는다(감사가 적발).
	# 중앙 고정 크기로 못 박고 목록만 안에서 스크롤한다.
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5
	panel.add_theme_stylebox_override("panel", HudTheme.panel(10, 12))
	add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	panel.add_child(outer)

	var title := HudTheme.label(tr("UI_SHOP_TITLE"), 16, HudTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	_money_label = HudTheme.label("", 13, HudTheme.TEXT)
	_money_label.text = (
		tr("UI_SHOP_MONEY") % HudTheme.money(GameState.player_stats.get("money", 0))
	)
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	outer.add_child(_money_label)

	# 재고가 22종으로 늘어 고정 높이로는 화면을 넘친다 — 스크롤 안에 담는다.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	for item_def in _stock():
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = str(item_def["name_ko"])
		name_lbl.custom_minimum_size = Vector2(120, 0)
		row.add_child(name_lbl)

		var price_lbl := Label.new()
		price_lbl.text = HudTheme.money(_price(item_def))
		price_lbl.custom_minimum_size = Vector2(60, 0)
		row.add_child(price_lbl)

		var btn := Button.new()
		btn.text = tr("UI_SHOP_BUY")
		btn.pressed.connect(_on_buy.bind(item_def))
		row.add_child(btn)
		vbox.add_child(row)

	var close_btn := Button.new()
	close_btn.text = tr("UI_SHOP_CLOSE")
	close_btn.pressed.connect(close)
	outer.add_child(close_btn)


## 재고 목록 — shops.json의 id 순서대로 items.json 정의를 끌어온다.
func _stock() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var shops: Dictionary = JsonUtil.load_dict("res://data/shops.json", "ShopUI").get("shops", {})
	var entry: Dictionary = shops.get(SHOP_ID, {})
	for item_id: String in entry.get("stock", []):
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


func _on_buy(item_def: Dictionary) -> void:
	var price := _price(item_def)
	var money: int = GameState.player_stats.get("money", 0)
	if money < price:
		return
	GameState.player_stats["money"] = money - price
	GameState.inventory.add(StringName(str(item_def["id"])))
	_money_label.text = tr("UI_SHOP_MONEY") % HudTheme.money(GameState.player_stats["money"])
