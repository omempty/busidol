extends Node
## UI 갤러리 캡처 — 필드/전투의 각 패널을 실제로 세워 PNG로 남긴다.
##
## UI 작업은 눈으로 봐야 판단이 된다. world_audit은 "화면 밖으로 나갔는가"만 보고
## 여백·정렬·대비·밀도 같은 것은 못 본다. 이 도구는 판정하지 않고 **보여 준다**.
##
## 실행(창 모드 필요 — 헤드리스는 렌더 결과가 없다):
##   godot --path . --resolution 960x540 res://tools/dev/ui_shots.tscn -- <출력 폴더>
## 출력 폴더를 생략하면 user://ui_shots.

const FIELD_SCENE := preload("res://scenes/field.tscn")
const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const SETTLE_FRAMES := 6

var _out_dir := "user://ui_shots"
var _shots := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("[ui_shots] out=%s" % ProjectSettings.globalize_path(_out_dir))
	await _capture_field()
	await _capture_floor_lighting()
	await _capture_battle()
	print("[ui_shots] done - %d장" % _shots)
	get_tree().quit(0)


func _capture_field() -> void:
	# 실제 플레이와 같은 출발점 — reset()이 스킬·플래그·스탯 기본값을 세운다.
	# (이걸 빼먹으면 전투 기술 메뉴가 빈 채로 찍혀 UI 문제로 오해하게 된다.)
	GameState.reset()
	GameState.flags["q_f1_opening_seen"] = true
	GameState.flags["Q_F1_START"] = true
	GameState.current_floor = 1
	GameState.player_cell = Vector2i(-1, -1)
	# 빈 가방·빈 지갑은 UI의 최악/최선 어느 쪽도 아니다 — 실제 플레이 중간값을 만든다.
	GameState.player_stats["money"] = 4820
	GameState.player_stats["level"] = 7
	GameState.player_stats["exp"] = 1200
	for iid: String in ["ITEM_MEDICINE", "ITEM_BATTERY", "ITEM_WEAPON_KAL", "ITEM_BOOK"]:
		GameState.inventory.add(StringName(iid), 3)

	var field: Node2D = FIELD_SCENE.instantiate()
	add_child(field)
	if field.enemy_manager != null:
		field.enemy_manager.queue_free()
	await _settle()
	await _shot("field_hud", field)

	field.inventory_panel.open()
	await _settle()
	await _shot("field_inventory", field)
	await _shot("field_inventory_items", field)

	field.inventory_panel.call("_set_tab", InventoryPanel.Tab.GEAR)
	await _settle()
	await _shot("field_inventory_gear", field)

	field.inventory_panel.call("_set_tab", InventoryPanel.Tab.STATUS)
	await _settle()
	await _shot("field_inventory_status", field)

	field.inventory_panel.call("_set_tab", InventoryPanel.Tab.SYSTEM)
	await _settle()
	await _shot("field_inventory_system", field)
	field.inventory_panel.close()
	await _settle()

	# 미니맵 캡처 — **안개 켠 것과 끈 것을 같은 자리에서 두 장.**
	# 한 장만 찍으면 "원래 저만큼만 보이는 지도"와 구분이 안 된다.
	# F1은 **밝은 층**이라 안개가 없다 — 지도 전체가 보이는 것이 정상이다(대조군).
	if field.minimap != null:
		field.minimap.repaint()
		field.minimap.visible = true
		await _settle()
		await _shot("field_minimap", field)
		field.minimap.visible = false
		await _settle()

	# 대화창 캡처 (초상화 포함)
	var test_steps: Array = [{"speaker": "수위 아저씨", "text": "@c102", "portrait": "npc_guard_v2"}]
	field.dialogue_box.start(&"guard_warning", test_steps)
	field.dialogue_box._revealed = 1000.0
	field.dialogue_box._body_label.visible_characters = -1
	await _settle()
	await _shot("field_dialogue", field)
	field.dialogue_box.close()
	await _settle()

	# 1F 멍청 조교 조사 프롬프트 및 신규 대사 캡처
	var tutor: NpcEntity = field.get_npc("tutor_dumb")
	if tutor != null:
		field.player.mover.grid_pos = tutor.cell + Vector2i.RIGHT
		field.player.facing = &"left"
		field.player.position = GridMover.block_center(field.player.mover.grid_pos)
		field._prompt.show_at("%s   SPACE" % tutor.display_name, tutor.position + Vector2(0, -46))
		field._focus.show_cells(tutor.body_cells())
		await _settle()
		await _shot("field_npc_tutor_focus", field)
		field._prompt.visible = false
		field._focus.visible = false
		var tutor_steps: Array = Database.sequence(tutor.resolve_sequence())
		field.dialogue_box.start(tutor.resolve_sequence(), tutor_steps)
		field.dialogue_box._revealed = 1000.0
		field.dialogue_box._body_label.visible_characters = -1
		await _settle()
		await _shot("field_npc_tutor_dialogue", field)
		field.dialogue_box.close()
		await _settle()

	field.shop.open()
	await _settle()
	await _shot("field_shop", field)
	field.shop.close()

	for f: int in [0, 1, 2]:
		GameState.mark_visited(f)
	field.fast_travel.open_for(GameState.current_floor)
	await _settle()
	await _shot("field_fast_travel", field)
	field.fast_travel.close()

	var pause := PauseMenu.new()
	field.add_child(pause)
	pause.toggle()
	await _settle()
	await _shot("menu_pause", field)
	pause.toggle()
	await _settle()

	# Control 패널은 CanvasLayer 아래에서만 전체 화면 앵커가 먹는다(게임에서는 PauseMenu가 그 역할).
	var layer := CanvasLayer.new()
	layer.layer = 50
	field.add_child(layer)

	var settings := SettingsPanel.new()
	layer.add_child(settings)
	settings.visible = true
	await _settle()
	await _shot("menu_settings", field)
	settings.queue_free()
	await _settle()

	var help := HelpPanel.new()
	layer.add_child(help)
	help.visible = true
	await _settle()
	await _shot("menu_help", field)
	help.queue_free()
	await _settle()

	var log_panel := QuestLogPanel.new()
	layer.add_child(log_panel)
	log_panel.visible = true
	await _settle()
	await _shot("menu_quest_log", field)
	log_panel.queue_free()

	await _capture_field_interaction(field)

	field.queue_free()
	await get_tree().process_frame


