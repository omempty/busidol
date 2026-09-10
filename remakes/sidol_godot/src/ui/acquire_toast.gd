class_name AcquireToast
extends CanvasLayer
## 획득 알림 — **얻은 줄 모르면 얻은 것이 아니다.**
##
## 왜 생겼나(2026-09-06). 마스터 시나리오 §2.2의 성장 트리(스킬 4종)를 배선했는데,
## 습득 신호가 콘솔 `print` 하나뿐이라 화면에는 아무 일도 일어나지 않았다. 상자에서
## 나오는 아이템도 마찬가지였다. 보상이 인지되지 않으면 보상 설계 전체가 없는 것과 같다.
##
## 화면 어휘는 기존 것을 따른다 — 문패·NPC 알약과 같은 칩(HudTheme.chip) 모양으로,
## 우상단에 잠깐 떴다가 사라진다. 여러 개가 한꺼번에 들어오면 줄을 세운다(컷신 하나가
## 아이템과 스킬을 같이 주는 경우가 있다).

const SHOW_TIME := 2.6
const FADE_TIME := 0.45
const MAX_ROWS := 3
const Z_LAYER := 55  # 대사창(41)·미니게임(45) 위, 개발자 좌표(60) 아래

var _box: VBoxContainer


func _ready() -> void:
	layer = Z_LAYER
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	margin.offset_left = -420
	margin.offset_right = -18
	margin.offset_top = 14
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_box.add_theme_constant_override("separation", 5)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_box)
	GameState.acquired.connect(_on_acquired)


func _on_acquired(kind: StringName, id: StringName, amount: int) -> void:
	var label := _describe(kind, id, amount)
	if label.is_empty():
		return
	show_text(label, HudTheme.ACCENT if kind == &"skill" else HudTheme.TEXT)


## 이름은 **데이터가 정한다** — 여기 문자열을 박으면 개명 때 이 자리가 빠진다
## (2026-08-30 「부싯돌 → 시돌」 개명에서 실제로 겪은 자리).
func _describe(kind: StringName, id: StringName, amount: int) -> String:
	if kind == &"heal":
		return tr("UI_ACQUIRE_HEAL") % amount
	if kind == &"skill":
		for sk: Dictionary in _all_skills():
			if str(sk.get("id", "")) == String(id):
				return tr("UI_ACQUIRE_SKILL") % str(sk.get("display_key", String(id)))
		return tr("UI_ACQUIRE_SKILL") % String(id)
	var def := Database.get_item(id)
	var nm := str(def.get("name_ko", String(id)))
	if amount > 1:
		return tr("UI_ACQUIRE_ITEM_N") % [nm, amount]
	return tr("UI_ACQUIRE_ITEM") % nm


func _all_skills() -> Array:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/skills.json"))
	if typeof(raw) != TYPE_DICTIONARY:
		return []
	return (raw as Dictionary).get("skills", [])


## 직접 띄우기 — 시그널을 거치지 않는 알림(디버그·연출)도 같은 어휘를 쓰게 열어 둔다.
func show_text(text: String, color: Color) -> void:
	if _box == null:
		return
	while _box.get_child_count() >= MAX_ROWS:
		var oldest := _box.get_child(0)
		_box.remove_child(oldest)
		oldest.queue_free()
	var panel := PanelContainer.new()
	var sb := HudTheme.chip(Color(0.10, 0.12, 0.17, 0.94), 6, 12, 6)
	sb.border_color = Color(color, 0.75)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var lbl := HudTheme.label(text, 14, color)
	panel.add_child(lbl)
	_box.add_child(panel)
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.16)
	tw.tween_interval(SHOW_TIME)
	tw.tween_property(panel, "modulate:a", 0.0, FADE_TIME)
	tw.tween_callback(panel.queue_free)
	AudioManager.play_sfx(&"sfx_item_get")
