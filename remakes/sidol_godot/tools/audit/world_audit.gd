extends Node
## 월드 감사 — 전 층의 **조립된 씬**을 실제로 세워 놓고 불변식을 검사한다.
## 실행: godot --headless --path . res://tools/audit/world_audit.tscn   (exit 0=통과)
##
## 기존 4종 관문이 못 보는 계층을 맡는다:
##   validate.gd     = 데이터 참조(파일·키·id가 존재하는가)
##   self_check.gd   = 시스템 통합(로직 단위 규약)
##   smoke_*.tscn    = 시나리오 한 줄기(이 조작이 이 결과를 내는가)
##   **world_audit** = 조립 결과(화면에 실제로 뭐가 서 있고 갈 수 있는가)
##
## 2026-08-26 회귀 4건(오브젝트 전량 미렌더 · NPC 시트 오배정 · 몬스터 벽 통과/초당 60칸 ·
## 좌·하 전방 셀 어긋남)은 전부 앞의 셋을 통과하고도 살아 있었다. 그 구멍을 메운다.
##
## 주의: 이 파일에 **다중행 람다를 딕셔너리 리터럴로 넣지 말 것.**
## gdformat이 그 구조에서 무한 재포맷하며 독스트링을 본문에 복제해 파일을 망가뜨린다
## (2026-08-27 실측). 패널 순회는 문자열 목록 + match로 편다.

const FIELD_SCENE := preload("res://scenes/field.tscn")
const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const FLOORS := [0, 1, 2, 3, 4, 5]
const SIM_TICKS := 40  # 이동 규칙 검증용 시뮬레이션 물리 틱 수
## 아무도 안 움직였을 때만 더 굴려 보는 관측 창. 40틱=약 0.66초라
## 행동 주기가 긴 종(teleport 0.45초·ambusher 0.4초)만 있는 층은 우연히 0회가 된다
## — 실제로 f0(sparker 2체)이 그렇게 오탐 WARN을 냈다. 설계상 정지와 진짜 정지를 가른다.
const IDLE_RECHECK_TICKS := 180  # 약 3초
const WATCHDOG := 240.0
const WAIVERS := "res://tools/audit/known_issues.json"
const VIEW := Rect2(Vector2.ZERO, Vector2(960, 540))
## 필드 위에 열리는 패널 — 하나씩 닫고 열어야 남의 위반이 이 이름으로 보고되지 않는다.
const FIELD_PANELS := ["가방", "빠른 이동", "매점"]
const BATTLE_MENUS := ["커맨드", "기술", "도구"]
## 메뉴 패널은 로케일마다 문자열 길이가 달라 배치가 달라진다 — ui.csv의 열과 1:1.
const MENU_LOCALES := ["ko", "en"]

var _rep := AuditReport.new()


func _ready() -> void:
	get_tree().create_timer(WATCHDOG).timeout.connect(
		func() -> void:
			push_error("[world_audit] WATCHDOG timeout")
			get_tree().quit(2)
	)
	print("[world_audit] start")
	_rep.load_waivers(WAIVERS)

	_rep.scope("")
	MotionProbe.check_contact_symmetry(_rep)
	ActorProbe.check_pattern_coverage(_rep)
	RenderProbe.check_atlas_transparency(_rep)

	for f: int in FLOORS:
		await _audit_floor(f)
	await _audit_battle_ui()
	await _audit_menu_ui()

	print("\n".join(_rep.lines))
	var tail := _rep.summary_tail()
	if not tail.is_empty():
		print("접힌 항목 총량:")
		print("\n".join(tail))
	var stale := _rep.stale_waivers()
	if not stale.is_empty():
		_rep.warns += stale.size()
		print("\n".join(stale))
	print("[world_audit] done - FAIL %d / WARN %d" % [_rep.fails, _rep.warns])
	get_tree().quit(1 if _rep.fails > 0 else 0)


