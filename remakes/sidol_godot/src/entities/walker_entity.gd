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

const STEP_TIME := 0.34
const TURN_PAUSE_TIME := 1.0
## 괴물 접근 경고 반경(체비셰프) — 안으로 들어오면 머리 위에 느낌표를 든다.
## 적 엔티티의 추적 경고와 같은 어휘(빨간 ! 칩+팝)로 맞춘다. 빨간 느낌표는
## 이 게임에서 "괴물 관련 위험" 하나만 뜻한다(EnemyEntity._build_alert_marker와 동기화).
const FOE_ALERT_RADIUS := 5
const FOE_ALERT_Y := -62.0

var walker_id := &""
var sprite_id := &""
var display_name := ""
var sequence_id := &""
var repeat_sequence_id: Variant = null
var sequence_variants: Array = []
var cell := Vector2i.ZERO
var sprite := AnimatedSprite2D.new()

var _runtime: MapRuntime
## 적 위치 공급원 — 필드가 스폰 때 넘긴다. 없으면 회피·경고 없이 걷는다.
var foe_source: EnemyManager = null
var _foe_alert: PanelContainer
var _foe_warned := false
var _legs: Array = []  # [{dir: Vector2i, steps: int}, ...]
var _leg := 0
var _left := 0
var _wait := 0.0
var _current_dir := Vector2i.DOWN
var _is_stepping := false
var _is_talking := false
var _breath_phase := 0.0
var _base_scale := Vector2.ONE
var _paths: Dictionary = {}
var _meta: Dictionary = {}


func setup(
	p_id: StringName,
	p_sprite: StringName,
	p_cell: Vector2i,
	legs: Array,
	rt: MapRuntime,
	p_name: String = "",
	p_seq: StringName = &"",
	p_variants: Array = [],
	p_repeat_seq: Variant = null,
	p_tint: Color = Color.WHITE
) -> void:
	walker_id = p_id
	sprite_id = p_sprite
	cell = p_cell
	_legs = legs
	_runtime = rt
	display_name = p_name
	sequence_id = p_seq
	sequence_variants = p_variants
	repeat_sequence_id = p_repeat_seq
	position = GridMover.block_center(cell)
	z_index = 14
	_build_visual()
	# tint는 스프라이트에만 — 경고 칩까지 물들이면 빨간 !의 어휘가 흐려진다.
	sprite.modulate = p_tint
	if not _legs.is_empty():
		_left = int(Dictionary(_legs[0]).get("steps", 0))
		_current_dir = Dictionary(_legs[0]).get("dir", Vector2i.DOWN)
	_wait = randf_range(0.0, STEP_TIME)
	_breath_phase = randf_range(0.0, PI * 2.0)


func resolve_sequence() -> StringName:
	return DialogueManager.resolve_npc_sequence(sequence_id, sequence_variants, repeat_sequence_id)


## 기록 없는 미리보기 — 말풍선 장식 판단용(NpcEntity.peek_sequence와 같은 이유).
func peek_sequence() -> StringName:
	return DialogueManager.resolve_npc_sequence(
		sequence_id, sequence_variants, repeat_sequence_id, false
	)


func occupies(c: Vector2i) -> bool:
	return c in Placement.body_cells(cell)


func set_talking(talking: bool) -> void:
	_is_talking = talking
	if not talking:
		_face(_current_dir, false)
		_wait = 0.6


func face_towards(target_cell: Vector2i) -> void:
	var diff := target_cell - cell
	var next := _current_dir
	if absi(diff.x) > absi(diff.y):
		next = Vector2i.RIGHT if diff.x > 0 else Vector2i.LEFT
	else:
		next = Vector2i.DOWN if diff.y > 0 else Vector2i.UP
	_face(next, false)


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
	_base_scale = sprite.scale
	add_child(sprite)
	_build_foe_alert()
	_face(Vector2i.DOWN, false)


func _process(delta: float) -> void:
	if _legs.is_empty() or _runtime == null:
		return
	# 외형 호흡은 매 프레임(정지 중에도 살아 있게). 이동은 아래 게이트를 통과해야.
	_update_breathing(delta)
	_update_foe_alert()
	if _is_talking:
		return
	if _is_stepping:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_step_once()


## 괴물 접근 경고 — 반경 안에 적이 있으면 느낌표를 든다(없으면 내린다).
## 몸은 붉히지 않는다 — 그건 "쫓기고 있다"는 적 엔티티의 어휘다.
## 워커는 "무서워하고 있다"라 표식만 든다.
func _update_foe_alert() -> void:
	if _foe_alert == null:
		return
	var dist := _nearest_foe_dist()
	var near := dist >= 0 and dist <= FOE_ALERT_RADIUS
	if near == _foe_warned:
		return
	_foe_warned = near
	_foe_alert.visible = near
	if not near:
		return
	var tw := create_tween()
	_foe_alert.position.y = FOE_ALERT_Y + 8.0
	tw.tween_property(_foe_alert, "position:y", FOE_ALERT_Y - 5.0, 0.14).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_foe_alert, "position:y", FOE_ALERT_Y, 0.10)


