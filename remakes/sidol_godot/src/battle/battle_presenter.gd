class_name BattlePresenter
extends Node2D
## 전투 연출 프리젠터 — 로직(BattleController)과 분리된 시각·청각 표현 계층.
## 설계: docs/02_design/01_oop_redesign.md §5 (로직↔연출 완전 분리).
## ChoreographyRunner가 채널 키프레임을 중계하면 본 노드가
## 스프라이트 안무·이펙트·화면 흔들림/플래시·히트스톱·데미지 팝을 실행한다.

const ELEMENT_COLORS := {
	&"physical": Color(1.0, 0.9, 0.15),
	&"fire": Color(1.0, 0.45, 0.1),
	&"electric": Color(0.55, 0.85, 1.0),
	&"none": Color(0.92, 0.92, 0.98),
}
const PLAYER_HURT_COLOR := Color(1, 0.25, 0.15)
const HITSTOP_SCALE := 0.05
## 전투 화면 플레이어 실효 셀(px) — 구형(64셀 × 1.5배)과 동일.
## 노드 배율을 cell×scale로 정규화해 시트 교체(아트 모드·해상도 무관)에도 구도 보존.
const BATTLE_PLAYER_CELL_PX := 96.0

var target_index := 0   ## 현재 타겟 적 인덱스 — 컨트롤러가 move 재생 전 설정

var player_sprite: Sprite2D
var enemy_sprites: Array[Sprite2D] = []

var _root: Node2D
var _shake_power := 0.0
var _root_base := Vector2.ZERO
var _was_shaken := false
var _hitstop_busy := false
var _player_paths: Dictionary = {}


func setup(root: Node2D) -> void:
	_root = root
	_root_base = root.position


## 전투 스프라이트 구성 — 플레이어(셀 크기 메타 기반, 비정형 비율 허용) + 적
func build_sprites(enemy_count: int) -> void:
	player_sprite = Sprite2D.new()
	var cs := _player_cell_size()
	var ptex: Texture2D = load(str(_resolved_player()["sheet"]))
	if ptex != null:
		var at := AtlasTexture.new()
		at.atlas = ptex
		at.region = Rect2(0, 0, cs.x, cs.y)
		player_sprite.texture = at
	player_sprite.position = Vector2(120, 220)
	var rs := maxf(_player_render_scale(), 0.01)
	player_sprite.scale = Vector2.ONE * (BATTLE_PLAYER_CELL_PX
			/ (float(cs.x) * rs))
	player_sprite.set_meta(&"base_pos", player_sprite.position)
	_root.add_child(player_sprite)

	for i in enemy_count:
		var es := Sprite2D.new()
		# 적 아트는 LLM 리메이크 파이프라인(assets/raw/llm → 30_packed) 확정 후 교체.
		# 원본 bmp(originals_ref)는 참조자료로 격하돼 임포트 불가 — 로드 시도 시
		# 매 전투 ERROR 스팸이 발생하므로 플레이스홀더만 생성한다(8/25 스윕 발견).
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(randf_range(0.5, 1.0), randf_range(0.2, 0.6),
				randf_range(0.2, 0.5)))
		es.texture = ImageTexture.create_from_image(img)
		es.position = Vector2(600 + i * 100, 180)
		es.scale = Vector2(1.5, 1.5)
		es.set_meta(&"base_pos", es.position)
		_root.add_child(es)
		enemy_sprites.append(es)


func on_move_start(_move_data: Dictionary) -> void:
	_reset_sprites()


## 활성 아트 모드의 플레이어 시트 경로 — 설정 모드 우선, 부재 시 반대 세트 폴백
func _resolved_player() -> Dictionary:
	if _player_paths.is_empty():
		_player_paths = SpriteSets.character_sheet(&"player")
	return _player_paths


## 플레이어 시트 셀 크기 — 활성 세트 메타 기반(cell_w/cell_h 지원)
func _player_cell_size() -> Vector2i:
	var meta_path := str(_resolved_player()["meta"])
	if not meta_path.is_empty() and FileAccess.file_exists(meta_path):
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if typeof(m) == TYPE_DICTIONARY:
			var d: Dictionary = m
			return Vector2i(int(d.get("cell_w", d.get("cell", 64))),
					int(d.get("cell_h", d.get("cell", 64))))
	return Vector2i(64, 64)


## 아트 해상도와 게임 내 크기 분리 — 메타 scale (기본 1)
func _player_render_scale() -> float:
	var meta_path := str(_resolved_player()["meta"])
	if not meta_path.is_empty() and FileAccess.file_exists(meta_path):
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if typeof(m) == TYPE_DICTIONARY:
			return float(m.get("scale", 1.0))
	return 1.0


