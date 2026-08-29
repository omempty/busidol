extends RefCounted
## [공용] 자동 주행 뼈대 — **게임을 스스로 끝까지 몰아 본다.**
##
## 설치: 이 파일을 각 프로젝트의 `tools/lib/autoplay_driver.gd` 로 복사하고,
## 프로젝트마다 **어댑터**(아래 규약)를 하나 쓴다. 어댑터가 게임을 알고,
## 이 파일은 「어떻게 몰아붙일 것인가」만 안다.
##
## ---------------------------------------------------------------------------
## 왜 이런 것이 필요한가
## ---------------------------------------------------------------------------
##
## 검사에는 층이 있고, **위 두 층은 통과하는데 게임은 막혀 있는** 일이 흔하다.
##
##   1. 정적 검사   좌표·참조·스키마가 말이 되는가          (파일만 읽는다)
##   2. 단품 실행   이벤트/기능이 **혼자서는** 도는가        (매번 초기화한다)
##   3. 연속 주행   한 판으로 **이어 붙는가**                ← 이 파일
##
## 2층은 매번 새 게임으로 되돌리므로 **순서와 누적 상태를 못 본다.** 앞이 열어야
## 뒤가 열리는 문, 두 번 찾아가야 넘어가는 대화, 특정 상태에서만 뜨는 통로가
## 전부 사각지대다. 실제로 어느 프로젝트에서 1·2층을 다 통과한 채
## **새 게임에서 첫 마을 밖으로 나갈 수 없던** 일이 있었다.
##
## ---------------------------------------------------------------------------
## 어댑터 규약 (프로젝트가 구현한다)
## ---------------------------------------------------------------------------
##
## **필수**
##
##   `autoplay_begin()`              새 판을 세운다(씬 띄우기 등). await 가능
##   `autoplay_end()`                뒷정리. await 가능
##   `autoplay_region() -> Variant`  지금 구역 식별자(맵 번호·씬 이름 등).
##                                   값이 바뀌면 드라이버가 새 구역으로 센다
##   `autoplay_fingerprint() -> String`
##                                   세상 상태 지문. **늘 변하는 값을 넣지 말 것**
##                                   (좌표·시간·경험치). 넣으면 「달라졌으니 한
##                                   바퀴 더」가 영원히 참이 된다 — 실제로 421
##                                   바퀴를 돈 적이 있다. 문을 여는 값만 넣는다
##   `autoplay_goals() -> Array`     지금 구역에서 가 볼 곳들. 각 항목은
##                                   `{"id": String, "kind": String,
##                                     "label": String, "priority": int}`.
##                                   `priority` 는 작을수록 먼저(기본 10).
##                                   **새 구역으로 나가는 목표를 낮게 준다** —
##                                   한 구역을 훑고 넘어가면 예산이 앞에서 닳는다
##   `autoplay_travel(goal) -> bool` 그 목표까지 실제로 가서 밟는다. await 가능.
##                                   못 갔으면 false (드라이버가 기록한다)
##   `autoplay_tick()`               매 프레임 부른다. 사람 대신 눌러 주는 자리 —
##                                   대사 확인·선택지·전투·죽음 처리
##
## **선택**
##
##   `autoplay_unblock() -> bool`    막혔을 때 마지막으로 열어 볼 수단
##                                   (이동 마법, 아이템 사용 등). 열었으면 true
##   `autoplay_steps() -> int`       걸음 수 같은 진행량. 보고서에만 쓴다
##   `autoplay_report_rows() -> Array` 보고서 끝에 붙일 표 줄들
##   `autoplay_alive() -> bool`      주행을 이어도 되는가(false 면 즉시 끝낸다)
##   `autoplay_last_failure() -> String`
##                                   방금 `autoplay_travel` 이 왜 실패했는가.
##                                   보고서의 「막힌 자리」에 그대로 실린다
##
## ---------------------------------------------------------------------------
## 드라이버가 하는 일
## ---------------------------------------------------------------------------
##
##   - 목표를 모아 **가까운 것부터** 밟고, 밟은 것은 소진 처리한다
##   - 구역이 바뀌면 방문 기록과 들어간 경위를 남긴다
##   - 막히면 ① `autoplay_unblock()` ② **상태가 달라졌으면 한 바퀴 더**
##     ③ 그래도 그대로면 접는다. 「달라졌을 때만」이 핵심이다
##   - 예산(목표 수·바퀴 수·시간)을 넘기면 **멈추지 말고 끝내고 보고한다**
##   - 보고서를 쓴다. **「못 갔다」만 적힌 보고서는 도구가 고장 난 것인지
##     게임이 막힌 것인지 구별해 주지 못한다** — 근거를 함께 적는다

