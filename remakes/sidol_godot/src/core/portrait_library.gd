class_name PortraitLibrary
## 대화 초상 조회 — 설치된 `assets/portraits/<id>.png`(768×256 = 256셀 3개)를 화자로 찾는다.
##
## 왜 생겼나(2026-08-28): 초상 스펙 16종·의뢰 패키지·납품 검증기까지 다 있는데
## **화면에 띄우는 코드가 어디에도 없었다**(`grep -rn portrait src/` 0건).
## 설치해도 안 보이면 사문화 데이터다 — 이 저장소의 지배적 결함이라 배선까지 같이 둔다.
##
## 셀 = 표정. 스펙의 `expressions` 순서가 곧 셀 순서다(0 normal / 1 / 2).
## 초상이 없는 화자는 조용히 빈 결과를 돌려준다 — 16종이 다 차기 전에도 게임이 돌아야 한다.

const DIR := "res://assets/portraits/"
const SPEC_DIR := "res://assets/spec/portraits/"
const CELL := 256
## 설치된 초상이 없을 때 세우는 실루엣. 생성기: tools/dev/make_keyart_fallback.py
const FALLBACK_ID := "_fallback"

static var _name_to_id: Dictionary = {}
static var _expressions: Dictionary = {}
static var _scanned := false


## 스펙 폴더를 한 번만 훑어 이름·표정 색인을 만든다.
static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	var dir := DirAccess.open(SPEC_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPEC_DIR + f))
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = raw
		var asset_id := str(spec.get("asset_id", f.get_basename()))
		var exprs: Array = spec.get("expressions", ["normal"])
		_expressions[asset_id] = exprs
		var display_name := str(spec.get("name", ""))
		if not display_name.is_empty():
			_name_to_id[display_name] = asset_id


## 화자 문자열(대사 데이터의 speaker) 또는 asset_id → 설치된 초상의 asset_id. 없으면 "".
static func resolve(speaker: String) -> String:
	_scan()
	var candidates: Array[String] = []
	if _name_to_id.has(speaker):
		candidates.append(str(_name_to_id[speaker]))
	candidates.append(speaker)
	for cand in candidates:
		if not cand.is_empty() and ResourceLoader.exists(DIR + cand + ".png"):
			return cand
	return ""


## 표정 이름 → 셀 인덱스. 모르는 이름은 0(normal)으로 떨어뜨린다.
static func expression_index(asset_id: String, expr: String) -> int:
	_scan()
	if expr.is_empty():
		return 0
	var exprs: Array = _expressions.get(asset_id, [])
	var idx := exprs.find(expr)
	return idx if idx >= 0 else 0


## 초상 한 칸 텍스처. 미설치·미해석이면 null.
static func texture_for(speaker: String, expr: String = "") -> AtlasTexture:
	var asset_id := resolve(speaker)
	var tex: Texture2D = load(DIR + asset_id + ".png") if not asset_id.is_empty() else null
	if tex == null:
		# **비면 늘 대체가 나온다**(2026-08-29 유저 방침). 초상은 대사보다 늦게 오는
		# 것이 정상 순서라 미설치가 흔한데, 그때 말하는 자리가 통째로 비어 있었다.
		# 얼굴을 흉내 내지 않는 실루엣이다 — 누군가 거기 있다는 것만 말한다.
		var fallback: Texture2D = load(DIR + FALLBACK_ID + ".png")
		if fallback == null:
			return null
		var plain := AtlasTexture.new()
		plain.atlas = fallback
		plain.region = Rect2(0, 0, fallback.get_width(), fallback.get_height())
		return plain
	var at := AtlasTexture.new()
	at.atlas = tex
	var col := expression_index(asset_id, expr)
	# 납품이 3셀이 아닐 수도 있다(시트 폭으로 셀 수를 재 계산 — 규격 밖이어도 크래시는 없다).
	var max_col := maxi(int(tex.get_width() / CELL) - 1, 0)
	at.region = Rect2(mini(col, max_col) * CELL, 0, CELL, mini(CELL, int(tex.get_height())))
	return at


## 설치된 초상 수 — 진단·관문 출력용.
static func installed_count() -> int:
	_scan()
	var n := 0
	for asset_id: String in _expressions.keys():
		if ResourceLoader.exists(DIR + asset_id + ".png"):
			n += 1
	return n
