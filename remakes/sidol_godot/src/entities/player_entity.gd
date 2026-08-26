class_name PlayerEntity
extends Node2D
## 그리드 이동 플레이어 — 방향 즉시 프레임 반응·끊김 없는 보행 체인·정지 포즈 방향 유지.
## 품질 기준: docs/03_plan/01_roadmap.md Phase 1.

## 입력 액션 → 방향. 동시 입력은 "마지막에 누른 쪽" 우선(_held 스택).
const DIRS := {
	&"move_left": Vector2i.LEFT,
	&"move_right": Vector2i.RIGHT,
	&"move_up": Vector2i.UP,
	&"move_down": Vector2i.DOWN,
}
## 보행 사이클 길이 — 2보에 1사이클(왼발/오른발).
## 원작 move_you()가 한 걸음마다 스프라이트를 토글한 박자(2프레임 시트 기준)와 동일.
const STEPS_PER_CYCLE := 2.0
## 막힌 방향으로 밀리는 거리(px) — 벽에 부딪혔음을 즉시 알리는 최소 피드백.
const BUMP_PX := 3.0

var mover := GridMover.new()
var sprite := AnimatedSprite2D.new()
var facing := &"down"
var _wired := false
var _paths: Dictionary = {}
## 현재 눌려 있는 이동 액션, 누른 순서. 자체 엣지 검출을 겸한다
## (코드 주입 Input.action_press와 실입력 양쪽에서 안정 — field.gd _edge와 같은 이유).
var _held: Array[StringName] = []
## 마지막으로 적용한 포즈 키("walk_left" 등) — 같은 포즈 재적용을 건너뛴다.
var _pose := &""
## 직전에 막힌 방향 — 벽을 향해 키를 누르고 있는 동안 범프가 반복되지 않게 한다.
var _blocked_dir := Vector2i.ZERO


func _ready() -> void:
	_paths = SpriteSets.character_sheet(&"player")
	z_index = 15
	ShadowBlob.attach(self)
	sprite.sprite_frames = _build_frames()
	add_child(sprite)
	# 렌더 스케일 — 메타 scale (아트 해상도와 게임 내 크기 분리)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(_paths["meta"])))
	if typeof(meta) == TYPE_DICTIONARY:
		sprite.scale = Vector2.ONE * float(meta.get("scale", 1.0))
		sprite.offset = Vector2(0.0, SpriteSets.foot_offset(meta))
	_play_idle()


func attach_map(runtime: MapRuntime, start_cell: Vector2i) -> void:
	mover.body = self
	mover.is_passable = runtime.is_passable
	mover.grid_pos = start_cell
	position = GridMover.block_center(start_cell)
	if not _wired:
		_wired = true
		mover.step_started.connect(_on_step_started)
		mover.step_blocked.connect(_on_step_blocked)


func teleport(cell: Vector2i) -> void:
	mover.teleport(cell)


## 스모크/컷신용 — 지정 방향을 바라보게만 한다.
func face(dir_name: StringName) -> void:
	facing = dir_name
	_play_idle()


func _physics_process(_delta: float) -> void:
	var dir := _poll_dir()
	if not mover.enabled:
		dir = Vector2i.ZERO

	if mover.moving:
		# 보행 중 입력은 버퍼로만 전달 — 도착 즉시 다음 걸음이 이어져 정지 프레임이 끼지 않는다.
		# 키를 떼면 그대로 ZERO가 들어가 과보행도 없다.
		mover.buffered_dir = dir
		return

	if dir == Vector2i.ZERO:
		_play_idle()
		return

	facing = dir_to_name(dir)
	if mover.try_step(dir):
		_blocked_dir = Vector2i.ZERO
	else:
		_play_idle()  # 막힘 — 방향만 돌린 채 정지 포즈