## sprite 채널 — 액터 스프라이트를 base_pos 기준 오프셋으로 tween.
func play_sprite_kf(kf: Dictionary) -> void:
	var spr := _actor_sprite(str(kf.get("actor", "self")))
	if spr == null or not is_instance_valid(spr):
		return
	var pos_arr: Array = kf.get("pos", [0, 0])
	var off := Vector2(float(pos_arr[0]), float(pos_arr[1])) if pos_arr.size() >= 2 \
			else Vector2.ZERO
	var dur := maxf(float(kf.get("dur", 0.12)), 0.01)
	var tw := spr.create_tween()
	tw.tween_property(spr, "position",
			(spr.get_meta(&"base_pos") as Vector2) + off, dur)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## fx 채널 — 히트 스파크 등 원샷 파티클.
func play_fx_kf(kf: Dictionary) -> void:
	match str(kf.get("effect", "hit_spark")):
		"hit_spark":
			var anchor := _actor_sprite(str(kf.get("at_actor", "target")))
			if anchor == null:
				return
			_spawn_spark(anchor.position)


func play_camera_kf(_kf: Dictionary) -> void:
	pass  # 전투 씬 카메라 미도입 — Phase 8 오디오/연출 고도화 때 zoom/pan 확장


## screen 채널 — shake / flash.
func play_screen_kf(kf: Dictionary) -> void:
	if kf.has("shake"):
		_shake_power = maxf(_shake_power, float(kf["shake"]))
	if kf.has("flash"):
		var col := Color(str(kf["flash"]))
		col.a = float(kf.get("a", 0.3))
		_do_flash(col)


## 데미지 팝 — 속성 색상 + 양 비례 크기.
func show_damage_number(amount: int, on_player: bool,
		element: StringName = &"physical", enemy_index: int = -1) -> void:
	var lbl := Label.new()
	lbl.text = str(maxi(amount, 0))
	var font_size := clampi(16 + absi(amount) / 4, 16, 44)
	lbl.add_theme_font_size_override("font_size", font_size)
	if on_player:
		lbl.add_theme_color_override("font_color", PLAYER_HURT_COLOR)
	else:
		lbl.add_theme_color_override("font_color",
				ELEMENT_COLORS.get(element, ELEMENT_COLORS[&"none"]))
	lbl.position = _pop_position(on_player, enemy_index, font_size)
	_root.add_child(lbl)
	var tw := lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 28.0, 0.35)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(lbl.queue_free)


## 피격 플래시 — 타겟이 빨갛게 깜빡임.
func hurt_flash(spr: Sprite2D) -> void:
	if spr == null or not is_instance_valid(spr):
		return
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate", Color(5, 0.3, 0.3), 0.05)
	tw.tween_property(spr, "modulate", Color.WHITE, 0.1)


## 히트스톱 — 임팩트 순간 시간 감속.
func hitstop(duration: float = 0.06) -> void:
	if _hitstop_busy:
		return
	_hitstop_busy = true
	Engine.time_scale = HITSTOP_SCALE
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_busy = false


func _process(delta: float) -> void:
	if _root == null:
		return
	if _shake_power > 0.01:
		_shake_power = lerpf(_shake_power, 0.0, minf(delta * 10.0, 1.0))
		_root.position = _root_base + Vector2(
				randf_range(-_shake_power, _shake_power),
				randf_range(-_shake_power, _shake_power))
		_was_shaken = true
	elif _was_shaken:
		_root.position = _root_base
		_was_shaken = false


func _actor_sprite(actor_id: String) -> Sprite2D:
	if actor_id == "self":
		return player_sprite
	var idx := clampi(target_index, 0, enemy_sprites.size() - 1)
	return enemy_sprites[idx] if not enemy_sprites.is_empty() else null


func _reset_sprites() -> void:
	for spr: Sprite2D in ([player_sprite] as Array[Sprite2D]) + enemy_sprites:
		if spr != null and is_instance_valid(spr) and spr.has_meta(&"base_pos"):
			spr.position = spr.get_meta(&"base_pos")
			spr.modulate = Color.WHITE


func _pop_position(on_player: bool, enemy_index: int, font_size: int) -> Vector2:
	if on_player and player_sprite != null:
		var pp := player_sprite.position
		return Vector2(pp.x - font_size * 0.5 + randf_range(-8, 8), pp.y - 40)
	if enemy_index >= 0 and enemy_index < enemy_sprites.size():
		var ep := enemy_sprites[enemy_index].position
		return Vector2(ep.x - font_size * 0.5 + randf_range(-6, 6), ep.y - 48)
	return Vector2(randf_range(190, 260), randf_range(60, 100))


func _spawn_spark(at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 14
	p.lifetime = 0.28
	p.spread = 180.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 140.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = Color(1.0, 0.85, 0.3)
	_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)


func _do_flash(col: Color) -> void:
	if _flash_rect() != null:
		return
	var rect := ColorRect.new()
	rect.name = "FlashOverlay"
	rect.color = col
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.position = Vector2.ZERO
	rect.size = _root.get_viewport_rect().size
	rect.z_index = 100
	_root.add_child(rect)
	var tw := rect.create_tween()
	tw.tween_property(rect, "modulate:a", 0.0, 0.18)
	tw.tween_callback(rect.queue_free)


func _flash_rect() -> ColorRect:
	var n := _root.get_node_or_null(^"FlashOverlay")
	return n as ColorRect
