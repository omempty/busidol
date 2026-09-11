class_name ChatterBank
extends RefCounted
## 잡담 은행 — 고정인물 반복 피로용 3순위 대사 풀(data/chatter.json).
##
## 왜 슬롯형 템플릿이 아니라 풀 회전인가 — 한국어 조사(은/는·이/가·을/를) 때문에
## 빈칸 채우기는 어미가 깨진다. 완성문을 역할별로 묶어 count로 돌리면 문법이 안 깨진다.
## 파이프라인도 키 참조 그대로(@c → Database.text)라 손댈 곳이 없다.
## count 기반 회전 — 같은 방문에 같은 줄, 다음 방문에 다음 줄. 랜덤 아님(감사·재현성).

const PATH := "res://data/chatter.json"
const SERVE_LINES := 2

static var _roles: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(raw) == TYPE_DICTIONARY:
		_roles = (raw as Dictionary).get("roles", {})


## 역할 풀에서 count번째 2줄. 풀이 비면 빈 배열(호출부는 기본 대사로 간다).
static func lines_for(role: String, count: int) -> Array:
	_load()
	var pool: Array = _roles.get(role, [])
	if pool.is_empty():
		return []
	var out: Array = []
	for i in SERVE_LINES:
		out.append(pool[(count + i) % pool.size()])
	return out
