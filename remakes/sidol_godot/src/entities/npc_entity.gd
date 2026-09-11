class_name NpcEntity
extends Node2D
## 필드 NPC — 2×2 셀 점유, 상호작용 시 DialogueBox로 시퀀스 재생.
## 전용 시트(<npc_id>_original/_remake)를 쓰고, 없을 때만 플레이어 시트 플레이스홀더.
## 제자리 아이들(정수 픽셀 호흡 + 간헐 무게중심 이동) 및 필요 시 소폭 배회(wander_range) 지원.
##
## 아이들 연출이 왜 "정수 픽셀 오프셋"뿐인가 — 2026-09-09 시트 실측 근거:
## 고정 NPC 11명이 쓰는 시트는 전부 128×128 · scale 0.6667 → 화면 85.34px다.
## 이 배율이 **이미 비정수**라, 여기에 스케일 스쿼시를 곱하면 최근접 샘플링
## (project.godot: default_texture_filter=0)이 통째로 어긋난다. 실측:
##   ×1.035 → 85행 중 73행(86%)이 **다른 원본 행**을 집는다
##   ×1.010 → 53행(62%) · ×1.005 → 53행(62%)
## 즉 숨을 쉴 때마다 스프라이트 전체 도트가 끓는다. 예전 코드가 쓰던 0.035가 바로 그 값이다.
## 회전도 같은 이유로 불가: 0.09rad(5.16°)면 85px 높이 스프라이트의 윗변이 아랫변보다
## 7.70px 밀려 축에 남는 픽셀 행이 하나도 없다. assets/style_bible.md 28행 "AA 금지"의 취지에 어긋난다.
## 남는 수단은 정수 픽셀 오프셋 하나뿐이고, 1px = 32px 타일의 3.12% · 85px 몸의 1.17%로
## 리샘플이 정확히 0이다. 카메라 zoom=1 · 뷰포트 960×540이라 1 world px = 1 viewport px.

var npc_id := &""
var display_name := ""
var sequence_id := &""
var repeat_sequence_id: Variant = null
## 상태에 따라 갈아 끼우는 대사. `[{requires_flag: String|Array, sequence_id: String}]`,
## **먼저 맞는 것이 이긴다**. 비어 있으면 sequence_id 하나만 쓴다.
var sequence_variants: Array = []
var cell := Vector2i.ZERO
var sprite := AnimatedSprite2D.new()
var wander_range := 0
## 제자리 아이들 on/off. 연출을 통째로 끄고 재기 위한 스위치 —
## 관문·스크린샷 도구가 프레임 0 정지 상태를 보장받아야 할 때 false로 둔다.
var idle_motion := true

## 데이터 계약 `idle_anim`(data/maps/npcs_f*.json) → 실제 연출.
##
## 왜 값이 둘뿐인가 — 데이터가 원래 달고 있던 `"squash"`는 이 배율에서 **쓸 수 없는 값**이다
## (파일 머리 주석의 리샘플 실측: ×1.035면 85행 중 73행이 다른 원본 행을 집는다).
## 스케일·회전을 건드리지 않는 연출만 계약에 남긴다.
##
## 실측 근거(2026-09-09): npcs_f*.json 5파일 11명 **전원**이 `idle_anim: "squash"`를 달고
## 있었는데 그 키를 읽는 코드는 0곳이었다. 선언은 있고 읽는 쪽이 없는 그 유형이라,
## 값을 고치는 것만으로는 다시 죽는다 — 그래서 읽는 자리(set_idle_anim)와
## 재는 자리(ActorProbe.check_idle_anim_coverage)를 같이 붙인다.
const IDLE_ANIMS := {
	&"bob": true,  # 정수 픽셀 호흡 + 간헐 무게중심 이동(_update_breathing)
	&"none": false,  # 연출 없음 — 프레임 0으로 세워 둔다
}
const DEFAULT_IDLE_ANIM := &"bob"

