extends "res://tools/dev/autoplay.gd"
## 층 훑기 — **데려다 놓으면 그 층 내용이 도는가.**
##
## 실행: godot --headless --path . res://tools/dev/autoplay_sweep.tscn --
##       [--seconds N] [--goals N] [--encounters 1] [--floors 3,4] [--out PATH]
## 결과: docs/05_status/02_floor_sweep.md
##
## `autoplay.gd`와 짝이다. 두 도구는 **다른 질문**에 답한다.
##
##   autoplay  새 게임에서 **걸어서** 거기까지 갈 수 있는가   순간이동 안 씀
##   sweep     **데려다 놓으면** 그 층 내용이 도는가          순간이동 씀
##
## 앞의 것만 있으면 막힌 뒤의 층을 영영 못 보고(지금 F3~F5가 그렇다), 뒤의 것만
## 있으면 "내용은 도는데 갈 길이 없는" 층을 못 잡는다. 사람 손 검사는 그다음 —
## 화면·소리·연출처럼 헤드리스가 원리적으로 못 보는 것에만 쓴다.
##
## 데려다 놓는 규칙(전부 데이터에서 온다):
##   입구  다른 층에서 이 층으로 오는 전이의 착지점(transitions.json)
##   힘    growth.json 성장 테이블의 만렙 + 전 기술 — 균형이 아니라 도달이 목적이다
##   무장  items.json에서 가장 센 무기·방어구 — 죽어서 훑기가 끊기지 않게
##   방해  인카운터 밀도 NONE — 몬스터에 끌려다니면 내용에 못 닿는다(`--encounters 1`로 켬)
##   문    모든 requires_flag를 미리 켠다 — "열리면 그 뒤가 도는가"를 보는 것이다

const SWEEP_OUT := "res://docs/05_status/02_floor_sweep.md"
## 성장 테이블 만렙을 확실히 넘기는 값(도구 센티널 — 게임 콘텐츠 수치가 아니다).
const MAX_EXP := 9_999_999
const SKILLS_PATH := "res://data/skills.json"
const ITEMS_PATH := "res://data/items.json"

var _floor := 1
var _entrance_rows: Array[String] = []
var _floor_rows: Array[String] = []
var _entry_note := ""
var _content_note := ""


func _run() -> void:
	_setup()
	var floors := _floors()
	var budget := _arg("--seconds", 900.0) / float(maxi(floors.size(), 1))
	for floor_variant: Variant in floors:
		_floor = int(floor_variant)
		_reached = 0
		var driver := AutoplayDriver.new(self, get_tree())
		driver.max_seconds = budget
		driver.max_goals = int(_arg("--goals", 300.0))
		driver.time_scale = _arg("--scale", driver.time_scale)
		print("")
		print("=== f%d 훑기 (예산 %.0f초) ===" % [_floor, budget])
		await driver.run()
		var why := _entry_note if not _entry_note.is_empty() else driver.stop_reason
		_floor_rows.append(
			(
				"| f%d | %s | %d | %d | %s |"
				% [_floor, _content_note, _reached, driver.stalls.size(), why]
			)
		)
	_write_sweep_report()
	print("")
	print(
		(
			"=== 층 훑기 끝: 걸음 %d / 전투 %d / 상자 %d / 대사 %d ==="
			% [_log.steps, _log.battles, _log.chests, _log.dialogues]
		)
	)
	get_tree().quit(0 if _log.steps > 0 else 1)


# ---------------------------------------------------------------------------
# 데려다 놓기
# ---------------------------------------------------------------------------


func autoplay_begin() -> void:
	_entry_note = ""
	_content_note = "(재지 못함)"
	_prepare_state()
	get_tree().change_scene_to_file(FIELD_SCENE)
	if not await _wait_for_field():
		_entry_note = "필드가 서지 않았다 — 들어서자마자 다른 씬으로 넘어갔다"
		return
	await _settle()
	if _field() == null:
		_entry_note = "들어서자마자 컷신이 씬을 바꿨다 (%s)" % _scene_name()
		return
	await _survey_entrances()


