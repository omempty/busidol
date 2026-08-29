extends Node
## 자동 주행 — **새 판 하나로 시작해 되돌리지 않고** 끝까지 몰아 본다(헤드리스).
##
## 실행: godot --headless --path . res://tools/dev/autoplay.tscn --
##       [--seconds N] [--goals N] [--require-floors N]
## 결과: docs/05_status/01_autoplay.md
## 관문으로 쓸 때는 `--require-floors` 로 **최소 몇 층까지 걸어서 닿아야 하는가**를 건다.
##
## 여기 있는 것은 **시돌이 어댑터**뿐이다. 몰아붙이는 뼈대는 공용 모듈에 있다.
##   tools/lib/autoplay_driver.gd  목표 고르기·막힘 처리·다시 한 바퀴·예산·보고서
##   tools/dev/autoplay_map.gd     길찾기(BFS) — 걸음과 문 통과를 같이 본다
##   tools/dev/autoplay_goals.gd   무엇이 목표인가(계단·트리거·NPC·상자)
##   tools/dev/autoplay_pilot.gd   어떻게 누르는가(폴링·이벤트 두 경로)
##   tools/dev/autoplay_log.gd     무엇을 세고 무엇을 표로 남기는가
##
## 기존 관문과 무엇이 다른가 — smoke_*와 world_audit은 검사할 상태를 **손으로 세운다**
## (`GameState.flags["Q_F1_START"] = true`, `GameState.current_floor = f`). 그래서
## "앞 단계가 실제로 그 문을 여는가"는 아무도 안 본다. 여기서는 아무것도 세워 주지
## 않고 새 판에서 걸어서 간다. 못 가면 못 간 채로 보고한다.
##
## 짝이 되는 도구: `autoplay_sweep.gd` — **데려다 놓으면** 그 층 내용이 도는가.
## 이쪽만 있으면 막힌 뒤의 층을 영영 못 보고, 그쪽만 있으면 "내용은 도는데 갈 길이
## 없는" 층을 못 잡는다.

const AutoplayDriver := preload("res://tools/lib/autoplay_driver.gd")
const AutoplayGoals := preload("res://tools/dev/autoplay_goals.gd")
const AutoplayLog := preload("res://tools/dev/autoplay_log.gd")
const AutoplayMap := preload("res://tools/dev/autoplay_map.gd")
const AutoplayPilot := preload("res://tools/dev/autoplay_pilot.gd")

const FIELD_SCENE := "res://scenes/field.tscn"
## 타이틀 — 여기로 나왔으면 한 판이 끝난 것이다(엔딩 뒤 돌아오는 자리).
const TITLE_SCENE := "res://scenes/main.tscn"
const OUT_PATH := "res://docs/05_status/01_autoplay.md"
const ALL_FLOORS := [0, 1, 2, 3, 4, 5]

## 조사 앵커를 찾는 창 반경 — 2×2 몸에 전방 2셀이라 목표에서 두 칸을 넘지 않는다.
const APPROACH_WINDOW := 3
const DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
## 문 한 번에 건너뛰는 칸 수 — TransitionGate._try_door와 같은 규약.
const DOOR_JUMP := 3
## 씬 전환(전투 진입·복귀)을 기다릴 상한. 전투가 서 있는 동안은 세지 않는다.
const SCENE_FRAMES := 600
## 전투가 아무리 길어도 여기까지 — 이걸 넘기면 전투가 끝나지 않는 것이다.
const BATTLE_FRAMES := 24000
## 목표 하나에 길을 다시 짜 볼 횟수. 가는 길에 전투·문이 끼어들면 경로가 낡는다.
const TRAVEL_ATTEMPTS := 3
## 발동 결과가 나타나기를 기다릴 상한.
const EFFECT_FRAMES := 240
## 대사·컷신이 끝나기를 기다릴 상한. 넘기면 손을 대고 기록한다.
const SETTLE_FRAMES := 3000
## 초당 물리 틱 — 기본 60. 걸음 판정의 관측 주기라 주행 속도를 그대로 정한다.
## `--ticks` 로 올릴 수 있다. 올릴수록 걸음이 촘촘히 관측되지만 한 프레임이
## 삼켜야 할 스텝 수도 같이 늘어 프레임률이 떨어진다 — 그래서 실측으로 고른다.
## 240은 실측으로 고른 값이다(2026-08-29, 배율 120에서 목표 100개까지의 벽시계 초):
## 틱 240 → 73초, 480 → 70초, 960 → 48~83초로 요동, 1920 → 49초. 480 위쪽의 이득은
## 재현되지 않는 데다 **동시 실행을 못 견딘다** — 층 훑기를 두 프로세스로 돌리자
## 틱 480 설정에서 물리가 초당 172밖에 안 돌았다. 240은 같은 속도에 여유가 크다.
const PHYSICS_TICKS := 240

