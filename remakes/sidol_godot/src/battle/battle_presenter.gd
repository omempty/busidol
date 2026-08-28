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
## 이펙트 시트 — assets/effects/<id>.png (+ .json 메타). 미납품이면 파티클 폴백.
## 2026-08-28까지 전투 fx는 CPUParticles2D 점 스파크 하나뿐이라 물리·화염·전격이
## 전부 같은 흰 불꽃이었다. data/effect_specs.json이 종을, 여기가 재생을 담당한다.
const EFFECT_DIR := "res://assets/effects/"
const EFFECT_DEFAULT_FPS := 14.0
## 전투 대형 컷 — assets/battle_cuts/<id>.png (+ .json). 공격·피격 순간에만 뜬다.
## 원작(1995)은 전투 전체를 320×200 전체 화면 프레임으로 연출했다(격투게임 패러디의
## 리미티드 애니메이션). 리메이크는 평소엔 96px 도트 화면을 유지하고 결정적 순간에만
## 큰 그림으로 바꿔 그 인상만 되살린다. 미납품이면 조용히 건너뛴다(기존 연출 유지).
const CUT_DIR := "res://assets/battle_cuts/"
const CUT_TARGET_H := 400.0  ## 화면(540) 대비 컷 인물 높이 — 원작의 화면 점유감
const CUT_DEFAULT_FPS := 12.0
## 시트 애니 — 적 시트에는 attack/hurt/death 행이 이미 들어 있는데(c_bug·null_pointer·
## rogue_vending 실측) 전투는 행0 idle 2프레임만 토글하고 있었다. 그 행들을 쓴다.
const ANIM_DEFAULT_FPS := 10.0
## 잔상 — 러지·공격 순간에 스프라이트를 몇 장 복제해 흘린다(에셋 없이 속도감).
const AFTERIMAGE_COUNT := 3
const AFTERIMAGE_FADE := 0.22
## 피격 넉백 — 맞은 쪽이 뒤로 밀렸다 돌아온다.
const KNOCKBACK_PX := 14.0
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
## 적 종 id — 시트 메타 조회(애니 행)에 필요하다.
var _enemy_ids: Array[String] = []
## 재생 중인 시트 이펙트 — {spr, cell, row, frames, fps, clock}. _process가 프레임을 넘긴다
## (타이머·람다 체인 대신 배열 하나로 두면 히트스톱·전투 속도 배율이 자동으로 따라온다).
var _fx_playing: Array[Dictionary] = []
var _fx_meta_cache: Dictionary = {}
## 재생 중 대형 컷 — {spr, cell, frames, fps, clock, hidden}. hidden은 컷이 대신하는
## 작은 액터 스프라이트(컷이 끝나면 되돌린다).
var _cut_playing: Array[Dictionary] = []
## 재생 중 시트 애니 — {spr, cell, row, frames, fps, clock, loop}. 끝나면 idle로 돌아간다.
var _anim_playing: Array[Dictionary] = []
## 액터별 시트 메타 캐시(경로 조회·JSON 파싱을 매 프레임 하지 않기 위해).
var _sheet_meta_cache: Dictionary = {}

## 전투 바닥은 어두워 필드 기본 세기(0.35)로는 그림자가 묻힌다.
const BATTLE_SHADOW_ALPHA := 0.62


func setup(root: Node2D) -> void:
	_root = root
	_root_base = root.position


## 전투 스프라이트 구성 — 플레이어(셀 크기 메타 기반, 비정형 비율 허용) + 적
## 적은 종별 시트(SpriteSets — <species>_original/_remake)를 사용하며,
## 시트 미정착 종(보스 등 신규 창작 대상)은 기존 플레이스홀더 사각형 폴백.
func build_sprites(enemy_ids: Array[String]) -> void:
	_enemy_ids = enemy_ids.duplicate()
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
		_slide_in(es, 1.0)  # 등장 — 화면 밖에서 미끄러져 들어온다(전투 시작의 박진감)
	if player_sprite != null:
		_slide_in(player_sprite, -1.0)


func on_move_start(_move_data: Dictionary) -> void:
	_reset_sprites()


