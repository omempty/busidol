class_name FieldFx
extends Node2D
## 필드 연출 전담 — 문 통과 · 상자 개봉. **판정은 하나도 하지 않는다.**
##
## 방침은 [04_uiux §0](../../docs/02_design/04_uiux_modernization.md): 큰 문맥은 원작,
## 세세한 연출은 현대 트렌드로 적극 도입. 그래서 문은 원작이 그리던 그림을 되살리고
## (원작 `GOODITEM.C:move_check_gate()`), 상자는 원작에 없던 개봉 연출을 새로 만든다.
##
## 이동·조사 판정의 단일 소스(`ReachProbe.neighbors` · `Field._chest_in_front`)는
## 건드리지 않는다. 갈라지면 감사 도구와 게임이 서로 다른 세계를 보게 된다.

const Z := 15  # 오브젝트 레이어(10)보다 위, 상호작용 알약(40)보다 아래
## 문 그림은 **주인공보다 위**에 온다(주인공 z=15). 같은 z면 그리는 순서가 트리
## 순서에 좌우돼 주인공이 문 위로 떠 보인다 — 문을 통과하는 게 아니라 벽을 뚫는
## 것처럼 보이던 원인의 절반이다.
const Z_DOOR := 18

## 원작이 문 통과 직전에 그리는 문 그림. 아래 문은 2열×4행(y+1~y+4), 위 문은 2열×3행(y-2~y).
const DOOR_DOWN := [163, 164, 165, 166, 167, 168, 169, 170]
const DOOR_UP := [157, 158, 159, 160, 161, 162]

const DOOR_FADE := 0.12
const CHEST_RISE := 10.0
const CHEST_TIME := 0.28

## 번개 섬광 — 화면이 한순간 밝아졌다 꺼진다(백로그 §1.3 정전 중 이벤트).
## 두 번 깜빡인다(번개는 대개 다중 방전이다). 정전 돌입 때 field.set_blackout이 부른다.
const FLASH_LAYER := 35
const FLASH_PEAK := 0.75
const FLASH_TIME := 0.09


## 창밖 번개 — 정전의 원인. 앞이 한순간 보이지만 안개는 걷지 않는다.
func lightning_flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = FLASH_LAYER
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 0)
	# **`set_anchors_preset`이 아니다.** 그쪽은 오프셋을 지금 크기(0×0)에 맞춰 남기므로
	# 전체화면 앵커를 줘도 0 크기가 되어 섬광이 화면에 한 픽셀도 안 뜬다
	# (이 저장소가 창 UI에서 한 번 물린 함정과 같은 것이다).
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	var tw := create_tween()
	for _i in 2:
		tw.tween_property(rect, "color:a", FLASH_PEAK, FLASH_TIME)
		tw.tween_property(rect, "color:a", 0.0, FLASH_TIME * 2.0)
	tw.tween_callback(layer.queue_free)


## 문이 열린다 — 원작 그림을 그 자리에 띄우고 효과음을 낸다.
##
## 원작에는 `door.voc` 호출이 있었으나 **주석 처리**되어 실제로는 소리가 없었다
## (`GOODITEM.C:1402` · 위·아래 문 두 곳 다 `/* */` 안에 있다). 연출 층은 켜는 쪽이
## 기본값이라는 방침(04_uiux §0)에 따라 되살린다.
##
## 2026-08-30: **원작 door.voc를 실제로 변환해 넣었으므로 그것을 먼저 쓴다**(04_uiux §5 —
## 원작 보이스는 재생성이 아니라 변환해 그대로). 미설치 PC에서는 AI 효과음으로 내려간다.
func door_open(renderer: MapRenderer, anchor: Vector2i, dir: Vector2i, hold: float) -> void:
	if not AudioManager.play_voice(&"door"):
		AudioManager.play_sfx(&"sfx_door_open")
	var ids: Array = DOOR_DOWN if dir == Vector2i.DOWN else DOOR_UP
	var top := anchor.y + 1 if dir == Vector2i.DOWN else anchor.y - 2
	var sprites: Array[Sprite2D] = []
	for i in ids.size():
		var tex := renderer.object_texture(int(ids[i]))
		if tex == null:
			continue
		var cell := Vector2i(anchor.x + i % 2, top + i / 2)
		var spr := _put(tex, cell)
		spr.z_index = Z_DOOR
		sprites.append(spr)
	if sprites.is_empty():
		return
	var tw := create_tween().set_parallel(true)
	for s: Sprite2D in sprites:
		tw.tween_property(s, "modulate:a", 0.0, DOOR_FADE).set_delay(maxf(hold, 0.0))
	tw.chain().tween_callback(
		func() -> void:
			for s: Sprite2D in sprites:
				s.queue_free()
	)