## 이 NPC에 적용된 계약 이름. idle_motion은 그것을 옮긴 결과다 —
## 관문·스크린샷 도구가 idle_motion을 직접 꺼도 계약 이름은 남는다.
var idle_anim := DEFAULT_IDLE_ANIM

## 배회 착지 — 필드가 발먼지 등 착지 연출을 붙이는 자리.
signal step_landed(cell: Vector2i)

var _paths: Dictionary = {}
var _meta: Dictionary = {}
var _runtime: MapRuntime
var _home_cell := Vector2i.ZERO

const LOOK_MIN := 2.6
const LOOK_MAX := 6.4
const WANDER_STEP_TIME := 0.38
const FACINGS: Array[StringName] = [&"down", &"left", &"right", &"up"]

## 정지 포즈에서 프레임 0을 세워 둘 것인가.
## 실측(2026-09-09): 전용 시트 7종(cafeteria_girl · guard_idle · librarian · nothing_man ·
## prof_chem · rescue_girl · tutor_dumb) **전부** idle_down 행(row 4)이 walk_down 행(row 0)과
## **바이트 단위로 동일**하다. 즉 "아이들"이라고 이름만 붙은 걷기 사이클이라, play()하면
## fps=2로 제자리 행진을 한다. 플레이스홀더로 쓰는 player_original은 idle_down의 두 프레임이
## 서로 같아서 play()가 아무 일도 안 한다 — 어느 쪽이든 세워 두는 것이 맞다.
## 걷기 행의 복사본이 아닌 **진짜 정지 애니**를 그려 넣는 날 이 값을 false로 되돌린다.
const HOLD_RESTING_FRAME := true

## 호흡 진폭(px). 반드시 정수 — 위 파일 주석의 리샘플 실측 근거 참조.
## 1px은 85px 몸의 1.17%. 2px(2.34%)로 올리면 호흡이 아니라 위아래로 튀는 것으로 읽힌다.
const BREATH_AMP_PX := 1
## 호흡 1주기(초). 성인 안정시 호흡은 ~14회/분(4.3초)이지만 그대로 쓰면 게임 화면에서
## 멈춰 있는 것과 구분이 안 된다. 3초 = 절반인 1.5초 동안 1px 떠 있는 사각파.
const BREATH_PERIOD := 3.0

## 간헐 무게중심 이동 — 두 번째 walk 프레임을 한 박자만 보여 준다.
## 실측(2026-09-09): 각 방향 walk 행의 frame 1은 frame 0을 옮겨 그린 것이 아니라
## 몸 전체를 다시 그린 **별개 포즈**다(최적 정수 시프트를 먹여도 차이가 0~56%밖에 안 줄고,
## cafeteria_girl은 0%다). 즉 "정지 그림 한 장"이라는 전제가 틀렸고, 방향마다 쓸 수 있는
## 두 번째 포즈가 이미 시트에 있다. 짧게 스치면 무게중심 옮기기로 읽히고,
## 길게 끌면 걷다 만 자세로 굳는다 — 그래서 0.22초다.
const FIDGET_HOLD := 0.22
const FIDGET_MIN := 3.5
const FIDGET_MAX := 7.5
## 포즈를 바꾸는 순간 1px 내려앉는다. 그림만 갈리면 깜빡임으로 보이는데,
## 같은 박자에 몸이 내려가면 체중을 옮긴 것으로 읽힌다. 정수라 리샘플 0.
const FIDGET_DIP_PX := 1

var _look_wait := 0.0
var _wander_wait := 0.0
var _facing := &"down"
var _breath_phase := 0.0
var _fidget_wait := 0.0
var _fidget_hold := 0.0
var _is_talking := false
var _is_wandering := false


func setup(
	p_id: StringName,
	p_name: String,
	p_seq: StringName,
	p_cell: Vector2i,
	tint: Color,
	p_variants: Array = [],
	p_wander_range: int = 0,
	p_runtime: MapRuntime = null,
	p_repeat_seq: Variant = null
) -> void:
	npc_id = p_id
	display_name = p_name
	sequence_id = p_seq
	repeat_sequence_id = p_repeat_seq
	sequence_variants = p_variants
	cell = p_cell
	_home_cell = p_cell
	wander_range = p_wander_range
	_runtime = p_runtime
	position = GridMover.block_center(cell)
	modulate = tint
	z_index = 15
	_build_visual()
	_wander_wait = randf_range(3.0, 7.0)


