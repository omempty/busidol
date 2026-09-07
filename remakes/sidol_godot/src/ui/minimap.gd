class_name MinimapLayer
extends CanvasLayer
## 미니맵(Q4) — M키 토글. 원작 map_view()의 현대판.
## 구판은 타일 ID를 해시해 색을 뽑아 지형이 아니라 노이즈로 보였다.
## 지금은 통행 의미(벽/바닥/문/상자)만 칠한다 — 길 찾기라는 용도에 맞춘 단색 스킴.
##
## **전장의 안개**(2026-09-07): 층에 들어서는 순간 13,000칸을 전부 칠하던 것을 그만두고
## 본 곳만 칠한다([[FogOfWar]]). 이 게임에서 전지(全知)인 표면은 여기 하나였다 —
## 필드는 화면이 30×17칸이라 이미 맵의 3.9%만 보인다.
##
## 다만 **가리기만 하면 퇴행이다.** 지금까지 상자 자리를 노랗게 찍어 주던 것이
## 사실상 물건 찾기의 보조바퀴였기 때문이다. 그래서 셋을 같이 넣는다:
##   ① 한 번 본 것은 계속 보인다(상자 포함) — 발견은 어렵게, 재방문은 쉽게
##   ② 프론티어 — 본 칸에 맞닿은 **아직 안 가 본 칸**을 호박색으로 찍는다.
##      "어디에 뭐가 있나"가 아니라 **"내가 어디를 안 가봤나"**를 알려주는 쪽이
##      길찾기의 실제 어려움이다. 예전 미니맵은 후자를 못 알려줬다.
##   ③ 탐험률 % — 이 층을 얼마나 훑었는지. 분모는 **걸어 닿는 칸**이다(FogOfWar 주석).
## 설정에서 끄면 예전 동작 그대로다(SettingsManager.fog_of_war).

const SCALE := 2
const MARGIN := 12.0
const DOT := 7.0

## ATT 값 → 미니맵 색. 근거: docs/01_analysis/03_data_format_spec.md §1 ATT 표.
const C_WALL := Color(0.10, 0.11, 0.15)
const C_FLOOR := Color(0.31, 0.34, 0.42)
const C_OVERHEAD := Color(0.23, 0.26, 0.33)
const C_DOOR := Color(0.99, 0.76, 0.31)
const C_CHEST := Color(0.96, 0.86, 0.36)
const C_ROOM := Color(0.42, 0.50, 0.63)  # NPC/방 식별값 — 통행은 막히나 지형은 아님
## 아직 못 본 칸 — 배경 패널보다 어둡게 둬 "지도가 거기서 끝난 것"처럼 보이지 않게 한다.
const C_UNSEEN := Color(0.05, 0.05, 0.08)
## 프론티어 — 본 칸에 맞닿은 미탐색 칸. 갈 수 있는데 아직 안 간 방향이다.
const C_FRONTIER := Color(0.58, 0.42, 0.18)
const CHEST_MIN := 150
const CHEST_MAX := 184

var _card: PanelContainer
var _image_view: TextureRect
var _dot: Panel
var _title: Label
var _player: PlayerEntity
var _visible_now := false
var _rt: MapRuntime
var _img: Image
var _tex: ImageTexture
## 다시 칠해야 하는가 — **보일 때만** 칠한다. 안개는 걸을 때마다 늘지만
## 지도가 닫혀 있는 동안 13,000칸을 다시 칠하는 것은 순전한 낭비다.
var _dirty := true


func _ready() -> void:
	layer = 20
	visible = false
	_build_card()


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_card.offset_right = -MARGIN
	_card.offset_bottom = -MARGIN
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", HudTheme.panel(10, 8))
	add_child(_card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	_card.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	_title = HudTheme.label("", 10, HudTheme.TEXT_MUTED)
	header.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(HudTheme.label(tr("UI_MAP_CLOSE"), 10, HudTheme.TEXT_MUTED))

	_image_view = TextureRect.new()
	_image_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_image_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_image_view)

	_dot = Panel.new()
	_dot.size = Vector2(DOT, DOT)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := HudTheme.fill(Color(0.96, 0.32, 0.32), 4)
	sb.border_color = Color(1, 1, 1, 0.9)
	sb.set_border_width_all(1)
	_dot.add_theme_stylebox_override("panel", sb)
	_image_view.add_child(_dot)


