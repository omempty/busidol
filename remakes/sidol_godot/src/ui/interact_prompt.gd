class_name InteractPrompt
extends Node2D
## 상호작용 알약 — 조사 대상 머리 위에 뜨는 어두운 라운드 패널.
## 구판은 테마 없는 기본 Label 하나라 밝은 바닥 타일 위에서 글자가 묻혔다.
## 월드 좌표를 따라다니므로 CanvasLayer가 아니라 Node2D로 둔다.

const PAD := Vector2(9, 4)
const Z := 40

var _label: Label


func _ready() -> void:
	z_index = Z
	visible = false
	var sb := HudTheme.chip(HudTheme.BG, 8, int(PAD.x), int(PAD.y))
	sb.border_color = HudTheme.BORDER
	sb.set_border_width_all(1)
	sb.shadow_color = HudTheme.SHADOW
	sb.shadow_size = 4
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_label = HudTheme.label("", 12, HudTheme.TEXT)
	panel.add_child(_label)


## 월드 좌표 anchor의 위쪽 중앙에 띄운다.
## 패널 실측 size는 다음 프레임에야 갱신돼 첫 프레임이 어긋나므로
## 라벨 최소 크기 + 여백 + 테두리로 즉시 계산한다.
func show_at(text: String, anchor: Vector2) -> void:
	_label.text = text
	visible = true
	var box := _label.get_minimum_size() + PAD * 2.0 + Vector2(2, 2)
	position = anchor - Vector2(box.x * 0.5, box.y)
