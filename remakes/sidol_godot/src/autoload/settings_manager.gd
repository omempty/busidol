extends Node
## 볼륨/연출속도/아트모드 저장 — 원작 WVISUAL/SPEED/gitar() 대체. Phase 9 실구현.
## 파일: user://settings.json — 타이틀·설정 UI에서 즉시 반영+저장.

enum EffectSpeed { NORMAL, FAST, SKIP }
## 아트 모드 — LEGACY: 원작 도트 세트(_original) / REMAKE: 신규 생성 세트(_remake)
enum ArtMode { LEGACY, REMAKE }
## 본문 글자 크기(Q9 접근성) — DialogueBox 등 텍스트 UI 스케일
enum TextSize { SMALL, MEDIUM, LARGE }

const SETTINGS_PATH := "user://settings.json"
const BUSES: Array[StringName] = [&"Master", &"BGM", &"SFX", &"Voice"]
const DEFAULT_VOLUME := 0.8
const TEXT_SCALE := {
	TextSize.SMALL: 0.85,
	TextSize.MEDIUM: 1.0,
	TextSize.LARGE: 1.25,
}

var effect_speed: EffectSpeed = EffectSpeed.NORMAL
var art_mode: ArtMode = ArtMode.LEGACY
var text_size: TextSize = TextSize.MEDIUM
var screen_shake := true  # Q9 접근성 — 화면 흔들림 끄기(멀미 대응)
var volumes := {}  # StringName -> float


func get_text_scale() -> float:
	return float(TEXT_SCALE.get(text_size, 1.0))


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