## 조사 대상 표시와 상자 개봉 연출 — 눈으로만 판단되는 것들이라 그림을 남긴다.
## f1 (23,13) 상자 앞에 세운다(자동 주행이 실제로 여는 상자다).
func _capture_field_interaction(field: Node2D) -> void:
	var chest := Vector2i(23, 13)
	var anchor := Vector2i(chest.x - 1, chest.y + 1)
	field.player.mover.grid_pos = anchor
	field.player.position = GridMover.block_center(anchor)
	field.player.facing = &"up"
	await _settle()
	await _shot("field_chest_focus", field)

	field.call("_open_chest", chest)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("field_chest_open", field)
	await _settle()
	await _shot("field_chest_opened", field)

	# 문 통과 연출 — f1의 문(ATT 9) 앞에 세우지 않고 연출만 직접 호출한다.
	# 여기서 보고 싶은 것은 "문 그림이 제자리에 뜨는가"지 이동 판정이 아니다.
	field.call("play_door_fx", field.player.mover.grid_pos, Vector2i.DOWN, 0.6)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("field_door_open", field)

	# 배경 보행자 — 걷고 있는지는 그림 한 장으로는 못 보지만, **거기 서 있는지**는 보인다.
	# 자리는 데이터가 정한다(walkers_f1.json). 좌표를 여기 박으면 데이터와 갈라진다.
	if not field.walkers.is_empty():
		var w: WalkerEntity = field.walkers[0]
		var beside := w.cell + Vector2i(0, 2)
		field.player.mover.grid_pos = beside
		field.player.position = GridMover.block_center(beside)
		field.player.facing = &"up"
		await _settle()
		await _shot("field_walker", field)


