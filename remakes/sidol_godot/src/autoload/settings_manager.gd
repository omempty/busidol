extends Node
## 볼륨/연출속도/아트모드 저장 — 원작 WVISUAL/SPEED/gitar() 대체. Phase 9 실구현.
## 파일: user://settings.json — 타이틀·설정 UI에서 즉시 반영+저장.

enum EffectSpeed { NORMAL, FAST, SKIP }
## 아트 모드 — LEGACY: 원작 도트 세트(_original) / REMAKE: 신규 생성 세트(_remake)
enum ArtMode { LEGACY, REMAKE }
## 본문 글자 크기(Q9 접근성) — DialogueBox 등 텍스트 UI 스케일
enum TextSize { SMALL, MEDIUM, LARGE }
## 필드 몬스터 밀도(Q6) — 접촉이 곧 강제 전투라 밀도가 곧 난이도이자 피로도다.
## NONE은 탐험/시나리오만 보고 싶을 때(원작에는 없던 현대 편의).
enum EncounterDensity { NONE, LOW, NORMAL, HIGH }
## 화면 모드(Q10) — 원작은 DOS 전체화면 고정이었다.
enum ScreenMode { WINDOWED, FULLSCREEN }
## 난이도(G-FAITH) — growth.json difficulty_presets의 키와 1:1.
enum Difficulty { EASY, NORMAL, HARD }
## 표시 언어 — UI 문자열은 data/l10n/ui.csv 한 곳에서 온다(04_uiux §6).
enum Language { KO, EN }

const SETTINGS_PATH := "user://settings.json"
const BUSES: Array[StringName] = [&"Master", &"BGM", &"SFX", &"Voice"]
const DEFAULT_VOLUME := 0.8
const TEXT_SCALE := {
	TextSize.SMALL: 0.85,
	TextSize.MEDIUM: 1.0,
	TextSize.LARGE: 1.25,
}
## 밀도 → 층별 스폰 수 배율. monsters.json의 count에 곱한다.
## 난이도 enum → growth.json difficulty_presets 키.
const DIFFICULTY_KEYS := ["easy", "normal", "hard"]
## 언어 enum → 로케일 코드. data/l10n/ui.csv의 열 이름과 1:1.
const LANGUAGE_CODES := ["ko", "en"]
const ENCOUNTER_SCALE := {
	EncounterDensity.NONE: 0.0,
	EncounterDensity.LOW: 0.5,
	EncounterDensity.NORMAL: 1.0,
	EncounterDensity.HIGH: 1.5,
}

var effect_speed: EffectSpeed = EffectSpeed.NORMAL
var art_mode: ArtMode = ArtMode.LEGACY
var text_size: TextSize = TextSize.MEDIUM
var screen_shake := true  # Q9 접근성 — 화면 흔들림 끄기(멀미 대응)
var encounter_density: EncounterDensity = EncounterDensity.NORMAL
var screen_mode: ScreenMode = ScreenMode.WINDOWED
var vsync := true
var difficulty: Difficulty = Difficulty.NORMAL
var language: Language = Language.KO
var volumes := {}  # StringName -> float


func get_text_scale() -> float:
	return float(TEXT_SCALE.get(text_size, 1.0))


## 층 스폰 수 = monsters.json count × 이 배율(최소 0). NONE이면 몬스터가 나오지 않는다.
## 난이도 배율 조회 — growth.json이 값의 출처(하드코딩 금지).
## key 예: exp_mult · enemy_hp_mult · enemy_ap_mult · item_price_mult · status_duration_mult
func difficulty_mult(key: String) -> float:
	Database.difficulty = difficulty_key()
	return Database.get_difficulty_mult(key)


func difficulty_key() -> String:
	return DIFFICULTY_KEYS[int(difficulty)]


func encounter_count(base_count: int) -> int:
	var scaled := float(base_count) * float(ENCOUNTER_SCALE.get(encounter_density, 1.0))
	if scaled <= 0.0:
		return 0
	return maxi(1, int(round(scaled)))


