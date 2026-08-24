class_name PlayerEntity
extends Node2D
## 그리드 이동 플레이어 — 방향 즉시 프레임 반응·버퍼 체인·idle 브리딩.
## 품질 기준: docs/03_plan/01_roadmap.md Phase 1.

const SHEET_PATH := "res://assets/sprites/player_original.png"
const META_PATH := "res://assets/sprites/player_original.json"

var mover := GridMover.new()
var sprite := AnimatedSprite2D.new()
var facing := &"down"
var _wired := false


func _ready() -> void:
	z_index = 15
	sprite.sprite_frames = _build_frames()
	sprite.animation = &"idle_down"
	sprite.play()
	add_child(sprite)


func attach_map(runtime: MapRuntime, start_cell: Vector2i) -> void:
	mover.body = self
	mover.is_passable = runtime.is_passable
	mover.grid_pos = start_cell
	position = GridMover.block_center(start_cell)
	if not _wired:
		_wired = true
		mover.step_started.connect(_on_step_started)
		mover.step_finished.connect(_on_step_finished)
		mover.step_blocked.connect(func(_d: Vector2i) -> void: _play_idle())


func teleport(cell: Vector2i) -> void:
	mover.teleport(cell)


## 스모크/컷신용 — 지정 방향을 바라보게만 한다.
func face(dir_name: StringName) -> void:
	facing = dir_name
	sprite.play(&"idle_down")


func _physics_process(_delta: float) -> void:
	if mover.moving:
		return
	var dir := Vector2i.ZERO
	if Input.is_action_pressed(&"move_left"):
		dir = Vector2i.LEFT
	elif Input.is_action_pressed(&"move_right"):
		dir = Vector2i.RIGHT
	elif Input.is_action_pressed(&"move_up"):
		dir = Vector2i.UP
	elif Input.is_action_pressed(&"move_down"):
		dir = Vector2i.DOWN
	if dir != Vector2i.ZERO:
		facing = dir_to_name(dir)
		mover.try_step(dir)


func _on_step_started(dir: Vector2i) -> void:
	facing = dir_to_name(dir)
	sprite.play(StringName("walk_" + String(facing)))


func _on_step_finished(_pos: Vector2i) -> void:
	if not mover.moving:
		_play_idle()


func _play_idle() -> void:
	# 플레이스홀더 시트는 idle_down 2프레임만 보유 — 나머지 방향도 이로 대체.
	sprite.play(&"idle_down")


func dir_to_name(dir: Vector2i) -> StringName:
	if dir == Vector2i.LEFT:
		return &"left"
	if dir == Vector2i.RIGHT:
		return &"right"
	if dir == Vector2i.UP:
		return &"up"
	return &"down"


func _build_frames() -> SpriteFrames:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	var tex: Texture2D = load(SHEET_PATH)
	var cell: int = int(meta["cell"])
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for anim_name: String in meta["animations"]:
		var a: Dictionary = meta["animations"][anim_name]
		var anim: StringName = StringName(anim_name)
		frames.add_animation(anim)
		frames.set_animation_speed(anim, float(a.get("fps", 8)))
		frames.set_animation_loop(anim, bool(a.get("loop", true)))
		for f in int(a["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(f * cell, int(a["row"]) * cell, cell, cell)
			frames.add_frame(anim, at)
	return frames
