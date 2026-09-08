class_name SpriteSets
## 아트 모드별 스프라이트 시트 경로 결정 단일 창구.
## 컨벤션: assets/sprites/<id>_original.* = 레거시(원작 도트) · <id>_remake.* = 신규 세트.
## 설정(SettingsManager.art_mode) 우선, 파일 부재 시 반대 세트로 폴백 —
## 신규 시트 미착용 상태에서도 게임 동작을 보장한다.
## 셀 크기·프레임 수·비율은 시트별 메타 JSON이 자기기술하므로 두 세트 규격이 달라도 무관.
## 근거: docs/02_design/04_uiux_modernization.md §2 (렌더 px ↔ 논리 그리드 분리).

const SPRITE_DIR := "res://assets/sprites/"
const LEGACY_TAG := "original"
const REMAKE_TAG := "remake"
## 외부 스탠드인 — 무료팩을 구운 것(<id>_external.*). REMAKE 모드에서
## remake → external → legacy 순으로 고른다. LLM _remake가 설치되는 순간
## 코드·데이터 수정 없이 외부팩이 밀려나고(역도 성립), 굽는 도구와 출처 기록은
## tools/dev/bake_external_bosses.py + data/external_sources.json.
const EXTERNAL_TAG := "external"
## 전투 전용 대형 시트 — 원작 E*.SPR의 320×200 전체 화면 프레임을 구운 것.
## 필드 도트(_original/_remake)와 **규격이 다르다**(셀이 정사각이 아니고 화면만 하다).
## 아트 모드를 타지 않는다 — 원작 프레임 자체라 "레거시/리메이크" 구분이 성립하지 않는다.
const BATTLE_TAG := "battle"


## 캐릭터 시트 경로 조회 — {"sheet": String, "meta": String}. 부재 시 빈 문자열.
## quiet=true면 부재를 오류로 기록하지 않는다(선행 조회 용도).
static func character_sheet(asset_id: StringName, quiet := false) -> Dictionary:
	var order: Array[String] = [LEGACY_TAG, EXTERNAL_TAG, REMAKE_TAG]
	if SettingsManager.art_mode == SettingsManager.ArtMode.REMAKE:
		order = [REMAKE_TAG, EXTERNAL_TAG, LEGACY_TAG]
	for tag in order:
		var sheet := "%s%s_%s.png" % [SPRITE_DIR, asset_id, tag]
		if ResourceLoader.exists(sheet) or FileAccess.file_exists(sheet):
			return {
				"sheet": sheet,
				"meta": "%s%s_%s.json" % [SPRITE_DIR, asset_id, tag],
			}
	if not quiet:
		push_error("SpriteSets: '%s' 시트 없음 — %s/%s 태그 모두 부재" % [asset_id, order[0], order[1]])
	return {"sheet": "", "meta": ""}


## 전투 대형 시트 조회 — {"sheet": String, "meta": String}. 부재 시 빈 문자열.
##
## 있으면 전투 화면이 필드 도트 대신 이것을 쓴다. 원작 전투는 적이 화면 높이의 52~73%를
## 차지했는데(WARMODE.C의 320×200 프레임 시퀀스) 리메이크는 필드 보행 도트를 96px로
## 정규화해 13~21%였다 — 압박감이 통째로 빠져 있었다.
## 굽는 도구: tools/dev/bake_battle_sheets.py (원작 SPR 직접 읽기).
static func battle_sheet(asset_id: StringName) -> Dictionary:
	var sheet := "%s%s_%s.png" % [SPRITE_DIR, asset_id, BATTLE_TAG]
	if ResourceLoader.exists(sheet) or FileAccess.file_exists(sheet):
		return {"sheet": sheet, "meta": "%s%s_%s.json" % [SPRITE_DIR, asset_id, BATTLE_TAG]}
	return {"sheet": "", "meta": ""}


## 방향 포즈 애니 이름 해석. walking=true면 walk 우선, false면 idle 우선.
## 원작 시트는 idle이 정면 하나뿐이라, 정지 폴백을 idle_down으로 두면 옆/뒤를 보다
## 멈출 때마다 정면 프레임이 튄다 — 같은 방향 walk 첫 프레임을 정지 포즈로 쓰는 것이 정답.
## 반환값이 "idle_"로 시작하면 진짜 정지 애니, 아니면 walk 프레임을 세워 쓰라는 뜻.
static func pose_anim(frames: SpriteFrames, facing: StringName, walking: bool) -> StringName:
	if frames == null:
		return &""
	var f := String(facing)
	var order: Array[StringName] = [StringName("idle_" + f), StringName("walk_" + f)]
	if walking:
		order.reverse()
	order.append_array([&"walk_down", &"idle_down"] if walking else [&"idle_down", &"walk_down"])
	for a in order:
		if frames.has_animation(a):
			return a
	return &""


