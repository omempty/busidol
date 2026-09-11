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
## 원작 전투 화면의 논리 해상도. 전투 대형 시트의 셀이 곧 이 화면이라,
## 배율을 여기서 한 번만 도출하면 구도가 원작 그대로 옮겨진다.
const ORIGIN_SCREEN_H := 200.0
## 빈사 포즈로 갈리는 HP 비율. 원작은 `EN.Hp <= 15` 절대값이었으나(WARMODE.C:1117)
## 리메이크는 적 HP가 층따라 52~444로 스케일되므로 비율로 옮긴다.
const WOUNDED_RATIO := 0.25
## 원작 전투 이펙트 — 화면 좌표계(RPut_Spr 좌상단)로 얹는다. bake_battle_sheets.py가 굽는다.
const ORIGIN_FX_DIR := "res://assets/effects/"
## 에너지파를 쏘는 종 — 원작 `EnemyAttackAni` WARMODE.C:601 `case 0:1:2:3:6:7`.
## Iron-Vic(4)·HellCop(5)은 근접만 한다. 이 구분이 종을 가르는 원작의 장치라 그대로 옮긴다.
const BOLT_SPECIES := [&"mad_eye", &"vulgar", &"dworm", &"ozzy", &"o_ray"]
## **발사 방향** — 원작 `:613`은 `for(i=-100;i<200;i+=20)` 으로 **오른쪽**으로 쏘고 `:607`
## 섬광도 (0,0) 고정이라, 적이 오른쪽에 있는 리메이크 구도에서는 빔이 시돌이 반대쪽으로
## 나가고 종마다 노즐과 어긋났다(2026-09-11 유저 지적). 플레이어가 언제나 화면 왼쪽이므로
## 왼쪽(-1)으로 쏜다. 굽는 도구가 `shot.dir`로 종마다 싣는다.
const BOLT_TRAVEL := 300.0  ## 화면을 가로지르는 거리 — 원작 루프의 −100→200(300px).
## 볼트가 나아가는 부호 — 플레이어가 화면 왼쪽이므로 −1.
const SHOT_DIR := -1.0
## 원작 `Delay(300)` — 섬광이 뜨고 에너지파가 나가기까지. 그동안 적은 그 자리에 머문다.
const MUZZLE_HOLD := 0.3
const BOLT_FLIGHT := 0.5
## `origin_muzzle`(fire[0]) 프레임에서 섬광(별) 중심 — 좌상단 기준. 적 노즐에 이 점을 맞춘다.
## 에셋 실측값(2026-09-11, 합성 대조)이다. 굽는 도구가 fire.spr을 바꾸면 다시 재야 한다.
const MUZZLE_FLASH := Vector2(105, 62)
## `origin_bolt`(fire[1]) 프레임에서 혜성 머리(밝은 핵) 중심 — 발사점에 이 점을 맞춘다.
const BOLT_HEAD := Vector2(133, 78)

## 원작 주인공 컷 — assets/battle_cuts/origin_player.png (bake_battle_sheets.py가 굽는다).
const ORIGIN_PLAYER_CUT := "res://assets/battle_cuts/origin_player.png"
## 원작 주인공 대치 포즈 오프셋 — WARMODE.C:1129 `RPut_Spr(0,20,&Back[MELoss],0)`.
const ORIGIN_PLAYER_OFFSET := Vector2(0, 20)
## **임팩트 게이트가 아닌 평범한 턴에 원작 컷이 나올 확률.**
##
## 원작 동작은 공격 3종·회피 3종뿐이다. 매 턴 틀면 몇 분 만에 물리고, 아예 안 틀면
## 자산이 다시 사문화된다. 그래서 큰 순간(마지막 일격·필살기·브레이크·약점)에는 반드시,
## 평범한 턴에는 가끔만 나오게 둔다 — 나올 때마다 사건처럼 보이는 빈도가 목표다.
const ORIGIN_CUT_IDLE_CHANCE := 0.15
## 원작 화면 논리 폭. 세로는 ORIGIN_SCREEN_H.
const ORIGIN_SCREEN_W := 320.0
## 대형 컷 상영 중 스테이지 딤 — 원작 전투 화면이 검은 바탕에 격투 컷만 올렸듯
## (WARMODE.C `Page_Clear` + `Set_Clip(0,20,319,180)`, 리메이크 스테이지 위에 풀스크린 컷을 겹치면
## 뒤의 도트 액터·바닥선과 섞여 난잡하다(2026-09-09 유저 지적). 컷(z=50) 바로 아래에
## 검은 막을 깔고 UI(CanvasLayer 20)는 그대로 둔다 — 메뉴·로그는 읽힌 채로 둔다.
## 원작은 불투명 검정이므로 0.86까지 올린다(2026-09-10 유저 지적 "더 어둡게").
## z 순서: 스테이지·액터(0) < 딤(45) < 레터박스(46)·적 공격자(46) < 원작FX(47) < 컷(50) < 플래시(100).
## 딤보다 위여야 할 것이 아래에 있으면 막 뒤에서 어둡게 보인다 — 빔(z=40)이 그랬다.
const CUT_DIM_ALPHA := 0.86
const CUT_DIM_Z := 45
const CUT_LETTER_Z := 46
const ORIGIN_FX_Z := 47
## 원작 돌진 슬라이드 시간 — `_origin_charge` 트윈과 같은 값. 적 턴 순서화(await)가
## 트윈을 기다리는 기준이다(트윈 자체는 콜백이 없어 시간으로 맞춘다).
const ORIGIN_CHARGE_TIME := 0.34
## 필드 도트 종의 러지 왕복 시간 — `enemy_lunge` 비-대형 경로(0.10 + 0.14)와 같은 값.
const DOT_LUNGE_TIME := 0.24
## 주인공 회피 컷 상영 시간(배속 전) — 원작 `MAvoid1~3` 슬라이드 분량을 한 장으로 뭉뚱그린 것.
const ORIGIN_AVOID_HOLD := 0.5

var _last_origin_cut := ""
var _last_avoid_cut := ""
var _origin_player_meta_cache: Dictionary = {}
## 딤 오버레이 참조 수 — 컷·빔이 겹치면 먼저 끝난 쪽이 막을 걷어 버리면 안 된다.
var _dim_rect: ColorRect = null
var _dim_count := 0
## 원작 클립(`Set_Clip(0,20,319,180)`) 자리 — 상하 검은 띠. 딤과 함께 깔고 걷는다.
var _letter_bars: Array[ColorRect] = []

var _idle_clock := 0.0
## 적 전투원 참조 — 빈사·사망 포즈를 매 프레임 스스로 맞추기 위한 것.
## 컨트롤러가 갱신 시점마다 불러 주는 방식은 부르는 곳을 하나 빠뜨리면 조용히 죽는다.
## 이 저장소의 지배적 결함이 그것이라, 여기서는 폴링으로 둔다(적 최대 3체).
var enemy_combatants: Array[Combatant] = []

var target_index := 0  ## 현재 타겟 적 인덱스 — 컨트롤러가 move 재생 전 설정
var is_player_low_hp := false  ## 빈사 상태 여부 — 호흡 연출(헐떡임 가속) 연동

var player_sprite: Sprite2D
var enemy_sprites: Array[Sprite2D] = []

var _root: Node2D
var _shake_power := 0.0
var _root_base := Vector2.ZERO
var _was_shaken := false
var _hitstop_busy := false
## 히트스톱이 낮추기 직전의 Engine.time_scale. 음수면 "지금 낮춰 둔 것이 없다"는 뜻이다.
## 코루틴이 죽어도 _exit_tree가 이 값으로 되돌린다(hitstop 주석 참조).
var _hitstop_prev_scale := -1.0
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
## 재생 중 시트 애니 — {spr, cell, row, frames, fps, clock, loop, frame_flip}. 끝나면 idle로 돌아간다.
## frame_flip: 프레임별 좌우 반전(없으면 빈 배열 — bake_battle_sheets.HURT_FRAME_FLIP 자리).
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
	player_sprite.set_meta(&"base_scale", player_sprite.scale)
	player_sprite.set_meta(&"phase", 0.0)
	_root.add_child(player_sprite)
	_attach_ground_shadow(player_sprite)
	_face_combat_idle(player_sprite)

	for i in enemy_ids.size():
		var es := Sprite2D.new()
		var node_scale := 1.5  # 폴백(64px 사각형) 기본 배율 — 기존 값 유지
		var eid := StringName(enemy_ids[i])
		# 전투 대형 시트가 있으면 그것이 우선 — 원작 구도를 그대로 쓰는 길이다.
		var battle := SpriteSets.battle_sheet(eid)
		var is_battle := not str(battle["sheet"]).is_empty()
		var paths: Dictionary = battle if is_battle else SpriteSets.character_sheet(eid, true)
		var pos := Vector2(600 + i * 100, 180)
		if not str(paths["sheet"]).is_empty():
			var meta: Dictionary = {}
			var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(paths["meta"])))
			if typeof(raw) == TYPE_DICTIONARY:
				meta = raw
			var cell_w := float(meta.get("cell_w", meta.get("cell", 64)))
			var cell_h := float(meta.get("cell_h", meta.get("cell", cell_w)))
			var meta_scale := maxf(float(meta.get("scale", 1.0)), 0.01)
			var tex: Texture2D = load(str(paths["sheet"]))
			if tex != null:
				var eat := AtlasTexture.new()
				eat.atlas = tex
				eat.region = Rect2(0, 0, cell_w, cell_h)  # 행 0 = 대치 포즈 1프레임
				es.texture = eat
				es.set_meta(&"anim_cell", Vector2i(int(cell_w), int(cell_h)))
				if is_battle:
					es.set_meta(&"battle_sheet", true)
					es.set_meta(&"sheet_meta", meta)
					node_scale = _origin_scale()
					# 원작은 언제나 1대1이었고 지금도 실플레이는 그렇다(필드 인카운터 1체,
					# 컷신 강제 전투 2건도 단일 — battle_scene_controller._enemy_act 경고).
					# 2체 이상은 계측 도구에서만 서므로 겹쳐 보이지만 않게 밀어 둔다.
					pos = (
						Vector2(float(i) * 110.0, 0.0)
						+ _origin_point(
							Vector2(
								meta.get("draw_offset", [0, 0])[0],
								meta.get("draw_offset", [0, 0])[1]
							)
						)
					)
				else:
					# 실효 크기 정규화 — 셀×스케일 무관하게 화면상 크기 일관
					node_scale = BATTLE_PLAYER_CELL_PX / (cell_w * meta_scale)
		if es.texture == null:
			var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
			img.fill(Color(randf_range(0.5, 1.0), randf_range(0.2, 0.6), randf_range(0.2, 0.5)))
			es.texture = ImageTexture.create_from_image(img)
		es.position = pos
		es.scale = Vector2.ONE * node_scale
		es.set_meta(&"base_pos", es.position)
		es.set_meta(&"base_scale", es.scale)
		es.set_meta(&"phase", float(i + 1) * 1.35)
		_root.add_child(es)
		_attach_ground_shadow(es)
		enemy_sprites.append(es)
		_face_combat_idle(es)
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
	# 전투 대형 시트는 셀이 곧 원작 화면(320×200)이라 텍스처 하단이 발밑이 아니다 —
	# 여기서 계산하는 half_h가 화면 밖을 가리킨다. 원작 프레임에는 그림자가 이미
	# 그려져 있으므로(e5·e6의 발밑 타원) 얹지 않는 것이 맞다.
	if spr.has_meta(&"battle_sheet"):
		return
	var half_h := spr.texture.get_size().y * spr.scale.y * 0.5
	var blob := Sprite2D.new()
	blob.texture = ShadowBlob.shadow_texture(BATTLE_SHADOW_ALPHA)
	blob.scale = Vector2(2.4, 1.5)
	blob.position = spr.position + Vector2(0, half_h - 4.0)
	blob.z_index = spr.z_index - 1
	_root.add_child(blob)
	_root.move_child(blob, maxi(spr.get_index(), 0))