func _audit_floor(floor_no: int) -> void:
	_rep.scope("f%d" % floor_no)
	_rep.lines.append("── f%d ──" % floor_no)

	# 컷신·트리거가 입력을 가로채면 조립 상태를 볼 수 없다 — 게이트를 미리 연다.
	GameState.current_floor = floor_no
	GameState.player_cell = Vector2i(-1, -1)
	GameState.flags["q_f1_opening_seen"] = true
	GameState.flags["Q_F1_START"] = true

	var field: Node2D = FIELD_SCENE.instantiate()
	add_child(field)
	await get_tree().process_frame
	await get_tree().process_frame

	var player: PlayerEntity = field.get_player()
	var rt: MapRuntime = field.get_runtime()
	if player == null or rt == null:
		_rep.fail("씬 조립", "player/runtime 없음")
		field.queue_free()
		return

	var renderer := _find_renderer(field)
	if renderer == null:
		_rep.fail("씬 조립", "MapRenderer 없음")
	else:
		RenderProbe.check_layers(_rep, renderer, rt)

	var enemies: Array = field.enemy_manager.enemies if field.enemy_manager != null else []
	ActorProbe.check_sheets(_rep, field.npcs, enemies)
	ActorProbe.check_pose_coverage(_rep, player, enemies)
	ActorProbe.check_placement(_rep, rt, player, field.npcs, enemies)
	ActorProbe.check_spawn_distance(_rep, player, enemies)
	ActorProbe.check_actor_clearance(_rep, field.npcs, enemies)

	# 도달성은 NPC 차단 오버라이드가 적용된 런타임 기준 — 그래야 "NPC가 길을 막았다"가 보인다.
	var reach := ReachProbe.reachable_anchors(rt, player.mover.grid_pos)
	var facable := ReachProbe.facable_cells(reach)
	_rep.ok("도달 앵커", "%d개" % reach.size())
	ReachProbe.check_connectivity(_rep, rt, reach)
	# 안개는 **가리되 가두지 않아야** 한다 — 도달 집합을 이미 구한 이 자리가 쌀 곳이다.
	FogProbe.check_reveal(_rep, rt, floor_no, VIEW.size, reach)
	RenderProbe.check_invisible_walls(_rep, rt, facable)
	ReachProbe.check_interactables(_rep, rt, facable)
	ReachProbe.check_npcs(_rep, facable, field.npcs)
	ReachProbe.check_transitions(_rep, reach, floor_no)
	ReachProbe.check_triggers(_rep, reach, facable, floor_no)

	await _audit_field_ui(field, floor_no)
	await _simulate_motion(field, rt, floor_no, enemies)
	field.queue_free()
	await get_tree().process_frame


## 필드 위에 열리는 패널들도 화면 안에 들어오는가.
## 전투 UI만 보던 검사를 필드까지 넓힌다 — 가방 상세가 우측으로 넘치던 것을 놓쳤다.
func _audit_field_ui(field: Node2D, floor_no: int) -> void:
	# 가방·매점은 목록이 길수록 넘치기 쉽다 — 최악 상태로 검사한다.
	var items: Array = JsonUtil.load_dict("res://data/items.json", "world_audit").get("items", [])
	for item: Dictionary in items:
		GameState.inventory.add(StringName(str(item["id"])), 1)
	for f: int in FLOORS:
		GameState.mark_visited(f)

	for panel_name: String in FIELD_PANELS:
		_close_field_panels(field)
		await get_tree().process_frame
		_open_field_panel(field, panel_name)
		await get_tree().process_frame
		await get_tree().process_frame
		_rep.scope("field_ui/%s" % panel_name)
		UiProbe.check_onscreen(_rep, field, VIEW, panel_name + " 패널")

	_close_field_panels(field)
	GameState.inventory.clear()
	_rep.scope("f%d" % floor_no)


func _open_field_panel(field: Node2D, panel_name: String) -> void:
	match panel_name:
		"가방":
			field.inventory_panel.open()
		"빠른 이동":
			field.fast_travel.open_for(GameState.current_floor)
		"매점":
			field.shop.open()


func _close_field_panels(field: Node2D) -> void:
	field.inventory_panel.close()
	field.fast_travel.close()
	field.shop.close()


## 몇 틱 굴려 이동 규칙 위반을 잡는다 — 벽 통과·순간이동·과속.
func _simulate_motion(field: Node2D, rt: MapRuntime, floor_no: int, enemies: Array) -> void:
	if field.enemy_manager == null or enemies.is_empty():
		MotionProbe.check_activity(_rep, 0, SIM_TICKS, 0)
		return
	var warp: Dictionary = {}
	var phase: Dictionary = {}
	for spec: Dictionary in Database.encounter_species(floor_no):
		var kind := MovementPattern.kind_from_name(str(spec["pattern"]))
		if kind == MovementPattern.Kind.BURROW or kind == MovementPattern.Kind.TELEPORT:
			warp[str(spec["id"])] = true
		if MovementPattern.ignores_walls(kind):
			phase[str(spec["id"])] = true

	var player_cell: Vector2i = field.get_player().mover.grid_pos
	var moved := 0
	for t in SIM_TICKS:
		var before := MotionProbe.snapshot(enemies)
		await get_tree().physics_frame
		MotionProbe.check_tick(_rep, rt, before, warp, phase)
		MotionProbe.check_warp_landing(_rep, before, player_cell, warp)
		for b: Dictionary in before:
			var e: EnemyEntity = b["ref"]
			if is_instance_valid(e) and e.mover.grid_pos != b["cell"]:
				moved += 1
	var ticks := SIM_TICKS
	if moved == 0:
		for t2 in IDLE_RECHECK_TICKS:
			var before2 := MotionProbe.snapshot(enemies)
			await get_tree().physics_frame
			for b2: Dictionary in before2:
				var e2: EnemyEntity = b2["ref"]
				if is_instance_valid(e2) and e2.mover.grid_pos != b2["cell"]:
					moved += 1
		ticks += IDLE_RECHECK_TICKS
	MotionProbe.check_activity(_rep, moved, ticks, enemies.size())


