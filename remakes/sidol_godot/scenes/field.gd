extends Node2D
## 필드 씬 — 맵 빌드 + 플레이어 스폰 + 카메라/HUD 조립 (Phase 1 MVP).
## TODO(Phase 2): 층별 아틀라스 일반화(현재 f1 플레이스홀더 전용), 문/계단/오버라이드 복원.

const SPAWN_DEFAULT := Vector2i(9, 9)   # 원작 main() x=9,y=9
const SEARCH_RADIUS := 8

var runtime: MapRuntime
var player: PlayerEntity
var gate: TransitionGate
var minimap: MinimapLayer
var dialogue_box: DialogueBox
var npcs: Array[NpcEntity] = []
var enemy_manager: EnemyManager
var triggers: TriggerSystem
var cutscene_player: CutscenePlayer
var _prompt_label: Label
var _talking_npc: NpcEntity
var _trigger_seq_active := false
var _prev_states := {}


## 코드 주입(action_press)과 실입력 모두에서 안정적인 엣지 검출.
func _edge(action: StringName) -> bool:
	var now := Input.is_action_pressed(action)
	var was: bool = bool(_prev_states.get(action, false))
	_prev_states[action] = now
	return now and not was


func _ready() -> void:
	var def := MapDefinition.load_from_json("res://data/maps/f%d.json" % GameState.current_floor)
	runtime = MapRuntime.new(def)
	_apply_chest_overrides()

	var renderer := MapRenderer.new()
	add_child(renderer)
	renderer.build(runtime)

	player = PlayerEntity.new()
	add_child(player)
	player.attach_map(runtime, find_spawn(def))

	var cam := Camera2D.new()
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = def.width * MapDefinition.TILE_PX
	cam.limit_bottom = def.height * MapDefinition.TILE_PX
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	player.add_child(cam)
	cam.make_current()

	add_child(HudV0.new())

	minimap = MinimapLayer.new()
	add_child(minimap)
	minimap.build(def)
	minimap.track(player)

	gate = TransitionGate.new()
	add_child(gate)
	gate.setup(self)

	dialogue_box = DialogueBox.new()
	add_child(dialogue_box)
	dialogue_box.finished.connect(_on_dialogue_finished)

	enemy_manager = EnemyManager.new()
	add_child(enemy_manager)
	enemy_manager.spawn_for_floor(GameState.current_floor, runtime, self)

	_prompt_label = Label.new()
	_prompt_label.text = "SPACE"
	_prompt_label.visible = false
	add_child(_prompt_label)

	_spawn_npcs()

	triggers = TriggerSystem.new()
	add_child(triggers)
	triggers.load_for_floor(GameState.current_floor)
	triggers.cutscene_requested.connect(_play_cutscene)
	triggers.sequence_requested.connect(_play_sequence)

	cutscene_player = CutscenePlayer.new()
	add_child(cutscene_player)
	cutscene_player.setup(self)
	cutscene_player.finished.connect(_on_cutscene_finished)

	add_child(PauseMenu.new())
	add_child(DebugPanel.new())   # F10 — 디버그 빌드 한정(패널 내부 가드)

	AudioManager.play_bgm(&"bgm_field")

	SaveManager.consume_autosave()


