class_name FloorLighting
extends Node2D
## 층 조명 — 어두운 층에서만 화면 전체 톤을 낮추고 액터에 광원을 붙인다.
##
## 참조 구현: `D:\Game\LodeRunner` 의 `scenes/game/game.gd`
## (`_apply_biome_tint()` / `_attach_light()`). 가져온 것은 **조합**이다 —
## CanvasModulate로 캔버스 톤을 낮추고, 런타임에 구운 GradientTexture2D 한 장을
## 텍스처로 쓰는 PointLight2D를 액터에 붙인다. 광원은 액터의 자식이라 액터가
## 사라지면 같이 사라진다(누적을 지우는 코드가 필요 없다).
##
## **가져오지 않은 것**: 그쪽의 "5레벨마다 바이옴 순환" 산술. 이 게임은 층별 테마가
## 이미 확정돼 있으므로(`data/maps/floors.json`) 순환이 아니라 상수표여야 한다.
##
## **차폐는 없다.** 참조 구현도 LightOccluder2D를 쓰지 않는다. 빛이 벽을 통과하므로
## 반경을 작게 잡아야 옆방으로 새는 것이 눈에 덜 띈다. 격자 시선 차폐
## (`PerceptionProbe.has_line_of_sight`)를 픽셀 광원에 물리는 것은 비용이 다른 문제라
## 여기서는 하지 않는다.
##
## 동적 조명을 쓰지 않는다는 기존 판단(`src/entities/shadow_blob.gd`)은 **발밑 그림자**를
## 무엇으로 그릴지에 대한 것이었다. 여기서 켜는 것은 그림자가 아니라 층 분위기이고
## 지하 한 층에만 든다. 표에 없는 층은 손대지 않으므로 원작 그대로 밝다.

## 조명을 켜는 층과 그 층의 톤. **여기 없는 층은 조명이 없다.**
## F0은 백로그 1.2 "어둠 미로"의 무대다(03_content_backlog.md). 랜턴 아이템이
## 들어오면 반경을 넓히는 자리도 여기가 된다.
const FLOOR_TINT := {
	0: Color(0.34, 0.32, 0.44),  # 잊혀진 서고 — 식은 형광등 색 (주변 20% 다운)
}

## 정전 비상등 톤 — F0의 식은 형광등과 다른 붉은색(백로그 §1.3).
## 정전 층도 어두운 층이다(안개가 같은 문을 탄다).
const BLACKOUT_TINT := Color(0.38, 0.14, 0.14)

## 광원 반경 = 64 × texture_scale (px). 타일이 32px이므로 칸 수로는 그 절반이다.
## 참조 구현은 16px 타일에 플레이어 2.4 · 적 1.2를 썼다(반경 9.6칸 · 4.8칸).
## 그 칸 수를 그대로 옮기면 세로 17칸인 이 화면을 위아래로 다 덮어 어둠이 좌우로만
## 남는다. 그래서 칸 기준으로 줄여 잡는다.
const PLAYER_SCALE := 3.0  # 반경 6칸
const PLAYER_ENERGY := 1.15

## 플레이어 아닌 액터 — 적 · NPC · 배경 보행자. 반경 3칸.
##
## 참조 구현은 적에게만 달지만 여기서는 NPC와 보행자에게도 단다. F0에는 **상점
## (식당 아가씨)** 을 포함해 NPC 3명과 보행자 1명이 산다(data/maps/npcs_f0.json).
## 어둠에 묻혀 안 보이는 상점은 없는 상점이다 — 이 저장소가 반복해 잡아 온 결함과
## 같은 모양이 된다. 적에게 다는 이유는 반대다: 어둠 속에서 **적이 자기 위치를 빛으로
## 먼저 알린다**(모퉁이 너머 예고).
const ACTOR_SCALE := 1.5  # 반경 3칸
const ACTOR_ENERGY := 0.8

const LIGHT_NAME := "FloorLight"
const TINT_NAME := "FloorTint"
const TEX_PX := 128

## 광원 텍스처는 한 장이면 된다 — 클래스 단위로 캐시한다(ShadowBlob과 같은 방식).
static var _light_tex: GradientTexture2D = null
## 런타임 정전 층 집합(층 번호 → true). 정적 표와 달리 세션 중 바뀐다.
## 세이브에는 실리지 않는다 — 정전 한복판에서 저장 후 불러오면 밝은 F1로 깨어나지만
## 분전반 트리거(requires Q_F1_BLACKOUT)는 살아 있어 스위치를 올리면 정합해진다.
static var _blackout := {}

var _floor := -1
var _tint: CanvasModulate = null


## 이 층이 어두운 층인가 — **안개도 이것을 탄다.**
##
## 규칙을 하나로 둔다: 어두운 층은 지도도 안 그려진다. 조명 표와 안개 판정을 갈라 두면
## "불은 꺼졌는데 지도는 다 보이는" 층이 생긴다. 정전 이벤트도 같은 문을 통과하게 된다.
static func is_dark(floor_index: int) -> bool:
	return FLOOR_TINT.has(floor_index) or _blackout.has(floor_index)


## 이 층이 지금 정전 중인가.
static func is_blackout(floor_index: int) -> bool:
	return _blackout.has(floor_index)