var _log: AutoplayLog
var _pilot: AutoplayPilot
var _goals: AutoplayGoals
var _nav: AutoplayMap

var _failure := ""  # 방금 travel이 실패한 사유 — 드라이버가 「막힌 자리」에 싣는다
var _effective := true
var _reached := 0  # 밟은 목표 누적(드라이버 쪽 수치는 바퀴마다 초기화된다)

var _nav_stamp := ""
var _reach: Dictionary = {}
var _reach_key := ""
var _cand: Array = []
var _cand_stamp := ""


func _ready() -> void:
	if get_tree().current_scene == self:
		# 나는 부팅 껍데기다. 전투·엔딩은 change_scene_to_file로 **현재 씬을 지운다** —
		# 주행자가 현재 씬이면 첫 전투에서 도구가 통째로 사라진다. root 밑에 따로 세운다.
		var runner: Node = (get_script() as GDScript).new()
		runner.name = "AutoplayRunner"
		get_tree().root.add_child.call_deferred(runner)
		return
	await _run()


func _run() -> void:
	_setup()
	var driver := AutoplayDriver.new(self, get_tree())
	driver.max_seconds = _arg("--seconds", 600.0)
	driver.max_goals = int(_arg("--goals", 400.0))
	driver.time_scale = _arg("--scale", driver.time_scale)
	print("[autoplay] start (예산 %.0f초 / 목표 %d개)" % [driver.max_seconds, driver.max_goals])
	await driver.run()
	_write_report(driver)
	print("")
	print("=== 자동 주행 끝: %s ===" % driver.stop_reason)
	_print_pace(driver.elapsed)
	print(
		(
			"걸음 %d / 층 %d / 전투 %d / 상자 %d / 대사 %d / 사망복구 %d"
			% [
				_log.steps,
				driver.visited_regions.size(),
				_log.battles,
				_log.chests,
				_log.dialogues,
				_log.revivals,
			]
		)
	)
	get_tree().quit(_exit_code(driver))


## 주행이 왜 그 속도인가 — 프레임을 어디서 기다렸는지 나눠 찍는다.
## 걸음은 물리 프레임에서 판정되므로 **초당 물리 프레임이 곧 주행 속도의 상한**이다.
## `Engine.time_scale`은 물리 델타만 키우고 초당 스텝 수는 안 바꾼다(실측).
## 「물리 초당」이 설정 틱에 못 미치는 것 자체는 결함이 아니다 — 빨리 감기가 걸려
## 있으면 한 프레임이 삼켜야 할 스텝 수가 프레임률에 달리고, 전투·컷신처럼 무거운
## 구간에서는 당연히 내려간다(실측: 같은 관문 주행이 틱 240에서도 480에서도
## **걸음 초당 18.7로 같았다**). 그래서 설정 대비 경고는 늑대 소년이 된다.
## 고를 때 보는 수치는 하나다 — **경과 초와 걸음 초당.**
func _print_pace(seconds: float) -> void:
	var span := maxf(seconds, 0.001)
	var steps := maxf(float(_log.steps), 1.0)
	print("경과 %.1f초 / 걸음 초당 %.1f" % [seconds, steps / span])
	var other := _log.physics_frames - _log.step_frames - _log.still_frames
	print(
		(
			"프레임 %d(초당 %.0f) / 물리 %d(초당 %.0f) / 배율 %.0f(최저 %.2f) / 틱 %d"
			% [
				_log.frames,
				float(_log.frames) / span,
				_log.physics_frames,
				float(_log.physics_frames) / span,
				_log.scale_seen,
				_log.scale_min,
				Engine.physics_ticks_per_second,
			]
		)
	)
	print(
		(
			"걸음당 물리 %.1f = 걸음대기 %.1f + 정지대기 %.1f + 나머지 %.1f"
			% [
				float(_log.physics_frames) / steps,
				float(_log.step_frames) / steps,
				float(_log.still_frames) / steps,
				float(other) / steps,
			]
		)
	)