## 전투 시작 등장 — 화면 밖에서 제자리로. SKIP이면 즉시 제자리(연출 생략).
func _slide_in(spr: Sprite2D, from_dir: float) -> void:
	if spr == null or not spr.has_meta(&"base_pos"):
		return
	var base: Vector2 = spr.get_meta(&"base_pos")
	if SettingsManager.effect_speed == SettingsManager.EffectSpeed.SKIP:
		spr.position = base
		return
	spr.position = base + Vector2(from_dir * 260.0, 0)
	var speed := maxf(SettingsManager.battle_speed_factor(), 0.1)
	var tw := spr.create_tween()
	tw.tween_property(spr, "position", base, 0.34 / speed).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)


## 활성 아트 모드의 플레이어 시트 경로 — 설정 모드 우선, 부재 시 반대 세트 폴백.
## **전투 전용 시트(player_battle)가 설치돼 있으면 그쪽을 먼저 쓴다** — 필드 시트에는
## 공격·피격 행이 없어서 전투에서 주인공만 동작이 없었다(적 시트에는 이미 있다).
func _resolved_player() -> Dictionary:
	if _player_paths.is_empty():
		var battle := SpriteSets.character_sheet(&"player_battle", true)
		_player_paths = (
			battle if not str(battle["sheet"]).is_empty() else SpriteSets.character_sheet(&"player")
		)
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
## 액터 시트의 이름 있는 행을 재생한다(attack/hurt/death 등). 행이 없으면 false —
## 호출부는 그대로 기존 연출(플래시·트윈)로 간다. 시트가 가진 것을 쓰는 것이 먼저다.
func play_anim(spr: Sprite2D, anim_name: String, asset_id: String = "") -> bool:
	if spr == null or not is_instance_valid(spr) or not spr.has_meta(&"anim_cell"):
		return false
	var meta := _sheet_meta(spr, asset_id)
	var anims: Dictionary = meta.get("animations", {})
	if not anims.has(anim_name):
		return false
	var anim: Dictionary = anims[anim_name]
	var cell: Vector2i = spr.get_meta(&"anim_cell")
	var at := spr.texture as AtlasTexture
	if at == null:
		return false
	# 이미 이 스프라이트가 애니 중이면 새 것으로 갈아탄다(연타 시 마지막 것이 이긴다).
	_stop_anim(spr)
	at.region.position = Vector2(0, float(int(anim.get("row", 0)) * cell.y))
	(
		_anim_playing
		. append(
			{
				"spr": spr,
				"cell": cell,
				"row": int(anim.get("row", 0)),
				"frames": maxi(int(anim.get("frames", 1)), 1),
				"fps": maxf(float(anim.get("fps", ANIM_DEFAULT_FPS)), 1.0),
				"clock": 0.0,
				"loop": bool(anim.get("loop", false)),
			}
		)
	)
	return true


## 적 인덱스로 부르는 편의 함수 — 컨트롤러·적 턴이 쓴다.
func play_enemy_anim(index: int, anim_name: String) -> bool:
	if index < 0 or index >= enemy_sprites.size():
		return false
	return play_anim(
		enemy_sprites[index], anim_name, str(_enemy_ids[index]) if index < _enemy_ids.size() else ""
	)


func _stop_anim(spr: Sprite2D) -> void:
	var kept: Array[Dictionary] = []
	for a in _anim_playing:
		if a["spr"] != spr:
			kept.append(a)
	_anim_playing = kept


## 시트 메타(JSON) — SpriteSets가 알려 준 경로에서 읽는다.
func _sheet_meta(spr: Sprite2D, asset_id: String) -> Dictionary:
	var key := asset_id if not asset_id.is_empty() else str(spr.get_instance_id())
	if _sheet_meta_cache.has(key):
		return _sheet_meta_cache[key]
	var meta: Dictionary = {}
	var path := ""
	if spr == player_sprite:
		path = str(_resolved_player()["meta"])
	elif not asset_id.is_empty():
		path = str(SpriteSets.character_sheet(StringName(asset_id), true)["meta"])
	if not path.is_empty() and FileAccess.file_exists(path):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(raw) == TYPE_DICTIONARY:
			meta = raw
	_sheet_meta_cache[key] = meta
	return meta


