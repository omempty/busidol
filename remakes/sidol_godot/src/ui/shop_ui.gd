class_name ShopUI
extends CanvasLayer
## 상점 UI — 음식 구매로 HP 회복. 원작 store()의 현대판.
## 데이터: Database.items 중 kind=="consumable" 필터.

signal closed

const SHOP_ITEMS := [
	{"id": "ITEM_HERB_TEA", "name_ko": "생약차", "price": 50},
	{"id": "ITEM_MEDICINE", "name_ko": "의약품", "price": 100},
	{"id": "ITEM_ION_DRINK", "name_ko": "이온음료", "price": 150},
	{"id": "ITEM_UHWANGCHEONGSIM", "name_ko": "우황청심환", "price": 200},
	{"id": "ITEM_SAMGYETANG", "name_ko": "삼계탕", "price": 400},
	{"id": "ITEM_HONGSAM", "name_ko": "홍삼 액초", "price": 600},
]

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
	panel.custom_minimum_size = Vector2(360, 280)
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "=== 매점 ==="
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	_money_label = Label.new()
	_money_label.text = "소지금: %d온" % GameState.player_stats.get("money", 0)
	vbox.add_child(_money_label)

	for item_def in SHOP_ITEMS:
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = str(item_def["name_ko"])
		name_lbl.custom_minimum_size = Vector2(120, 0)
		row.add_child(name_lbl)

		var price_lbl := Label.new()
		price_lbl.text = "%d온" % int(item_def["price"])
		price_lbl.custom_minimum_size = Vector2(60, 0)
		row.add_child(price_lbl)

		var btn := Button.new()
		btn.text = "구매"
		btn.pressed.connect(_on_buy.bind(item_def))
		row.add_child(btn)
		vbox.add_child(row)

	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)


func _on_buy(item_def: Dictionary) -> void:
	var price := int(item_def["price"])
	var money: int = GameState.player_stats.get("money", 0)
	if money < price:
		return
	GameState.player_stats["money"] = money - price
	GameState.inventory.add(StringName(str(item_def["id"])))
	_money_label.text = "소지금: %d온" % GameState.player_stats["money"]