func _setup() -> void:
	# **빨리 감기의 진짜 상한은 물리 틱 수다.** `Engine.time_scale`은 물리 델타만 키우고
	# 초당 물리 스텝 수는 60 그대로다(2026-08-29 실측: 배율 30인데 물리 초당 61).
	# 걸음은 물리 프레임에서 판정되고 도구는 그 프레임을 기다리므로, 틱을 올리지 않으면
	# 배율을 아무리 올려도 초당 7걸음에 묶인다. 틱을 올리면 관측 지점이 그만큼 촘촘해진다.
	# 스텝 상한도 같이 올린다 — 프레임당 필요한 스텝 수(틱/프레임률)를 넘어야 한다.
	var ticks := int(_arg("--ticks", PHYSICS_TICKS))
	Engine.physics_ticks_per_second = ticks
	# 스텝 상한은 틱과 함께 올린다. 상한이 모자라면 남은 스텝을 다음 프레임으로
	# 미루므로 틱만 올리고 여기를 두면 **초당 물리 프레임이 설정값에 못 미친다.**
	Engine.max_physics_steps_per_frame = ticks
	_log = AutoplayLog.new()
	_pilot = AutoplayPilot.new(get_tree(), _log)
	_goals = AutoplayGoals.new()


## 관문 판정. **보고서 내용으로 실패시키지 않는다** — 사문화 데이터는 world_audit이
## 보류 목록과 함께 다루는 몫이다. 여기서 잡는 것은 "새 판에서 걸을 수조차 없다",
## "층을 넘어갈 수 없다" 같은 **주행 자체의 퇴행**이다.
func _exit_code(driver: AutoplayDriver) -> int:
	if _log.steps <= 0:
		push_error("[autoplay] 한 걸음도 걷지 못했다 — 새 게임이 조작 불가 상태다")
		return 1
	var need := int(_arg("--require-floors", 0.0))
	var reached := driver.visited_regions.size()
	if reached < need:
		push_error("[autoplay] 걸어서 닿은 층 %d < 요구 %d — 층 전환이 막혔다" % [reached, need])
		return 1
	return 0


# ---------------------------------------------------------------------------
# 어댑터 — 판 세우기
# ---------------------------------------------------------------------------


## 새 게임. 타이틀의 "새로 시작"과 같은 경로(main.gd _confirm)다.
func autoplay_begin() -> void:
	GameState.reset()
	GameState.inventory = Inventory.new()
	get_tree().change_scene_to_file(FIELD_SCENE)
	_log.scale_seen = Engine.time_scale  # 드라이버가 걸어 둔 빨리 감기 배율
	_count_physics_frames()
	if await _wait_for_field():
		await _settle()  # 프롤로그 컷신 — 끝나기 전에 걸으려 하면 전부 "못 갔다"가 된다


## 물리 프레임을 센다 — 띄워 두고 기다리지 않는 코루틴. 주행이 느릴 때
## "CPU가 모자란가, 프레임이 안 오는가"를 가르는 유일한 수치다.
func _count_physics_frames() -> void:
	while is_inside_tree():
		await get_tree().physics_frame
		_log.physics_frames += 1
		# 배율은 주행 중에 남이 덮어쓸 수 있다(전투 히트스톱). 최솟값을 남긴다.
		if _log.scale_min <= 0.0 or Engine.time_scale < _log.scale_min:
			_log.scale_min = Engine.time_scale


func autoplay_end() -> void:
	_pilot.settle()
	await get_tree().process_frame