func _physics_process(_delta: float) -> void:
	if player == null:
		return

	GameState.player_cell = player.mover.grid_pos

	# 컷신 재생 중 — 입력·인카운터 전면 차단
	if cutscene_player != null and cutscene_player.is_running():
		return

	# 몬스터 틱 (EnemyManager에 위임)
	if enemy_manager != null:
		enemy_manager.tick(player.mover.grid_pos)
		var contact := enemy_manager.get_contact(player.mover.grid_pos)
		if contact != "":
			_trigger_encounter(contact)
			return

	# 이벤트 트리거 판정 (zone/auto)
	if triggers != null:
		triggers.tick(player.mover.grid_pos, _delta)

	var interact_edge := _edge(&"interact")
	var cancel_edge := _edge(&"cancel")

	# 대화 중: 입력을 박스 진행으로 중재 (단일 입력 경로)
	if dialogue_box.is_open:
		if interact_edge or cancel_edge:
			dialogue_box.advance()
		return

	# interact 트리거 우선 — NPC/상자보다 앞서 판정
	if triggers != null and interact_edge \
			and triggers.try_interact(front_cells()):
		return

	var npc := _npc_in_front()
	if npc != null:
		_prompt_label.visible = true
		_prompt_label.text = "%s  [SPACE]" % npc.display_name
		_prompt_label.position = npc.position + Vector2(-30, -44)
		if interact_edge:
			_start_dialogue(npc)
		return

	# 상자 상호작용
	var chest := _chest_in_front()
	if chest.x >= 0:
		_prompt_label.visible = true
		_prompt_label.text = "[SPACE] 열기"
		_prompt_label.position = Vector2(
				chest.x * MapDefinition.TILE_PX - 20,
				chest.y * MapDefinition.TILE_PX - 30)
		if interact_edge:
			_open_chest(chest)
		return

	_prompt_label.visible = false


func _chest_in_front() -> Vector2i:
	for c in front_cells():
		var a := runtime.definition.attr_at(c)
		if a >= 150 and a <= 184:
			return c
	return Vector2i(-9, -9)


func _open_chest(cell: Vector2i) -> void:
	var attr := runtime.definition.attr_at(cell)
	runtime.set_override_attr(cell, 1)   # 빈 상자 처리
	GameState.set_chest_override(cell, 1)   # 세이브 유지 대상
	EventBus.item_obtained.emit(StringName("chest_%d" % attr))
	AudioManager.play_sfx(&"sfx_item_get")
	_show_pickup_popup("아이템 획득!")