## 원작 화면(320×200) → 지금 화면 배율. 세로를 기준으로 잡아 정사각 픽셀을 유지한다.
## 가로로 맞추면(960/320=3.0) 원작이 4:3 화면에서 세로로 늘어나 보이던 것까지 흉내내게
## 되는데, 그건 CRT 왜곡이지 그림의 규격이 아니다 — 셰이더가 따로 담당한다.
func _origin_scale() -> float:
	var h := float(ProjectSettings.get_setting("display/window/size/viewport_height", 540))
	return h / ORIGIN_SCREEN_H


## 원작 화면 좌표계의 그리기 오프셋 → 지금 화면의 스프라이트 중심 위치.
## 원작은 320×200 화면 위 (offset) 자리에 프레임 전체를 얹었다(WARMODE.C `RPut_Spr`).
## 셀이 화면 전체이므로 중심은 화면 중앙 + 오프셋×배율이 된다.
func _origin_point(offset: Vector2) -> Vector2:
	var s := _origin_scale()
	var w := float(ProjectSettings.get_setting("display/window/size/viewport_width", 960))
	var h := float(ProjectSettings.get_setting("display/window/size/viewport_height", 540))
	return Vector2(w * 0.5, h * 0.5) + offset * s


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
## `hold`: 1회 재생이 끝나도 마지막 프레임에 멈춰 선다(적 공격 자세). 풀어 주는 쪽은
##   `end_enemy_action()`이다. 적 공격은 「돌진→섬광→빔」이 1.2초 남짓인데 시트의 attack
##   행은 0.33초라, hold가 없으면 빔이 나갈 때 적이 이미 대치 자세로 돌아가 있다
##   (2026-09-11 캡처: 노즐이 옮겨가 빔이 어긋난 원인).
func play_anim(spr: Sprite2D, anim_name: String, asset_id: String = "", hold: bool = false) -> bool:
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
	# 프레임별 좌우 반전(마드아이 hurt col0 — WARMODE.C:278). 없으면 빈 배열이다.
	var frame_flip: Array = []
	if anim.has("frame_flip") and anim["frame_flip"] is Array:
		frame_flip = anim["frame_flip"]
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
				"hold": hold,
				"frame_flip": frame_flip,
			}
		)
	)
	return true


## 적 인덱스로 부르는 편의 함수 — 컨트롤러·적 턴이 쓴다.
## 공격·특수 자세는 시트의 `shot.flip`에 따라 좌우 반전한다 — 원작 공격 프레임이
## 오른쪽을 향해 저장돼 있어(플레이어는 왼쪽) 반전해야 적이 플레이어를 마주 본다.
func play_enemy_anim(index: int, anim_name: String) -> bool:
	if index < 0 or index >= enemy_sprites.size():
		return false
	var spr := enemy_sprites[index]
	var asset_id := str(_enemy_ids[index]) if index < _enemy_ids.size() else ""
	# 공격·특수는 마지막 프레임에 멈춰 선다 — 빔이 나갈 때까지 자세를 유지해야
	# 노즐이 안 움직인다(`end_enemy_action`이 푼다).
	var ok := play_anim(spr, anim_name, asset_id, anim_name in ["attack", "special"])
	if ok and spr != null and is_instance_valid(spr):
		var flip := false
		if anim_name in ["attack", "special"]:
			flip = bool(
				(_sheet_meta(spr, asset_id).get("shot", {}) as Dictionary).get("flip", false)
			)
		spr.flip_h = flip
	return ok


## 적 행동이 끝나면 공격 자세를 풀고 대치 자세로 돌린다 — `play_enemy_anim`의 `hold` 짝.
## 적 턴(`regular_attack`·`try_special`·`unleash_heavy`) 마지막에서 부른다.
## 대치 행(`idle_row`)도 존중한다 — 빈사면 빈사 포즈로 돌아간다.
func end_enemy_action(index: int) -> void:
	if index < 0 or index >= enemy_sprites.size():
		return
	var spr := enemy_sprites[index]
	if spr == null or not is_instance_valid(spr):
		return
	_stop_anim(spr)
	spr.flip_h = false
	var at := spr.texture as AtlasTexture
	if at == null or not spr.has_meta(&"anim_cell"):
		return
	var cell: Vector2i = spr.get_meta(&"anim_cell")
	var row := int(spr.get_meta(&"idle_row", 0))
	at.region.position = Vector2(0, float(row * cell.y))


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
	# 대형 시트는 build_sprites에서 메타를 통째로 들려 보냈다 — 경로로 다시 찾으면
	# `character_sheet`(필드 도트)로 새어 나가 attack/wounded 행을 못 찾는다.
	if spr.has_meta(&"sheet_meta"):
		meta = spr.get_meta(&"sheet_meta")
		_sheet_meta_cache[key] = meta
		return meta
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
			elif bool(a.get("hold", false)):
				idx = frames - 1  # 마지막 프레임 고정 — `end_enemy_action`이 푼다
			else:
				at.region.position = Vector2.ZERO  # idle 행으로 복귀
				continue
		_apply_anim_frame_flip(a, spr, idx)
		at.region.position = Vector2(float(idx * cell.x), float(int(a["row"]) * cell.y))
		still.append(a)
	_anim_playing = still


## 프레임별 좌우 반전 — 한 행 안의 프레임이 서로 다른 방향을 볼 때(마드아이 hurt [4,5]).
## 공격·특수는 `play_enemy_anim`이 `shot.flip`으로 한 번에 뒤집고, hurt는 그 경로를 안 타서
## 여기서만 뒤집으면 된다. 종료 시 복원은 `end_enemy_action` 몫이다.
func _apply_anim_frame_flip(a: Dictionary, spr: Sprite2D, idx: int) -> void:
	if not a.has("frame_flip") or not (a["frame_flip"] is Array):
		return
	var flips: Array = a["frame_flip"]
	if flips.is_empty():
		return
	spr.flip_h = bool(flips[clampi(idx, 0, flips.size() - 1)])


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
		# 잔상은 빛의 궤적이다 — 가산으로 겹칠수록 밝아진다.
		ghost.material = BattleFxMaterials.additive()
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
	# 시트에 이름 있는 행이 있으면 그 동작을 재생하고, 없으면 타겟 방향 보행 행으로 전환
	var anim_name := str(kf.get("anim", ""))
	if anim_name in ["rush", "attack"]:
		var actor_id := "" if spr == player_sprite else _sprite_asset_id(spr)
		if play_anim(spr, "attack", actor_id):
			spawn_afterimage(spr, -1.0 if spr == player_sprite else 1.0)
		else:
			# attack 애니가 없으면 공격 대상 방향으로 보행 행을 세워 응시
			var dir_anim := "walk_right" if spr == player_sprite else "walk_left"
			if not play_anim(spr, dir_anim, actor_id):
				if spr != player_sprite:
					spr.flip_h = true
			if off.length() > 4.0:
				spawn_afterimage(spr, -1.0 if spr == player_sprite else 1.0)
	elif anim_name == "idle" or (off == Vector2.ZERO and not anim_name in ["rush", "attack"]):
		_face_combat_idle(spr)
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
		var target_pos := anchor.position + Vector2(0, float(kf.get("offset_y", -8)))
		_spawn_procedural_fx(fx_id, target_pos, kf)


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