## 엔딩으로 나갔으면 주행은 끝이다(더 몰 판이 없다).
##
## **타이틀도 끝이다.** 엔딩이 끝나면 게임은 타이틀로 돌아오는데, 여기서 그것을
## 안 보다가 「더 갈 곳이 없다」로 접었다 — 처음으로 한 판을 완주한 주행이
## 실패처럼 보고됐다(2026-08-29). TITLE_SCENE 상수는 선언만 돼 있고 아무도 안
## 읽고 있었다: 이 저장소의 지배적 결함(사문화 데이터)이 도구에서 재현된 자리다.
func autoplay_alive() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return true  # 씬 교체 중
	var path := scene.scene_file_path
	return not (path.ends_with("ending_console.tscn") or path == TITLE_SCENE)


func autoplay_region() -> Variant:
	return GameState.current_floor


func autoplay_steps() -> int:
	return _log.steps


func autoplay_last_failure() -> String:
	return _failure


## 마지막 목표가 **실제로 무언가를 일으켰는가.** 드라이버는 이 값이 거짓이면
## 그 목표를 소진 처리하지 않고, 세상이 달라졌을 때 다시 데려간다 — 재료를 얻기
## 전에 조합 트리거를 건드린 경우가 그렇다(f2_poster를 HP실보다 먼저 밟는다).
func autoplay_effective() -> bool:
	return _effective


## 세상 상태 지문. **좌표·HP·경험치·돈은 넣지 않는다** — 걸을 때마다 달라져서
## "달라졌으니 한 바퀴 더"가 영원히 참이 된다. 문을 여는 것은 플래그와 상자다.
func autoplay_fingerprint() -> String:
	var on: Array[String] = []
	var keys: Array = GameState.flags.keys()
	keys.sort()
	for k: Variant in keys:
		if GameState.has_flag(str(k)):
			on.append(str(k))
	return (
		"층%s|상자%d|기술%d|플래그%s"
		% [
			str(GameState.visited_list()),
			_chest_count(),
			GameState.owned_skill_ids().size(),
			",".join(on),
		]
	)


## 드라이버의 "밟은 목표"는 바퀴마다 초기화된다 — 누적치를 따로 싣는다.
func autoplay_report_rows() -> Array:
	var rows: Array = ["| 밟은 목표(누적) | %d |" % _reached]
	rows.append_array(_log.summary_rows())
	return rows


# ---------------------------------------------------------------------------
# 어댑터 — 무엇이 목표인가
# ---------------------------------------------------------------------------


## 지금 층에서 가 볼 곳. **실제로 붙을 수 있는 것만** 낸다 — 못 가는 것을 목표로
## 내면 드라이버가 "갔다 치고" 소진해 버린다. 못 가는 것은 대신 보고서에 남긴다.
func autoplay_goals() -> Array:
	var field := _field()
	if field == null:
		return []
	var player: PlayerEntity = field.get_player()
	if player == null or not player.is_inside_tree():
		return []
	var reach := _reachable(field, player)
	var out: Array = []
	for candidate: Dictionary in _candidates(field):
		if _spent(candidate):
			continue
		var approach := _approach(player, reach, candidate)
		var id := String(candidate["id"])
		if approach.is_empty():
			_log.mark_unreachable(
				GameState.current_floor,
				id,
				String(candidate["kind"]),
				String(candidate["label"]),
				candidate["cell"]
			)
			continue
		_log.mark_reachable(GameState.current_floor, id)
		var goal := candidate.duplicate()
		goal["approach"] = approach
		goal["priority"] = int(candidate["rank"]) + int(approach["distance"])
		out.append(goal)
	return out


## 이미 소진된 목표인가 — 연 상자, 켜진 플래그. 후보 목록은 층마다 한 번만 짓고
## 달라지는 것은 여기서 걸러 낸다(목록을 매번 다시 짓는 것이 비싸다).
func _spent(candidate: Dictionary) -> bool:
	var expect: Dictionary = candidate["expect"]
	if expect.has("chest"):
		return GameState.chest_overrides_for(GameState.current_floor).has(expect["chest"])
	var flag := String(expect.get("flag", ""))
	return not flag.is_empty() and GameState.has_flag(flag)


