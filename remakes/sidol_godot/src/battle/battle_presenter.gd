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
const IDLE_FPS := 2.0  ## 전투 중 idle 프레임 순환 속도
## 전투 화면 플레이어 실효 셀(px) — 구형(64셀 × 1.5배)과 동일.
## 노드 배율을 cell×scale로 정규화해 시트 교체(아트 모드·해상도 무관)에도 구도 보존.
const BATTLE_PLAYER_CELL_PX := 96.0

var _idle_clock := 0.0

var target_index := 0  ## 현재 타겟 적 인덱스 — 컨트롤러가 move 재생 전 설정

var player_sprite: Sprite2D
var enemy_sprites: Array[Sprite2D] = []

var _root: Node2D
var _shake_power := 0.0
var _root_base := Vector2.ZERO
var _was_shaken := false
var _hitstop_busy := false
var _player_paths: Dictionary = {}

## 전투 바닥은 어두워 필드 기본 세기(0.35)로는 그림자가 묻힌다.
const BATTLE_SHADOW_ALPHA := 0.62


func setup(root: Node2D) -> void:
	_root = root
	_root_base = root.position


## 전투 스프라이트 구성 — 플레이어(셀 크기 메타 기반, 비정형 비율 허용) + 적
## 적은 종별 시트(SpriteSets — <species>_original/_remake)를 사용하며,
## 시트 미정착 종(보스 등 신규 창작 대상)은 기존 플레이스홀더 사각형 폴백.
func build_sprites(enemy_ids: Array[String]) -> void:
	player_sprite = Sprite2D.new()
	var cs := _player_cell_size()
	var ptex: Texture2D = load(str(_resolved_player()["sheet"]))
	if ptex != null:
		var at := AtlasTexture.new()
		at.atlas = ptex
		at.region = Rect2(0, 0, cs.x, cs.y)
		player_sprite.texture = at
		player_sprite.set_meta(&"anim_cell", cs)  # idle 프레임 순환용(행0 정면 2프레임)
	player_sprite.position = Vector2(120, 220)
	var rs := maxf(_player_render_scale(), 0.01)
	player_sprite.scale = Vector2.ONE * (BATTLE_PLAYER_CELL_PX / (float(cs.x) * rs))
	player_sprite.set_meta(&"base_pos", player_sprite.position)
	_root.add_child(player_sprite)
	_attach_ground_shadow(player_sprite)

	for i in enemy_ids.size():
		var es := Sprite2D.new()
		var node_scale := 1.5  # 폴백(64px 사각형) 기본 배율 — 기존 값 유지
		var paths := SpriteSets.character_sheet(StringName(enemy_ids[i]), true)
		if not str(paths["sheet"]).is_empty():
			var meta: Dictionary = {}
			var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(paths["meta"])))
			if typeof(raw) == TYPE_DICTIONARY:
				meta = raw
			var cell := float(meta.get("cell_w", meta.get("cell", 64)))
			var meta_scale := maxf(float(meta.get("scale", 1.0)), 0.01)
			var tex: Texture2D = load(str(paths["sheet"]))
			if tex != null:
				var eat := AtlasTexture.new()
				eat.atlas = tex
				eat.region = Rect2(0, 0, cell, cell)  # 행 0 = 정면(walk_down) 1프레임
				es.texture = eat
				es.set_meta(&"anim_cell", Vector2i(int(cell), int(cell)))
				# 실효 크기 정규화 — 셀×스케일 무관하게 화면상 크기 일관
				node_scale = BATTLE_PLAYER_CELL_PX / (cell * meta_scale)
		if es.texture == null:
			var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
			img.fill(Color(randf_range(0.5, 1.0), randf_range(0.2, 0.6), randf_range(0.2, 0.5)))
			es.texture = ImageTexture.create_from_image(img)
		es.position = Vector2(600 + i * 100, 180)
		es.scale = Vector2.ONE * node_scale
		es.set_meta(&"base_pos", es.position)
		_root.add_child(es)
		_attach_ground_shadow(es)
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
			return Vector2i(
				int(d.get("cell_w", d.get("cell", 64))), int(d.get("cell_h", d.get("cell", 64)))
			)
	return Vector2i(64, 64)


## 발밑 접지 그림자. 배경에 바닥이 생기면서(BattleBackdrop) 액터가 허공에 뜬 것이
## 눈에 띄게 됐다 — 접지 근거를 준다.
## 스프라이트의 **자식이 아니라 형제**로 붙인다: 자식이면 스프라이트 scale(시트마다 다름)에
## 같이 늘어나 그림자가 제각각이 된다. 위치는 셀 하단(= 발끝)에 맞춘다.
func _attach_ground_shadow(spr: Sprite2D) -> void:
	if spr.texture == null:
		return
	var half_h := spr.texture.get_size().y * spr.scale.y * 0.5
	var blob := Sprite2D.new()
	blob.texture = ShadowBlob.shadow_texture(BATTLE_SHADOW_ALPHA)
	blob.scale = Vector2(2.4, 1.5)
	blob.position = spr.position + Vector2(0, half_h - 4.0)
	blob.z_index = spr.z_index - 1
	_root.add_child(blob)
	_root.move_child(blob, maxi(spr.get_index(), 0))


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
	var off := (
		Vector2(float(pos_arr[0]), float(pos_arr[1])) if pos_arr.size() >= 2 else Vector2.ZERO
	)
	var dur := maxf(float(kf.get("dur", 0.12)), 0.01) / SettingsManager.battle_speed_factor()
	var tw := spr.create_tween()
	(
		tw
		. tween_property(spr, "position", (spr.get_meta(&"base_pos") as Vector2) + off, dur)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)


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
	if kf.has("shake") and SettingsManager.screen_shake:
		_shake_power = maxf(_shake_power, float(kf["shake"]))
	if kf.has("flash"):
		var col := Color(str(kf["flash"]))
		col.a = float(kf.get("a", 0.3))
		_do_flash(col)