## 발바닥 앵커 보정 offset.y — 중앙 앵커 스프라이트가 scale≠1일 때도
## 발끝이 논리 바닥(2×2 발판 하단 = TILE_PX)에 닿게 한다.
## 도출: 바닥 = 위치 + scale×(offset.y + cell_h/2) ⇒ offset.y = TILE_PX/scale − cell_h/2
## scale=1이면 0(구 시트 64셀 호환), 메타 파싱 실패 시 빈 Dictionary → 0.
static func foot_offset(meta: Dictionary) -> float:
	if meta.is_empty():
		return 0.0
	var s := float(meta.get("scale", 1.0))
	if s <= 0.0:
		return 0.0
	var ch := float(meta.get("cell_h", meta.get("cell", 64)))
	return float(MapDefinition.TILE_PX) / s - ch / 2.0


## 시트 + 메타 → SpriteFrames. **메타에 있는 애니메이션을 전부 만든다.**
##
## NpcEntity는 `idle` 하나만 만들고 있었다. 그래서 방향별 포즈를 물어보는 코드
## (`pose_anim`)가 언제나 빈 이름을 받아 조용히 아무것도 하지 않았다 — 데이터(시트에는
## 4방향이 다 있다)는 있는데 코드가 안 읽는, 이 저장소의 단골 결함이다(2026-08-29).
## 플레이어·NPC·배경 보행자가 같은 것을 쓰게 한다.
static func build_frames(sheet_path: String, meta: Dictionary) -> SpriteFrames:
	var tex: Texture2D = load(sheet_path)
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	if tex == null:
		return frames
	# 셀 크기: cell_w/cell_h 우선, 구형 단일 cell 호환(아트 모드별 규격 차이를 흡수).
	var cw: int = int(meta.get("cell_w", meta.get("cell", 64)))
	var ch: int = int(meta.get("cell_h", meta.get("cell", 64)))
	var anims: Dictionary = meta.get("animations", {})
	for anim_name: String in anims:
		var a: Dictionary = anims[anim_name]
		var anim := StringName(anim_name)
		frames.add_animation(anim)
		frames.set_animation_speed(anim, float(a.get("fps", 8)))
		frames.set_animation_loop(anim, bool(a.get("loop", true)))
		for f in int(a["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(f * cw, int(a["row"]) * ch, cw, ch)
			frames.add_frame(anim, at)
	# `idle`은 정지 포즈의 기본 이름이다. 시트에 없으면 정면 것을 복제해 세운다.
	if not frames.has_animation(&"idle") and not anims.is_empty():
		var src := "idle_down" if anims.has("idle_down") else str(anims.keys()[0])
		frames.add_animation(&"idle")
		frames.set_animation_speed(&"idle", frames.get_animation_speed(StringName(src)))
		frames.set_animation_loop(&"idle", true)
		for i in frames.get_frame_count(StringName(src)):
			frames.add_frame(&"idle", frames.get_frame_texture(StringName(src), i))

	# 단일 walk/idle만 있는 단방향 시트 지원 (4방향으로 자동 복제)
	var fallback_walk: StringName = &""
	if frames.has_animation(&"walk"):
		fallback_walk = &"walk"
	elif frames.has_animation(&"idle"):
		fallback_walk = &"idle"
	elif frames.has_animation(&"idle_down"):
		fallback_walk = &"idle_down"

	if fallback_walk != &"":
		for dir_name in ["down", "up", "left", "right"]:
			var walk_dir := StringName("walk_" + dir_name)
			if not frames.has_animation(walk_dir):
				frames.add_animation(walk_dir)
				frames.set_animation_speed(walk_dir, frames.get_animation_speed(fallback_walk))
				frames.set_animation_loop(walk_dir, true)
				for i in frames.get_frame_count(fallback_walk):
					frames.add_frame(walk_dir, frames.get_frame_texture(fallback_walk, i))

	return frames