## 정전 기록을 통째로 지운다 — **새 게임·불러오기의 대칭 짝**이다(`GameState.fog.clear()` 옆).
##
## `_blackout`은 클래스 정적이라 씬 교체는 물론 **판이 바뀌어도 살아남는다.** 지우지
## 않으면 정전 중에 끝낸 판의 어둠이 다음 판 F1에 그대로 얹히는데, 새 판에는
## `Q_F1_BLACKOUT`이 없어 분전반 트리거(requires_flag)가 열리지 않는다 —
## **끌 수 없는 정전**, 즉 진행 불가다. 세이브에 싣지 않기로 한 이상 여기서 지워야 한다.
static func clear_blackout() -> void:
	_blackout.clear()


## 이 층의 톤 — 정전이면 비상등, 아니면 표. 어두운 층에서만 부른다.
static func tint_for(floor_index: int) -> Color:
	if _blackout.has(floor_index):
		return BLACKOUT_TINT
	return FLOOR_TINT[floor_index]


## 방사형 광원 텍스처 — 가운데가 밝고 가장자리에서 알파 0으로 사라진다.
static func light_texture() -> GradientTexture2D:
	if _light_tex != null:
		return _light_tex
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = TEX_PX
	tex.height = TEX_PX
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	_light_tex = tex
	return tex


## 층 조명을 그 층 것으로 맞춘다 — 층 전환마다 불린다.
## `actors`는 지금 서 있는 액터 전부(플레이어 · 적 · NPC · 보행자).
func apply(floor_index: int, actors: Array) -> void:
	_floor = floor_index
	_kill_restore_tw()
	if _tint != null:
		_tint.queue_free()
		_tint = null
	if not is_dark(floor_index):
		for a: Variant in actors:
			_strip(a as Node2D)
		return
	_tint = CanvasModulate.new()
	_tint.name = TINT_NAME
	_tint.color = tint_for(floor_index)
	add_child(_tint)
	for a: Variant in actors:
		attach(a as Node2D)


## 런타임 정전 토글 — 컷신 blackout op → field.set_blackout이 이 문으로 들어온다.
## 켜면 비상등 톤 + 액터 광원, 끄면(분전반 복구) 형광등 순차 점등으로 밝아진다.
func set_blackout_enabled(floor_index: int, enabled: bool, actors: Array) -> void:
	if enabled:
		_blackout[floor_index] = true
		apply(floor_index, actors)
	else:
		_blackout.erase(floor_index)
		_restore_sequential(actors)


## 액터 하나에 광원을 붙인다. 밝은 층이거나 이미 붙어 있으면 아무 일도 하지 않는다.
## **리스폰된 몬스터도 이 문으로 들어온다**(EnemyManager.enemy_spawned).
## 그렇지 않으면 첫 무리만 빛나고 나중에 태어난 놈은 어둠에 묻힌다.
func attach(actor: Node2D) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if not is_dark(_floor):
		return
	if actor.has_node(NodePath(LIGHT_NAME)):
		return
	var is_player := actor is PlayerEntity
	var light := PointLight2D.new()
	light.name = LIGHT_NAME
	light.texture = light_texture()
	light.texture_scale = PLAYER_SCALE if is_player else ACTOR_SCALE
	light.energy = PLAYER_ENERGY if is_player else ACTOR_ENERGY
	# 액터의 논리 발밑이 아니라 몸 가운데를 비춘다 — 2×2 발판의 중심(minimap과 같은 기준).
	light.position = Vector2(MapDefinition.TILE_PX, MapDefinition.TILE_PX) * 0.5
	actor.add_child(light)


## 액터의 광원을 거둔다 — 정전 복구(밝은 층으로 돌아감) 때만 쓴다.
func _strip(actor: Node2D) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if actor.has_node(NodePath(LIGHT_NAME)):
		actor.get_node(NodePath(LIGHT_NAME)).queue_free()


## 복구 점등 — 형광등이 하나둘 켜지듯 3단으로 밝아진다(백로그 §1.3).
## 액터 광원은 마지막에 거둔다. 연타해도 트윈 하나로 직렬화된다.
const RESTORE_STEPS := 3
const RESTORE_STEP_TIME := 0.3

var _restore_tw: Tween = null


func _kill_restore_tw() -> void:
	if _restore_tw != null and _restore_tw.is_valid():
		_restore_tw.kill()
	_restore_tw = null


func _restore_sequential(actors: Array) -> void:
	_kill_restore_tw()
	if _tint == null:
		apply(_floor, actors)
		return
	var from: Color = _tint.color
	var tw := create_tween()
	_restore_tw = tw
	for i in range(1, RESTORE_STEPS + 1):
		var c: Color = from.lerp(Color.WHITE, float(i) / float(RESTORE_STEPS))
		tw.tween_property(_tint, "color", c, RESTORE_STEP_TIME)
	tw.tween_callback(_finish_restore.bind(actors))


func _finish_restore(actors: Array) -> void:
	_restore_tw = null
	if _tint != null:
		_tint.queue_free()
		_tint = null
	for a: Variant in actors:
		_strip(a as Node2D)
