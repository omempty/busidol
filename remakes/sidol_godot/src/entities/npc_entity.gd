class_name NpcEntity
extends Node2D
## 필드 NPC — 단일 셀 점유, 상호작용 시 DialogueBox로 시퀀스 재생.
## 시각은 플레이스홀더 시트 재사용(색조 틴트) — 전용 도트는 에셋 파이프라인 경유.

var npc_id := &""
var display_name := ""
var sequence_id := &""
var cell := Vector2i.ZERO
var sprite := AnimatedSprite2D.new()
var _paths: Dictionary = {}
var _meta: Dictionary = {}


func setup(p_id: StringName, p_name: String, p_seq: StringName, p_cell: Vector2i, tint: Color) -> void:
	npc_id = p_id
	display_name = p_name
	sequence_id = p_seq
	cell = p_cell
	position = GridMover.block_center(cell)
	modulate = tint
	z_index = 15


func _ready() -> void:
	# 전용 시트(<npc_id>_original/_remake) 우선 — 부재 시 플레이어 시트 플레이스홀더.
	_paths = SpriteSets.character_sheet(npc_id, true)
	if str(_paths["sheet"]).is_empty():
		_paths = SpriteSets.character_sheet(&"player")
	var raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(str(_paths["meta"])))
	if typeof(raw) == TYPE_DICTIONARY:
		_meta = raw
	sprite.sprite_frames = _build_frames()
	if not _meta.is_empty():
		sprite.scale = Vector2.ONE * float(_meta.get("scale", 1.0))
		sprite.offset = Vector2(0.0, SpriteSets.foot_offset(_meta))
	sprite.animation = &"idle"
	sprite.play()
	add_child(sprite)


func _build_frames() -> SpriteFrames:
	var tex: Texture2D = load(str(_paths["sheet"]))
	# 셀 크기: cell_w/cell_h 우선, 구형 단일 cell 호환 (아트 모드별 규격 상이 흡수)
	var cw: int = int(_meta.get("cell_w", _meta.get("cell", 64)))
	var ch: int = int(_meta.get("cell_h", _meta.get("cell", 64)))
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var a: Dictionary = _meta["animations"]["idle_down"]
	frames.add_animation(&"idle")
	frames.set_animation_speed(&"idle", float(a.get("fps", 2)))
	frames.set_animation_loop(&"idle", true)
	for f in int(a["frames"]):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(f * cw, int(a["row"]) * ch, cw, ch)
		frames.add_frame(&"idle", at)
	return frames