## 재생 중 시트 애니 진행 — 1회 재생이 끝나면 행0(정면)으로 되돌린다.
func _advance_anims(delta: float) -> void:
	if _anim_playing.is_empty():
		return
	var speed := SettingsManager.battle_speed_factor()
	var still: Array[Dictionary] = []
	for a in _anim_playing:
		var spr: Sprite2D = a["spr"]
		if spr == null or not is_instance_valid(spr):
			continue
		var at := spr.texture as AtlasTexture
		if at == null:
			continue
		a["clock"] = float(a["clock"]) + delta * speed
		var idx := int(float(a["clock"]) * float(a["fps"]))
		var frames := int(a["frames"])
		var cell: Vector2i = a["cell"]
		if idx >= frames:
			if bool(a["loop"]):
				idx = idx % frames
			else:
				at.region.position = Vector2.ZERO  # idle 행으로 복귀
				continue
		at.region.position = Vector2(float(idx * cell.x), float(int(a["row"]) * cell.y))
		still.append(a)
	_anim_playing = still


## 잔상 — 지금 포즈를 복제해 뒤에 흘린다. 프레임 수를 늘리지 않고 속도감만 얻는 값싼 수단.
func spawn_afterimage(spr: Sprite2D, dir: float = -1.0) -> void:
	if spr == null or not is_instance_valid(spr) or spr.texture == null:
		return
	if SettingsManager.effect_speed == SettingsManager.EffectSpeed.SKIP:
		return
	for i in AFTERIMAGE_COUNT:
		var ghost := Sprite2D.new()
		ghost.texture = spr.texture
		ghost.scale = spr.scale
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ghost.position = spr.position + Vector2(dir * 12.0 * float(i + 1), 0)
		ghost.modulate = Color(0.75, 0.8, 1.0, 0.42 - 0.1 * float(i))
		ghost.z_index = spr.z_index - 1
		_root.add_child(ghost)
		var tw := ghost.create_tween()
		tw.tween_property(ghost, "modulate:a", 0.0, AFTERIMAGE_FADE + 0.05 * float(i))
		tw.tween_callback(ghost.queue_free)