## 가장 가까운 적까지 체비셰프 거리. 적이 없으면 -1.
func _nearest_foe_dist() -> int:
	if foe_source == null:
		return -1
	var best := -1
	for f in foe_source.living_cells():
		var d := maxi(absi(f.x - cell.x), absi(f.y - cell.y))
		if best < 0 or d < best:
			best = d
	return best


## 추적 경고 표식 — EnemyEntity와 같은 칩+느낌표(빨간 ! = 괴물 위험).
func _build_foe_alert() -> void:
	_foe_alert = PanelContainer.new()
	var sb := HudTheme.chip(Color(0.10, 0.04, 0.04, 0.92), 5, 7, 1)
	sb.border_color = EnemyEntity.ALERT_COLOR
	sb.set_border_width_all(1)
	_foe_alert.add_theme_stylebox_override("panel", sb)
	_foe_alert.position = Vector2(-9, FOE_ALERT_Y)
	_foe_alert.visible = false
	_foe_alert.z_index = 20
	_foe_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := HudTheme.label("!", 15, EnemyEntity.ALERT_COLOR)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_foe_alert.add_child(mark)
	add_child(_foe_alert)


## 호흡 — **정수 1px 왕복만.** 스케일도 소수 오프셋도 쓰지 않는다.
##
## 왜 (2026-09-09 실측): 시트는 셀 128을 scale 0.6667로 그려 화면 85.34px가 되는데,
## 여기에 스케일을 1.02배만 얹어도 85행 중 대다수가 **다른 원본 행을 집는다** —
## 숨 쉴 때마다 도트 줄이 끓어오른다(픽셀 크롤링). 소수 y 오프셋(sin*1.5)도 같은 이유로
## 반올림 경계에서 그림이 한 줄씩 튄다. 안티에일리어싱 금지가 스타일 규약인 프로젝트에서
## 가장 눈에 띄는 어긋남이라, 고정 NPC와 같은 규칙으로 맞춘다(npc_entity.gd 참조).
##
## 위로만 뜬다(0 또는 -1): 아래로 내리면 고정 위치인 ShadowBlob을 파고들어 바닥에 가라앉아 보인다.
func _update_breathing(delta: float) -> void:
	_breath_phase += delta * 2.8
	sprite.position.y = -1.0 if sin(_breath_phase) > 0.0 else 0.0
	sprite.scale = _base_scale


## 한 스텝 판정 — _process에서만 호출. 막히면 다리를 한 칸만 넘기고 쉰다
## (예전에는 호흡 안에 있어 매 프레임 토글→접촉 시 좌우 왕복으로 보였다).
func _step_once() -> void:
	if _left <= 0:
		_face(_current_dir, false)
		_leg = (_leg + 1) % _legs.size()
		_left = int(Dictionary(_legs[_leg]).get("steps", 0))
		_current_dir = Dictionary(_legs[_leg]).get("dir", Vector2i.DOWN)
		_wait = TURN_PAUSE_TIME
		if _left <= 0:
			return

	var dir: Vector2i = Dictionary(_legs[_leg]).get("dir", Vector2i.ZERO)
	if dir == Vector2i.ZERO:
		return
	_current_dir = dir

	# 2×2 몸 진입 가능 여부 검사
	var want := cell + dir
	var blocked := false
	for c in Placement.body_cells(want):
		if not _runtime.is_passable(c):
			blocked = true
			break
	# 괴물이 서 있는 칸으로는 안 간다 — 겹치면 유령처럼 비치고, 그건 개그가 아니라 버그다.
	# 막힌 길과 같은 처리(다리 넘기고 대기)로 방향을 튼다.
	if not blocked:
		blocked = _foe_on(want)

	if blocked:
		_face(dir, false)
		# 장애물 충돌 시 반대 경로로 전환하고 대기
		_leg = (_leg + 1) % _legs.size()
		_left = int(Dictionary(_legs[_leg]).get("steps", 0))
		_current_dir = Dictionary(_legs[_leg]).get("dir", Vector2i.DOWN)
		_wait = TURN_PAUSE_TIME
		return

	_left -= 1
	_wait = STEP_TIME
	_face(dir, true)
	cell = want
	_is_stepping = true
	var tw := create_tween()
	tw.tween_property(self, "position", GridMover.block_center(cell), STEP_TIME)
	tw.finished.connect(
		func() -> void:
			_is_stepping = false
			if _left <= 0:
				_face(_current_dir, false)
	)


## 들어갈 칸에 적이 있으면 true — 회피 판정용.
func _foe_on(want: Vector2i) -> bool:
	if foe_source == null:
		return false
	var want_cells := Placement.body_cells(want)
	for f in foe_source.living_cells():
		for c in Placement.body_cells(f):
			if c in want_cells:
				return true
	return false


func _face(dir: Vector2i, walking: bool) -> void:
	var name := &"down"
	if dir.x < 0:
		name = &"left"
	elif dir.x > 0:
		name = &"right"
	elif dir.y < 0:
		name = &"up"
	var anim := SpriteSets.pose_anim(sprite.sprite_frames, name, walking)
	if anim.is_empty():
		return
	if sprite.animation != anim:
		sprite.animation = anim
	if walking:
		sprite.play()
	else:
		if String(anim).begins_with("idle_"):
			sprite.play()
		else:
			sprite.stop()
			sprite.frame = 0