func _show_pickup_popup(text: String) -> void:
	var popup := Label.new()
	popup.text = text
	popup.add_theme_font_size_override("font_size", 14)
	popup.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	popup.position = player.position + Vector2(-40, -60)
	add_child(popup)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(popup, "position:y", popup.position.y - 24, 0.6)
	tw.tween_property(popup, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(popup.queue_free)


## 층 전환 후 맵 재구축 — TransitionGate가 페이드 중 호출 (new_anchor = 도착 앵커).
func rebuild_floor(new_anchor: Vector2i) -> void:
	var def := MapDefinition.load_from_json("res://data/maps/f%d.json" % GameState.current_floor)
	runtime = MapRuntime.new(def)
	_apply_chest_overrides()
	for child in get_children():
		if child is MapRenderer:
			child.queue_free()
	var renderer := MapRenderer.new()
	add_child(renderer)
	renderer.build(runtime)
	player.attach_map(runtime, new_anchor)
	minimap.build(def)


## 저장된 상자 개봉 상태를 런타임 오버라이드에 재적용 — 세이브/로드·층전환 공용.
func _apply_chest_overrides() -> void:
	var cells := GameState.chest_overrides_for(GameState.current_floor)
	for cell: Vector2i in cells:
		runtime.set_override_attr(cell, int(cells[cell]))


## ---- NPC / 대화 (Phase 3) ----

func _spawn_npcs() -> void:
	var path := "res://data/maps/npcs_f%d.json" % GameState.current_floor
	if not FileAccess.file_exists(path):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for n: Dictionary in raw.get("npcs", []):
		var cell := _nearest_passable(Vector2i(int(n["pos"][0]), int(n["pos"][1])))
		var tint_arr: Array = n.get("tint", [1.0, 1.0, 1.0])
		var npc := NpcEntity.new()
		add_child(npc)
		npc.setup(StringName(str(n["id"])), str(n["name"]),
				StringName(str(n["sequence_id"])), cell,
				Color(tint_arr[0], tint_arr[1], tint_arr[2]))
		npcs.append(npc)


func _nearest_passable(cell: Vector2i) -> Vector2i:
	if runtime.is_passable(cell):
		return cell
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := cell + Vector2i(dx, dy)
				if runtime.is_passable(c):
					return c
	return cell


func get_npc(npc_id: String) -> NpcEntity:
	for npc in npcs:
		if npc.npc_id == StringName(npc_id):
			return npc
	return null


## 플레이어 전방 2셀(원작 Talk() 상대 오프셋과 동일).
func front_cells() -> Array[Vector2i]:
	var p := player.mover.grid_pos
	match player.facing:
		&"left":
			return [p + Vector2i(-2, 0), p + Vector2i(-2, 1)]
		&"right":
			return [p + Vector2i(2, 0), p + Vector2i(2, 1)]
		&"up":
			return [p + Vector2i(0, -1), p + Vector2i(1, -1)]
		_:
			return [p + Vector2i(0, 3), p + Vector2i(1, 3)]


func _npc_in_front() -> NpcEntity:
	var cells := front_cells()
	for npc in npcs:
		if cells.has(npc.cell):
			return npc
	return null


func _start_dialogue(npc: NpcEntity) -> void:
	_talking_npc = npc
	player.mover.enabled = false
	_prompt_label.visible = false
	var steps: Array = Database.sequence(npc.sequence_id)
	if steps.is_empty():
		push_warning("빈 시퀀스: %s" % npc.sequence_id)
		player.mover.enabled = true
		return
	dialogue_box.start(npc.sequence_id, steps)


func _on_dialogue_finished(_seq_id: StringName) -> void:
	if _talking_npc != null:
		player.mover.enabled = true
		_talking_npc = null
	elif _trigger_seq_active:
		_trigger_seq_active = false
		player.mover.enabled = true


## ---- 컷신 / 트리거 (Phase 7) ----

func _play_cutscene(cutscene_id: StringName) -> void:
	if player == null:
		return
	player.mover.enabled = false
	_prompt_label.visible = false
	var cfg := CutscenePlayer.load_cutscene(cutscene_id)
	if cfg.is_empty():
		push_warning("컷신 데이터 없음: %s" % cutscene_id)
		player.mover.enabled = true
		return
	cutscene_player.play(cfg)


func _on_cutscene_finished(_cutscene_id: StringName) -> void:
	if player != null:
		player.mover.enabled = true


func _play_sequence(sequence_id: StringName) -> void:
	var steps: Array = Database.sequence(sequence_id)
	if steps.is_empty():
		push_warning("빈 시퀀스(트리거): %s" % sequence_id)
		return
	player.mover.enabled = false
	_trigger_seq_active = true
	dialogue_box.start(sequence_id, steps)


## 몬스터 접촉 → 전투 씬 전환 (원작 Check_Quang 대응)
func _trigger_encounter(enemy_id: String) -> void:
	AudioManager.play_sfx(&"sfx_encounter")
	GameState.pending_encounter = {"enemies": [enemy_id]}
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


func get_player() -> PlayerEntity:
	return player


func get_runtime() -> MapRuntime:
	return runtime


## 원본 스폰(9,9)이 막혀 있으면 나선 탐색으로 최근 통행 셀 반환.
## 세이브 복원 시에는 저장 좌표가 유효하면 최우선 사용.
func find_spawn(def: MapDefinition) -> Vector2i:
	if GameState.player_cell.x >= 0 \
			and runtime.is_passable(GameState.player_cell):
		return GameState.player_cell
	if runtime.is_passable(SPAWN_DEFAULT):
		return SPAWN_DEFAULT
	for r in range(1, SEARCH_RADIUS):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := SPAWN_DEFAULT + Vector2i(dx, dy)
				if def.in_bounds(c) and runtime.is_passable(c):
					push_warning("스폰 보정: %s -> %s" % [SPAWN_DEFAULT, c])
					return c
	push_error("통행 가능한 스폰을 찾지 못함")
	return SPAWN_DEFAULT
