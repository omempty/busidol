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

## 원작이 문 통과 직전에 그리는 문 그림. 아래 문은 2열×4행(y+1~y+4), 위 문은 2열×3행(y-2~y).
const DOOR_DOWN := [163, 164, 165, 166, 167, 168, 169, 170]
const DOOR_UP := [157, 158, 159, 160, 161, 162]

const DOOR_FADE := 0.12
const CHEST_RISE := 10.0
const CHEST_TIME := 0.28


## 문이 열린다 — 원작 그림을 그 자리에 띄우고 효과음을 낸다.
##
## 원작에는 `door.voc` 호출이 있었으나 **주석 처리**되어 실제로는 소리가 없었다.
## 연출 층은 켜는 쪽이 기본값이라는 방침에 따라 되살린다(에셋 `sfx_door_open.wav`는
## 진작 납품돼 있었는데 어디서도 재생하지 않고 있었다).
func door_open(renderer: MapRenderer, anchor: Vector2i, dir: Vector2i, hold: float) -> void:
	AudioManager.play_sfx(&"sfx_door_open")
	var ids: Array = DOOR_DOWN if dir == Vector2i.DOWN else DOOR_UP
	var top := anchor.y + 1 if dir == Vector2i.DOWN else anchor.y - 2
	var sprites: Array[Sprite2D] = []
	for i in ids.size():
		var tex := renderer.object_texture(int(ids[i]))
		if tex == null:
			continue
		var cell := Vector2i(anchor.x + i % 2, top + i / 2)
		sprites.append(_put(tex, cell))
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
func chest_open(renderer: MapRenderer, cells: Array[Vector2i]) -> void:
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


func _put(tex: Texture2D, cell: Vector2i) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.z_index = Z
	s.position = (Vector2(cell) + Vector2(0.5, 0.5)) * float(MapDefinition.TILE_PX)
	add_child(s)
	return s
