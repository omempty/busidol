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

	# 미니맵 캡처
	if field.minimap != null:
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