## 적 돌진 — 때리는 쪽이 앞으로 나갔다 제자리로. 아군 rush의 반대 방향.
## 위치 트윈이라 시트 행이 없어도 돈다(행이 있으면 attack 재생은 호출부 몫).
func enemy_lunge(index: int) -> void:
	if index < 0 or index >= enemy_sprites.size():
		return
	var spr := enemy_sprites[index]
	if spr == null or not is_instance_valid(spr) or not spr.has_meta(&"base_pos"):
		return
	var base: Vector2 = spr.get_meta(&"base_pos")
	var speed := maxf(SettingsManager.battle_speed_factor(), 0.1)
	spawn_afterimage(spr, 1.0)
	if spr.has_meta(&"battle_sheet"):
		# 원작은 돌진이 끝난 자리(x=−50)에 **머문 채** 섬광을 뿜고 `Delay(300)` 뒤 에너지파를
		# 쏜다(WARMODE.C:604-625). 먼저 돌아와 버리면 빔이 허공에서 나오는 것처럼 보인다.
		var eid := StringName(_enemy_ids[index]) if index < _enemy_ids.size() else &""
		var hold := MUZZLE_HOLD + (BOLT_FLIGHT if BOLT_SPECIES.has(eid) else 0.0)
		_origin_charge(spr, speed, hold)
		return
	var tw := spr.create_tween()
	(
		tw
		. tween_property(spr, "position", base + Vector2(-26, 0), 0.1 / speed)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(spr, "position", base, 0.14 / speed).set_trans(Tween.TRANS_BACK)


## 원작 돌진 — 적이 화면을 가로질러 덮쳐 온다.
##
## `WARMODE.C:590` `for(i=100;i>=-50;i-=20)` — 공격 프레임을 원작 화면 x=+100에서
## -50까지 20씩 밀며 8단계로 그렸다. 오프셋 y는 0이라 대치 자세의 (30,10)보다 살짝
## 위로 뜬다. 그 폭(원작 150px = 지금 화면 405px)이 원작 전투의 압박감 자체다 —
## 필드 도트 시절의 26px 러지로는 나오지 않는다.
## 끝나면 대치 자세로 되돌린다(base_pos는 build_sprites가 심어 둔 그 자리).
func _origin_charge(spr: Sprite2D, speed: float, hold: float = 0.0) -> void:
	var meta: Dictionary = spr.get_meta(&"sheet_meta", {})
	var slide: Array = meta.get("attack_slide", [100, -50])
	var base: Vector2 = spr.get_meta(&"base_pos")
	spr.position = _origin_point(Vector2(float(slide[0]), 0.0))
	var tw := spr.create_tween()
	(
		tw
		. tween_property(
			spr, "position", _origin_point(Vector2(float(slide[1]), 0.0)), 0.34 / speed
		)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	if hold > 0.0:
		tw.tween_interval(hold / speed)
	tw.tween_property(spr, "position", base, 0.2 / speed).set_trans(Tween.TRANS_QUAD)


## 원작 좌표계 낱장 이펙트 하나를 띄운다. `RPut_Spr(x, y, spr)`와 같은 **좌상단 기준**이다.
## 반환: 만든 노드(에셋이 없으면 null — 호출부는 조용히 넘어간다).
func _origin_fx(fx_id: String, at: Vector2) -> Sprite2D:
	var png := ORIGIN_FX_DIR + fx_id + ".png"
	if not ResourceLoader.exists(png):
		return null
	var tex: Texture2D = load(png)
	if tex == null:
		return null
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	var sc := _origin_scale()
	spr.scale = Vector2.ONE * sc
	var w := float(ProjectSettings.get_setting("display/window/size/viewport_width", 960))
	spr.position = Vector2((w - float(ORIGIN_SCREEN_H) * 1.6 * sc) * 0.5, 0.0) + at * sc
	spr.z_index = ORIGIN_FX_Z  # 딤(45) 위 — 막 뒤에서 어둡게 보이던 빔의 처방
	# 섬광·빔·스파크는 발광이다 — 딤 위에서도 타오르게 가산으로 얹는다.
	spr.material = BattleFxMaterials.additive()
	_root.add_child(spr)
	return spr


## 대형 컷 상영 중 스테이지를 덮는 검은 막. 참조 수로 겹침을 견딘다 —
## 먼저 끝난 쪽이 막을 걷어 가면 뒤의 컷이 민낯으로 남는다.
func _cut_dim_show() -> void:
	if _root == null:
		return
	_dim_count += 1
	if _dim_rect != null and is_instance_valid(_dim_rect):
		return
	var rect := ColorRect.new()
	rect.name = "CutDim"
	rect.color = Color(0, 0, 0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.position = Vector2.ZERO
	rect.size = _root.get_viewport_rect().size
	rect.z_index = CUT_DIM_Z
	_root.add_child(rect)
	_dim_rect = rect
	_show_letterbox()
	var tw := rect.create_tween()
	tw.tween_property(rect, "color:a", CUT_DIM_ALPHA, 0.08)


func _cut_dim_hide() -> void:
	if _dim_count > 0:
		_dim_count -= 1
	if _dim_count > 0:
		return
	if _dim_rect == null or not is_instance_valid(_dim_rect):
		_dim_rect = null
		return
	var rect := _dim_rect
	_dim_rect = null
	_hide_letterbox()
	var tw := rect.create_tween()
	tw.tween_property(rect, "color:a", 0.0, 0.15)
	tw.tween_callback(rect.queue_free)


## 원작 클립(`Set_Clip(0,20,319,180)`) — 컷 상영 중에만 서는 상하 검은 띠.
## 딤의 참조 수 안에 묶는다(따로 세면 딤과 띠가 따로 걷힌다).
func _show_letterbox() -> void:
	if _root == null:
		return
	for b in _letter_bars:
		if b != null and is_instance_valid(b):
			return
	_letter_bars.clear()
	var sc := _origin_scale()
	var w := float(ProjectSettings.get_setting("display/window/size/viewport_width", 960))
	var h := float(ProjectSettings.get_setting("display/window/size/viewport_height", 540))
	var bar := 20.0 * sc
	for y in [0.0, h - bar]:
		var rect := ColorRect.new()
		rect.name = "CutLetter"
		rect.color = Color.BLACK
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.position = Vector2(0, y)
		rect.size = Vector2(w, bar)
		rect.z_index = CUT_LETTER_Z
		_root.add_child(rect)
		_letter_bars.append(rect)


func _hide_letterbox() -> void:
	for b in _letter_bars:
		if b != null and is_instance_valid(b):
			b.queue_free()
	_letter_bars.clear()


## 연출 박자 대기 — 배속을 나눈 실초. 적 턴 순서화(await)의 자다.
func _cut_beat(dur_unscaled: float) -> void:
	var speed := maxf(SettingsManager.battle_speed_factor(), 0.1)
	await get_tree().create_timer(maxf(dur_unscaled, 0.01) / speed).timeout


## **원작 단컷 — 풀 동작이 아니라 한 자세를 잠깐 끊어 보여준다.**
##
## 대형 컷(돌진·교대 TECH)은 길어서 남발하면 물린다. 방어는 매 턴 쓸 수 있고
## 승패는 한 번뿐이라 풀컷이 과하다 — 그 자리는 한 프레임 + 딤 + 짧은 홀드로 메운다.
## 쿨다운은 호출부(컨트롤러)가 대형 컷과 같은 자(`_actions_since_cut`)로 본다.
## 반환: 실제로 떴는가.
func play_origin_short_cut_async(row_name: String, col: int, hold: float) -> bool:
	if SettingsManager.effect_speed == SettingsManager.EffectSpeed.SKIP:
		return false
	if not ResourceLoader.exists(ORIGIN_PLAYER_CUT):
		return false
	var anims: Dictionary = _origin_player_meta().get("animations", {})
	if not anims.has(row_name):
		return false
	var frames := maxi(int((anims[row_name] as Dictionary).get("frames", 1)), 1)
	var spr := _make_origin_cut_sprite(
		int((anims[row_name] as Dictionary).get("row", 0)), clampi(col, 0, frames - 1)
	)
	if spr == null:
		return false
	_cut_dim_show()
	_hide_cut_actor()
	_place_origin_topleft(spr, ORIGIN_PLAYER_OFFSET)
	var speed := maxf(SettingsManager.battle_speed_factor(), 0.1)
	var tw := spr.create_tween()
	tw.tween_interval(maxf(hold, 0.05) / speed)
	tw.tween_property(spr, "modulate:a", 0.0, 0.12 / speed)
	tw.tween_callback(spr.queue_free)
	await _cut_beat(maxf(hold, 0.05) + 0.12)
	_show_cut_actor()
	_cut_dim_hide()
	return true


## 적 돌진 박자(배속 전 실초) — 돌진 슬라이드만의 길이.
## 적 턴은 이만큼 기다렸다가 빔·피해를 이어 간다. 빔 상영 시간은
## `origin_attack_fx_async`가 안에서 기다리므로 여기 두면 두 번 잰다.
## 필드 도트 종은 `enemy_lunge` 러지 왕복과 같은 길이.
##
## **배속을 여기서 나누지 않는다** — 호출부가 `_cut_beat()`로 감싸는데 그쪽도 배속을
## 나눈다. 여기서 한 번 더 나누면 배속 2배에서 대기가 트윈의 절반이 되어, 적이
## 돌진하는 중간에 섬광·볼트가 터진다(2026-09-11 캡처에서 적이 86% 지점에서 발사).
func enemy_attack_beat(index: int) -> float:
	if index < 0 or index >= enemy_sprites.size():
		return DOT_LUNGE_TIME
	var spr := enemy_sprites[index]
	if spr != null and is_instance_valid(spr) and spr.has_meta(&"battle_sheet"):
		return ORIGIN_CHARGE_TIME
	return DOT_LUNGE_TIME


## **원작 공격의 나머지 절반** — 돌진이 끝난 뒤 섬광이 터지고 에너지파가 화면을 가로지른다.
##
## `WARMODE.C:599-625`. 돌진(`_origin_charge`)만 옮기고 여기서 멈춰 있었다 —
## 유저 지적("적 무기/에너지파등 발사 등이 있는걸로 기억됨")이 가리킨 자리다.
## 발사 종이 아니면(Iron-Vic·HellCop) 섬광까지만 하고 끝난다 — 원작이 그렇다.
##
## 순서화 버전(`_async`)이 정본이다 — 구 버전은 캡처 도구(`battle_anim_shots`) 호환용으로만 남긴다.
func origin_attack_fx(impact: bool = false) -> void:
	_origin_attack_fx_fire(impact)


## 섬광·빔이 뜰 것인가 — 게이트 판정만. 그리는 쪽과 기다리는 쪽이 같은 답을 봐야 한다.
func _origin_fx_will_show(impact: bool) -> bool:
	if SettingsManager.effect_speed == SettingsManager.EffectSpeed.SKIP:
		return false
	# 돌진은 적의 공격 동작 자체라 늘 나가지만(그게 없으면 적이 가만히 있는다),
	# **섬광과 에너지파는 임팩트 순간에만** 터뜨린다 — 매 턴이면 화면이 시끄럽고 물린다.
	if not impact and EnemyManager.rng.randf() >= ORIGIN_CUT_IDLE_CHANCE:
		return false
	# 대형 시트를 쓰는 적일 때만 — 필드 도트 종은 기존 리메이크 연출로 간다(하이브리드).
	var idx := target_index
	if idx < 0 or idx >= enemy_sprites.size() or not enemy_sprites[idx].has_meta(&"battle_sheet"):
		return false
	return true


## 빔 상영 시간(배속 전) — 발사 종이면 섬광 대기 + 비행, 아니면 섬광 대기만.
func _origin_fx_hold() -> float:
	var idx := target_index
	var enemy_id := StringName(_enemy_ids[idx]) if idx >= 0 and idx < _enemy_ids.size() else &""
	return MUZZLE_HOLD + (BOLT_FLIGHT if BOLT_SPECIES.has(enemy_id) else 0.0)


func _origin_attack_fx_fire(impact: bool) -> bool:
	if not _origin_fx_will_show(impact):
		return false
	var idx := target_index
	var enemy_id := StringName(_enemy_ids[idx]) if idx < _enemy_ids.size() else &""
	var speed := maxf(SettingsManager.battle_speed_factor(), 0.1)
	# 발사점 — 적의 노즐(시트 `shot.muzzle`). 반전 자세면 노즐도 뒤집혀 있다.
	var anchor := _enemy_muzzle_anchor()
	# 섬광은 원작 fire[0]을 **좌우 반전**해 왼쪽(플레이어)을 향하게 하고, 섬광 중심을
	# 노즐에 맞춘다. 원작은 (0,0) 고정이었지만 그러면 종마다 노즐과 어긋난다(2026-09-11).
	var muzzle := _origin_fx(
		"origin_muzzle", anchor - Vector2(ORIGIN_SCREEN_W - MUZZLE_FLASH.x, MUZZLE_FLASH.y)
	)
	if muzzle != null:
		muzzle.flip_h = true
		var mt := muzzle.create_tween()
		mt.tween_interval(MUZZLE_HOLD / speed)
		mt.tween_property(muzzle, "modulate:a", 0.0, 0.12 / speed)
		mt.tween_callback(muzzle.queue_free)
	if not BOLT_SPECIES.has(enemy_id):
		return true
	# Iron-Vic만 전용 투사체를 대각선으로 끌고 온다(`:280` `RPut_Spr(i,i,&Eff[0],0)`) —
	# 다만 그 종은 위에서 이미 걸러졌으므로 여기 오는 것은 공용 에너지파뿐이다.
	# 혜성은 섬광과 같은 쪽(왼쪽·플레이어)을 향한다 — 원작 fire[1]은 오른쪽을 향해
	# 저장돼 있어 뒤집지 않으면 머리가 오른쪽인 채 왼쪽으로 날아 거꾸로 간다.
	var bolt := _origin_fx(
		"origin_bolt", anchor - Vector2(ORIGIN_SCREEN_W - BOLT_HEAD.x, BOLT_HEAD.y)
	)
	if bolt == null:
		return true
	bolt.flip_h = true
	# **섬광 대기 동안 볼트를 미리 보이면 안 된다.** 원작은 `:607`에서 fire[0]만 그리고
	# `:613` 루프에 들어가서야 fire[1]을 그린다. 리메이크는 볼트를 화면 왼쪽 끝에
	# 만들어 두고 0.3초를 기다려, 혜성이 미리 떠 있었다(2026-09-11 실측).
	bolt.visible = false
	var sc := _origin_scale()
	var bt := bolt.create_tween()
	bt.tween_interval(MUZZLE_HOLD / speed)
	bt.tween_callback(
		func() -> void:
			if is_instance_valid(bolt):
				bolt.visible = true
	)
	(
		bt
		. tween_property(
			bolt, "position:x", bolt.position.x + BOLT_TRAVEL * SHOT_DIR * sc, BOLT_FLIGHT / speed
		)
		. set_trans(Tween.TRANS_LINEAR)
	)
	bt.tween_callback(bolt.queue_free)
	return true


## 적의 발사점을 원작 좌표계로 돌려준다 — 시트 `shot.muzzle`을 **돌진 종점**에 얹는다.
## `flip`이면 노즐도 좌우 반전된 자리(`320 - x`)로 옮긴다. `shot`이 없으면 적 몸 중심.
##
## 종점(`attack_slide[1]`)에 고정하는 이유: 섬광은 돌진이 다 끝난 자리에서 뜨는데
## (`_origin_charge`가 그 자리에서 hold한다) 타이머가 몇 프레임 일찍 떨어져도 섬광이
## 적을 따라 미끄러지지 않게 하려는 것이다. 살아 있는 `position`을 쓰면 섬광이 뜬 뒤
## 적이 마지막 몇 px를 더 가면서 노즐과 어긋난다(2026-09-11 실측).
func _enemy_muzzle_anchor() -> Vector2:
	var spr := _attacker_sprite()
	if spr == null or not is_instance_valid(spr):
		return Vector2.ZERO
	var meta := _sheet_meta(spr, _sprite_asset_id(spr))
	var sc := maxf(_origin_scale(), 0.01)
	var w := float(ProjectSettings.get_setting("display/window/size/viewport_width", 960))
	var h := float(ProjectSettings.get_setting("display/window/size/viewport_height", 540))
	var sprite_topleft := (spr.position - Vector2(w * 0.5, h * 0.5)) / sc
	var shot: Dictionary = meta.get("shot", {})
	var mz: Array = shot.get("muzzle", [])
	if mz.size() < 2:
		return sprite_topleft + Vector2(ORIGIN_SCREEN_W, ORIGIN_SCREEN_H) * 0.5
	var local := Vector2(float(mz[0]), float(mz[1]))
	if bool(shot.get("flip", false)):
		local.x = ORIGIN_SCREEN_W - local.x
	var slide: Array = meta.get("attack_slide", [])
	var end_x := float(slide[1]) if slide.size() >= 2 else sprite_topleft.x
	return Vector2(end_x, 0.0) + local


## 순서화 버전 — 빔이 화면을 가로지를 동안 딤을 깔고 끝까지 기다렸다가 걷는다.
## 적 턴은 이 await 뒤에 피해를 깎는다(원작 `EnemyAttackAni` → `MyAvoid` 순서).
## 원작(`:599-625`) 자리 재현:
##   돌진 끝(-50)에 머문 적 + 섬광 → Delay(300) → Page_Clear(적 퇴장) →
##   볼트만 검은 화면을 가로지른다 → Delay(200) → MyAvoid.
## 그래서 섬광 동안 공격자를 딤 위(46)로 올리고, 볼트 비행 동안은 숨긴다.
## 발사 종이 아니면 섬광까지만(숨김 없음 — 원작이 그렇다).
## **2026-09-11 보완**: 섬광·볼트를 적 노즐에 맞추고(종별 `shot.muzzle`), 원작의 오른쪽
## 발사를 플레이어 쪽(왼쪽)으로 뒤집었다. 볼트는 섬광 동안 숨긴다(원작 `:613` 순서).
func origin_attack_fx_async(impact: bool) -> bool:
	if not _origin_fx_will_show(impact):
		return false
	_cut_dim_show()
	var foe := _attacker_sprite()
	var bolts := _attacker_bolts()
	if foe != null:
		foe.z_index = CUT_LETTER_Z
	_origin_attack_fx_fire(impact)
	await _cut_beat(MUZZLE_HOLD)
	if foe != null and is_instance_valid(foe) and bolts:
		foe.visible = false
	await _cut_beat(maxf(_origin_fx_hold() - MUZZLE_HOLD, 0.01))
	if foe != null and is_instance_valid(foe):
		foe.visible = true
		foe.z_index = 0
	_cut_dim_hide()
	return true


## 이번에 때리는 적 스프라이트(없으면 null).
func _attacker_sprite() -> Sprite2D:
	var idx := target_index
	if idx < 0 or idx >= enemy_sprites.size():
		return null
	return enemy_sprites[idx]


## 이번 공격자가 볼트를 쏘는 종인가(원작 `:601` 발사 종 + 에셋 실재).
func _attacker_bolts() -> bool:
	var idx := target_index
	var enemy_id := StringName(_enemy_ids[idx]) if idx >= 0 and idx < _enemy_ids.size() else &""
	if not BOLT_SPECIES.has(enemy_id):
		return false
	return ResourceLoader.exists(ORIGIN_FX_DIR + "origin_bolt.png")


## **주인공 원작 대형 컷 — 임팩트 순간에만.**
##
## 원작 주인공은 320×200 전체 화면이었다(`MyAttackAni` :370). 그런데 동작이 공격 3종·
## 회피 3종뿐이라 매 턴 틀면 금방 물린다 — 그래서 상시 대형인 적과 달리 **끊고 들어오는
## 컷**으로 둔다. 평소 주인공은 96px 도트 그대로다(하이브리드, 유저 판단 2026-09-07).
##
## 원작이 고르는 방식과 확률을 그대로 옮긴다(`:390` `random(6)`):
##   5 → `rise`(a5, 승룡권 패러디 — y 200→0) · 0~3 → `swing`(a1 4종 — x −50→150)
##   4 → `flurry`(a3, 백열 장수 패러디 — 두 프레임을 20회 교대하며 점점 빨라진다)
## 다만 **직전에 쓴 것은 다시 안 고른다** — 셋뿐이라 연속으로 같은 게 나오면 티가 크다.
##
## 순서: 컷(딤 상영) → 러지·타격 → 적 피격. 원작 `MyAttackAni` → `EnemyAvoid`와 같은
## 자리다. 데미지 숫자가 먼저 뜨고 컷이 뒤늦게 덮던 순서가 여기 고쳐진다(2026-09-09).
## 반환: 실제로 컷이 떴는가(에셋이 없으면 false — 호출부는 기존 연출로 간다).
func play_origin_player_cut() -> bool:
	var pick := _pick_origin_player_cut()
	if pick.is_empty():
		return false
	_cut_dim_show()
	return _play_origin_cut_anim(pick, true)


## 순서화 버전 — 컷 상영이 끝날 때까지 기다렸다가 딤을 걷는다.
## 플레이어 턴은 이 await 뒤에 안무(`_play_move`)를 튼다.
## prefer_big: 쓰러뜨린 일격이면 큰 동작(rise/flurry) 중에서만 고른다 —
## 평범한 스윙이 킬샷에 걸리면 마무리가 싱겁다.
func play_origin_player_cut_async(prefer_big: bool = false) -> bool:
	var pick := _pick_origin_player_cut(prefer_big)
	if pick.is_empty():
		return false
	_cut_dim_show()
	if not _play_origin_cut_anim(pick, false):
		_cut_dim_hide()
		return false
	await _cut_beat(float(pick["dur"]))
	_show_cut_actor()
	_cut_dim_hide()
	return true


## 컷 고르기 — 없으면 {} (SKIP·미납품). 상영 시간(dur, 배속 전)까지 딸려 온다.
func _pick_origin_player_cut(prefer_big: bool = false) -> Dictionary:
	if SettingsManager.effect_speed == SettingsManager.EffectSpeed.SKIP:
		return {}
	if not ResourceLoader.exists(ORIGIN_PLAYER_CUT):
		return {}
	var meta := _origin_player_meta()
	var anims: Dictionary = meta.get("animations", {})
	var picks: Array[String] = []
	if prefer_big:
		picks.append("rise:0")
		picks.append("flurry:0")
	else:
		for i in 4:
			picks.append("swing:%d" % i)  # 원작 4/6 확률 — select 0~3
		picks.append("flurry:0")
		picks.append("rise:0")
	var pick := str(picks[EnemyManager.rng.randi_range(0, picks.size() - 1)])
	if pick == _last_origin_cut and picks.size() > 1:
		pick = str(picks[(picks.find(pick) + 1) % picks.size()])
	var parts := pick.split(":")
	var row_name := parts[0]
	if not anims.has(row_name):
		return {}
	_last_origin_cut = pick
	# flurry 간격 합(0.2×5 + 0.1×3 + 0.03×12) + 걷힘 0.14 — `_origin_cut_flurry`와 같은 값.
	# 원작(`:347`)은 Delay 200×5 + 100×3 + 0×12 ≈ 2.3초라 현대 박자로는 길어 간격만 축소하고
	# 20회 교대 구조는 유지한다.
	var dur := 1.80 if row_name == "flurry" else (0.54 if row_name == "rise" else 0.52)
	return {
		"row_name": row_name,
		"row": int((anims[row_name] as Dictionary).get("row", 0)),
		"col": int(parts[1]),
		"dur": dur,
	}


func _play_origin_cut_anim(pick: Dictionary, with_dim_hide: bool) -> bool:
	var row_name := str(pick["row_name"])
	# 공격 3종은 원작 `flag=1`(좌우 반전)로 그린다 — `_make_origin_cut_sprite` 주석 참조.
	var spr := _make_origin_cut_sprite(int(pick["row"]), int(pick["col"]), true)
	if spr == null:
		if with_dim_hide:
			_cut_dim_hide()
		return false
	# 원작은 컷 상영 전에 화면을 지운다(`Page_Clear`) — 작은 도트가 딤 뒤에 남으면
	# 화면 끝에 희미한 잔상이 선다(2026-09-10 캡처 실측). 상영 중 숨기고 끝에서 되돌린다.
	_hide_cut_actor()
	var speed := maxf(SettingsManager.battle_speed_factor(), 0.1)
	match row_name:
		"rise":
			# `:301` `for(i=200;i>=0;i-=25)` — 아래에서 솟아오른다.
			_origin_cut_move(spr, Vector2(0, 200), Vector2(0, 0), 0.42 / speed, with_dim_hide)
		"flurry":
			# `:347` 두 프레임 20회 교대 + 점점 빨라짐. 위치는 고정.
			_origin_cut_flurry(spr, int(pick["row"]), speed, with_dim_hide)
		_:  # `:322` `for(i=-50;i<=150;i+=30)` — 왼쪽에서 오른쪽으로 파고든다.
			# 실제 마지막 스텝은 130이다(-50+30×6. 150은 루프 조건일 뿐 도달하지 않는다).
			# 반전한 a1은 몸통이 프레임 왼쪽으로 가므로 130까지 밀어도 몸통이 화면에 남는다 —
			# 2026-09-10에 150→130으로 줄였던 것은 반전 누락을 가린 임시처방이었다(09-11 정정).
			_origin_cut_move(spr, Vector2(-50, 0), Vector2(130, 0), 0.40 / speed, with_dim_hide)
	origin_hit_spark()
	return true


## **주인공 피격 원작 컷 — 적 턴의 `MyAvoid()` 자리.**
##
## 원작은 적 공격이 끝나면 주인공 회피 풀스크린(`d1~d3`)이 붙었다(`:499 MyAvoid`).
## 리메이크는 `player_hurt.png` 미납품이라 그 자리가 플래시·흔들림뿐이었다(§8.2).
## 원작 회피 3종 분포(`:517` `random(6)` — 0~2 avoid_a · 3 avoid_b · 4·5 avoid_c)를
## 그대로 옮긴다. 적 빔 다음·피해 숫자 전에 상영한다. 강제면 분포 무시하고 avoid_a.
## 행별 구조도 원작을 따른다(2026-09-10 정교화):
##   avoid_a(`MAvoid1`) — 굴린 프레임(sprnum) 한 장을 x 0→40으로 민다 + 스파크.
##   avoid_b(`MAvoid2`) — 0→50으로 민 뒤 마무리 포즈(2번 칸)를 0.4초 홀드(원작 500ms).
##   avoid_c(`MAvoid3`) — 0·1번 칸을 0.3초씩 홀드(원작 1초씩. 현대 박자로 축소)한 뒤
##     2번 칸을 x −20→60으로 밀며 스파크(원작은 2·3번 이중 그리기).
## 홀드용 정지 컷은 from==to 이동으로 멈춰 세운다(끝의 0.12초 걷힘은 공통).
func play_origin_avoid_cut_async(forced: bool = false) -> bool:
	if SettingsManager.effect_speed == SettingsManager.EffectSpeed.SKIP:
		return false
	if not ResourceLoader.exists(ORIGIN_PLAYER_CUT):
		return false
	var meta := _origin_player_meta()
	var anims: Dictionary = meta.get("animations", {})
	var row_name := "avoid_a"
	var col := 0
	if not forced:
		var roll := EnemyManager.rng.randi_range(0, 5)
		row_name = "avoid_a" if roll <= 2 else ("avoid_b" if roll == 3 else "avoid_c")
		col = roll if row_name == "avoid_a" else 0  # `MAvoid1(sprnum)` — 굴린 칸을 든다
	if row_name == _last_avoid_cut:
		row_name = "avoid_b" if row_name != "avoid_b" else "avoid_a"
		col = 0
	if not anims.has(row_name):
		return false
	_last_avoid_cut = row_name
	var row := int((anims[row_name] as Dictionary).get("row", 0))
	_cut_dim_show()
	_hide_cut_actor()
	var speed := maxf(SettingsManager.battle_speed_factor(), 0.1)
	match row_name:
		"avoid_b":
			var slide := _make_origin_cut_sprite(row, 0)
			if slide == null:
				_show_cut_actor()
				_cut_dim_hide()
				return false
			_origin_cut_move(slide, Vector2(0, 0), Vector2(50, 0), ORIGIN_AVOID_HOLD / speed, false)
			origin_hit_spark(Vector2(10, 60))
			await _cut_beat(ORIGIN_AVOID_HOLD + 0.12)
			var fin := _make_origin_cut_sprite(row, 1)
			if fin != null:
				_origin_cut_move(fin, Vector2(50, 0), Vector2(50, 0), 0.4 / speed, false)
				await _cut_beat(0.4 + 0.12)
		"avoid_c":
			for h in [0, 1]:
				var hold := _make_origin_cut_sprite(row, h)
				if hold != null:
					_origin_cut_move(hold, Vector2.ZERO, Vector2.ZERO, 0.3 / speed, false)
					await _cut_beat(0.3 + 0.12)
			var rush := _make_origin_cut_sprite(row, 2)
			if rush == null:
				_show_cut_actor()
				_cut_dim_hide()
				return false
			_origin_cut_move(
				rush, Vector2(-20, 0), Vector2(60, 0), ORIGIN_AVOID_HOLD / speed, false
			)
			origin_hit_spark(Vector2(10, 60))
			await _cut_beat(ORIGIN_AVOID_HOLD + 0.12)
		_:
			var spr := _make_origin_cut_sprite(row, col)
			if spr == null:
				_show_cut_actor()
				_cut_dim_hide()
				return false
			_origin_cut_move(spr, Vector2(0, 0), Vector2(40, 0), ORIGIN_AVOID_HOLD / speed, false)
			origin_hit_spark(Vector2(10, 60))
			await _cut_beat(ORIGIN_AVOID_HOLD + 0.12)
	_show_cut_actor()
	_cut_dim_hide()
	return true


## 원작 컷 상영 중 작은 주인공 도트 숨김/복원 — 원작은 `Page_Clear`라 도트가 없다.
## 숨긴 채로 두면 전투 복귀 때 주인공이 사라진 것처럼 보인다. 호출부(컷 종료)가 되돌린다.
func _hide_cut_actor() -> void:
	if player_sprite != null and is_instance_valid(player_sprite):
		player_sprite.visible = false


func _show_cut_actor() -> void:
	if player_sprite != null and is_instance_valid(player_sprite):
		player_sprite.visible = true


## 컷 스프라이트 한 장 — 시트의 (행, 칸)을 잘라 원작 화면 좌표계에 얹는다.
##
## `flip`: **공격 컷은 반드시 좌우 반전한다.** 원작 엔진의 `RPut_Spr(x,y,spr,flag)` 4번째
## 인자가 좌우 반전 플래그이고, 주인공 공격 3종(`AttackAni1/2/3` — a5·a1·a3)만 `flag=1`로
## 그린다(`WARMODE.C:306·327·344·353`). 회피·적·배경은 전부 `flag=0`이다. 근거는 두 가지다:
##   · a1~a5는 파일에 **왼쪽을 향해** 저장돼 있는데 시돌이는 화면 왼쪽에서 적(오른쪽)을 본다.
##     반전하지 않으면 주먹이 적 반대쪽으로 나가고, x=130까지 밀 때 몸통이 화면 밖으로 나간다
##     (2026-09-10·09-11 유저 지적 "몸통이 안 보이고 팔만 나온다").
##   · `EnemyAvoid`가 마드아이(e1)의 4번 프레임만 `flag=1`로 그린다(`:278`) — e1의 4·5번
##     프레임이 서로 반대를 향해 저장돼 있어 한 장을 뒤집어야 같은 방향이 된다. 이게
##     `flag`가 좌우 반전임을 확정한다.
## 좌상단 앵커(`centered=false`)는 `flip_h`로도 그대로다 — 프레임 사각형 안에서만 뒤집힌다.
func _make_origin_cut_sprite(row: int, col: int, flip: bool = false) -> Sprite2D:
	var tex: Texture2D = load(ORIGIN_PLAYER_CUT)
	if tex == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(
		float(col) * ORIGIN_SCREEN_W, float(row) * ORIGIN_SCREEN_H, ORIGIN_SCREEN_W, ORIGIN_SCREEN_H
	)
	var spr := Sprite2D.new()
	spr.texture = at
	spr.centered = false
	spr.flip_h = flip
	spr.scale = Vector2.ONE * _origin_scale()
	spr.z_index = 50  # 적 대형 시트(기본 0)보다 앞 — 컷은 화면을 끊고 들어오는 것이다.
	_root.add_child(spr)
	return spr


## 컷을 원작 좌표 a → b로 밀고 지운다. dim_hide면 끝에서 딤도 걷는다
## (fire-and-forget 상영 — 트윈이 스프라이트에 묶여 씬 전환에 같이 죽는다).
func _origin_cut_move(
	spr: Sprite2D, from: Vector2, to: Vector2, dur: float, dim_hide: bool = false
) -> void:
	_place_origin_topleft(spr, ORIGIN_PLAYER_OFFSET + from)
	var target := spr.position + (to - from) * _origin_scale()
	var tw := spr.create_tween()
	tw.tween_property(spr, "position", target, dur).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(spr, "modulate:a", 0.0, 0.12)
	if dim_hide:
		tw.tween_callback(_cut_dim_hide)
		tw.tween_callback(_show_cut_actor)
	tw.tween_callback(spr.queue_free)


## 백열 장수 — 두 프레임을 교대하며 점점 빨라진다(`:347` Delay 200 → 100 → 0).
## 원작 그대로 20회 교대다. `i 0~4: 200ms · 5~7: 100ms · 8~19: 0(vsync)` —
## 현대 박자로 간격만 축소(0.2 · 0.1 · 0.03)하고 구조(5/3/12)는 유지한다.
## a3의 1·2번 칸은 팔 오버레이 낱장이라(몸통 없음 — 실측) 그 둘만 교대하면
## 몸통이 사라지고 팔만 남는다(2026-09-11 유저 지적 "양팔만 보이고 몸통 사라짐").
## 원작은 몸통(0번) 위에 팔을 얹어 그렸다. 그래서 몸통 스프라이트는 0번에 고정하고
## 팔 오버레이 한 장을 같은 자리에 겹쳐 1·2번만 교대한다.
func _origin_cut_flurry(spr: Sprite2D, row: int, speed: float, dim_hide: bool = false) -> void:
	_place_origin_topleft(spr, ORIGIN_PLAYER_OFFSET)
	var base_at := spr.texture as AtlasTexture
	if base_at == null:
		return
	base_at.region.position.x = 0.0  # 몸통 고정 — 이 장은 다시 안 건드린다
	var overlay := _make_origin_cut_sprite(row, 1, spr.flip_h)
	if overlay == null:
		return
	_place_origin_topleft(overlay, ORIGIN_PLAYER_OFFSET)
	overlay.z_index = spr.z_index + 1
	var over_at := overlay.texture as AtlasTexture
	var tw := spr.create_tween()
	for i in 20:
		var col := i % 2 + 1  # 원작 `S[i%2+1]` — 0번은 몸통이라 오버레이에서만 돈다
		var gap := (0.2 if i < 5 else (0.1 if i < 8 else 0.03)) / speed
		tw.tween_callback(
			func() -> void:
				if is_instance_valid(overlay) and over_at != null:
					over_at.region.position.x = float(col) * ORIGIN_SCREEN_W
		)
		tw.tween_interval(gap)
	tw.set_parallel(true)
	tw.tween_property(spr, "modulate:a", 0.0, 0.14)
	tw.tween_property(overlay, "modulate:a", 0.0, 0.14)
	tw.chain()
	if dim_hide:
		tw.tween_callback(_cut_dim_hide)
		tw.tween_callback(_show_cut_actor)
	tw.tween_callback(spr.queue_free)
	tw.tween_callback(overlay.queue_free)


## 원작 `RPut_Spr(x, y, spr)`와 같은 좌상단 기준 배치.
func _place_origin_topleft(spr: Sprite2D, at: Vector2) -> void:
	var sc := _origin_scale()
	var w := float(ProjectSettings.get_setting("display/window/size/viewport_width", 960))
	spr.position = Vector2((w - ORIGIN_SCREEN_W * sc) * 0.5, 0.0) + at * sc


func _origin_player_meta() -> Dictionary:
	if not _origin_player_meta_cache.is_empty():
		return _origin_player_meta_cache
	var path := ORIGIN_PLAYER_CUT.replace(".png", ".json")
	if FileAccess.file_exists(path):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(raw) == TYPE_DICTIONARY:
			_origin_player_meta_cache = raw
	return _origin_player_meta_cache


## 히트 스파크 — 원작 `AttackEffect(x, y)`(`:220`). 주인공이 때린 자리에 터진다.
func origin_hit_spark(at: Vector2 = Vector2(100, 60)) -> void:
	if SettingsManager.effect_speed == SettingsManager.EffectSpeed.SKIP:
		return
	var spark := _origin_fx("origin_spark", at)
	if spark == null:
		return
	var speed := maxf(SettingsManager.battle_speed_factor(), 0.1)
	var tw := spark.create_tween()
	tw.tween_property(spark, "modulate:a", 0.0, 0.28 / speed)
	tw.tween_callback(spark.queue_free)


## 피격 플래시 — 타겟이 빨갛게 깜빡임.
## 피격 표현 — 붉은 플래시 + 넉백 + (시트에 hurt 행이 있으면) 피격 동작.
func hurt_flash(spr: Sprite2D) -> void:
	knockback(spr, 1.0 if spr == player_sprite else -1.0)
	if spr != null and is_instance_valid(spr):
		play_anim(spr, "hurt", "" if spr == player_sprite else _sprite_asset_id(spr))
		# 원작은 주인공이 때리면 `AttackEffect(100,60)`으로 붉은 스파크를 터뜨렸다
		# (`EnemyAvoid` 매 단계). 대형 시트를 쓰는 적에게만 얹는다 — 하이브리드 규칙.
		if spr != player_sprite and spr.has_meta(&"battle_sheet"):
			origin_hit_spark()
	if spr == null or not is_instance_valid(spr):
		return
	var f := SettingsManager.battle_speed_factor()
	var tw := spr.create_tween()
	# 백열 1프레임 — 맞은 순간 하얗게 타올랐다 붉어진다(가산 없이 HDR 클리핑으로 뽑는다).
	tw.tween_property(spr, "modulate", Color(8, 8, 8), 0.03 / f)
	tw.tween_property(spr, "modulate", Color(5, 0.3, 0.3), 0.05 / f)
	tw.tween_property(spr, "modulate", Color.WHITE, 0.1 / f)


## 히트스톱 — 임팩트 순간 시간 감속.
## 히트스톱 — 타격 순간 시간을 5%로 떨어뜨렸다가 되돌린다.
##
## **되돌리는 일을 코루틴에만 맡기면 안 된다**(2026-09-09 실측). 되돌리는 줄은 await
## 뒤에 있고, 이 노드는 전투 씬의 자식이다. 타이머가 울리기 전에 씬이 갈리면
## (`change_scene_to_file`) 노드와 함께 코루틴이 사라져 **그 줄에 영영 도달하지 못하고
## Engine.time_scale이 5%에 남는다.** 그러면 그 판이 끝날 때까지 게임 전체가 20배 느려진다.
##
## 호출부 둘(battle_scene_controller._on_choreo_finished · battle_enemy_phase)은 await
## 없이 던져 놓으므로 아무도 그것을 기다리지 않는다. 자동 주행처럼 배율을 120으로
## 올려 둔 상태에서는 결과 연출의 0.9초 타이머가 실시간 7.5ms라 히트스톱 타이머
## (최소 20ms)를 앞질러 이기는 **경주 조건**이 된다 — 관문 [19/24]가 회차마다 느려지던
## 지문(걸음 초당 44~47 → 7~15)이 이 모양이다.
##
## 그래서 되돌릴 값을 필드에 남기고 _exit_tree에서도 되돌린다. 어느 쪽이 먼저 오든 한 번만 돈다.
func hitstop(duration: float = 0.06) -> void:
	if _hitstop_busy:
		return
	_hitstop_busy = true
	# **되돌릴 값은 1.0이 아니라 「직전 값」이다.** 밖에서 시간을 빨리 감아 둔 경우
	# (자동 주행의 배율 30) 1.0으로 덮으면 첫 타격 이후 빨리 감기가 영영 꺼진다.
	_hitstop_prev_scale = Engine.time_scale
	Engine.time_scale = _hitstop_prev_scale * HITSTOP_SCALE
	var scaled := maxf(duration / SettingsManager.battle_speed_factor(), 0.02)
	await get_tree().create_timer(scaled, true, false, true).timeout
	restore_time_scale()


## 히트스톱으로 낮춘 배율을 되돌린다. 두 번 불러도 한 번만 돈다.
func restore_time_scale() -> void:
	if _hitstop_prev_scale < 0.0:
		return
	Engine.time_scale = _hitstop_prev_scale
	_hitstop_prev_scale = -1.0
	_hitstop_busy = false


## 씬이 갈리는 순간의 안전망 — 위 주석의 그 경주에서 코루틴이 진 경우가 여기다.
func _exit_tree() -> void:
	restore_time_scale()


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
	# idle 프레임 순환 — 정지 1프레임 해소 및 대치 호흡(헐떡임) 연출
	_idle_clock += delta
	_apply_anim_frame(int(_idle_clock * IDLE_FPS) % 2)
	_apply_idle_breathing(_idle_clock)
	_advance_effects(delta)
	_advance_cuts(delta)
	_advance_anims(delta)
	_sync_enemy_pose()


## 적 상태(빈사·사망)를 대치 포즈에 반영한다.
##
## **원작이 이미 하던 것이다.** `WARMODE.C:1116-1127`은 매 그리기마다 HP를 보고
## 프레임 0(평상)·1(빈사, HP≤15)·2(사망)를 골랐다. 리메이크는 그 세 프레임을 시트에
## 굽고도 평상 하나만 쓰고 있었다 — 게다가 필드 도트 시트 4종(c_bug·flying_thesis·
## rogue_vending·null_pointer)이 가진 `death` 행도 **호출부가 0곳**이었다.
##
## 컨트롤러가 갱신 때마다 불러 주는 방식을 쓰지 않는 이유: 부르는 곳을 하나 빠뜨리면
## 조용히 죽고, 그게 이 저장소의 지배적 결함이다. 여기서 스스로 본다(적 최대 3체).
func _sync_enemy_pose() -> void:
	for i in enemy_sprites.size():
		if i >= enemy_combatants.size():
			break
		var spr := enemy_sprites[i]
		if spr == null or not is_instance_valid(spr) or not spr.has_meta(&"anim_cell"):
			continue
		var c: Combatant = enemy_combatants[i]
		if c == null:
			continue
		var anims: Dictionary = _sheet_meta(spr, _sprite_asset_id(spr)).get("animations", {})
		var row := int(spr.get_meta(&"pose_row", 0))
		if c.is_down() and anims.has("death"):
			row = int((anims["death"] as Dictionary).get("row", row))
		elif float(c.hp) <= float(maxi(c.max_hp, 1)) * WOUNDED_RATIO and anims.has("wounded"):
			row = int((anims["wounded"] as Dictionary).get("row", row))
		spr.set_meta(&"idle_row", row)


## 애니 메타 보유 스프라이트의 대치 프레임 순환
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
		var idle_row: int = int(spr.get_meta(&"idle_row", 0))
		at.region.position.x = frame * float(cell.x)
		at.region.position.y = idle_row * float(cell.y)


## 전투 중 대치 자세 — 좌측 플레이어는 우측(적)을 보고, 우측 적은 좌측(플레이어)을 본다.
func _face_combat_idle(spr: Sprite2D) -> void:
	if spr == null or not is_instance_valid(spr) or not spr.has_meta(&"anim_cell"):
		return
	var at := spr.texture as AtlasTexture
	if at == null:
		return
	var cell: Vector2i = spr.get_meta(&"anim_cell")
	var meta := _sheet_meta(spr, "" if spr == player_sprite else _sprite_asset_id(spr))
	var anims: Dictionary = meta.get("animations", {})
	if spr == player_sprite:
		spr.flip_h = false
		if anims.has("walk_right"):
			var row := int(anims["walk_right"].get("row", 3))
			spr.set_meta(&"idle_row", row)
			at.region.position.y = float(row * cell.y)
	elif spr.has_meta(&"battle_sheet"):
		# 대형 시트는 원작 화면 구도 자체다 — 좌우를 뒤집으면 조명·그림자까지 뒤집힌다.
		var row := int((anims.get("idle", {}) as Dictionary).get("row", 0))
		spr.set_meta(&"idle_row", row)
		spr.set_meta(&"pose_row", row)
		at.region.position.y = float(row * cell.y)
		spr.flip_h = false
	else:
		if anims.has("walk_left"):
			var row := int(anims["walk_left"].get("row", 2))
			spr.set_meta(&"idle_row", row)
			spr.set_meta(&"pose_row", row)
			at.region.position.y = float(row * cell.y)
			spr.flip_h = false
		else:
			spr.flip_h = true


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
		if spr != null and is_instance_valid(spr):
			if spr.has_meta(&"base_pos"):
				spr.position = spr.get_meta(&"base_pos")
			if spr.has_meta(&"base_scale"):
				spr.scale = spr.get_meta(&"base_scale")
			spr.modulate = Color.WHITE
			spr.flip_h = false  # 공격 자세의 좌우 반전(`shot.flip`)을 대치 자세로 되돌린다.


## 대치 중 유기적인 호흡(헐떡임) 연출 — 정지된 도트에 긴장감 부여
func _apply_idle_breathing(clock: float) -> void:
	var list: Array[Sprite2D] = []
	if player_sprite != null and is_instance_valid(player_sprite):
		list.append(player_sprite)
	for es in enemy_sprites:
		if es != null and is_instance_valid(es):
			list.append(es)

	for spr in list:
		if not spr.has_meta(&"base_pos") or not spr.has_meta(&"base_scale"):
			continue
		if _is_animating(spr):
			continue
		var base_pos: Vector2 = spr.get_meta(&"base_pos")
		var base_scale: Vector2 = spr.get_meta(&"base_scale")
		# 이동 트윈 또는 큰 변위 중에는 호흡 애니메이션 억제
		if spr.position.distance_to(base_pos) > 5.0:
			continue

		var is_p := spr == player_sprite
		var phase: float = float(spr.get_meta(&"phase", 0.0))
		var speed: float = 3.6
		var amp_y: float = 1.8
		var stretch_y: float = 0.024
		var squash_x: float = 0.014

		if is_p and is_player_low_hp:
			# 빈사(HP 30% 이하): 헐떡임 주기 가속 및 상하 진폭 강화
			speed = 7.0
			amp_y = 2.6
			stretch_y = 0.045
			squash_x = 0.025

		var s := sin(clock * speed + phase)
		spr.position.y = base_pos.y + s * amp_y
		spr.scale.y = base_scale.y * (1.0 + s * stretch_y)
		spr.scale.x = base_scale.x * (1.0 - s * squash_x)


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
	p.color = Color.WHITE
	# 불티는 가산+수명 곡선 — 흰핵→앰버→소멸. 단색 점들의 집합이 아니다.
	p.material = BattleFxMaterials.additive()
	p.color_ramp = BattleFxMaterials.spark_ramp()
	_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)


## 임팩트 글로우 — 큰 일격의 발광 핵. 색·끝크기만 정한다(지속·z는 규격).
func spawn_impact_glow(at: Vector2, edge: Color, end_px: float) -> void:
	if SettingsManager.effect_speed == SettingsManager.EffectSpeed.SKIP:
		return
	BattleFxMaterials.spawn_glow(
		_root, at, edge, 12.0, end_px, 0.3 / maxf(SettingsManager.battle_speed_factor(), 0.1), 55
	)


## 절차적 전투 VFX 디스패처 — 물리 베기 아크, 화염 폭발, 번개 스트라이크, 대폭발, 실드
func _spawn_procedural_fx(fx_id: String, at: Vector2, kf: Dictionary) -> void:
	var scale_mult := float(kf.get("scale", 1.0))
	match fx_id:
		"hit_spark":
			_spawn_slash_arc_fx(at, scale_mult)
		"flame_burst":
			_spawn_flame_burst_fx(at, scale_mult)
		"volt_arc":
			_spawn_volt_arc_fx(at, scale_mult)
		"blast":
			_spawn_blast_fx(at, scale_mult)
		"shield_up":
			_spawn_shield_up_fx(at, scale_mult)
		_:
			_spawn_spark(at)


## 물리 베기 아크 & 타격 스파크 (Physical Slash Arc)
func _spawn_slash_arc_fx(at: Vector2, scale_mult: float = 1.0) -> void:
	var slash := Line2D.new()
	slash.width = 6.0 * scale_mult
	slash.default_color = Color(1.0, 0.95, 0.8, 1.0)
	slash.material = BattleFxMaterials.additive()
	slash.begin_cap_mode = Line2D.LINE_CAP_ROUND
	slash.end_cap_mode = Line2D.LINE_CAP_ROUND
	slash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	slash.z_index = 60

	var angle := randf_range(-0.65, -0.45)
	var length := 48.0 * scale_mult
	var p0 := at + Vector2(-cos(angle), -sin(angle)) * length
	var p1 := at + Vector2(sin(angle) * 10.0, -cos(angle) * 10.0)
	var p2 := at + Vector2(cos(angle), sin(angle)) * length

	var points := PackedVector2Array()
	var steps := 8
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var pt := (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2
		points.append(pt)
	slash.points = points
	_root.add_child(slash)

	var tw := slash.create_tween()
	tw.set_parallel(true)
	tw.tween_property(slash, "modulate:a", 0.0, 0.13).set_ease(Tween.EASE_OUT)
	tw.tween_property(slash, "width", 1.0, 0.13)
	tw.finished.connect(slash.queue_free)

	var cross := Line2D.new()
	cross.width = 3.0 * scale_mult
	cross.default_color = Color.WHITE
	cross.z_index = 61
	var c_len := 16.0 * scale_mult
	cross.points = PackedVector2Array(
		[
			at + Vector2(-c_len, -c_len * 0.4),
			at + Vector2(c_len, c_len * 0.4),
			at,
			at + Vector2(-c_len * 0.4, c_len),
			at + Vector2(c_len * 0.4, -c_len)
		]
	)
	_root.add_child(cross)
	var c_tw := cross.create_tween()
	c_tw.tween_property(cross, "modulate:a", 0.0, 0.08)
	c_tw.finished.connect(cross.queue_free)

	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 16
	p.lifetime = 0.24
	p.spread = 180.0
	p.initial_velocity_min = 80.0 * scale_mult
	p.initial_velocity_max = 180.0 * scale_mult
	p.scale_amount_min = 2.0 * scale_mult
	p.scale_amount_max = 4.5 * scale_mult
	p.color = Color.WHITE
	p.material = BattleFxMaterials.additive()
	p.color_ramp = BattleFxMaterials.spark_ramp()
	_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.6).timeout.connect(p.queue_free)


## 화염 폭발 & 불기둥 (Flame Burst VFX)
func _spawn_flame_burst_fx(at: Vector2, scale_mult: float = 1.0) -> void:
	var ring := Line2D.new()
	ring.width = 4.0 * scale_mult
	ring.default_color = Color(1.0, 0.45, 0.08, 0.95)
	ring.z_index = 58
	var ring_pts := PackedVector2Array()
	var r_segs := 32
	for i in range(r_segs + 1):
		var rad := (float(i) / float(r_segs)) * TAU
		ring_pts.append(Vector2(cos(rad), sin(rad)))
	ring.points = ring_pts
	ring.position = at
	ring.scale = Vector2.ONE * (12.0 * scale_mult)
	_root.add_child(ring)

	var r_tw := ring.create_tween()
	r_tw.set_parallel(true)
	r_tw.tween_property(ring, "scale", Vector2.ONE * (52.0 * scale_mult), 0.25).set_ease(
		Tween.EASE_OUT
	)
	r_tw.tween_property(ring, "modulate:a", 0.0, 0.25).set_ease(Tween.EASE_IN)
	r_tw.finished.connect(ring.queue_free)

	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = 26
	p.lifetime = 0.38
	p.direction = Vector2(0, -1)
	p.spread = 65.0
	p.gravity = Vector2(0, -90.0)
	p.initial_velocity_min = 70.0 * scale_mult
	p.initial_velocity_max = 160.0 * scale_mult
	p.scale_amount_min = 3.5 * scale_mult
	p.scale_amount_max = 7.5 * scale_mult
	p.color = Color.WHITE
	p.material = BattleFxMaterials.additive()
	p.color_ramp = BattleFxMaterials.fire_ramp()
	_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)

	_do_flash(Color(1.0, 0.4, 0.05, 0.22))


## 전격 스트라이크 & 10,000V 볼트 아크 (Volt Arc Lightning Strike)
func _spawn_volt_arc_fx(at: Vector2, scale_mult: float = 1.0) -> void:
	var bolt := Line2D.new()
	bolt.width = 4.0 * scale_mult
	bolt.default_color = Color(0.4, 0.85, 1.0, 0.95)
	bolt.material = BattleFxMaterials.additive()
	bolt.z_index = 62

	var core := Line2D.new()
	core.width = 1.8 * scale_mult
	core.default_color = Color.WHITE
	core.material = BattleFxMaterials.additive()
	core.z_index = 63

	var top_pt := at + Vector2(randf_range(-25, 25) * scale_mult, -120.0 * scale_mult)
	var segs := 6
	var pts := PackedVector2Array([top_pt])
	for i in range(1, segs):
		var frac := float(i) / float(segs)
		var base := top_pt.lerp(at, frac)
		var jitter := Vector2(randf_range(-18, 18), randf_range(-6, 6)) * scale_mult
		pts.append(base + jitter)
	pts.append(at)
	bolt.points = pts
	core.points = pts

	_root.add_child(bolt)
	_root.add_child(core)

	var b_tw := bolt.create_tween()
	b_tw.set_parallel(true)
	b_tw.tween_property(bolt, "modulate:a", 0.0, 0.14)
	b_tw.tween_property(core, "modulate:a", 0.0, 0.14)
	b_tw.finished.connect(bolt.queue_free)
	b_tw.finished.connect(core.queue_free)

	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 22
	p.lifetime = 0.22
	p.spread = 180.0
	p.initial_velocity_min = 120.0 * scale_mult
	p.initial_velocity_max = 240.0 * scale_mult
	p.damping_min = 60.0
	p.damping_max = 100.0
	p.scale_amount_min = 2.0 * scale_mult
	p.scale_amount_max = 4.5 * scale_mult
	p.color = Color.WHITE
	p.material = BattleFxMaterials.additive()
	p.color_ramp = BattleFxMaterials.volt_ramp()
	_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.6).timeout.connect(p.queue_free)

	_do_flash(Color(0.35, 0.75, 1.0, 0.26))