## 이 층을 벗어나면 훑기는 끝이다 — 여기서 보려는 것은 **이 층 안**이다.
## 전투는 잠깐 나갔다 오는 것이라 살아 있는 것으로 친다.
func autoplay_alive() -> bool:
	if GameState.current_floor != _floor:
		return false
	var scene := get_tree().current_scene
	if scene == null:
		return true  # 씬 교체 중
	return _field() != null or scene is BattleSceneController


func _scene_name() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path.get_file() if scene != null else "(없음)"


## 나가는 문은 목표로 삼지 않는다. 계단이 실제로 열리는지는 autoplay가 이미 본다.
func autoplay_goals() -> Array:
	var out: Array = []
	for goal_variant: Variant in super():
		var goal: Dictionary = goal_variant
		if String(goal["kind"]) == "계단":
			continue
		out.append(goal)
	return out


func _prepare_state() -> void:
	GameState.reset()
	GameState.inventory = Inventory.new()
	GameState.current_floor = _floor
	GameState.player_cell = Vector2i(-1, -1)
	# 몬스터는 기본으로 끈다. **죽어서가 아니라**(만렙+최고 무장이면 전 층을 돌아도
	# 죽지 않는다) 끌려다니느라 내용에 못 닿기 때문이다 — 전투 한 판이 예산을 먹고,
	# 이 도구가 묻는 것은 "그 층 내용이 도는가"다. 전투 자체는 autoplay가 실제 강도로 본다.
	# `--encounters 1`로 켤 수 있다.
	var density := SettingsManager.EncounterDensity.NONE
	if _arg("--encounters", 0.0) > 0.0:
		density = SettingsManager.EncounterDensity.NORMAL
	SettingsManager.encounter_density = density
	_open_gates()
	_grow_up()


## 층·트리거를 잠근 플래그를 켠다. 잠겨 있다는 사실은 autoplay가 재고, 여기서는
## **열렸을 때 그 뒤가 도는가**를 잰다.
##
## 다만 **auto 트리거의 잠금은 켜지 않는다.** auto는 층에 들어서는 순간 발동하고,
## 그중에는 다른 씬으로 데려가는 것이 있다(f2 hp_room_visit → 크레딧룸). 미리 켜면
## 층에 발도 못 붙이고 쫓겨나 그 층 내용을 하나도 못 본다. 그 자리는 컷신 스모크의 몫.
func _open_gates() -> void:
	for t: Dictionary in JsonUtil.load_dict(AutoplayGoals.TRANSITIONS_PATH, "sweep").get(
		"transitions", []
	):
		var req: Variant = t.get("requires_flag")
		if req != null:
			GameState.set_flag(str(req), true)
	for floor_variant: Variant in ALL_FLOORS:
		var path := "res://data/maps/triggers_f%d.json" % int(floor_variant)
		if not FileAccess.file_exists(path):
			continue
		for t: Dictionary in JsonUtil.load_dict(path, "sweep").get("triggers", []):
			if str(t.get("type", "")) == "auto":
				continue
			var req: Variant = t.get("requires_flag")
			if req != null:
				GameState.set_flag(str(req), true)


## 성장 테이블 만렙 + 전 기술 + **최고 무장**. 균형이 아니라 도달이 목적이라 수치를
## 지어내지 않고 growth.json·skills.json·items.json을 그대로 쓴다. 이만큼 주면 전 층을
## 돌아도 죽지 않으므로, 훑기가 전투에 걸려 중단되는 일이 없다.
func _grow_up() -> void:
	GameState.grant_exp(MAX_EXP)
	GameState.init_skills(true)
	# BattleSetup.load_skills()는 **습득한 것만** 돌려준다 — 여기서는 표 전체가 필요하다.
	for skill: Dictionary in JsonUtil.load_dict(SKILLS_PATH, "sweep").get("skills", []):
		GameState.grant_skill(StringName(str(skill.get("id", ""))))
	_equip_best("weapon", "ap")
	_equip_best("armor", "dp")
	GameState.player_stats["hp"] = GameState.max_hp()


