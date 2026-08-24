class_name HudV0
extends CanvasLayer
## HUD v0 — 우측 상단 패널(LV/HP/EXP/AP/MONEY). 원작 8자리 숫자 스프라이트의 현대판.
## 품질 기준(docs/03_plan Phase 1): 처음부터 Control 포커스 내비 구조를 전제로 설계.
## TODO(Phase 4): 아이템 미니 슬롯 4칸 추가.

const STATS_LAYOUT := [
	["LV", "level"], ["HP", "hp"], ["EXP", "exp"], ["AP", "ap"], ["MONEY", "money"],
]

var _labels := {}


func _ready() -> void:
	layer = 10
	var panel := PanelContainer.new()
	panel.name = "StatsPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-170, 10)
	panel.custom_minimum_size = Vector2(160, 0)
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	for entry in STATS_LAYOUT:
		var row := HBoxContainer.new()
		var cap := Label.new()
		cap.text = entry[0]
		cap.custom_minimum_size = Vector2(64, 0)
		cap.modulate = Color(1, 1, 1, 0.65)
		row.add_child(cap)
		var val := Label.new()
		val.name = StringName(entry[1])
		row.add_child(val)
		vbox.add_child(row)
		_labels[entry[1]] = val
	refresh()
	GameState.state_changed.connect(refresh)


func refresh() -> void:
	var stats: Dictionary = GameState.player_stats
	for entry in STATS_LAYOUT:
		var key: String = entry[1]
		var label: Label = _labels[key]
		label.text = str(stats.get(key, 0))