## 그 목표에 어떻게 붙을 것인가. stand는 그 칸에 올라서고, face는 **전방 판정이 그
## 칸을 집는 앵커**에 선다. 조사 판정 셀은 게임의 `InteractProbe`에 그대로 묻는다 —
## 몸이 2×2라 "옆 칸"이 한 칸 옆이 아니다.
func _approach(player: PlayerEntity, reach: Dictionary, candidate: Dictionary) -> Dictionary:
	var cell: Vector2i = candidate["cell"]
	if String(candidate["mode"]) == "stand":
		if not reach.has(cell):
			return {}
		return {"anchor": cell, "dir": Vector2i.ZERO, "distance": int(reach[cell])}

	var best: Dictionary = {}
	var best_distance := 1 << 30
	for dy in range(-APPROACH_WINDOW, APPROACH_WINDOW + 1):
		for dx in range(-APPROACH_WINDOW, APPROACH_WINDOW + 1):
			var anchor := cell + Vector2i(dx, dy)
			if not reach.has(anchor):
				continue
			var distance := int(reach[anchor])
			if distance >= best_distance:
				continue
			for dir: Vector2i in DIRS:
				if cell in InteractProbe.probe_cells(player.mover, anchor, dir):
					best = {"anchor": anchor, "dir": dir, "distance": distance}
					best_distance = distance
					break
	return best


# ---------------------------------------------------------------------------
# 어댑터 — 어떻게 걷는가
# ---------------------------------------------------------------------------


## 목표까지 실제로 걸어가 밟는다. 순간이동은 쓰지 않는다 — 쓰는 순간
## "갈 수 있는가"라는 질문 자체가 사라진다.
func autoplay_travel(goal: Dictionary) -> bool:
	_failure = ""
	_effective = true
	await _settle()  # 대사·컷신이 조작을 쥐고 있으면 한 걸음도 못 걷는다
	if not await _walk_to(goal):
		return false
	_reached += 1
	var fired := await _provoke(goal)
	if not fired:
		_log.mark_dead(
			GameState.current_floor, String(goal["kind"]), String(goal["label"]), goal["cell"]
		)
	await _settle()
	# **계단은 층이 바뀌어야 밟은 것이다.** 앵커까지 걸어갔다는 사실만으로 성공을
	# 돌려주면 잠긴 계단이 한 번 만에 소진돼, 나중에 게이트 플래그가 서도 드라이버가
	# 다시 데려가지 않았다(2026-08-29 F3~F5 미도달). 다른 목표는 종전대로 —
	# 닿았는데 아무 일도 없었다는 것 자체가 재려는 값이라 실패로 접으면 안 된다.
	_effective = fired
	if not fired and Dictionary(goal["expect"]).has("floor"):
		_failure = "계단 앵커에는 섰으나 층이 바뀌지 않았다 — %s" % String(goal["label"])
		return false
	return true


func _walk_to(goal: Dictionary) -> bool:
	var anchor: Vector2i = Dictionary(goal["approach"])["anchor"]
	var floor_before: int = GameState.current_floor
	for _attempt in TRAVEL_ATTEMPTS:
		if not await _wait_for_field():
			_failure = "필드가 서지 않는다 — 전투에서 돌아오지 못했다"
			return false
		var field := _field()
		var player: PlayerEntity = field.get_player()
		if player.mover.grid_pos == anchor:
			return true
		var path := _path_to(field, player, anchor)
		if path.is_empty():
			var here := str(player.mover.grid_pos)
			_failure = "길이 끊겼다 — %s에서 %s까지 경로가 없다" % [here, str(anchor)]
			return false
		var stopped_at := player.mover.grid_pos
		if await _follow(path):
			return true
		if GameState.current_floor != floor_before:
			_failure = "가는 길에 층이 바뀌었다 (f%d → f%d)" % [floor_before, GameState.current_floor]
			return false
		_failure = "걷다가 막혔다 — %s 부근에서 한 걸음이 나가지 않았다" % str(stopped_at)
	return false


func _path_to(field: Node2D, player: PlayerEntity, anchor: Vector2i) -> Array:
	return _nav.path_to(_reachable(field, player), anchor)


