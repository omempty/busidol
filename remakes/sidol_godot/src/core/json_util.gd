class_name JsonUtil
extends RefCounted
## [공용] JSON 파일 로더 표준 유틸 — 프로젝트마다 흩어진
## "file_exists → get_file_as_string → parse_string → 실패 처리" 패턴의 단일 구현.
##
## 사용:
##   var d := JsonUtil.load_dict("res://data/items.json")
##   var arr := JsonUtil.load_array(path, "MissionLoader")
## 실패 시 push_warning(태그+경로) 후 빈 컨테이너 반환 — 호출자는 null 체크 불필요.
## 원문 Variant가 필요하면 load_value를 쓴다.


static func load_value(path: String, tag := "JsonUtil") -> Variant:
	if path.is_empty():
		return null
	if not FileAccess.file_exists(path):
		push_warning("%s: 파일 없음 %s" % [tag, path])
		return null
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if raw == null:
		push_warning("%s: JSON 파싱 실패 %s" % [tag, path])
		return null
	return raw


static func load_dict(path: String, tag := "JsonUtil") -> Dictionary:
	var raw: Variant = load_value(path, tag)
	return raw if raw is Dictionary else {}


static func load_array(path: String, tag := "JsonUtil") -> Array:
	var raw: Variant = load_value(path, tag)
	return raw if raw is Array else []
