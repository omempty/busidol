class_name HudSlotBar
extends HBoxContainer
## 좌하단 상시 아이템 슬롯 — 소지품 앞 SLOT_COUNT칸.
## 구판은 빈 칸까지 항상 6개를 깔아 화면 아래를 회색 상자로 채웠다.
## 지금은 보유분만 그리고, 하나도 없으면 바 자체를 숨긴다.

const SLOT_COUNT := 6
const SLOT_SIZE := 38.0


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 12
	offset_top = -12.0 - SLOT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func refresh(slots: Array[Dictionary]) -> void:
	for child in get_children():
		child.queue_free()
	visible = not slots.is_empty()
	if not visible:
		return
	for i in mini(SLOT_COUNT, slots.size()):
		add_child(_make_slot(slots[i]))
	if slots.size() > SLOT_COUNT:
		add_child(_make_more(slots.size() - SLOT_COUNT))


func _make_slot(slot: Dictionary) -> PanelContainer:
	var item_def := Database.get_item(StringName(str(slot["item_id"])))
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	box.tooltip_text = str(item_def.get("name_ko", slot["item_id"]))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kind := ItemIcons.kind_color(StringName(str(item_def.get("kind", ""))))
	var sb := HudTheme.panel(8, 3)
	sb.bg_color = Color(kind.r * 0.45, kind.g * 0.45, kind.b * 0.45, 0.92)
	sb.border_color = Color(kind, 0.75)
	sb.shadow_size = 3
	box.add_theme_stylebox_override("panel", sb)
	box.add_child(_icon(item_def))
	box.add_child(_count_badge(int(slot["count"])))
	return box


func _icon(item_def: Dictionary) -> Control:
	var tex := ItemIcons.texture(item_def)
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	var glyph := HudTheme.label(ItemIcons.glyph(item_def), 17, HudTheme.TEXT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return glyph


## 수량 배지 — 아이콘 위 우하단. PanelContainer는 자식을 늘려 채우므로 앵커·오프셋이 아니라
## 정렬로 붙인다(구판은 오프셋을 줘 배지가 슬롯 밖으로 잘려 나갔다).
func _count_badge(count: int) -> Control:
	var badge := HudTheme.outlined_label(str(count), 10, HudTheme.TEXT)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return badge


func _make_more(extra: int) -> Control:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", HudTheme.panel(8, 3))
	var l := HudTheme.label("+%d" % extra, 12, HudTheme.TEXT_MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(l)
	return chip
