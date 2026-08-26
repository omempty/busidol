class_name NpcEntity
extends Node2D
## 필드 NPC — 단일 셀 점유, 상호작용 시 DialogueBox로 시퀀스 재생.
## 전용 시트(<npc_id>_original/_remake)를 쓰고, 없을 때만 플레이어 시트 플레이스홀더.

var npc_id := &""
var display_name := ""
var sequence_id := &""
var cell := Vector2i.ZERO
var sprite := AnimatedSprite2D.new()
var _paths: Dictionary = {}
var _meta: Dictionary = {}


## 비주얼 조립까지 여기서 끝낸다. _ready()에 두면 add_child() 시점에 먼저 돌아
## npc_id가 아직 빈 문자열 — 전용 시트를 못 찾고 전원이 주인공 얼굴로 나왔다.
func setup(
	p_id: StringName, p_name: String, p_seq: StringName, p_cell: Vector2i, tint: Color
) -> void:
	npc_id = p_id
	display_name = p_name
	sequence_id = p_seq
	cell = p_cell
	position = GridMover.block_center(cell)
	modulate = tint
	z_index = 15
	_build_visual()


## NPC는 움직이지 않는 고정 액터이므로 그려지는 2×2를 그대로 점유한다
## (앵커 한 칸만 보면 오른쪽/아래에서 다가갔을 때 말을 걸 수 없다).
func body_cells() -> Array[Vector2i]:
	return Placement.body_cells(cell)


func occupies(c: Vector2i) -> bool:
	var d := c - cell
	return d.x >= 0 and d.y >= 0 and d.x < Placement.BODY.x and d.y < Placement.BODY.y


## 감사 도구용 — 전용 시트를 못 찾아 플레이어 시트로 떨어졌는지 확인.
func sheet_path() -> String:
	return str(_paths.get("sheet", ""))


func _build_visual() -> void:
	# 전용 시트 우선 — 부재 시 플레이어 시트 플레이스홀더(quiet: 미정착은 정상 경로)
	_paths = SpriteSets.character_sheet(npc_id, true)
	if str(_paths["sheet"]).is_empty():
		_paths = SpriteSets.character_sheet(&"player")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(_paths["meta"])))
	if typeof(raw) == TYPE_DICTIONARY:
		_meta = raw
	ShadowBlob.attach(self)
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
	# 정면 정지 포즈 — idle_down이 없는 시트(단일 행 NPC 시트)는 walk_down으로 폴백.
	var anims: Dictionary = _meta.get("animations", {})
	var src_key: String = "idle_down" if anims.has("idle_down") else str(anims.keys()[0])
	var a: Dictionary = anims[src_key]
	frames.add_animation(&"idle")
	frames.set_animation_speed(&"idle", float(a.get("fps", 2)))
	frames.set_animation_loop(&"idle", true)
	for f in int(a["frames"]):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(f * cw, int(a["row"]) * ch, cw, ch)
		frames.add_frame(&"idle", at)
	return frames