## 상자가 열린다 — 원작에 없던 연출이다(원작은 ATT를 지워 즉시 끝냈다).
## 뚜껑이 튀어 오르듯 위로 밀리며 사라진다. 그림 자체는 호출자가 지운다.
## celebratory=false(빈 상자·기습)면 뚜껑 팝만 나가고 스파클은 생략한다.
func chest_open(renderer: MapRenderer, cells: Array[Vector2i], celebratory: bool = true) -> void:
	var sprites: Array[Sprite2D] = []
	for cell: Vector2i in cells:
		var tex := renderer.object_texture_at(cell)
		if tex == null:
			continue
		sprites.append(_put(tex, cell))
	if sprites.is_empty():
		return
	var tw := create_tween().set_parallel(true)
	for s: Sprite2D in sprites:
		(
			tw
			. tween_property(s, "position:y", s.position.y - CHEST_RISE, CHEST_TIME)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)
		tw.tween_property(s, "modulate:a", 0.0, CHEST_TIME)
		tw.tween_property(s, "scale", Vector2(1.15, 0.85), CHEST_TIME)
	tw.chain().tween_callback(
		func() -> void:
			for s: Sprite2D in sprites:
				s.queue_free()
	)
	if celebratory:
		_chest_sparkle(cells)


## 기습 상자(MEET) — 뚜껑이 날아가고 검은 연기가 뿜는다.
## 금빛 스파클의 반대 자리다: 보상이 아니라 위협이 튀어나온다.
## 뚜껑은 높이·빠르게 + 제각각 기울어 날아가고, 적색 섬광이 한 번 번쩍인다.
func chest_ambush(renderer: MapRenderer, cells: Array[Vector2i]) -> void:
	var sprites: Array[Sprite2D] = []
	for cell: Vector2i in cells:
		var tex := renderer.object_texture_at(cell)
		if tex == null:
			continue
		sprites.append(_put(tex, cell))
	if sprites.is_empty():
		return
	var tw := create_tween().set_parallel(true)
	for s: Sprite2D in sprites:
		(
			tw
			. tween_property(s, "position:y", s.position.y - 26.0, 0.22)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		tw.tween_property(s, "rotation", randf_range(-0.45, 0.45), 0.3)
		tw.tween_property(s, "modulate:a", 0.0, 0.3).set_delay(0.1)
	tw.chain().tween_callback(
		func() -> void:
			for s: Sprite2D in sprites:
				s.queue_free()
	)
	_chest_puff(cells)
	_red_flash()


## 기습 연기 — 검붉은 먼지가 위로 솟는다(금빛 스파클과 반대 색).
func _chest_puff(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	var center := Vector2.ZERO
	for cell: Vector2i in cells:
		center += (Vector2(cell) + Vector2(0.5, 0.5)) * float(MapDefinition.TILE_PX)
	center /= float(cells.size())
	var p := CPUParticles2D.new()
	p.position = center + Vector2(0, -6)
	p.amount = 22
	p.one_shot = true
	p.explosiveness = 0.85
	p.lifetime = 0.7
	p.direction = Vector2(0, -1)
	p.spread = 50.0
	p.gravity = Vector2(0, -50)
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 160.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 5.5
	p.color = Color(0.32, 0.22, 0.3)
	p.z_index = Z + 1
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.4).timeout.connect(p.queue_free)


## 적색 섬광 — `lightning_flash`의 붉은 판. 기습 순간 화면이 한 번 굳는다.
func _red_flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = FLASH_LAYER
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(0.7, 0.05, 0.05, 0)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 0.28, 0.08)
	tw.tween_property(rect, "color:a", 0.0, 0.32)
	tw.tween_callback(layer.queue_free)