## 연출을 그대로 기다리면 한 판에 몇십 분이 걸린다. 트윈·타이머는
## `Engine.time_scale` 을 따르므로 시간을 빨리 감는다. 끝나면 반드시 되돌린다.
##
## 120은 실측으로 고른 값이다(2026-08-29, 목표 100개를 끝내는 데 걸린 벽시계 초):
## 배율 30 → 86초, 60 → 80초, 120 → 73초, 240 → 72초. 120에서 이득이 사실상
## 끝난다 — 그 위는 **걸음 판정의 관측 주기(물리 틱)** 가 상한이라 배율만 올려도
## 걸음당 물리 프레임이 4.4 아래로 안 내려간다. 틱과 함께 올리면 오히려 깨진다
## (배율 240 × 틱 960: 물리가 초당 226밖에 안 돌아 300초 예산을 넘겼다).
const DEFAULT_TIME_SCALE := 120.0
## 안전 예산. 넘기면 멈추지 말고 끝낸다.
const DEFAULT_MAX_GOALS := 900
const DEFAULT_MAX_ROUNDS := 8
const DEFAULT_MAX_SECONDS := 900.0

var adapter: Object
var tree: SceneTree
var time_scale: float = DEFAULT_TIME_SCALE
var max_goals: int = DEFAULT_MAX_GOALS
var max_rounds: int = DEFAULT_MAX_ROUNDS
var max_seconds: float = DEFAULT_MAX_SECONDS
var verbose: bool = true

## 결과 — 보고서를 쓰거나 스모크에서 단언할 때 읽는다.
var stop_reason: String = ""
var rounds: int = 1
var visited_regions: Dictionary = {}
var region_entry_reason: Dictionary = {}
var journal: Array[String] = []
var stalls: Array[String] = []
## 실제로 흐른 벽시계 초 — 예산과 다르다(목표를 다 밟고 일찍 끝날 수 있다).
## 속도를 예산으로 나누면 일찍 끝난 주행일수록 느려 보인다. 잴 때는 이 값을 쓴다.
var elapsed: float = 0.0

var _consumed: Dictionary = {}
var _last_fingerprint: String = ""
var _running := false
var _started_at := 0.0


func _init(autoplay_adapter: Object, scene_tree: SceneTree) -> void:
	adapter = autoplay_adapter
	tree = scene_tree


## 주행을 처음부터 끝까지 돌린다. 끝나면 `stop_reason` 에 이유가 남는다.
func run() -> void:
	var missing := _missing_methods()
	if not missing.is_empty():
		stop_reason = "어댑터에 없는 메서드: %s" % ", ".join(missing)
		push_error(stop_reason)
		return

	var previous_scale := Engine.time_scale
	Engine.time_scale = time_scale
	_running = true
	_started_at = Time.get_ticks_msec() / 1000.0
	await adapter.call("autoplay_begin")
	_watchdog()
	_mark_region("주행 시작")
	await _travel()
	_running = false
	elapsed = Time.get_ticks_msec() / 1000.0 - _started_at
	await adapter.call("autoplay_end")
	Engine.time_scale = previous_scale


func _missing_methods() -> Array[String]:
	var missing: Array[String] = []
	for name in [
		"autoplay_begin",
		"autoplay_end",
		"autoplay_region",
		"autoplay_fingerprint",
		"autoplay_goals",
		"autoplay_travel",
		"autoplay_tick"
	]:
		if not adapter.has_method(name):
			missing.append(name)
	return missing


# ---------------------------------------------------------------------------
# 주행 고리
# ---------------------------------------------------------------------------


func _travel() -> void:
	while true:
		if not _within_budget():
			return
		if adapter.has_method("autoplay_alive") and not bool(adapter.call("autoplay_alive")):
			stop_reason = "어댑터가 주행을 끝냈다 (씬이 사라졌거나 게임이 끝났다)"
			return

		var goal := _pick_goal()
		if goal.is_empty():
			if await _try_to_get_unstuck():
				continue
			stop_reason = "더 갈 곳이 없다 (%s)" % _diagnose()
			return

		if verbose:
			print(
				(
					"  [%s] 구역 %s -> %s %s"
					% [
						_progress_label(),
						str(_region()),
						String(goal.get("kind", "")),
						String(goal.get("id", ""))
					]
				)
			)
		await _pursue(goal)


