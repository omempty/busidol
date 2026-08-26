class_name EnemyEntity
extends Node2D
## 필드 몬스터 데이터+비주얼. 이동 판정은 EnemyManager가 수행(순환 참조 방지).
## 시트는 SpriteSets 경유(<species>_original/_remake) — 부재 시 플레이스홀더 폴백.
## 몸은 플레이어와 같은 2×2(Placement.BODY) — 그리는 크기와 막는 크기를 맞춘다.

const FALLBACK_SHEET := "res://assets/sprites/player_placeholder.png"
const FALLBACK_META := "res://assets/sprites/player_placeholder.json"
## 기본 행동 주기(초) — 패턴별 값은 EnemyManager가 덮어쓴다.
const DEFAULT_ACT_INTERVAL := 0.34
## 추적 경고 표식 — 몸 위쪽으로 충분히 띄워 스프라이트와 겹치지 않게.
const ALERT_COLOR := Color(1.0, 0.42, 0.30)
const ALERT_Y := -62.0

var species_id: StringName
var display_name := ""
var mover := GridMover.new()
var sprite := AnimatedSprite2D.new()
var act_interval := DEFAULT_ACT_INTERVAL
var facing := &"down"

var _paths: Dictionary = {}
var _meta: Dictionary = {}
var _pose := &""
var _alert: PanelContainer
var _alerted := false


func setup(p_id: StringName, p_cell: Vector2i, tint: Color) -> void:
	species_id = p_id
	display_name = String(p_id)
	# 종별 시트 우선 — 부재 시 플레이스홀더(quiet: 신규 종 미정착은 정상 경로)
	_paths = SpriteSets.character_sheet(species_id, true)
	if str(_paths["sheet"]).is_empty():
		_paths = {"sheet": FALLBACK_SHEET, "meta": FALLBACK_META}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(_paths["meta"])))
	if typeof(raw) == TYPE_DICTIONARY:
		_meta = raw
	add_child(sprite)
	sprite.sprite_frames = _build_frames()
	if not _meta.is_empty():
		sprite.scale = Vector2.ONE * float(_meta.get("scale", 1.0))
		sprite.offset = Vector2(0.0, SpriteSets.foot_offset(_meta))
	modulate = tint
	z_index = 15
	ShadowBlob.attach(self)
	mover.body = self
	mover.grid_pos = p_cell
	position = GridMover.block_center(p_cell)
	add_to_group(&"enemies")
	_build_alert_marker()
	face(Vector2i.DOWN)


## 추적 경고 표식 — 접촉이 곧 강제 전투이므로 "지금 쫓기고 있다"가 보여야
## 플레이어가 피할 수 있다(Q6 현대 편의). 머리 위 느낌표 + 몸통 붉은 기.
func _build_alert_marker() -> void:
	# 맨 라벨은 6px 폭이라 어수선한 타일 위에서 묻힌다 — 어두운 칩에 얹어 대비를 준다.
	_alert = PanelContainer.new()
	var sb := HudTheme.chip(Color(0.10, 0.04, 0.04, 0.92), 5, 7, 1)
	sb.border_color = ALERT_COLOR
	sb.set_border_width_all(1)
	_alert.add_theme_stylebox_override("panel", sb)
	_alert.position = Vector2(-9, ALERT_Y)
	_alert.visible = false
	_alert.z_index = 20
	_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := HudTheme.label("!", 15, ALERT_COLOR)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert.add_child(mark)
	add_child(_alert)


func set_alerted(on: bool) -> void:
	if on == _alerted or _alert == null:
		return
	_alerted = on
	_alert.visible = on
	modulate = Color(1.0, 0.72, 0.68) if on else Color.WHITE
	if not on:
		return
	# 짧게 튀어 오르는 등장 — 정지 표식보다 시야에 걸린다.
	var tw := create_tween()
	_alert.position.y = ALERT_Y + 8.0
	tw.tween_property(_alert, "position:y", ALERT_Y - 5.0, 0.14).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_alert, "position:y", ALERT_Y, 0.10)


## 이동 방향을 바라본다 — 시트가 방향별 프레임을 갖추면 그쪽 포즈로.
func face(dir: Vector2i) -> void:
	facing = GridMover.dir_name(dir)
	var anim := SpriteSets.pose_anim(sprite.sprite_frames, facing, true)
	if anim == &"" or _pose == anim:
		return
	_pose = anim
	# play(이름)은 프레임 0으로 되감아 걸음 위상을 끊는다 — 프로퍼티만 바꾼다.
	sprite.animation = anim
	sprite.play()


## 시트에 없는 방향은 플레이스홀더로 떨어졌는지 감사 도구가 볼 수 있게 노출.
func sheet_path() -> String:
	return str(_paths.get("sheet", ""))


func _build_frames() -> SpriteFrames:
	var tex: Texture2D = load(str(_paths["sheet"]))
	# 셀 크기: cell_w/cell_h 우선, 구형 단일 cell 호환 (아트 모드별 규격 상이 흡수)
	var cw: int = int(_meta.get("cell_w", _meta.get("cell", 64)))
	var ch: int = int(_meta.get("cell_h", _meta.get("cell", 64)))
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for anim_name: String in _meta["animations"]:
		var a: Dictionary = _meta["animations"][anim_name]
		var anim := StringName(anim_name)
		frames.add_animation(anim)
		frames.set_animation_speed(anim, float(a.get("fps", 6)))
		frames.set_animation_loop(anim, bool(a.get("loop", true)))
		for f in int(a["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(f * cw, int(a["row"]) * ch, cw, ch)
			frames.add_frame(anim, at)
	return frames