## 개봉 스파클 — 뚜껑이 열리는 자리에 금빛 파티클을 한 줌 뿌린다.
## 팝업·동전분수·개봉음과 겹쳐 "열었다"를 여러 감각으로 못 박는다.
func _chest_sparkle(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	var center := Vector2.ZERO
	for cell: Vector2i in cells:
		center += (Vector2(cell) + Vector2(0.5, 0.5)) * float(MapDefinition.TILE_PX)
	center /= float(cells.size())
	var p := CPUParticles2D.new()
	p.position = center + Vector2(0, -10)
	p.amount = 16
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 0.55
	p.direction = Vector2(0, -1)
	p.spread = 55.0
	p.gravity = Vector2(0, 160)
	p.initial_velocity_min = 70.0
	p.initial_velocity_max = 150.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.5
	p.color = Color(1.0, 0.86, 0.35)
	p.z_index = Z + 1
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


## 적 워프(잠복·순간이동) 먼지 — 사라진 자리와 나타난 자리에 각각 뿜는다.
## burrow의 설계는 "땅속으로 숨었다 나타난다"인데 연출이 스펙만 있고 재생이 없어
## 순간이동 버그로 읽혔다(2026-09-10 유저 지적). 자리 표시만으로 납득이 생긴다.
## 발걸음 먼지 — NPC 배회 착지용 공개 창구. `_dust_at` 그대로라 아군·적 구분이 없다.
## 발밑에 깔리면 이동이 "디딤"으로 읽힌다(무음 이동이 유령처럼 보이던 자리).
func step_puff(cell: Vector2i) -> void:
	_dust_at(cell)


func enemy_warp_puff(from_cell: Vector2i, to_cell: Vector2i) -> void:
	for cell: Vector2i in [from_cell, to_cell]:
		_dust_at(cell)


## 먼지 한 줌 — 상자 기습 연기(_chest_puff)의 옅은 판. 회색이라 아군·적 구분이 없다.
func _dust_at(cell: Vector2i) -> void:
	var p := CPUParticles2D.new()
	p.position = (
		(Vector2(cell) + Vector2(0.5, 0.5)) * float(MapDefinition.TILE_PX) + Vector2(0, -6)
	)
	p.amount = 14
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 0.55
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.gravity = Vector2(0, -30)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 90.0
	p.scale_amount_min = 2.5
	p.scale_amount_max = 4.5
	p.color = Color(0.55, 0.5, 0.42)
	p.z_index = Z + 1
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func _put(tex: Texture2D, cell: Vector2i) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.z_index = Z
	s.position = (Vector2(cell) + Vector2(0.5, 0.5)) * float(MapDefinition.TILE_PX)
	add_child(s)
	return s


## 문을 지나는 동안 주인공을 문 안으로 들여보낸다.
##
## **원작은 이렇게 하지 않는다.** `move_check_gate()`는 문 그림을 한 프레임 띄우고
## 곧바로 `mapy += 3`으로 3칸을 옮긴다 — 주인공은 내내 보이고, 문을 여는 동작도
## 사라졌다 나타나는 연출도 없다. 그래서 개선본에서도 "문을 통과해 버린다"는 지적이
## 나왔다(2026-08-29).
##
## 이동 모델(3칸 점프)은 원작 그대로 두고 **보이는 것만** 고친다 — 문 그림 뒤로
## 사라졌다가 반대편에서 다시 나타난다. 큰 문맥은 원작, 세세한 연출은 현대 트렌드.
func actor_through_door(actor: Node2D, hold: float) -> void:
	if actor == null:
		return
	var half := maxf(hold, 0.04) * 0.5
	var tw := create_tween()
	tw.tween_property(actor, "modulate:a", 0.0, half).set_trans(Tween.TRANS_SINE)
	tw.tween_property(actor, "modulate:a", 1.0, half).set_trans(Tween.TRANS_SINE)
	# 어떤 이유로 트윈이 끊겨도 투명한 주인공이 남으면 안 된다.
	tw.finished.connect(func() -> void: actor.modulate.a = 1.0)