## 전투 씬 UI — 커맨드·기술·도구 세 메뉴를 모두 열어 본다.
## 커맨드만 보면 부족하다: 같은 박스를 쓰는 도구 메뉴가 항목이 가장 많아 먼저 밀려난다.
func _audit_battle_ui() -> void:
	_rep.scope("battle_ui")
	_rep.lines.append("── 전투 UI ──")
	UiProbe.check_display_names(_rep)

	GameState.player_stats = {"hp": 50, "ap": 30, "money": 0, "level": 1, "exp": 0}
	GameState.pending_encounter = {"enemies": ["vulgar"], "on_win_flag": ""}
	var battle: Node = BATTLE_SCENE.instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame

	# 도구 메뉴는 인벤토리가 비면 한 줄짜리라 최악 케이스를 못 본다.
	var items: Array = JsonUtil.load_dict("res://data/items.json", "world_audit").get("items", [])
	for item: Dictionary in items:
		if int(item.get("hp_restore", 0)) > 0:
			GameState.inventory.add(StringName(str(item["id"])), 1)

	var ui: BattleUI = _find_battle_ui(battle)
	if ui == null:
		_rep.warn("전투 UI 탐색", "BattleUI 노드를 찾지 못해 메뉴별 검사를 생략")
		UiProbe.check_onscreen(_rep, battle, VIEW)
	else:
		for menu_name: String in BATTLE_MENUS:
			_open_battle_menu(ui, menu_name)
			await get_tree().process_frame
			await get_tree().process_frame
			_rep.scope("battle_ui/%s" % menu_name)
			UiProbe.check_onscreen(_rep, battle, VIEW, menu_name + " 메뉴")
		ui.hide_menu()
		_rep.scope("battle_ui")
	UiProbe.check_text_overflow(_rep, battle)

	GameState.inventory.clear()
	battle.queue_free()
	await get_tree().process_frame


func _open_battle_menu(ui: BattleUI, menu_name: String) -> void:
	match menu_name:
		"커맨드":
			ui.show_command_menu()
		"기술":
			ui.show_skill_menu()
		"도구":
			ui.show_item_menu()


## 전투 씬 하위에서 BattleUI 계층을 찾는다(씬 구조 변경에 견디도록 탐색으로).
func _find_battle_ui(node: Node) -> BattleUI:
	if node is BattleUI:
		return node
	for child: Node in node.get_children():
		var found := _find_battle_ui(child)
		if found != null:
			return found
	return null


func _find_renderer(field: Node2D) -> MapRenderer:
	for child in field.get_children():
		if child is MapRenderer:
			return child
	return null


## 타이틀·일시정지에서 열리는 패널(설정·도움말)이 화면 안에 들어오는가.
## 필드/전투 밖이라 기존 검사가 닿지 않던 자리다 — 설정은 행이 늘 때마다 아래로 자란다
## (2026-08-28 언어 행 추가). 언어를 바꾸면 문자열 길이가 달라지므로 로케일별로 본다.
func _audit_menu_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panels := {"설정": SettingsPanel.new(), "도움말": HelpPanel.new()}
	for name: String in panels:
		layer.add_child(panels[name])
	for locale: String in MENU_LOCALES:
		TranslationServer.set_locale(locale)
		for name2: String in panels:
			var panel: Control = panels[name2]
			panel.visible = true
			if panel.has_method("_refresh"):
				panel.call("_refresh")
			await get_tree().process_frame
			await get_tree().process_frame
			_rep.scope("menu_ui/%s/%s" % [locale, name2])
			UiProbe.check_onscreen(_rep, panel, VIEW, "%s 패널(%s)" % [name2, locale])
			panel.visible = false
	TranslationServer.set_locale(SettingsManager.LANGUAGE_CODES[int(SettingsManager.language)])
	_rep.scope("menu_ui")
	layer.queue_free()
	await get_tree().process_frame