## 그 칸에서 가장 센 것을 집어 든다 — **무엇이 가장 센지도 데이터가 정한다**
## (items.json의 kind와 능력치). 도구에 아이템 id를 적어 두면 표가 바뀔 때 조용히 낡는다.
func _equip_best(slot: String, stat: String) -> void:
	var best := {}
	for item: Dictionary in JsonUtil.load_dict(ITEMS_PATH, "sweep").get("items", []):
		if str(item.get("kind", "")) != slot:
			continue
		if best.is_empty() or int(item.get(stat, 0)) > int(best.get(stat, 0)):
			best = item
	if best.is_empty():
		return
	var id := StringName(str(best["id"]))
	GameState.inventory.add(id, 1)
	GameState.equip(id)
	print("[sweep] %s 장착: %s (%s %d)" % [slot, id, stat, int(best.get(stat, 0))])


# ---------------------------------------------------------------------------
# 입구 — 어디로 들어오느냐가 갈 수 있는 범위를 정한다
# ---------------------------------------------------------------------------


## 입구마다 데려다 놓고 **거기서 갈 수 있는 범위**를 잰다. 계단을 내려왔는데 그
## 자리에 갇히는 층이 있을 수 있다 — 스폰을 한 점으로 고정하는 world_audit은
## 원리적으로 못 보는 것이다. 가장 넓게 열리는 입구에서 훑는다.
func _survey_entrances() -> void:
	var field := _field()
	if field == null:
		return
	var best := Vector2i(-1, -1)
	var best_open := -1
	for entrance: Vector2i in _entrances():
		await _land_at(field, entrance)
		var player: PlayerEntity = field.get_player()
		var reach := _reachable(field, player)
		var candidates := _candidates(field)
		var open := 0
		for candidate: Dictionary in candidates:
			if not _approach(player, reach, candidate).is_empty():
				open += 1
		_entrance_rows.append(
			(
				"| f%d | %s | %d | %d / %d |"
				% [_floor, str(entrance), reach.size(), open, candidates.size()]
			)
		)
		if open > best_open:
			best_open = open
			best = entrance
	if best.x >= 0:
		await _land_at(field, best)
	_content_note = _content_tally(field)


## 이 층에 **좌표가 붙은 목표가 몇이나 있는가.** 0이면 훑기가 할 일이 없다는 뜻이지
## 훑기가 실패한 것이 아니다 — f5가 그렇다(내용이 전부 auto 트리거와 보스전이라
## 밟을 좌표가 없다). 이 칸이 없으면 "0"만 남아 도구 고장과 구별되지 않는다.
func _content_tally(field: Node2D) -> String:
	var tally: Dictionary = {}
	for candidate: Dictionary in _candidates(field):
		var kind := String(candidate["kind"])
		if kind == "계단":
			continue  # 나가는 문은 훑기 대상이 아니다
		tally[kind] = int(tally.get(kind, 0)) + 1
	if tally.is_empty():
		return "없음(내용이 전부 auto 트리거)"
	var parts: Array[String] = []
	for kind: String in tally:
		parts.append("%s %d" % [kind, int(tally[kind])])
	return ", ".join(parts)


