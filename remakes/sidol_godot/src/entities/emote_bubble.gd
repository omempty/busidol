class_name EmoteBubble
extends Node2D
## 머리 위 한 글자 말풍선(…, ?, !) — 주목·정보·경고 어휘.
##
## 어휘 분리(2026-09-11): 빨간 `!`는 괴물 위험 전용(적 추적 경고·워커 `!`)이라
## 대화 강조에 같이 쓰면 희석된다. 대화는 `…`(주목) · `?`(새 정보)만 쓴다.
##
## 스프라이트 확대·회전이 금지인 픽셀 규약(npc_entity.gd 머리 주석)에서도
## UI 텍스트는 벡터 렌더라 리샘플이 없다. 위치는 정수에 둔다.
## 기호만 쓴다 — 자연어 UI 문자열이 아니라 번역표(ui.csv) 대상이 아니다.

const HOLD := 1.1
const HEAD_Y := -92.0
const BOX_W := 38.0
## 대화 어휘 색 — 경고 빨강과 겹치지 않게 흰·하늘만 쓴다.
const COLOR_SPOT := Color(0.92, 0.92, 0.96)
const COLOR_NEWINFO := Color(0.55, 0.80, 1.00)


## 액터 머리 위에 기호를 띄운다. 이미 있으면 새 것이 이긴다(연타 방지).
static func pop(actor: Node2D, glyph: String, color: Color = COLOR_SPOT) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	for c in actor.get_children():
		if c is EmoteBubble:
			c.queue_free()
	var b := EmoteBubble.new()
	b.position = Vector2(0, HEAD_Y)
	b.z_index = 30
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(BOX_W, 0)
	panel.add_theme_stylebox_override(
		"panel", HudTheme.chip(Color(0.07, 0.07, 0.11, 0.92), 8, 8, 2)
	)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := HudTheme.label(glyph, 18, color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(BOX_W, 0)
	panel.add_child(lbl)
	panel.position = Vector2(-BOX_W * 0.5, -30)
	b.add_child(panel)
	actor.add_child(b)
	b.scale = Vector2.ONE * 0.5
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_interval(HOLD)
	tw.tween_property(b, "modulate:a", 0.0, 0.25)
	tw.tween_callback(b.queue_free)