func _follow(path: Array) -> bool:
	var field := _field()
	if field == null:
		return false
	var player: PlayerEntity = field.get_player()
	for cell_variant: Variant in path:
		var cell: Vector2i = cell_variant
		if not is_instance_valid(player) or not player.is_inside_tree():
			return false
		var delta := cell - player.mover.grid_pos
		if delta == Vector2i.ZERO:
			continue
		# 걸음은 한 칸, 문 통과는 위아래로 세 칸(TransitionGate._try_door).
		var door := delta.x == 0 and absi(delta.y) == DOOR_JUMP
		if not door and absi(delta.x) + absi(delta.y) != 1:
			return false  # 경로에서 벗어났다(문·전투) — 부른 쪽이 다시 짠다
		var dir := Vector2i(signi(delta.x), signi(delta.y))
		_log.steps += 1
		if not await _pilot.step_to(player, dir, cell, door):
			# **여기서 다시 확인해야 한다.** step_to 안에서 전투가 끼어들면 판이
			# 통째로 사라지고 player 는 이미 해제된 객체다. still()의 인자 형이
			# PlayerEntity 라 몸통의 is_instance_valid 검사에 닿기도 전에 형 검사가
			# 터진다(2026-08-29 관문 로그 8건).
			if is_instance_valid(player):
				await _pilot.still(player)
			return false
	# 길 끝에서만 멈춰 선다 — 그 다음이 조사(방향 잡기)라 서 있어야 한다.
	if is_instance_valid(player):
		await _pilot.still(player)
	return true


## 목표를 실제로 건드리고 **결과가 났는지** 본다. 여기가 사문화 데이터 탐지기다 —
## 닿는 데 성공했는데 아무 일도 안 일어나면 그 데이터는 게임에 없는 것과 같다.
func _provoke(goal: Dictionary) -> bool:
	var field := _field()
	if field == null:
		return false
	var player: PlayerEntity = field.get_player()
	if player == null:
		return false
	var expect: Dictionary = goal["expect"]
	var dir: Vector2i = Dictionary(goal["approach"])["dir"]
	if String(goal["mode"]) == "face" and dir != Vector2i.ZERO:
		await _aim(player, dir, bool(goal.get("passable", false)))

	if expect.has("floor"):
		var want_floor := int(expect["floor"])
		_pilot.press(&"move_down")
		var changed := await _until(func() -> bool: return GameState.current_floor == want_floor)
		_pilot.release(&"move_down")
		return changed
	if String(goal["mode"]) == "face":
		await _pilot.tap(&"interact")
	if expect.has("chest"):
		# **어느 상자든 열렸으면 조사는 먹힌 것이다.** 원작 상자는 가로 2셀씩 나란히
		# 깔려 있어 전방 2셀에 다른 덩어리가 걸치는 자리가 있고, 그때 게임은 앞쪽
		# 것부터 연다(field._chest_in_front). 지목한 덩어리만 보면 멀쩡히 열린
		# 상자를 "아무 일도 없었다"로 적게 된다(2026-08-29 f0에서 4건 오검출).
		# 못 연 덩어리는 여전히 후보로 남아 다음 바퀴에 다시 온다.
		var cell: Vector2i = expect["chest"]
		var before := _chest_count()
		var check := func() -> bool:
			if _chest_count() > before:
				return true
			return GameState.chest_overrides_for(GameState.current_floor).has(cell)
		var opened := await _until(check)
		if opened:
			_log.chests += 1
		return opened
	if expect.has("dialogue"):
		var talking := await _until(func() -> bool: return _busy(_field()))
		if talking:
			_log.dialogues += 1
		return talking
	var flag := String(expect.get("flag", ""))
	if flag.is_empty():
		return await _until(func() -> bool: return _busy(_field()))
	return await _until(func() -> bool: return GameState.has_flag(flag))


## 그 칸을 **앞에 둔다.** 막힌 칸이면 밀어 보는 것으로 방향만 돌면 되지만(face),
## 통행 가능한 칸은 밀면 걸어 들어간다 — 그럴 때는 한 걸음 물러났다가 그쪽으로 걸어와
## 멈춘다. 사람이 하는 것과 같다: 그 방향으로 걸어와 서면 그것이 곧 전방이다.
func _aim(player: PlayerEntity, dir: Vector2i, passable: bool) -> void:
	if not passable:
		await _pilot.face(player, dir)
		return
	var here := player.mover.grid_pos
	if await _pilot.step_to(player, -dir, here - dir, false):
		await _pilot.step_to(player, dir, here, false)
		return
	await _pilot.face(player, dir)  # 뒤가 막혔다 — 밀어 보는 수밖에 없다