## 필살기 대폭발 (Blast Finisher VFX)
func _spawn_blast_fx(at: Vector2, scale_mult: float = 1.0) -> void:
	for i in 2:
		var ring := Line2D.new()
		ring.width = (5.0 - float(i) * 1.5) * scale_mult
		ring.default_color = Color(1.0, 0.85, 0.3) if i == 0 else Color(1.0, 0.3, 0.1)
		ring.z_index = 59
		var ring_pts := PackedVector2Array()
		for s in 33:
			var rad := (float(s) / 32.0) * TAU
			ring_pts.append(Vector2(cos(rad), sin(rad)))
		ring.points = ring_pts
		ring.position = at
		ring.scale = Vector2.ONE * (14.0 * scale_mult)
		_root.add_child(ring)

		var tw := ring.create_tween()
		tw.set_parallel(true)
		var delay := float(i) * 0.05
		tw.tween_property(ring, "scale", Vector2.ONE * (80.0 * scale_mult), 0.30).set_delay(delay)
		tw.tween_property(ring, "modulate:a", 0.0, 0.30).set_delay(delay)
		tw.finished.connect(ring.queue_free)

	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 32
	p.lifetime = 0.35
	p.spread = 180.0
	p.initial_velocity_min = 120.0 * scale_mult
	p.initial_velocity_max = 280.0 * scale_mult
	p.scale_amount_min = 3.0 * scale_mult
	p.scale_amount_max = 8.0 * scale_mult
	p.color = Color.WHITE
	p.material = BattleFxMaterials.additive()
	p.color_ramp = BattleFxMaterials.fire_ramp()
	_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.7).timeout.connect(p.queue_free)

	# 필살핵 글로우 — 링보다 먼저 터지는 발광. 색은 불꽃 계열로 통일한다.
	BattleFxMaterials.spawn_glow(
		_root, at, Color(1.0, 0.6, 0.15), 16.0, 110.0 * scale_mult, 0.3, 55
	)
	if SettingsManager.screen_shake:
		_shake_power = maxf(_shake_power, 8.0)
	_do_flash(Color(1.0, 1.0, 1.0, 0.45))


