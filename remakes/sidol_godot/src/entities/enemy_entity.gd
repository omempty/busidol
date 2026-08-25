class_name EnemyEntity
extends Node2D
## 필드 몬스터 데이터+비주얼. 이동 판정은 EnemyManager가 수행(순환 참조 방지).

var species_id: StringName
var display_name := ""
var mover := GridMover.new()
var sprite := AnimatedSprite2D.new()
var act_interval := 0.25
var facing := &"down"

const SHEET_PATH := "res://assets/sprites/player_placeholder.png"
const META_PATH := "res://assets/sprites/player_placeholder.json"


func setup(p_id: StringName, p_cell: Vector2i, tint: Color) -> void:
	species_id = p_id
	display_name = String(p_id)
	add_child(sprite)
	sprite.sprite_frames = _build_frames()
	sprite.animation = &"idle_down"
	sprite.play()
	modulate = tint
	z_index = 15
	ShadowBlob.attach(self)
	mover.body = self
	mover.grid_pos = p_cell
	position = GridMover.block_center(p_cell)
	add_to_group(&"enemies")


func _build_frames() -> SpriteFrames:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	var tex: Texture2D = load(SHEET_PATH)
	var cell_px: int = int(meta["cell"])
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for anim_name: String in meta["animations"]:
		var a: Dictionary = meta["animations"][anim_name]
		var anim := StringName(anim_name)
		frames.add_animation(anim)
		frames.set_animation_speed(anim, float(a.get("fps", 6)))
		frames.set_animation_loop(anim, bool(a.get("loop", true)))
		for f in int(a["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(f * cell_px, int(a["row"]) * cell_px, cell_px, cell_px)
			frames.add_frame(anim, at)
	return frames