## 전투 연출 배수 — 안무·트윈 지속시간을 나누는 배속.
## 타이밍 링(입력 창)은 공정성을 위해 배속 제외. 원작 WVISUAL/SPEED 대체.
func battle_speed_factor() -> float:
	match effect_speed:
		EffectSpeed.FAST:
			return 2.0
		EffectSpeed.SKIP:
			return 6.0
		_:
			return 1.0


func _ready() -> void:
	for bus in BUSES:
		volumes[bus] = DEFAULT_VOLUME
	load_settings()


func set_volume(bus: StringName, linear: float) -> void:
	volumes[bus] = clampf(linear, 0.0, 1.0)
	_apply_bus(bus)


func get_volume(bus: StringName) -> float:
	return float(volumes.get(bus, DEFAULT_VOLUME))


## 파일 → 메모리 + 버스 적용. 파일 부재/손상 시 기본값 유지.
func load_settings() -> void:
	for bus in BUSES:
		volumes[bus] = DEFAULT_VOLUME
	if not FileAccess.file_exists(SETTINGS_PATH):
		_apply_all()
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("settings.json 손상 — 기본값 사용")
		_apply_all()
		return
	var data: Dictionary = raw
	for bus in BUSES:
		volumes[bus] = clampf(float(data.get("vol_" + String(bus), DEFAULT_VOLUME)), 0.0, 1.0)
	var speed_v: Variant = clampi(
		int(data.get("effect_speed", int(effect_speed))), 0, int(EffectSpeed.SKIP)
	)
	effect_speed = speed_v
	var art_v: Variant = clampi(int(data.get("art_mode", int(art_mode))), 0, int(ArtMode.REMAKE))
	art_mode = art_v
	var ts_v: Variant = clampi(int(data.get("text_size", int(text_size))), 0, int(TextSize.LARGE))
	text_size = ts_v
	screen_shake = bool(data.get("screen_shake", true))
	var ed_v: Variant = clampi(
		int(data.get("encounter_density", int(encounter_density))), 0, int(EncounterDensity.HIGH)
	)
	encounter_density = ed_v
	var sm_v: Variant = clampi(
		int(data.get("screen_mode", int(screen_mode))), 0, int(ScreenMode.FULLSCREEN)
	)
	screen_mode = sm_v
	vsync = bool(data.get("vsync", true))
	var df_v: Variant = clampi(
		int(data.get("difficulty", int(difficulty))), 0, int(Difficulty.HARD)
	)
	difficulty = df_v
	var lang_v: Variant = clampi(int(data.get("language", int(language))), 0, int(Language.EN))
	language = lang_v
	_apply_all()


## 메모리 → 파일 + 버스 적용. 설정 변경 UI가 호출한다.
func save_settings() -> void:
	var data := {}
	for bus in BUSES:
		data["vol_" + String(bus)] = get_volume(bus)
	data["effect_speed"] = int(effect_speed)
	data["art_mode"] = int(art_mode)
	data["text_size"] = int(text_size)
	data["screen_shake"] = screen_shake
	data["encounter_density"] = int(encounter_density)
	data["screen_mode"] = int(screen_mode)
	data["vsync"] = vsync
	data["difficulty"] = int(difficulty)
	data["language"] = int(language)
	var fh := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if fh == null:
		push_error("settings.json 저장 실패: %s" % FileAccess.get_open_error())
		return
	fh.store_string(JSON.stringify(data, "\t"))
	_apply_all()


func _apply_bus(bus: StringName) -> void:
	AudioManager.set_bus_volume(bus, get_volume(bus))


func _apply_all() -> void:
	for bus in BUSES:
		_apply_bus(bus)
	apply_display()
	apply_language()
	Database.difficulty = difficulty_key()


## 창모드·수직동기 적용(Q10). 헤드리스에서는 창이 없으므로 건너뛴다.
func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		(
			DisplayServer.WINDOW_MODE_FULLSCREEN
			if screen_mode == ScreenMode.FULLSCREEN
			else DisplayServer.WINDOW_MODE_WINDOWED
		)
	)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)


## 표시 언어 적용 — project.godot에 등록된 ui.csv 번역으로 전환한다.
## 대사(@t/@c)는 Database가 별도로 다루므로 여기서는 UI 문자열만 바뀐다.
func apply_language() -> void:
	TranslationServer.set_locale(LANGUAGE_CODES[int(language)])
