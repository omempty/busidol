class_name EnemyEntity
extends Node2D
## 필드 몬스터 데이터+비주얼. 이동 판정은 EnemyManager가 수행(순환 참조 방지).
## 시트는 SpriteSets 경유(<species>_original/_remake) — 부재 시 플레이스홀더 폴백.

var species_id: StringName
var display_name := ""
var mover := GridMover.new()
var sprite := AnimatedSprite2D.new()
var act_interval := 0.25
var facing := &"down"

const FALLBACK_SHEET := "res://assets/sprites/player_placeholder.png"
const FALLBACK_META := "res://assets/sprites/player_placeholder.json"

var _paths: Dictionary = {}
var _meta: Dictionary = {}


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
	sprite.animation = &"idle_down"
	sprite.play()
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