static func is_idle_anim_implemented(name: String) -> bool:
	return IDLE_ANIMS.has(StringName(name))


## 데이터 계약을 동작으로 옮긴다. 알 수 없는 이름은 기본값으로 떨어뜨리되 **조용히는 아니다** —
## 같은 것을 world_audit이 FAIL로 잡는다(런타임은 굴러가되 관문이 빨개진다).
func set_idle_anim(name: StringName) -> void:
	if not IDLE_ANIMS.has(name):
		push_warning("알 수 없는 idle_anim %s (%s) — %s로 떨어진다" % [name, npc_id, DEFAULT_IDLE_ANIM])
		name = DEFAULT_IDLE_ANIM
	idle_anim = name
	idle_motion = bool(IDLE_ANIMS[name])


func resolve_sequence() -> StringName:
	return DialogueManager.resolve_npc_sequence(sequence_id, sequence_variants, repeat_sequence_id)


## 기록 없는 미리보기 — 말풍선 장식 판단용. resolve_sequence()는 고를 때마다
## 청취 기록을 남기므로 프롬프트(매 프레임)에서 부르면 앞에 서 있기만 해도 회차가 돈다.
func peek_sequence() -> StringName:
	return DialogueManager.resolve_npc_sequence(
		sequence_id, sequence_variants, repeat_sequence_id, false
	)


func body_cells() -> Array[Vector2i]:
	return Placement.body_cells(cell)


func occupies(c: Vector2i) -> bool:
	var d := c - cell
	return d.x >= 0 and d.y >= 0 and d.x < Placement.BODY.x and d.y < Placement.BODY.y


func sheet_path() -> String:
	return str(_paths.get("sheet", ""))


func set_talking(talking: bool) -> void:
	_is_talking = talking
	if not talking:
		_look_wait = randf_range(LOOK_MIN, LOOK_MAX)
		_wander_wait = randf_range(3.0, 6.0)


func face_towards(target_cell: Vector2i) -> void:
	var diff := target_cell - cell
	var next := _facing
	if absi(diff.x) > absi(diff.y):
		next = &"right" if diff.x > 0 else &"left"
	else:
		next = &"down" if diff.y > 0 else &"up"
	if next == _facing:
		return  # 매 프레임 접근 반응으로 불러도 같은 방향이면 손대지 않는다
	_apply_facing(next)


## 접근 주목 — 3칸 안에 들어온 플레이어를 idle 중에만 본다(멀리서 알아보는 느낌).
## 랜덤 둘러보기와 겹치지 않게 look 타이머를 갱신한다. 대화·배회 중에는 손대지 않는다.
func notice(target_cell: Vector2i) -> void:
	if _is_talking or _is_wandering or not idle_motion:
		return
	face_towards(target_cell)
	_look_wait = randf_range(LOOK_MIN, LOOK_MAX)


func _build_visual() -> void:
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
	_hold_resting_frame()
	add_child(sprite)
	_look_wait = randf_range(0.0, LOOK_MAX)

	# 위상은 randf가 아니라 **npc_id 해시**로 흩는다.
	# 이유 둘: (1) 여럿이 같은 박자로 숨 쉬면 기계처럼 보인다 —
	# 한 방에 dev1·dev2가 나란히 서 있어서 실제로 눈에 띈다.
	# (2) 해시는 결정적이라 세이브·층 재입장 후에도 같은 NPC가 같은 박자를 유지한다.
	# randf였다면 문을 드나들 때마다 호흡 위상이 튀어 다른 사람처럼 보인다.
	var h := _scatter(npc_id)
	_breath_phase = float(h % 1000) / 1000.0 * TAU
	_fidget_wait = FIDGET_MIN + float((h / 1000) % 1000) / 1000.0 * (FIDGET_MAX - FIDGET_MIN)


