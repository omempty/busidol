class_name DoorPlates
extends Node2D
## 주요 방 문패 — 문(ATT 9) 위의 방 이름표. 원작 타일은 동결이라 런타임 표시다.
## 데이터: data/maps/door_plates.json (메모장 편집 가능 — 방 추가는 좌표 한 줄).
## 가까이 가면 보인다(상시 표시하면 복도가 간판으로 덮인다). NPC 알약과 같은 어휘.

const PLATES_PATH := "res://data/maps/door_plates.json"
const SHOW_DIST := 7  # 맨해튼 — 복도에서 문이 보이기 시작하는 거리
const MAX_LABELS := 6
const Z := 34  # 액터 위, 알약(40) 아래
const PAD := Vector2(8, 3)

var _plates: Array = []  # [{cell: Vector2i, ko: String, en: String}, ...]
var _pool: Array = []  # PanelContainer (자식 Label)


func setup(floor_no: int) -> void:
	z_index = Z
	_plates.clear()
	if not FileAccess.file_exists(PLATES_PATH):
		push_warning("DoorPlates: %s 없음 — 문패 없이 진행" % PLATES_PATH)
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLATES_PATH))
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("DoorPlates: 파싱 실패")
		return
	for entry: Variant in Dictionary(raw).get("plates", {}).get(str(floor_no), []):
		if not (entry is Dictionary):
			continue
		var xy: Array = entry.get("cell", [])
		if xy.size() < 2:
			continue
		(
			_plates
			. append(
				{
					"cell": Vector2i(int(xy[0]), int(xy[1])),
					"ko": str(entry.get("name_ko", "")),
					"en": str(entry.get("name_en", "")),
				}
			)
		)
	for _i in MAX_LABELS:
		var panel := PanelContainer.new()
		var sb := HudTheme.chip(HudTheme.BG, 7, int(PAD.x), int(PAD.y))
		sb.border_color = HudTheme.BORDER
		sb.set_border_width_all(1)
		panel.add_theme_stylebox_override("panel", sb)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.visible = false
		var lbl := HudTheme.label("", 12, HudTheme.TEXT)
		panel.add_child(lbl)
		add_child(panel)
		_pool.append(panel)


## 가까운 문패부터 풀에 채운다. 매 프레임 호출 — 문패가 몇 개 없어 값싸다.
func tick(player_cell: Vector2i) -> void:
	if _plates.is_empty():
		return
	var ranked: Array = _plates.duplicate()
	ranked.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return _dist(a, player_cell) < _dist(b, player_cell)
	)
	var shown := 0
	for p: Dictionary in ranked:
		if shown >= MAX_LABELS:
			break
		if _dist(p, player_cell) > SHOW_DIST:
			continue
		var panel: PanelContainer = _pool[shown]
		var lbl: Label = panel.get_child(0)
		lbl.text = str(p["ko"] if int(SettingsManager.language) == 0 else p["en"])
		var cell: Vector2i = p["cell"]
		var box := lbl.get_minimum_size() + PAD * 2.0 + Vector2(2, 2)
		panel.position = (
			Vector2(cell) * MapDefinition.TILE_PX
			+ Vector2(MapDefinition.TILE_PX, -34)
			- Vector2(box.x * 0.5, box.y)
		)
		panel.visible = true
		shown += 1
	for i in range(shown, MAX_LABELS):
		(_pool[i] as PanelContainer).visible = false


func _dist(p: Dictionary, player_cell: Vector2i) -> int:
	var d: Vector2i = (p["cell"] as Vector2i) - player_cell
	return absi(d.x) + absi(d.y)
