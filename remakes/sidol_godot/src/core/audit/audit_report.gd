class_name AuditReport
extends RefCounted
## 월드 감사 결과 수집기 — 프루브들이 공유하는 기록 창구.
## FAIL=반드시 고칠 위반 · WARN=사람이 판단할 사항 · OK=검사했고 이상 없음.
## 같은 종류의 위반이 수백 건 나올 수 있으므로 항목별 상한을 두고 나머지는 수만 센다.

const MAX_DETAIL := 6

var fails: int = 0
var warns: int = 0
var lines: PackedStringArray = []

var _scope := ""
var _counts: Dictionary = {}  # "레벨|검사명" -> 출력한 상세 수
var _waivers: Array = []
var _waiver_hits: Dictionary = {}


## 보류 목록 적재 — 코드로는 해결할 수 없다고 판단해 사유를 적어 둔 항목.
## 관문이 상시 빨간불이면 아무도 보지 않게 된다. 대신 사유와 날짜를 남기고,
## 더 이상 발생하지 않는 보류는 "낡음"으로 보고해 목록이 썩지 않게 한다.
func load_waivers(path: String) -> void:
	_waivers = JsonUtil.load_dict(path, "AuditReport").get("waivers", [])


func scope(name: String) -> void:
	_scope = name


func ok(check: String, detail: String = "") -> void:
	lines.append("  [ok]   %-22s %s" % [check, detail])


func warn(check: String, detail: String) -> void:
	# WARN도 보류 대상이다 — 원작 데이터에 기인해 영영 안 없어지는 항목이 상시 21건 쌓이면
	# 새로 생긴 WARN이 그 속에 묻힌다. 대신 사유·근거를 known_issues.json에 적게 한다.
	if _try_waive(check, detail):
		return
	warns += 1
	_emit("WARN", check, detail)


func fail(check: String, detail: String) -> void:
	if _try_waive(check, detail):
		return
	fails += 1
	_emit("FAIL", check, detail)


## 보류 목록에 있으면 [KNOWN]으로 강등하고 true. 적중 기록은 낡은 보류 판정에 쓴다.
func _try_waive(check: String, detail: String) -> bool:
	var w := _waiver_index(check, detail)
	if w < 0:
		return false
	_waiver_hits[w] = int(_waiver_hits.get(w, 0)) + 1
	lines.append(
		"  [KNOWN] %-20s %s%s — %s" % [check, _prefix(), detail, _waivers[w].get("reason", "")]
	)
	return true


func _waiver_index(check: String, detail: String) -> int:
	for i in _waivers.size():
		var w: Dictionary = _waivers[i]
		if str(w.get("scope", "")) != _scope or str(w.get("check", "")) != check:
			continue
		if detail.contains(str(w.get("detail", ""))):
			return i
	return -1


## 한 번도 걸리지 않은 보류 — 문제가 사라졌거나 항목이 낡았다는 신호.
func stale_waivers() -> PackedStringArray:
	var out := PackedStringArray()
	for i in _waivers.size():
		if not _waiver_hits.has(i):
			var w: Dictionary = _waivers[i]
			out.append(
				(
					"  [WARN] 낡은 보류            %s/%s %s — 더 이상 발생하지 않음(삭제 검토)"
					% [w.get("scope", "?"), w.get("check", "?"), w.get("detail", "")]
				)
			)
	return out


## 같은 검사에서 반복되는 위반을 접어 준다. 상한 초과분은 마지막에 총량으로 보고.
func _emit(level: String, check: String, detail: String) -> void:
	var key := "%s|%s|%s" % [level, _scope, check]
	var n := int(_counts.get(key, 0))
	_counts[key] = n + 1
	if n < MAX_DETAIL:
		lines.append("  [%s] %-22s %s%s" % [level, check, _prefix(), detail])
	elif n == MAX_DETAIL:
		lines.append("  [%s] %-22s %s... (이하 생략)" % [level, check, _prefix()])


func _prefix() -> String:
	return "" if _scope.is_empty() else "(%s) " % _scope


## 상한에 걸려 접힌 항목의 실제 총량.
func summary_tail() -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in _counts:
		var n: int = _counts[key]
		if n > MAX_DETAIL:
			var parts := key.split("|")
			out.append("  · %s %s/%s ×%d건" % [parts[0], parts[1], parts[2], n])
	return out