## 눌린 이동 액션을 순서대로 추적하고 최신 방향을 돌려준다.
func _poll_dir() -> Vector2i:
	for action: StringName in DIRS:
		var now := Input.is_action_pressed(action)
		var was := _held.has(action)
		if now and not was:
			_held.append(action)
		elif not now and was:
			_held.erase(action)
	if _held.is_empty():
		return Vector2i.ZERO
	return DIRS[_held[-1]]


func _on_step_started(dir: Vector2i) -> void:
	facing = dir_to_name(dir)
	_play_walk()


## 막힌 방향으로 살짝 밀렸다 되돌아온다. 같은 방향으로 계속 눌러도 한 번만 —
## 벽을 향해 키를 누르고 있는 동안 떨리지 않게 방향이 바뀔 때까지 잠근다.
func _on_step_blocked(dir: Vector2i) -> void:
	if _blocked_dir == dir:
		return
	_blocked_dir = dir
	var tw := create_tween()
	tw.tween_property(sprite, "position", Vector2(dir) * BUMP_PX, 0.05)
	tw.tween_property(sprite, "position", Vector2.ZERO, 0.09)


func _play_walk() -> void:
	var anim := SpriteSets.pose_anim(sprite.sprite_frames, facing, true)
	if anim == &"" or _pose == StringName("walk:" + String(anim)):
		return
	_pose = StringName("walk:" + String(anim))
	_switch_to(anim)
	sprite.speed_scale = _step_sync_scale(anim)
	sprite.play()


## 정지 포즈. 방향별 idle이 없는 시트(원작 시트는 idle_down 하나뿐)에서는
## 같은 방향 walk의 첫 프레임을 세워 쓴다 — idle_down으로 떨어뜨리면
## 옆/뒤를 보다 멈출 때마다 정면 프레임이 튀어 "다른 방향 프레임"으로 보인다.
func _play_idle() -> void:
	var anim := SpriteSets.pose_anim(sprite.sprite_frames, facing, false)
	var animate := String(anim).begins_with("idle_")
	if anim == &"" or _pose == StringName("idle:" + String(anim)):
		return
	_pose = StringName("idle:" + String(anim))
	_switch_to(anim)
	sprite.speed_scale = 1.0
	if animate:
		sprite.play()
	else:
		sprite.pause()
		sprite.set_frame_and_progress(0, 0.0)


## 애니메이션 교체. play(이름)은 프레임 0으로 되감아 걸음 위상이 끊기므로
## animation 프로퍼티만 바꾼다(set_animation은 프레임 인덱스를 보존한다).
func _switch_to(anim: StringName) -> void:
	if sprite.animation != anim:
		sprite.animation = anim


## 보행 애니 속도를 걸음 박자에 고정한다. 시트가 몇 프레임이든
## STEPS_PER_CYCLE 보에 정확히 한 사이클 — 걸음과 다리 동작이 어긋나지 않는다.
func _step_sync_scale(anim: StringName) -> float:
	var n := sprite.sprite_frames.get_frame_count(anim)
	var authored := sprite.sprite_frames.get_animation_speed(anim)
	if n <= 0 or authored <= 0.0:
		return 1.0
	return (float(n) / (GridMover.STEP_TIME * STEPS_PER_CYCLE)) / authored


## facing 이름 → 방향 벡터 — 전방 셀 조회용.
func facing_vector() -> Vector2i:
	return GridMover.name_dir(facing)


func dir_to_name(dir: Vector2i) -> StringName:
	return GridMover.dir_name(dir)


func _build_frames() -> SpriteFrames:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(_paths["meta"])))
	var tex: Texture2D = load(str(_paths["sheet"]))
	# 셀 크기: cell_w/cell_h 우선, 구형 단일 cell 호환 (비정형 비율 허용)
	var cw: int = int(meta.get("cell_w", meta.get("cell", 64)))
	var ch: int = int(meta.get("cell_h", meta.get("cell", 64)))
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
			at.region = Rect2(f * cw, int(a["row"]) * ch, cw, ch)
			frames.add_frame(anim, at)
	return frames
