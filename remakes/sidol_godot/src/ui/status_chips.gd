class_name StatusChips
## 상태이상 칩 — 부착된 효과의 종류와 잔여 턴을 한 줄로 보여 준다.
##
## DoT/방어 버프/마비 시스템은 동작하고 있었으나 화면에 아무 표시가 없어
## 플레이어가 "왜 피가 계속 닳는지" "왜 턴을 걸렀는지" 알 수 없었다(04_uiux §1.4).
##
## 아이콘 아트가 아직 없으므로 브레이크 게이지(ASCII 핍)와 같은 어휘로 짧은 한글 칩을 쓴다.
## 아이콘이 들어오면 라벨 자리만 TextureRect로 바꾸면 된다.

## Combatant.active_effects의 kind → (표기, 색)
const LABELS := {
	&"dot": "지속",
	&"buff_damage_taken": "방어",
	&"paralysis": "마비",
	&"buff_attack": "공격",
	&"buff_status_resist": "저항",
}
const COLORS := {
	&"dot": Color(0.94, 0.45, 0.30),
	&"buff_damage_taken": Color(0.45, 0.68, 0.96),
	&"paralysis": Color(0.96, 0.84, 0.32),
	&"buff_attack": Color(0.98, 0.60, 0.35),
	&"buff_status_resist": Color(0.62, 0.86, 0.72),
}
const FONT_SIZE := 9


static func make_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


## 효과 목록을 칩으로 다시 그린다. 효과가 없으면 줄 자체가 사라진다(빈 자리 차지 금지).
static func refresh(row: HBoxContainer, effects: Array[Dictionary]) -> void:
	for child in row.get_children():
		child.queue_free()
	row.visible = not effects.is_empty()
	for fx: Dictionary in effects:
		var kind: StringName = fx.get("kind", &"")
		if not LABELS.has(kind):
			continue
		row.add_child(_chip(String(LABELS[kind]), int(fx.get("turns", 0)), COLORS[kind]))


static func _chip(text: String, turns: int, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := HudTheme.chip(Color(color.r, color.g, color.b, 0.22), 3, 4, 1)
	sb.border_color = Color(color, 0.8)
	sb.set_border_width_all(1)
	chip.add_theme_stylebox_override("panel", sb)
	var label := HudTheme.label("%s %d" % [text, maxi(turns, 0)], FONT_SIZE, color)
	chip.add_child(label)
	return chip
