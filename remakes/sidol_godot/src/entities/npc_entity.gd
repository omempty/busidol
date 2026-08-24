class_name NpcEntity
extends Node2D
## 필드 NPC — 단일 셀 점유, 상호작용 시 DialogueBox로 시퀀스 재생.
## 시각은 플레이스홀더 시트 재사용(색조 틴트) — 전용 도트는 에셋 파이프라인 경유.

var npc_id := &""
var display_name := ""
var sequence_id := &""
var cell := Vector2i.ZERO
var sprite := AnimatedSprite2D.new()

const SHEET_PATH := "res://assets/sprites/player_original.png"
const META_PATH := "res://assets/sprites/player_original.json"


func setup(p_id: StringName, p_name: String, p_seq: StringName, p_cell: Vector2i, tint: Color) -> void:
	npc_id = p_id
	display_name = p_name
	sequence_id = p_seq
	cell = p_cell
	position = GridMover.block_center(cell)
	modulate = tint
	z_index = 15


func _ready() -> void:
	sprite.sprite_frames = _build_frames()
	sprite.animation = &"idle"
	sprite.play()
	add_child(sprite)


func _build_frames() -> SpriteFrames:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	var tex: Texture2D = load(SHEET_PATH)
	var cell_px: int = int(meta["cell"])
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var a: Dictionary = meta["animations"]["idle_down"]
	frames.add_animation(&"idle")
	frames.set_animation_speed(&"idle", float(a.get("fps", 2)))
	frames.set_animation_loop(&"idle", true)
	for f in int(a["frames"]):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(f * cell_px, int(a["row"]) * cell_px, cell_px, cell_px)
		frames.add_frame(&"idle", at)
	return frames
