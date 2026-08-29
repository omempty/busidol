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

## 둘러보는 주기(초). 원작 대조 결과 **대화 상대는 원작에서도 고정**이었다 —
## 움직이는 것은 `move_eventer()`가 모는 층당 1명의 **말 걸 수 없는** 배경 보행자이고,
## 그 둘을 잇는 `Talk_eventer()` 호출은 원작에서 주석 처리돼 있다. 그러니 대화 NPC를
## 걸어다니게 만드는 것은 고증이 아니다.
##
## 다만 **완전히 얼어 있으면 인형처럼 보인다**(2026-08-29 유저 지적). 자리를 지키되
## 가끔 고개를 돌리게 한다 — 칸을 옮기지 않으므로 통행 판정도 감사 도구도 흔들지
## 않는다. 진짜 순찰은 별개의 존재가 맡는다 — `WalkerEntity`(배경 보행자).
const LOOK_MIN := 2.6
const LOOK_MAX := 6.4
const FACINGS: Array[StringName] = [&"down", &"left", &"right", &"up"]

var _look_wait := 0.0
var _facing := &"down"


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
	sprite.sprite_frames = SpriteSets.build_frames(str(_paths["sheet"]), _meta)
	if not _meta.is_empty():
		sprite.scale = Vector2.ONE * float(_meta.get("scale", 1.0))
		sprite.offset = Vector2(0.0, SpriteSets.foot_offset(_meta))
	sprite.animation = &"idle"
	sprite.play()
	add_child(sprite)
	# 같은 순간에 전원이 고개를 돌리면 기계처럼 보인다 — 시작 시각을 흩는다.
	_look_wait = randf_range(0.0, LOOK_MAX)


## 가끔 고개를 돌린다. **칸은 옮기지 않는다** — 옮기는 순간 통행 오버라이드와
## 감사 도구의 도달성 계산을 같이 손봐야 한다.
func _process(delta: float) -> void:
	_look_wait -= delta
	if _look_wait > 0.0:
		return
	_look_wait = randf_range(LOOK_MIN, LOOK_MAX)
	var next: StringName = FACINGS[randi() % FACINGS.size()]
	if next == _facing:
		return
	var anim := SpriteSets.pose_anim(sprite.sprite_frames, next, false)
	if anim.is_empty():
		return
	_facing = next
	sprite.animation = anim
	# 정지 포즈로 walk 프레임을 쓸 때는 첫 장에서 세운다(SpriteSets.pose_anim 규약).
	if String(anim).begins_with("idle_"):
		sprite.play()
	else:
		sprite.stop()
		sprite.frame = 0