func _within_budget() -> bool:
	if _consumed.size() >= max_goals:
		stop_reason = "예산 소진 (목표 %d개)" % _consumed.size()
		return false
	var spent := Time.get_ticks_msec() / 1000.0 - _started_at
	if spent >= max_seconds:
		stop_reason = "예산 소진 (%.0f초)" % spent
		return false
	return true


## 아직 안 밟은 목표 중 `priority` 가 낮고 먼저 나온 것.
func _pick_goal() -> Dictionary:
	var best: Dictionary = {}
	var best_priority := 1 << 30
	for goal_variant: Variant in adapter.call("autoplay_goals"):
		var goal: Dictionary = goal_variant
		if _consumed.has(_key(goal)):
			continue
		var priority := int(goal.get("priority", 10))
		if priority < best_priority:
			best = goal
			best_priority = priority
	return best


func _pursue(goal: Dictionary) -> void:
	var region_before: Variant = _region()
	_consumed[_key(goal)] = true
	var reached: bool = await adapter.call("autoplay_travel", goal)
	if reached:
		journal.append(
			(
				"| %s | %s | %s | %s |"
				% [
					str(region_before),
					String(goal.get("id", "")),
					String(goal.get("kind", "")),
					String(goal.get("label", ""))
				]
			)
		)
	else:
		# **어댑터가 사유를 말해 주면 그것을 적는다.** 「가지 못했다」만 적힌
		# 보고서는 도구가 고장 난 것인지 게임이 막힌 것인지 구별해 주지 못한다.
		var reason := "가지 못했다"
		if adapter.has_method("autoplay_last_failure"):
			var detail := String(adapter.call("autoplay_last_failure"))
			if not detail.is_empty():
				reason = detail
		stalls.append(
			(
				"| %s | %s | %s | %s |"
				% [
					str(region_before),
					String(goal.get("id", "")),
					String(goal.get("kind", "")),
					reason
				]
			)
		)
	if _region() != region_before:
		_mark_region("%s %s" % [String(goal.get("kind", "")), String(goal.get("id", ""))])


## 막혔다. 두 가지를 차례로 해 본다.
##
## ① 어댑터가 아는 마지막 수단(이동 마법·아이템 등)
## ② **상태가 달라졌으면 한 바퀴 더.** 되돌아가야 열리는 자리가 흔하다 —
##    두 번째로 말을 걸어야 넘어가는 대화 같은 것. 그대로면 몇 바퀴를 더
##    돌아도 같은 자리에서 막히므로 접는다.
func _try_to_get_unstuck() -> bool:
	if adapter.has_method("autoplay_unblock") and await adapter.call("autoplay_unblock"):
		return true
	if rounds >= max_rounds:
		return false
	var now := String(adapter.call("autoplay_fingerprint"))
	if now == _last_fingerprint:
		return false
	_last_fingerprint = now
	rounds += 1
	_consumed.clear()
	if verbose:
		print("  --- %d 바퀴째: 상태가 달라졌다, 다시 돈다 ---" % rounds)
	return true


func _diagnose() -> String:
	var goals: Array = adapter.call("autoplay_goals")
	var left := 0
	for goal_variant: Variant in goals:
		if not _consumed.has(_key(goal_variant)):
			left += 1
	return "구역 %s: 목표 %d개 중 남은 것 %d개 / %d 바퀴 돌았다" % [str(_region()), goals.size(), left, rounds]


# ---------------------------------------------------------------------------
# 사람 대신 앉아 있는 감시자
# ---------------------------------------------------------------------------


## **띄워 두고 기다리지 않는** 코루틴이다. 주행이 끝날 때까지 매 프레임 돈다.
## 여기서 막힌 화면을 풀어 주지 않으면 주행이 한 자리에서 멈춘다 —
## **스모크든 주행이든 멈추는 것이 가장 나쁘다.** 멈추지 말고 실패하게 한다.
func _watchdog() -> void:
	while _running:
		await tree.process_frame
		if not _running:
			return
		adapter.call("autoplay_tick")


# ---------------------------------------------------------------------------
# 기록
# ---------------------------------------------------------------------------


func _region() -> Variant:
	return adapter.call("autoplay_region")