## npc_id → 잘 흩어진 양수. 위상 분산 전용.
##
## 왜 hash()를 그대로 안 쓰나 — 실측(2026-09-09, 실제 id 11개로 측정):
## hash("dev1")과 hash("dev2")는 **6밖에 차이나지 않는다**. 이대로 %1000을 하면 위상이
## 1.489 / 1.495 rad(0.003초 차)가 되어, f2에 나란히 선 두 NPC가 한 몸처럼 숨 쉰다 —
## 위상을 흩으려던 목적이 정확히 그 자리에서 무너진다. 한 글자만 다른 문자열이 인접한 값을
## 받는 것은 문자열 해시의 정상 동작이라 hash를 바꿔서는 못 고친다. 섞어야 한다.
## splitmix32 finalizer(곱셈+xorshift)를 먹이면 dev1·dev2 간격이 0.006 → 2.902 rad,
## 즉 주기의 46%(거의 역위상)로 벌어진다. 한 층에 같이 서는 NPC들 중 최악 간격도
## 0.472 rad = 3초 주기의 0.23초로, 눈으로 갈라 보인다(f2 nothing_man·dev1).
## 마스킹은 GDScript int가 64비트 부호형이라 곱셈 오버플로가 음수로 돌면
## `>>`가 산술 시프트로 바뀌어 비트가 안 섞이는 것을 막기 위함이다.
static func _scatter(seed_id: StringName) -> int:
	var x := absi(hash(seed_id)) & 0x7fffffff
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0x7fffffff
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0x7fffffff
	return (x ^ (x >> 16)) & 0x7fffffff


## 정지 포즈 고정 — HOLD_RESTING_FRAME 근거는 상수 주석 참조.
func _hold_resting_frame() -> void:
	if HOLD_RESTING_FRAME:
		sprite.stop()
		sprite.frame = 0
	else:
		sprite.play()


func _process(delta: float) -> void:
	_update_breathing(delta)
	if _is_talking or _is_wandering:
		return

	if wander_range > 0 and _runtime != null:
		_wander_wait -= delta
		if _wander_wait <= 0.0:
			_wander_wait = randf_range(4.0, 8.0)
			if _try_wander_step():
				return

	_look_wait -= delta
	if _look_wait > 0.0:
		return
	_look_wait = randf_range(LOOK_MIN, LOOK_MAX)
	var next: StringName = FACINGS[randi() % FACINGS.size()]
	if next != _facing:
		_apply_facing(next)


## 제자리 아이들 — 정수 픽셀 호흡 + 간헐 무게중심 이동.
## 이름은 예전 그대로 둔다(tests/smoke_f1_events.gd가 이 이름으로 직접 부른다).
## 스케일·회전은 건드리지 않는다 — 파일 머리 주석의 리샘플 실측이 그 이유다.
func _update_breathing(delta: float) -> void:
	# 멈춰야 하는 세 경우:
	# - 배회 중: 진짜로 걷는 중이라 제자리 연출을 겹치면 걸음이 떤다.
	# - 대화 중: 말하는 상대가 계속 까딱거리면 시선이 대사창에서 떨어진다.
	#   (예전 코드는 호흡만은 대화 중에도 계속 돌았다 — 여기서 함께 막는다.)
	# - 스위치 off: 관문·스크린샷이 프레임 0 정지 상태를 보장받아야 할 때.
	if _is_wandering or _is_talking or not idle_motion:
		sprite.position.y = 0.0
		_fidget_hold = 0.0
		if HOLD_RESTING_FRAME and sprite.frame != 0:
			sprite.frame = 0
		return

	_breath_phase = fmod(_breath_phase + delta * TAU / BREATH_PERIOD, TAU)

	var dip := 0
	if _fidget_hold > 0.0:
		_fidget_hold -= delta
		if _fidget_hold <= 0.0:
			if HOLD_RESTING_FRAME:
				sprite.frame = 0
		else:
			dip = FIDGET_DIP_PX
	else:
		_fidget_wait -= delta
		if _fidget_wait <= 0.0:
			_fidget_wait = randf_range(FIDGET_MIN, FIDGET_MAX)
			# 프레임 0을 세워 두는 모드에서만 손댄다 — 애니가 도는 중에 frame을 찍으면
			# 다음 틱에 재생기가 덮어써서 아무 일도 안 일어난다.
			if (
				HOLD_RESTING_FRAME
				and sprite.sprite_frames != null
				and sprite.sprite_frames.has_animation(sprite.animation)
				and sprite.sprite_frames.get_frame_count(sprite.animation) > 1
			):
				_fidget_hold = FIDGET_HOLD
				sprite.frame = 1
				dip = FIDGET_DIP_PX

	# 위로만 뜬다(0 또는 -1). 아래로도 내려가게 하면 발이 그림자(ShadowBlob, 고정 위치)를
	# 파고들어 바닥에 가라앉는 것처럼 보인다. 사각파라 중간값이 없고, 따라서 리샘플도 없다.
	var rise := -BREATH_AMP_PX if sin(_breath_phase) > 0.0 else 0
	sprite.position.y = float(rise + dip)