## 막혔을 때 마지막 수단. 대개는 **정말 막힌 것이 아니라** 전투·컷신이 목표 조회를
## 가로챈 것이다 — 그 상태로 접으면 "갈 곳이 없다"며 한 바퀴를 헛돈다.
func autoplay_unblock() -> bool:
	if not await _wait_for_field():
		# **어느 씬에 갇혔는지 적어 둔다.** 「더 갈 곳이 없다」만 남은 보고서로는
		# 길이 끊긴 것인지 필드 밖 화면에 갇힌 것인지 가릴 수 없다.
		var scene := get_tree().current_scene
		var where := "(없음)" if scene == null else scene.scene_file_path
		_failure = "필드가 아닌 씬에 갇혔다: %s" % where
		return false
	await _settle()
	return not autoplay_goals().is_empty()


# ---------------------------------------------------------------------------
# 사람 대신 앉아 있는 손 — 매 프레임 불린다
# ---------------------------------------------------------------------------


func autoplay_tick() -> void:
	_log.frames += 1
	_pilot.attend(get_tree().current_scene)


# ---------------------------------------------------------------------------
# 상태 조회
# ---------------------------------------------------------------------------


func _field() -> Node2D:
	var scene := get_tree().current_scene
	if scene == null or not scene.is_inside_tree() or not scene.has_method("get_runtime"):
		return null
	return scene as Node2D


## 화면이 무언가로 막혀 있는가 — 발동 여부 판정과 "지금 걸어도 되는가"에 쓴다.
##
## 대사·컷신뿐 아니라 **층 전환 페이드와 문 슬라이드**도 조작을 쥔다(TransitionGate).
## 그 사이에 걸으려 하면 첫 걸음이 통째로 실패한다 — 착지 앵커 부근에서 "걷다가
## 막혔다"가 무더기로 찍히던 자리다(2026-08-29 실측). mover.enabled를 최종 신호로 본다.
func _busy(field: Node2D) -> bool:
	if field == null:
		return false
	if field.cutscene_player != null and field.cutscene_player.is_running():
		return true
	if field.dialogue_box != null and field.dialogue_box.is_open:
		return true
	if field.gate != null and field.gate.active:
		return true
	var player: PlayerEntity = field.get_player()
	return player != null and not player.mover.enabled


## 필드가 설 때까지. 전투가 씬을 갈아 끼우는 사이를 메우고, 쓰러진 채 돌아왔으면
## 되살린다 — HP 0으로 복귀하면 다음 전투도 즉사라 주행이 그 자리에서 끝난다.
func _wait_for_field() -> bool:
	var idle := 0
	var total := 0
	while idle < SCENE_FRAMES and total < BATTLE_FRAMES:
		var field := _field()
		if field != null and field.get_player() != null:
			_revive_if_down()
			return true
		# **전투 중에는 시계를 세운다.** 한 판이 이 상한보다 길어서 "전투에서 돌아오지
		# 못했다"가 무더기로 찍히던 자리다(2026-08-29 실측). 전투가 아닌 채로 안 서면
		# 그때는 진짜 문제이므로 상한을 건다.
		var scene := get_tree().current_scene
		# **타이틀로 돌아왔으면 판이 끝난 것이다.** 엔딩을 보면 여기로 나온다 —
		# 여기서 계속 눌러 대면 새 판을 시작하거나 엔진을 흔든다(2026-08-29 f5 훑기가
		# 엔딩 뒤 signal 11로 죽었다). 기다릴 판이 없으니 그냥 끝낸다.
		if scene != null and scene.scene_file_path == TITLE_SCENE:
			return false
		# 기다리기만 하면 안 된다 — 필드를 대신하는 씬은 눌러 줘야 돌아온다.
		_pilot.attend(scene)
		if not (scene is BattleSceneController):
			idle += 1
		total += 1
		await get_tree().process_frame
	return false