## 데미지 팝 — 속성 색상 + 양 비례 크기.
func show_damage_number(
	amount: int, on_player: bool, element: StringName = &"physical", enemy_index: int = -1
) -> void:
	var font_size := clampi(16 + absi(amount) / 4, 16, 44)
	var color: Color = (
		PLAYER_HURT_COLOR if on_player else ELEMENT_COLORS.get(element, ELEMENT_COLORS[&"none"])
	)
	_float_text(
		str(maxi(amount, 0)), color, _pop_position(on_player, enemy_index, font_size), font_size
	)


## 상태 플래그 팝 — WEAK!/BREAK! 등 텍스트 강조(데미지 팝 위).
func show_flag_pop(text: String, color: Color, enemy_index: int) -> void:
	_float_text(text, color, _pop_position(false, enemy_index, 20) - Vector2(0, 26), 20)


## 플레이어 회복 팝 — 초록 +N.
func show_player_heal(amount: int) -> void:
	var pos := (
		player_sprite.position + Vector2(-14, -52) if player_sprite != null else Vector2(140, 180)
	)
	_float_text("+%d" % maxi(amount, 0), Color(0.4, 1.0, 0.5), pos, 20)


## 도구 효과 문구 — 회복 팝보다 위에, 작게. 무엇이 일어났는지 글로 남긴다
## (상태이상 해제·공격 버프는 숫자 팝만으로는 안 보인다).
func show_player_note(text: String) -> void:
	if text.is_empty():
		return
	var pos := (
		player_sprite.position + Vector2(-30, -76) if player_sprite != null else Vector2(120, 150)
	)
	_float_text(text, Color(0.98, 0.86, 0.45), pos, 13)


func _float_text(text: String, color: Color, pos: Vector2, font_size: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.position = pos
	_root.add_child(lbl)
	var dur := 0.35 / SettingsManager.battle_speed_factor()
	var tw := lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", pos.y - 28.0, dur)
	tw.tween_property(lbl, "modulate:a", 0.0, dur)
	tw.chain().tween_callback(lbl.queue_free)


## 보스 특수공격 텔레그래그 — telegraph 코드 해석 연출(비블로킹).
## 지원 토큰: *flash*/*static*/*flicker* → 적색 플래시, *shake*/*rumble* → 흔들림,
## 접미 "0.8s" → 지속 시간. 미지정 코드는 기본 플래시.
func play_telegraph(code: String) -> void:
	var lower := code.to_lower()
	var dur := 0.8
	for p: String in lower.split("_"):
		if p.ends_with("s") and p.substr(0, p.length() - 1).is_valid_float():
			dur = maxf(float(p.substr(0, p.length() - 1)), 0.3)
	if lower.contains("shake") or lower.contains("rumble"):
		_shake_power = maxf(_shake_power, 7.0)
	var flashes := maxi(int(dur / 0.25), 1)
	for i in flashes:
		var col := Color(0.85, 0.15, 0.15, 0.22 if i % 2 == 0 else 0.10)
		get_tree().create_timer(0.25 * i).timeout.connect(_do_flash.bind(col))


## 타이밍 버튼 링 — 대상 위 수축 링, 입력 판정까지 블로킹(await).
func play_timing_ring(enemy_index: int, window: float) -> bool:
	if enemy_sprites.is_empty():
		return false
	var anchor := enemy_sprites[clampi(enemy_index, 0, enemy_sprites.size() - 1)]
	var ring := TimingRing.new()
	ring.window = window
	ring.position = anchor.position
	_root.add_child(ring)
	var success: bool = await ring.resolved
	return success


## 피격 플래시 — 타겟이 빨갛게 깜빡임.
func hurt_flash(spr: Sprite2D) -> void:
	if spr == null or not is_instance_valid(spr):
		return
	var f := SettingsManager.battle_speed_factor()
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate", Color(5, 0.3, 0.3), 0.05 / f)
	tw.tween_property(spr, "modulate", Color.WHITE, 0.1 / f)


## 히트스톱 — 임팩트 순간 시간 감속.
func hitstop(duration: float = 0.06) -> void:
	if _hitstop_busy:
		return
	_hitstop_busy = true
	Engine.time_scale = HITSTOP_SCALE
	var scaled := maxf(duration / SettingsManager.battle_speed_factor(), 0.02)
	await get_tree().create_timer(scaled, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_busy = false


func _process(delta: float) -> void:
	if _root == null:
		return
	if _shake_power > 0.01:
		_shake_power = lerpf(_shake_power, 0.0, minf(delta * 10.0, 1.0))
		_root.position = (
			_root_base
			+ Vector2(
				randf_range(-_shake_power, _shake_power), randf_range(-_shake_power, _shake_power)
			)
		)
		_was_shaken = true
	elif _was_shaken:
		_root.position = _root_base
		_was_shaken = false
	# idle 프레임 순환 — 정지 1프레임 해소(행0 정면 2프레임 토글)
	_idle_clock += delta
	_apply_anim_frame(int(_idle_clock * IDLE_FPS) % 2)


## 애니 메타 보유 스프라이트의 정면 프레임 순환
func _apply_anim_frame(frame: int) -> void:
	for spr: Sprite2D in ([player_sprite] as Array[Sprite2D]) + enemy_sprites:
		if spr == null or not is_instance_valid(spr) or not spr.has_meta(&"anim_cell"):
			continue
		var at := spr.texture as AtlasTexture
		if at == null:
			continue
		var cell: Vector2i = spr.get_meta(&"anim_cell")
		at.region.position.x = frame * float(cell.x)


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