## **런타임을 받는다**(정의가 아니라). 안개는 통행 여부를 물어야 하고, 통행 여부는
## 상자 개봉 같은 오버라이드를 반영하는 MapRuntime 쪽이 정본이다.
func build(rt: MapRuntime) -> void:
	_rt = rt
	var def := rt.definition
	_img = Image.create(def.width, def.height, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	_image_view.texture = _tex
	_image_view.custom_minimum_size = Vector2(def.width * SCALE, def.height * SCALE)
	_dirty = true
	repaint()


## 안개가 늘었다 — 다음에 보일 때 다시 칠한다. 필드가 걸음마다 부른다.
func on_revealed() -> void:
	_dirty = true
	if visible:
		repaint()


## 한 장을 통째로 다시 칠한다. 여는 순간과 안개가 는 순간에만 돈다.
func repaint() -> void:
	if _img == null or _rt == null:
		return
	var def := _rt.definition
	# 필드와 **같은 판정**을 써야 한다 — 갈라지면 안개는 도는데 지도는 다 보인다.
	var fog_on: bool = SettingsManager.fog_of_war and FloorLighting.is_dark(GameState.current_floor)
	var floor_index := GameState.current_floor
	for y in def.height:
		for x in def.width:
			var cell := Vector2i(x, y)
			var col := color_for(def.attr_at(cell))
			if fog_on and not GameState.fog.is_seen(floor_index, def, cell):
				col = C_FRONTIER if _is_frontier(def, floor_index, cell) else C_UNSEEN
			_img.set_pixel(x, y, col)
	_tex.update(_img)
	_title.text = _title_text(def, fog_on)
	_dirty = false


## 아직 안 본 칸인데 **본 통행칸에 맞닿아** 있는가 — 갈 수 있는데 안 간 방향.
func _is_frontier(def: MapDefinition, floor_index: int, cell: Vector2i) -> bool:
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n := cell + d
		if not def.in_bounds(n):
			continue
		if _rt.is_passable(n) and GameState.fog.is_seen(floor_index, def, n):
			return true
	return false


## "F0 · 탐험 42%". 탐험률은 지도를 열 때만 센다 — 분모(걸어 닿는 칸)를 구하는
## 도달 판정이 층당 만 단위 BFS라 걸음마다 돌릴 것이 아니다(FogOfWar가 캐시한다).
func _title_text(def: MapDefinition, fog_on: bool) -> String:
	var base: String = tr("UI_MAP_TITLE") % def.map_id.to_upper()
	if not fog_on or _player == null:
		return base
	var ratio := GameState.fog.explored_ratio(GameState.current_floor, _rt, _player.mover.grid_pos)
	if ratio < 0.0:
		return base
	return base + "  " + (tr("UI_MAP_EXPLORED") % roundi(ratio * 100.0))


func track(player: PlayerEntity) -> void:
	_player = player


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"minimap"):
		_visible_now = not _visible_now
		visible = _visible_now
		# 열 때는 조건 없이 다시 칠한다 — 설정에서 안개를 껐다 켠 것도 여기서 반영된다.
		if _visible_now:
			repaint()
	if not (visible and _player != null and _image_view != null):
		return
	# 2×2 발판의 중심을 찍는다 — 셀 좌상단 기준이면 캐릭터가 반 칸 위로 보인다.
	var center := (Vector2(_player.mover.grid_pos) + Vector2.ONE) * SCALE
	_dot.position = center - Vector2(DOT, DOT) * 0.5


## ATT 한 칸의 색 — 미니맵과 맵 굽기 도구(tools/dev/map_shots.gd)가 같은 표를 쓴다.
## 색이 갈라지면 도구로 고른 좌표와 게임 안에서 보이는 지형이 어긋난다.
static func color_for(attr: int) -> Color:
	if attr >= CHEST_MIN and attr <= CHEST_MAX:
		return C_CHEST
	match attr:
		0:
			return C_FLOOR
		1:
			return C_WALL
		2:
			return C_OVERHEAD
		9:
			return C_DOOR
	return C_ROOM