## 층 조명(F0) — **켠 것과 끈 것을 같은 자리에서 두 장 찍는다.**
##
## 조명은 수치로 판정할 수 있는 것이 아니라 눈으로 봐야 하는 층이다. 한 장만 찍으면
## "원래 저런 색인가"와 구분이 안 되므로, 톤을 잠시 흰색으로 되돌린 대조군을 같이 남긴다.
## 이 두 장이 갈라지지 않으면 조명이 죽은 것이다.
func _capture_floor_lighting() -> void:
	GameState.reset()
	GameState.flags["q_f1_opening_seen"] = true
	GameState.current_floor = 0
	# 지하 사서 방 앞 — NPC·문·벽이 한 화면에 같이 잡히는 자리(npcs_f0.json librarian @175,50).
	GameState.player_cell = Vector2i(173, 50)

	var field: Node2D = FIELD_SCENE.instantiate()
	add_child(field)
	await _settle()
	await _shot("field_f0_lit", field)

	# 대조군 — 톤만 흰색으로 되돌린다(광원은 그대로 두어 차이를 톤에 가둔다).
	var tint: CanvasModulate = field.lighting.get_node_or_null(NodePath(FloorLighting.TINT_NAME))
	if tint != null:
		tint.color = Color(1, 1, 1)
	await _settle()
	await _shot("field_f0_unlit", field)

	# 톤을 되돌린다 — 아래 지도 캡처는 조명이 켜진 상태에서 찍어야 한다.
	if tint != null:
		tint.color = FloorLighting.FLOOR_TINT[0]

	# **안개는 어두운 층에서만 돈다** — 그래서 지도 캡처도 여기서 찍는다.
	if field.minimap != null:
		_walk_for_fog(field, 120)
		field.minimap.repaint()
		field.minimap.visible = true
		await _settle()
		await _shot("field_f0_minimap_fog", field)
		SettingsManager.fog_of_war = false
		field.minimap.repaint()
		await _settle()
		await _shot("field_f0_minimap_nofog", field)
		SettingsManager.fog_of_war = true
		field.minimap.repaint()
		field.minimap.visible = false
		await _settle()

	print(
		(
			"[ui_shots] f0 조명: tint=%s  광원 %d개 (플레이어 scale %.1f / 액터 %.1f)"
			% [
				str(FloorLighting.FLOOR_TINT.get(0)),
				_count_lights(field),
				FloorLighting.PLAYER_SCALE,
				FloorLighting.ACTOR_SCALE,
			]
		)
	)
	field.queue_free()
	await _settle()


## 이 씬에 실제로 붙은 광원 수 — 배선이 끊기면 0이 나온다.
func _count_lights(node: Node) -> int:
	var n := 0
	if node.get_node_or_null(NodePath(FloorLighting.LIGHT_NAME)) != null:
		n += 1
	for c: Node in node.get_children():
		n += _count_lights(c)
	return n


func _capture_battle() -> void:
	# 약점 보유 종을 섞는다 — 브레이크 게이지가 그려지는지 보려면 필요하다.
	GameState.pending_encounter = {"enemies": ["mad_eye", "vulgar"], "on_win_flag": ""}
	for iid: String in ["ITEM_MEDICINE", "ITEM_CONDITION"]:
		GameState.inventory.add(StringName(iid), 2)
	var battle: Node = BATTLE_SCENE.instantiate()
	add_child(battle)
	await _settle()
	await _settle()
	await _shot("battle_idle", battle)
	var ui := _find_battle_ui(battle)
	if ui == null:
		print("[ui_shots] BattleUI 없음 — 전투 메뉴 생략")
		return
	ui.show_command_menu()
	await _settle()
	await _shot("battle_command", battle)
	ui.show_skill_menu()
	await _settle()
	await _shot("battle_skill", battle)
	ui.show_item_menu()
	await _settle()
	await _shot("battle_item", battle)
	battle.queue_free()
	await get_tree().process_frame


func _find_battle_ui(node: Node) -> BattleUI:
	if node is BattleUI:
		return node
	for c in node.get_children():
		var found := _find_battle_ui(c)
		if found != null:
			return found
	return null


## 안개를 넓히려고 잠깐 걷는다 — 한 자리에서 찍으면 동그라미 하나라 지도로 판단이 안 된다.
## 시작점에서 **멀어지는 쪽**을 골라 걷는다(왔다 갔다 하면 같은 칸만 다시 밝힌다).
func _walk_for_fog(field: Node2D, steps: int) -> void:
	var start: Vector2i = field.player.mover.grid_pos
	var cur := start
	var been := {cur: true}
	for _i in steps:
		var best := Vector2i(-1, -1)
		var best_d := -1
		for n: Vector2i in ReachProbe.neighbors(field.runtime, cur):
			if been.has(n):
				continue
			var d: int = absi(n.x - start.x) + absi(n.y - start.y)
			if d > best_d:
				best_d = d
				best = n
		if best.x < 0:
			break
		cur = best
		been[cur] = true
		field.player.mover.grid_pos = cur
		# **몸도 옮겨야 한다.** 안개 범위는 카메라가 정하고 카메라는 주인공의 자식이라,
		# grid_pos만 바꾸면 화면은 제자리에 있고 안개가 한 칸도 늘지 않는다.
		field.player.position = GridMover.block_center(cur)
		field.call("_reveal_fog")
	field.player.mover.grid_pos = cur
	print("[ui_shots] 안개 걷기 %d칸 -> %s" % [been.size(), str(cur)])


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame


func _shot(name: String, _scene: Node) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	var err := img.save_png(path)
	if err != OK:
		push_error("[ui_shots] 저장 실패 %s (%d)" % [path, err])
		return
	_shots += 1
	print("[ui_shots] %s (%dx%d)" % [name, img.get_width(), img.get_height()])