## 피격 넉백 — 맞은 쪽이 밀렸다 제자리로. hurt_flash와 함께 쓴다.
func knockback(spr: Sprite2D, dir: float = 1.0) -> void:
	if spr == null or not is_instance_valid(spr) or not spr.has_meta(&"base_pos"):
		return
	var base: Vector2 = spr.get_meta(&"base_pos")
	var tw := spr.create_tween()
	var speed := maxf(SettingsManager.battle_speed_factor(), 0.1)
	(
		tw
		. tween_property(spr, "position", base + Vector2(dir * KNOCKBACK_PX, 0), 0.06 / speed)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(spr, "position", base, 0.12 / speed).set_trans(Tween.TRANS_BACK)


## 대형 컷 재생. 시트 미납품·연출 SKIP이면 false(호출부는 기존 연출을 유지한다).
## 원작의 WVISUAL=OFF 자리 — 연출 속도를 SKIP으로 두면 컷이 뜨지 않는다.
func play_cut(cut_id: String, actor_id: String = "self") -> bool:
	if cut_id.is_empty():
		return false
	if SettingsManager.effect_speed == SettingsManager.EffectSpeed.SKIP:
		return false
	var png := CUT_DIR + cut_id + ".png"
	if not ResourceLoader.exists(png):
		return false
	var tex: Texture2D = load(png)
	if tex == null:
		return false
	var actor := _actor_sprite(actor_id)
	if actor == null:
		return false
	var meta := _cut_meta(cut_id)
	var cell := int(meta.get("cell", 512))
	var anims: Dictionary = meta.get("animations", {})
	var anim: Dictionary = anims.get("play", {})
	var frames := maxi(int(anim.get("frames", int(tex.get_width() / maxi(cell, 1)))), 1)
	var fps := maxf(float(anim.get("fps", CUT_DEFAULT_FPS)), 1.0)
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(0, int(anim.get("row", 0)) * cell, cell, cell)
	var spr := Sprite2D.new()
	spr.texture = at
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var scale_f := CUT_TARGET_H / float(cell)
	spr.scale = Vector2.ONE * scale_f
	# 작은 액터의 발밑에 컷의 발이 오도록 — 구도가 튀지 않는다.
	var foot := (
		(actor.get_meta(&"base_pos") as Vector2)
		+ Vector2(0, actor.texture.get_size().y * actor.scale.y * 0.5)
	)
	spr.position = Vector2(actor.position.x, foot.y - CUT_TARGET_H * 0.5)
	spr.z_index = 40  # 이펙트(50)보다 아래, 액터보다 위
	_root.add_child(spr)
	actor.visible = false
	_cut_playing.append(
		{"spr": spr, "cell": cell, "frames": frames, "fps": fps, "clock": 0.0, "hidden": actor}
	)
	return true


## 컷 메타 JSON(설치 시 install_delivery.py가 스펙에서 생성).
func _cut_meta(cut_id: String) -> Dictionary:
	var path := CUT_DIR + cut_id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


## 재생 중 컷의 프레임 진행 — 끝나면 컷을 버리고 작은 액터를 되돌린다.
func _advance_cuts(delta: float) -> void:
	if _cut_playing.is_empty():
		return
	var speed := SettingsManager.battle_speed_factor()
	var still: Array[Dictionary] = []
	for cut in _cut_playing:
		var spr: Sprite2D = cut["spr"]
		var hidden: Sprite2D = cut["hidden"]
		if spr == null or not is_instance_valid(spr):
			if hidden != null and is_instance_valid(hidden):
				hidden.visible = true
			continue
		cut["clock"] = float(cut["clock"]) + delta * speed
		var idx := int(float(cut["clock"]) * float(cut["fps"]))
		if idx >= int(cut["frames"]):
			spr.queue_free()
			if hidden != null and is_instance_valid(hidden):
				hidden.visible = true
			continue
		var at := spr.texture as AtlasTexture
		if at != null:
			at.region.position.x = idx * float(cut["cell"])
		still.append(cut)
	_cut_playing = still


func play_sprite_kf(kf: Dictionary) -> void:
	# cut 키가 있으면 대형 컷을 띄운다 — 뜨지 않으면(미납품·SKIP) 기존 러지 트윈으로 간다.
	if kf.has("cut") and play_cut(str(kf["cut"]), str(kf.get("actor", "self"))):
		return
	var spr := _actor_sprite(str(kf.get("actor", "self")))
	if spr == null or not is_instance_valid(spr):
		return
	var pos_arr: Array = kf.get("pos", [0, 0])
	var off := (
		Vector2(float(pos_arr[0]), float(pos_arr[1])) if pos_arr.size() >= 2 else Vector2.ZERO
	)
	var dur := maxf(float(kf.get("dur", 0.12)), 0.01) / SettingsManager.battle_speed_factor()
	# 시트에 이름 있는 행이 있으면 그 동작을 재생하고, 없으면 위치 트윈만으로 간다.
	var anim_name := str(kf.get("anim", ""))
	if anim_name in ["rush", "attack"]:
		var actor_id := "" if spr == player_sprite else _sprite_asset_id(spr)
		if play_anim(spr, "attack", actor_id):
			spawn_afterimage(spr, -1.0 if spr == player_sprite else 1.0)
		elif off.length() > 4.0:
			spawn_afterimage(spr, -1.0 if spr == player_sprite else 1.0)
	var tw := spr.create_tween()
	(
		tw
		. tween_property(spr, "position", (spr.get_meta(&"base_pos") as Vector2) + off, dur)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)


## fx 채널 — 이펙트 시트 재생. 시트가 없으면 기존 파티클 스파크로 폴백한다.
## effect 토큰 = data/effect_specs.json의 id = assets/effects/<id>.png.
func play_fx_kf(kf: Dictionary) -> void:
	var anchor := _actor_sprite(str(kf.get("at_actor", "target")))
	if anchor == null:
		return
	var fx_id := str(kf.get("effect", "hit_spark"))
	if not _play_effect_sheet(fx_id, anchor, kf):
		_spawn_spark(anchor.position)


## 시트 이펙트 재생 시도. 반환 false = 미납품(폴백하라).
func _play_effect_sheet(fx_id: String, anchor: Sprite2D, kf: Dictionary) -> bool:
	var png := EFFECT_DIR + fx_id + ".png"
	if not ResourceLoader.exists(png):
		return false
	var tex: Texture2D = load(png)
	if tex == null:
		return false
	var meta := _effect_meta(fx_id)
	var cell := int(meta.get("cell", 128))
	var anims: Dictionary = meta.get("animations", {})
	var anim: Dictionary = anims.get("play", {})
	var row := int(anim.get("row", 0))
	var frames := maxi(int(anim.get("frames", int(tex.get_width() / maxi(cell, 1)))), 1)
	var fps := maxf(float(anim.get("fps", EFFECT_DEFAULT_FPS)), 1.0)
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(0, row * cell, cell, cell)
	var spr := Sprite2D.new()
	spr.texture = at
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = anchor.position + Vector2(0, float(kf.get("offset_y", -8)))
	spr.scale = Vector2.ONE * float(kf.get("scale", 1.0))
	spr.z_index = 50  # 액터 위
	_root.add_child(spr)
	_fx_playing.append(
		{"spr": spr, "cell": cell, "row": row, "frames": frames, "fps": fps, "clock": 0.0}
	)
	return true


## 이펙트 메타 JSON(설치 시 install_delivery.py가 스펙에서 생성). 없으면 빈 사전.
func _effect_meta(fx_id: String) -> Dictionary:
	if _fx_meta_cache.has(fx_id):
		return _fx_meta_cache[fx_id]
	var meta: Dictionary = {}
	var path := EFFECT_DIR + fx_id + ".json"
	if FileAccess.file_exists(path):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(raw) == TYPE_DICTIONARY:
			meta = raw
	_fx_meta_cache[fx_id] = meta
	return meta


## 재생 중 이펙트의 프레임 진행 — 마지막 프레임이 끝나면 노드를 버린다.
func _advance_effects(delta: float) -> void:
	if _fx_playing.is_empty():
		return
	var speed := SettingsManager.battle_speed_factor()
	var still: Array[Dictionary] = []
	for fx in _fx_playing:
		var spr: Sprite2D = fx["spr"]
		if spr == null or not is_instance_valid(spr):
			continue
		fx["clock"] = float(fx["clock"]) + delta * speed
		var idx := int(float(fx["clock"]) * float(fx["fps"]))
		if idx >= int(fx["frames"]):
			spr.queue_free()
			continue
		var at := spr.texture as AtlasTexture
		if at != null:
			at.region.position.x = idx * float(fx["cell"])
		still.append(fx)
	_fx_playing = still


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
## 피격 표현 — 붉은 플래시 + 넉백 + (시트에 hurt 행이 있으면) 피격 동작.
func hurt_flash(spr: Sprite2D) -> void:
	knockback(spr, 1.0 if spr == player_sprite else -1.0)
	if spr != player_sprite:
		play_anim(spr, "hurt", _sprite_asset_id(spr))
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
	_advance_effects(delta)
	_advance_cuts(delta)
	_advance_anims(delta)


## 애니 메타 보유 스프라이트의 정면 프레임 순환
func _apply_anim_frame(frame: int) -> void:
	for spr: Sprite2D in ([player_sprite] as Array[Sprite2D]) + enemy_sprites:
		if spr == null or not is_instance_valid(spr) or not spr.has_meta(&"anim_cell"):
			continue
		if _is_animating(spr):
			continue  # 시트 애니 재생 중 — idle 토글이 프레임을 빼앗으면 동작이 끊긴다
		var at := spr.texture as AtlasTexture
		if at == null:
			continue
		var cell: Vector2i = spr.get_meta(&"anim_cell")
		at.region.position.x = frame * float(cell.x)


## 스프라이트 → 종 id(적만). 시트 메타 조회에 쓴다.
func _sprite_asset_id(spr: Sprite2D) -> String:
	var idx := enemy_sprites.find(spr)
	return str(_enemy_ids[idx]) if idx >= 0 and idx < _enemy_ids.size() else ""


func _is_animating(spr: Sprite2D) -> bool:
	for a in _anim_playing:
		if a["spr"] == spr:
			return true
	return false


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
