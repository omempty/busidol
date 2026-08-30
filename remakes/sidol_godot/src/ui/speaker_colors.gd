class_name SpeakerColors
## 화자색 — 대사창 이름 라벨의 색을 화자마다 다르게 준다(04_uiux §1.2).
##
## 왜 생겼나(2026-08-30): 이름 라벨이 화자와 무관하게 금색 하나로 고정돼 있어
## 04_uiux §1.2가 요구한 "화자색 하이라이트"가 사문화 상태였다. 만담 톤의 이 게임은
## 한 장면에 서너 명이 번갈아 말하므로, 색이 없으면 누가 말하는지 이름을 매번 읽어야 한다.
##
## 표에 없는 화자도 **반드시 색을 받는다** — 이름 해시로 palette에서 고른다.
## 데이터가 코드보다 먼저 늘어나는 저장소라(대사 → 화자 추가), 표에 없으면 색이 없는
## 설계는 곧 사문화된다. 대신 같은 이름은 언제나 같은 색이라 장면 안에서 안정적이다.

const PATH := "res://data/speakers.json"

static var _default := Color(0.91, 0.93, 0.97)
static var _narration := Color(0.6, 0.63, 0.71)
static var _narration_prefix := "("
static var _overrides: Dictionary = {}
static var _palette: Array[Color] = []
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_warning("화자색 표 없음: %s — 기본색으로 진행" % PATH)
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("화자색 표 파싱 실패: %s" % PATH)
		return
	var cfg: Dictionary = raw
	_default = Color.from_string(str(cfg.get("default", "")), _default)
	_narration = Color.from_string(str(cfg.get("narration", "")), _narration)
	_narration_prefix = str(cfg.get("narration_prefix", _narration_prefix))
	var ov: Dictionary = cfg.get("overrides", {})
	for name: String in ov:
		_overrides[name] = Color.from_string(str(ov[name]), _default)
	for hex: String in cfg.get("palette", []) as Array:
		_palette.append(Color.from_string(hex, _default))


## 화자 이름 → 색. 빈 이름은 기본색(이름 라벨이 비어 있으면 어차피 안 보인다).
static func color_for(speaker: String) -> Color:
	_load()
	if speaker.is_empty():
		return _default
	if _overrides.has(speaker):
		return _overrides[speaker]
	if not _narration_prefix.is_empty() and speaker.begins_with(_narration_prefix):
		return _narration
	if _palette.is_empty():
		return _default
	return _palette[absi(speaker.hash()) % _palette.size()]