func _key(goal: Variant) -> String:
	return "%s:%s" % [str(_region()), String(Dictionary(goal).get("id", ""))]


func _mark_region(reason: String) -> void:
	var region: Variant = _region()
	if visited_regions.has(region):
		return
	visited_regions[region] = true
	region_entry_reason[region] = reason


func _progress_label() -> String:
	if adapter.has_method("autoplay_steps"):
		return "%5d걸음" % int(adapter.call("autoplay_steps"))
	return "%4d목표" % _consumed.size()


# ---------------------------------------------------------------------------
# 보고서
# ---------------------------------------------------------------------------


## 사람이 읽을 보고서. `extra_regions` 로 「닿았어야 하는 구역 전부」를 주면
## **도달하지 못한 구역**을 따로 뽑아 준다 — 그게 대개 가장 중요한 표다.
func build_report(title: String, all_regions: Array = []) -> String:
	var lines: Array[String] = [
		"# %s" % title,
		"",
		"**한 판을 이어서 자동으로 몰아 본 결과다.** 생성기: 자동 주행 도구",
		"(`_godot_shared/godot/autoplay/autoplay_driver.gd` + 프로젝트 어댑터).",
		"",
		"정적 검사와 단품 실행은 **순서와 누적 상태를 못 본다.** 앞이 열어야 뒤가",
		"열리는 문, 두 번 찾아가야 넘어가는 대화가 그 사각지대다. 여기서는 새 판",
		"하나로 시작해 되돌리지 않고 실제로 몰아 본다.",
		"",
		"## 요약",
		"",
		"| 항목 | 값 |",
		"|---|---|",
		"| 끝난 이유 | %s |" % stop_reason,
		"| 밟은 목표 | %d |" % _consumed.size(),
		"| 다시 돈 바퀴 | %d |" % rounds,
		(
			"| 닿은 구역 | %d%s |"
			% [
				visited_regions.size(),
				(" / %d" % all_regions.size()) if not all_regions.is_empty() else ""
			]
		),
	]
	if adapter.has_method("autoplay_steps"):
		lines.append("| 걸음 | %d |" % int(adapter.call("autoplay_steps")))
	if adapter.has_method("autoplay_report_rows"):
		for row_variant: Variant in adapter.call("autoplay_report_rows"):
			lines.append(String(row_variant))
	lines.append("")

	if not all_regions.is_empty():
		var unreached: Array[String] = []
		for region_variant: Variant in all_regions:
			if not visited_regions.has(region_variant):
				unreached.append("| %s |" % str(region_variant))
		lines.append("## 닿지 못한 구역")
		lines.append("")
		if unreached.is_empty():
			lines.append("없음 — 전부 닿았다.")
		else:
			lines.append("**여기가 가장 중요한 표다.** 앞 단계가 열어야 하는 문이")
			lines.append("안 열렸거나, 연결이 데이터에만 있고 런타임에 없거나,")
			lines.append("예산이 먼저 닳았다.")
			lines.append("")
			lines.append("| 구역 |")
			lines.append("|---|")
			lines.append_array(unreached)
		lines.append("")

	lines.append("## 닿은 구역과 들어간 경위")
	lines.append("")
	lines.append("| 구역 | 들어간 경위 |")
	lines.append("|---|---|")
	var visited: Array = visited_regions.keys()
	visited.sort()
	for region_variant: Variant in visited:
		lines.append(
			(
				"| %s | %s |"
				% [str(region_variant), String(region_entry_reason.get(region_variant, ""))]
			)
		)
	lines.append("")

	lines.append("## 막힌 자리")
	lines.append("")
	if stalls.is_empty():
		lines.append("없음.")
	else:
		lines.append("갈 수 있다고 본 곳인데 실제로는 못 갔다.")
		lines.append("")
		lines.append("| 구역 | 목표 | 종류 | 증상 |")
		lines.append("|---|---|---|---|")
		lines.append_array(stalls)
	lines.append("")

	lines.append("## 밟은 목표 (순서대로)")
	lines.append("")
	lines.append("| 구역 | 목표 | 종류 | 이름 |")
	lines.append("|---|---|---|---|")
	lines.append_array(journal)
	lines.append("")
	return "\n".join(lines)


func write_report(path: String, title: String, all_regions: Array = []) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("보고서를 쓰지 못했다: %s" % path)
		return
	file.store_string(build_report(title, all_regions))
	file.close()
	print("-> %s" % path)