func _revive_if_down() -> void:
	if int(GameState.player_stats["hp"]) > 0:
		return
	_log.revivals += 1
	GameState.player_stats["hp"] = GameState.max_hp()


## 대사·컷신이 끝나 다시 걸을 수 있을 때까지. 끝나지 않으면 손을 대고 기록한다.
func _settle() -> void:
	for _i in SETTLE_FRAMES:
		var field := _field()
		if field == null:
			if not await _wait_for_field():
				return
			continue
		if not _busy(field):
			return
		await get_tree().process_frame
	var stuck := _field()
	if stuck == null:
		return
	_log.mark_dead(
		GameState.current_floor,
		"진행 정지",
		"대사/컷신이 끝나지 않아 도구가 강제로 닫았다",
		stuck.get_player().mover.grid_pos
	)
	stuck.cutscene_player.stop()
	stuck.dialogue_box.close()
	stuck.get_player().mover.enabled = true


func _until(predicate: Callable) -> bool:
	for _i in EFFECT_FRAMES:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return false


# ---------------------------------------------------------------------------
# 길찾기 판정 · 목표 수집 (둘 다 비싸다 — 세상이 달라졌을 때만 다시 짓는다)
# ---------------------------------------------------------------------------


## 세상이 "다시 지어야 할 만큼" 달라졌는가. **상자를 열어도 여기는 안 바뀐다** —
## 상자는 열기 전(ATT 150~199)에도 후에도(1) 통행 불가라 길이 달라지지 않고, 후보에서
## 빠지는 것은 조회할 때 걸러 내면 된다. 이걸 스탬프에 넣었더니 상자 하나 열 때마다
## 맵 1만 3천 칸 재주사 + 앵커 6천 개 BFS를 다시 했다(2026-08-29 실측 101회).
func _world_stamp(field: Node2D) -> String:
	return "%d|%d" % [field.get_instance_id(), GameState.current_floor]


func _reachable(field: Node2D, player: PlayerEntity) -> Dictionary:
	var stamp := _world_stamp(field)
	if stamp != _nav_stamp:
		_nav_stamp = stamp
		_nav = AutoplayMap.new(field.get_runtime())
		_reach_key = ""
	var key := "%s|%s" % [stamp, str(player.mover.grid_pos)]
	if key != _reach_key:
		_reach_key = key
		_reach = _nav.reachable_from(player.mover.grid_pos)
	return _reach


## 후보 목록은 층마다 한 번 짓는다. 다만 **플래그가 새로 켜지면 다시 짓는다** —
## 잠겨 있던 트리거가 그때 후보로 올라오기 때문이다(Q_F1_START가 f1_sopo를 연다).
## 플래그 개수는 새 키가 생길 때만 늘어 재주사가 드물다.
func _candidates(field: Node2D) -> Array:
	var stamp := "%s|%d" % [_world_stamp(field), GameState.flags.size()]
	if stamp != _cand_stamp:
		_cand_stamp = stamp
		_cand = _goals.collect(field, GameState.current_floor, GameState.visited_floors)
		for note: String in _goals.notes:
			_log.data_notes[note] = true
	return _cand


func _chest_count() -> int:
	var total := 0
	for floor_key: Variant in GameState.chest_overrides:
		total += Dictionary(GameState.chest_overrides[floor_key]).size()
	return total


func _arg(name: String, fallback: float) -> float:
	return float(_arg_str(name, str(fallback)))


## `--out` — 보고서를 어디에 쓸 것인가. 관문은 저장소 밖(user://)으로 돌린다:
## 검증할 때마다 추적 파일이 덮여 쓰이면 `git status`가 늘 더러워진다.
func _arg_str(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var idx := args.find(name)
	if idx < 0 or idx + 1 >= args.size():
		return fallback
	return args[idx + 1]


# ---------------------------------------------------------------------------
# 보고서
# ---------------------------------------------------------------------------


func _write_report(driver: AutoplayDriver) -> void:
	var lines: Array[String] = [driver.build_report("자동 주행 결과", ALL_FLOORS)]
	lines.append_array(_log.sections())
	_log.store(_arg_str("--out", OUT_PATH), lines, "autoplay")