func _apply_facing(next: StringName) -> void:
	var anim := SpriteSets.pose_anim(sprite.sprite_frames, next, false)
	if anim.is_empty():
		return
	_facing = next
	sprite.animation = anim
	_fidget_hold = 0.0  # 방향이 바뀌면 이전 방향의 두 번째 포즈가 남아 있으면 안 된다
	_hold_resting_frame()
	# 예전에는 여기서 회전 트윈(0.08rad)으로 "고개 까딱"을 넣었다. 뺐다 —
	# 0.08rad(4.58°)이면 85px 높이 스프라이트의 윗변이 아랫변보다 6.84px 밀려
	# 축에 정렬된 픽셀 행이 하나도 남지 않는다(파일 머리 주석 참조).
	# 방향 전환 자체가 이미 몸 전체가 다시 그려지는 큰 변화라 덧댈 것이 없다.


func _try_wander_step() -> bool:
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	dirs.shuffle()
	if cell != _home_cell and randf() < 0.5:
		var back := _step_towards(cell, _home_cell)
		if back != Vector2i.ZERO:
			dirs.push_front(back)

	for dir in dirs:
		var target := cell + dir
		if (
			absi(target.x - _home_cell.x) > wander_range
			or absi(target.y - _home_cell.y) > wander_range
		):
			continue
		for c in body_cells():
			_runtime.set_override_attr(c, 0)
		var fits := Placement.body_fits(_runtime, target)
		if not fits:
			for c in body_cells():
				_runtime.set_override_attr(c, 1)
			continue
		if Placement.bodies_touch(target, GameState.player_cell):
			for c in body_cells():
				_runtime.set_override_attr(c, 1)
			continue

		cell = target
		for c in body_cells():
			_runtime.set_override_attr(c, 1)

		_is_wandering = true
		var face_name := &"down"
		if dir.x < 0:
			face_name = &"left"
		elif dir.x > 0:
			face_name = &"right"
		elif dir.y < 0:
			face_name = &"up"

		var walk_anim := SpriteSets.pose_anim(sprite.sprite_frames, face_name, true)
		if not walk_anim.is_empty():
			sprite.animation = walk_anim
			sprite.play()
		_facing = face_name

		var tw := create_tween()
		tw.tween_property(self, "position", GridMover.block_center(cell), WANDER_STEP_TIME)
		tw.finished.connect(
			func() -> void:
				_is_wandering = false
				step_landed.emit(cell)
				_apply_facing(_facing)
		)
		return true
	return false


func _step_towards(from: Vector2i, to: Vector2i) -> Vector2i:
	var diff := to - from
	if absi(diff.x) >= absi(diff.y) and diff.x != 0:
		return Vector2i(1 if diff.x > 0 else -1, 0)
	elif diff.y != 0:
		return Vector2i(0, 1 if diff.y > 0 else -1)
	return Vector2i.ZERO