## 방어/실드 전개 (Shield Up VFX)
func _spawn_shield_up_fx(at: Vector2, scale_mult: float = 1.0) -> void:
	var hex := Line2D.new()
	hex.width = 3.0 * scale_mult
	hex.default_color = Color(0.2, 0.9, 0.8, 0.9)
	hex.z_index = 60
	var pts := PackedVector2Array()
	for i in range(7):
		var rad := (float(i) / 6.0) * TAU - PI * 0.5
		pts.append(Vector2(cos(rad), sin(rad)))
	hex.points = pts
	hex.position = at + Vector2(0, -8.0 * scale_mult)
	hex.scale = Vector2.ONE * (20.0 * scale_mult)
	_root.add_child(hex)

	var tw := hex.create_tween()
	tw.set_parallel(true)
	tw.tween_property(hex, "scale", Vector2.ONE * (44.0 * scale_mult), 0.35).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_property(hex, "modulate:a", 0.0, 0.35).set_ease(Tween.EASE_IN)
	tw.finished.connect(hex.queue_free)

	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 0.7
	p.amount = 14
	p.lifetime = 0.40
	p.direction = Vector2(0, -1)
	p.spread = 45.0
	p.gravity = Vector2(0, -60.0)
	p.initial_velocity_min = 40.0 * scale_mult
	p.initial_velocity_max = 90.0 * scale_mult
	p.scale_amount_min = 2.0 * scale_mult
	p.scale_amount_max = 4.0 * scale_mult
	p.color = Color(0.35, 1.0, 0.85)
	p.material = BattleFxMaterials.additive()
	_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.7).timeout.connect(p.queue_free)


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