## 이 층으로 들어오는 문 — **다른 층에서 여기로 오는 전이의 착지점**이다.
## 하나도 없으면(들어올 길이 없는 층) 게임이 고른 스폰 자리를 쓴다.
func _entrances() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var raw := JsonUtil.load_dict(AutoplayGoals.TRANSITIONS_PATH, "sweep")
	for t: Dictionary in raw.get("transitions", []):
		var delta := int(t["floor_delta"])
		for from_floor in range(int(t["guard_min_floor"]), int(t["guard_max_floor"]) + 1):
			if from_floor + delta != _floor:
				continue
			var landing := Vector2i(
				int(t["anchor"][0]) + int(t["spawn_offset"][0]),
				int(t["anchor"][1]) + int(t["spawn_offset"][1])
			)
			if not out.has(landing):
				out.append(landing)
	if out.is_empty():
		var field := _field()
		if field != null:
			out.append(field.get_player().mover.grid_pos)
	return out


## 게임 자신의 착지 절차로 데려다 놓는다(막힌 앵커 보정·NPC/몬스터 재배치 포함).
func _land_at(field: Node2D, cell: Vector2i) -> void:
	field.rebuild_floor(cell)
	_nav_stamp = ""
	_cand_stamp = ""
	_reach_key = ""
	await get_tree().process_frame
	await get_tree().process_frame
	await _settle()


# ---------------------------------------------------------------------------
# 보고서
# ---------------------------------------------------------------------------


## 어느 층을 훑을 것인가 — `--floors 3,4`. 기본은 전부.
##
## **층끼리는 서로를 안 본다**(각 층마다 판을 새로 세우고 데려다 놓는다). 그래서
## 층을 갈라 여러 프로세스로 동시에 돌려도 결과가 달라지지 않는다. 다만 `--out`을
## 갈라 줘야 한다 — 같은 파일을 두 프로세스가 쓰면 나중 것이 앞 것을 지운다.
## 시간을 잴 목적이라면 동시 실행하지 마라: CPU를 나눠 쓰면 수치가 섞인다.
func _floors() -> Array:
	var raw := _arg_str("--floors", "")
	if raw.strip_edges().is_empty():
		return ALL_FLOORS
	var picked: Array = []
	for piece in raw.split(",", false):
		var f := int(piece.strip_edges())
		if f in ALL_FLOORS and not picked.has(f):
			picked.append(f)
	if picked.is_empty():
		push_error("[sweep] --floors %s 에서 훑을 층을 못 골랐다 (있는 층: %s)" % [raw, ALL_FLOORS])
		return ALL_FLOORS
	return picked


func _write_sweep_report() -> void:
	var lines: Array[String] = [
		"# 층 훑기 결과",
		"",
		"**데려다 놓으면 그 층 내용이 도는가.** 생성기: `tools/dev/autoplay_sweep.tscn`.",
		"",
		"걸어서 갈 수 있는지는 여기서 묻지 않는다(그건 [자동 주행](01_autoplay.md)의 몫이다).",
		"여기서는 층마다 **입구에 데려다 놓고** 만렙·인카운터 없음·잠금 해제 상태로",
		"그 층의 트리거·NPC·상자를 실제로 건드려 본다.",
		"",
		"## 층별 결과",
		"",
		"| 층 | 그 층의 좌표 목표 | 밟은 목표 | 못 간 목표 | 끝난 이유 |",
		"|---|---|---|---|---|",
	]
	lines.append_array(_floor_rows)
	lines.append("")
	lines.append("## 입구별로 열리는 범위")
	lines.append("")
	lines.append("**어디로 들어오느냐가 갈 수 있는 범위를 정한다.** 다른 층에서 이 층으로 오는")
	lines.append("전이의 착지점마다, 거기서 2×2 몸으로 닿는 앵커 수와 붙을 수 있는 목표 수다.")
	lines.append("숫자가 유독 작은 입구는 **내려서면 갇히는 자리**다.")
	lines.append("")
	lines.append("| 층 | 착지점 | 닿는 앵커 | 붙을 수 있는 목표 |")
	lines.append("|---|---|---|---|")
	lines.append_array(_entrance_rows)
	lines.append("")
	lines.append_array(_log.sections())
	_log.store(_arg_str("--out", SWEEP_OUT), lines, "sweep")
