class_name WalkerEntity
extends Node2D
## 배경 보행자 — 정해진 경로를 왕복하는, **말 걸 수 없는** 사람.
##
## 원작 대조: `EVENT.C:move_eventer()`가 층당 1명을 `EVE_PATTERN[i][40]`의 40스텝
## 방향표대로 왕복시킨다(예: UP 21회 → DOWN 19회). 이동 전 `ATT==0`을 2셀 검사하고,
## 걸을 때마다 `mode`를 토글해 2프레임 걷기를 낸다.
##
## **길을 막지 않는다 — 그게 원작이다.** 원작 eventer는 ATT를 쓰지 않아 주인공이
## 그대로 통과했다. 막게 만들면 지나간 자리를 되돌려 놓아야 하고, 자동 주행이 짜 둔
## 경로가 도중에 끊긴다. 대화도 없다: 보행자와 대화를 잇는 `Talk_eventer()` 호출은
## 원작 소스에서 주석 처리돼 있다.
##
## 대화 상대(`NpcEntity`)와는 다른 종류의 존재다. 섞지 않는다.

## 한 칸 옮기는 데 걸리는 시간(초). 주인공(GridMover.STEP_TIME)보다 느긋하게 —
## 배경이므로 시선을 끌면 안 된다.
const STEP_TIME := 0.34

var walker_id := &""
var sprite_id := &""
var cell := Vector2i.ZERO
var sprite := AnimatedSprite2D.new()

var _runtime: MapRuntime
var _legs: Array = []  # [{dir: Vector2i, steps: int}, ...] — 원작 EVE_PATTERN에 대응
var _leg := 0
var _left := 0
var _wait := 0.0
var _paths: Dictionary = {}
var _meta: Dictionary = {}


func setup(
	p_id: StringName, p_sprite: StringName, p_cell: Vector2i, legs: Array, rt: MapRuntime
) -> void:
	walker_id = p_id
	sprite_id = p_sprite
	cell = p_cell
	_legs = legs
	_runtime = rt
	position = GridMover.block_center(cell)
	# 액터보다 살짝 아래 — 주인공·NPC(z 15)에 가려지는 배경이다.
	z_index = 14
	_build_visual()
	if not _legs.is_empty():
		_left = int(Dictionary(_legs[0]).get("steps", 0))
	# 전원이 같은 박자로 걸으면 행진처럼 보인다.
	_wait = randf_range(0.0, STEP_TIME)


func _build_visual() -> void:
	_paths = SpriteSets.character_sheet(sprite_id, true)
	if str(_paths["sheet"]).is_empty():
		_paths = SpriteSets.character_sheet(&"player")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(_paths["meta"])))
	if typeof(raw) == TYPE_DICTIONARY:
		_meta = raw
	ShadowBlob.attach(self)
	sprite.sprite_frames = SpriteSets.build_frames(str(_paths["sheet"]), _meta)
	if not _meta.is_empty():
		sprite.scale = Vector2.ONE * float(_meta.get("scale", 1.0))
		sprite.offset = Vector2(0.0, SpriteSets.foot_offset(_meta))
	add_child(sprite)
	_face(Vector2i.DOWN, false)


func _process(delta: float) -> void:
	if _legs.is_empty() or _runtime == null:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = STEP_TIME
	if _left <= 0:
		_leg = (_leg + 1) % _legs.size()
		_left = int(Dictionary(_legs[_leg]).get("steps", 0))
		if _left <= 0:
			return
	_left -= 1
	var dir: Vector2i = Dictionary(_legs[_leg]).get("dir", Vector2i.ZERO)
	if dir == Vector2i.ZERO:
		return
	_face(dir, true)
	# 원작과 같은 검사 — 2×2 몸이 들어갈 자리인가. 안 되면 그 박자는 제자리다.
	var want := cell + dir
	for c in Placement.body_cells(want):
		if not _runtime.is_passable(c):
			return
	cell = want
	var tw := create_tween()
	tw.tween_property(self, "position", GridMover.block_center(cell), STEP_TIME)


func _face(dir: Vector2i, walking: bool) -> void:
	var name := &"down"
	if dir.x < 0:
		name = &"left"
	elif dir.x > 0:
		name = &"right"
	elif dir.y < 0:
		name = &"up"
	var anim := SpriteSets.pose_anim(sprite.sprite_frames, name, walking)
	if anim.is_empty() or sprite.animation == anim:
		return
	sprite.animation = anim
	sprite.play()
