class_name BattleResultPanel
extends CanvasLayer
## 전투 결과 요약(Q7) — 얻은 EXP·골드·레벨업을 보여 준다.
##
## 구판은 "WIN!" 라벨만 띄우고 보상을 조용히 적용했다. 레벨업은 `print()`로만 나가서
## 플레이어는 뭘 얼마나 얻었는지, 레벨이 올랐는지조차 알 수 없었다(04_uiux Q7).
##
## 입력으로 즉시 넘길 수 있고, 두지 않아도 AUTO_DISMISS 후 자동으로 닫힌다 —
## 헤드리스 스모크가 입력 없이도 진행되도록.

signal dismissed

const AUTO_DISMISS := 2.2
const PANEL_WIDTH := 260.0

var _elapsed := 0.0
var _armed := false


func show_summary(rewards: Dictionary, growth: Dictionary) -> void:
	layer = 40
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", HudTheme.panel(10, 14))
	add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	card.add_child(box)

	var title := HudTheme.label(tr("UI_RESULT_WIN"), 17, HudTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_divider())

	box.add_child(_row("EXP", "+%s" % HudTheme.grouped(int(rewards.get("exp", 0))), HudTheme.EXP))
	box.add_child(
		_row(
			tr("UI_RESULT_MONEY"),
			"+%s" % HudTheme.money(int(rewards.get("money", 0))),
			HudTheme.ACCENT
		)
	)

	if bool(growth.get("level_up", false)):
		box.add_child(_divider())
		box.add_child(_level_up_block(growth))

	box.add_child(_divider())
	var hint := HudTheme.label(tr("UI_RESULT_CONTINUE"), 11, HudTheme.TEXT_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_armed = true


func _process(delta: float) -> void:
	if not _armed:
		return
	_elapsed += delta
	if _elapsed >= AUTO_DISMISS or Input.is_action_pressed(&"interact"):
		_armed = false
		dismissed.emit()


## 레벨업 구간의 HP/AP 상승 총합 — grant_exp는 상승분을 돌려주지 않으므로
## 성장 테이블에서 (도달 레벨 − 오른 단계 + 1) ~ (도달 레벨)을 다시 합산한다.
func _level_up_block(growth: Dictionary) -> Control:
	var to_lv := int(growth.get("level", 1))
	var gained := maxi(int(growth.get("levels_gained", 1)), 1)
	var from_lv := to_lv - gained
	var hp_up := 0
	var ap_up := 0
	for entry: Dictionary in Database.level_table():
		var lv := int(entry.get("level", 0))
		if lv > from_lv and lv <= to_lv:
			hp_up += int(entry.get("hp_up", 0))
			ap_up += int(entry.get("ap_up", 0))

	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	var head := HudTheme.label("LEVEL UP   %d → %d" % [from_lv, to_lv], 14, HudTheme.HP_OK)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	block.add_child(head)
	if hp_up > 0:
		block.add_child(_row(tr("UI_RESULT_MAX_HP"), "+%d" % hp_up, HudTheme.HP_OK))
	if ap_up > 0:
		block.add_child(_row("AP", "+%d" % ap_up, HudTheme.HP_OK))
	return block


func _row(label: String, value: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_child(HudTheme.label(label, 12, HudTheme.TEXT_MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(HudTheme.label(value, 14, color))
	return row


func _divider() -> Control:
	var line := ColorRect.new()
	line.color = HudTheme.BORDER
	line.custom_minimum_size = Vector2(0, 1)
	return line
