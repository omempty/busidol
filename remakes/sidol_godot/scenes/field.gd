extends Node2D
## 필드 씬 — 맵 빌드 + 플레이어 스폰 + 카메라/HUD 조립 (Phase 1 MVP).
## TODO(Phase 2): 층별 아틀라스 일반화(현재 f1 플레이스홀더 전용), 문/계단/오버라이드 복원.

const SPAWN_DEFAULT := Vector2i(9, 9)  # 원작 main() x=9,y=9
const SEARCH_RADIUS := 8
const ENCOUNTER_GRACE := 1.1  # 필드 진입 후 접촉 무시(초)

var runtime: MapRuntime
var player: PlayerEntity
var gate: TransitionGate
var minimap: MinimapLayer
var dialogue_box: DialogueBox
var npcs: Array[NpcEntity] = []
## 배경 보행자 — 말 걸 수 없고 길도 막지 않는다(원작 eventer 대응). npcs와 섞지 않는다.
var walkers: Array[WalkerEntity] = []
var enemy_manager: EnemyManager
var triggers: TriggerSystem
var cutscene_player: CutscenePlayer
var inventory_panel: InventoryPanel
var fast_travel: FastTravelPanel
var shop: ShopUI
var _prompt: InteractPrompt
var _focus: InteractFocus
var _plates: DoorPlates
var _coord_label: Label
var _coord_layer: CanvasLayer
var fx: FieldFx
var renderer: MapRenderer
var _talking_npc: NpcEntity
var _talking_walker: WalkerEntity
var _trigger_seq_active := false
var _prev_states := {}
## 잠긴/막힌 계단 안내 — stairs_locked/dead 신호 시각+문구. 1.2초간 플레이어 머리 위에 유지.
var _stairs_hint_until := 0.0
var _stairs_hint_text := ""
const STAIRS_HINT_SECS := 1.2
## 필드 진입 직후 접촉 무시 시간(초) — 전투에서 돌아오자마자 옆에 선 몬스터에게
## 다시 끌려가는 사고를 막는다(Q6 현대 편의). 스폰 안전거리로도 못 막는 경우가 있다.
var _encounter_grace := 0.0


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

	renderer = MapRenderer.new()
	add_child(renderer)
	renderer.build(runtime)
	_restore_opened_chests()

	fx = FieldFx.new()
	add_child(fx)

	player = PlayerEntity.new()
	add_child(player)
	player.attach_map(runtime, find_spawn(def))

	var cam := Camera2D.new()
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = def.width * MapDefinition.TILE_PX
	cam.limit_bottom = def.height * MapDefinition.TILE_PX
	# 스무딩 없음 — 격자 보간 이동은 이미 등속이고, snap_2d_transforms_to_pixel과
	# 겹치면 카메라와 플레이어가 각자 1px씩 반올림돼 캐릭터가 배경 위에서 떤다.
	cam.position_smoothing_enabled = false
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
	gate.stairs_locked.connect(_on_stairs_locked)
	gate.stairs_dead.connect(_on_stairs_dead)

	dialogue_box = DialogueBox.new()
	add_child(dialogue_box)
	dialogue_box.finished.connect(_on_dialogue_finished)
	dialogue_box.op_requested.connect(_on_dialogue_op)

	enemy_manager = EnemyManager.new()
	add_child(enemy_manager)

	_prompt = InteractPrompt.new()
	add_child(_prompt)

	_focus = InteractFocus.new()
	add_child(_focus)

	_plates = DoorPlates.new()
	add_child(_plates)
	_plates.setup(GameState.current_floor)

	_coord_label = HudTheme.label("", 13, HudTheme.TEXT_MUTED)
	var coord_layer := CanvasLayer.new()
	coord_layer.layer = 60
	coord_layer.add_child(_coord_label)
	_coord_label.position = Vector2(8, 8)
	coord_layer.visible = false
	add_child(coord_layer)
	_coord_layer = coord_layer

	_spawn_npcs()
	_spawn_walkers()
	# **액터가 먼저 서고 몬스터가 나중이다.** 구판은 이 호출이 _spawn_npcs()보다
	# 위에 있어서, 첫 층에서는 NPC 통행 오버라이드도 안 선 상태로 자리를 골랐고
	# "NPC가 사는 방은 비운다"는 판정에 넘길 액터 목록도 비어 있었다(2026-09-06).
	enemy_manager.spawn_for_floor(
		GameState.current_floor, runtime, self, player.mover.grid_pos, _actor_anchors()
	)

	triggers = TriggerSystem.new()
	add_child(triggers)
	triggers.load_for_floor(GameState.current_floor)
	triggers.cutscene_requested.connect(_play_cutscene)
	triggers.sequence_requested.connect(_play_sequence)

	cutscene_player = CutscenePlayer.new()
	add_child(cutscene_player)
	cutscene_player.setup(self)
	cutscene_player.finished.connect(_on_cutscene_finished)

	# 시스템 탭은 기능을 다시 만들지 않고 신호만 보낸다 — 세이브/로드가 두 벌이 되면
	# 한쪽만 고쳐져 갈라진다(04_uiux §1.3 주석 참조).
	inventory_panel = InventoryPanel.new()
	add_child(inventory_panel)  # PauseMenu보다 먼저 — cancel 입력 우선권

	var pause_menu := PauseMenu.new()
	add_child(pause_menu)
	inventory_panel.system_requested.connect(pause_menu.open_action)
	add_child(DebugPanel.new())  # F10 — 디버그 빌드 한정(패널 내부 가드)

	AudioManager.play_bgm(&"bgm_field")

	shop = ShopUI.new()
	add_child(shop)
	shop.closed.connect(func() -> void: player.mover.enabled = true)

	fast_travel = FastTravelPanel.new()
	add_child(fast_travel)
	fast_travel.floor_chosen.connect(_on_fast_travel_chosen)

	GameState.mark_visited(GameState.current_floor)
	_encounter_grace = ENCOUNTER_GRACE
	SaveManager.consume_autosave()


func _physics_process(_delta: float) -> void:
	if player == null:
		return

	GameState.player_cell = player.mover.grid_pos

	# 개발자 모드 좌표 — F9를 켜면 좌상단에 실시간 셀 좌표.
	if SettingsManager.developer_mode:
		_coord_layer.visible = true
		_coord_label.text = (
			"F%d (%d, %d)"
			% [GameState.current_floor, player.mover.grid_pos.x, player.mover.grid_pos.y]
		)
	else:
		_coord_layer.visible = false

	# 문패 — 매 프레임 갱신(값싼 거리 비교). 대화·메뉴 중에는 _prompt와 무관하게 둔다.
	if _plates != null:
		_plates.tick(player.mover.grid_pos)

	# 컷신 재생 중 — 입력·인카운터 전면 차단
	if cutscene_player != null and cutscene_player.is_running():
		return

	# 빠른 이동 창이 열려 있으면 월드 입력을 넘기지 않는다(패널이 직접 처리).
	if fast_travel != null and fast_travel.is_open():
		return
	if shop != null and shop.is_open():
		return

	var interact_edge := _edge(&"interact")
	var cancel_edge := _edge(&"cancel")
	var inv_edge := _edge(&"inventory")

	if inv_edge and not inventory_panel.visible:
		inventory_panel.open()
		return
	if inventory_panel.visible:
		return  # 가방 개방 중 — 입력은 패널이, 월드 정지는 paused가 담당

	# 대화 중: 입력을 박스 진행으로 중재 (단일 입력 경로)
	#
	# **몬스터 틱·트리거 틱보다 앞이다.** 컷신·상점·빠른이동·가방은 이미 각자 위에서
	# 월드를 세우는데 대화창만 세우지 않아, 말을 거는 동안에도 적이 계속 다가와 닿으면
	# 인카운터가 씬을 갈아 대사를 통째로 삼켰다(2026-09-06). 그러면 DialogueManager가
	# 이미 올려 둔 청취 기록만 남아 "안 읽었는데 읽은 것"이 되고, 다음에 말을 걸면
	# 기준 대사를 건너뛰고 반복 풀부터 나온다. triggers.tick도 같은 이유로 막는다 —
	# 열려 있는 대화창 위로 _play_sequence()가 start()를 다시 불러 덮어썼다.
	# 적은 대화가 끝나면 그 자리에서 다시 움직인다(닿아 있으면 그때 인카운터가 뜬다).
	if dialogue_box.is_open:
		# 대화 중 ENTER = 대화 로그(04_uiux §1.2). 필드 메뉴는 대사가 없을 때만 뜬다.
		if _edge(&"menu"):
			dialogue_box.toggle_log()
			return
		if dialogue_box.is_log_open():
			return  # 로그를 읽는 중 — 진행 입력은 로그 창이 받는다
		if interact_edge or cancel_edge:
			dialogue_box.advance()
		return

	# 몬스터 틱 (EnemyManager에 위임)
	if _encounter_grace > 0.0:
		_encounter_grace -= _delta
	if enemy_manager != null:
		enemy_manager.tick(player.mover.grid_pos, _delta)
		var contact := enemy_manager.contact_entity(player.mover.grid_pos)
		if contact != null and _encounter_grace <= 0.0:
			# **붙은 개체는 명단에서 뺀다.** 이기면 잡은 것이고, 도망쳐도 그 자리에
			# 그대로 서 있으면 도망이 아니다. 전투는 씬 전환이라 지금 빼 둬야 한다.
			var species := String(contact.species_id)
			var p_face := player.facing_vector()
			var e_face := contact.facing_vector()
			var enemy_alerted := contact.is_alerted()
			var is_advantage := false
			var is_ambush := false

			if not enemy_alerted:
				# 적이 플레이어를 인지하지 못한 상태에서 기습 -> 선제 공격권(Advantage)
				is_advantage = true
			elif p_face != Vector2i.ZERO and e_face != Vector2i.ZERO and p_face == e_face:
				# 플레이어가 도망치는 중 등 뒤에서 적에게 닿음 -> 적 기습(Ambush)
				is_ambush = true

			enemy_manager.remove_entity(contact)
			_trigger_encounter(species, is_advantage, is_ambush)
			return

	# 이벤트 트리거 판정 (zone/auto)
	if triggers != null:
		triggers.tick(player.mover.grid_pos, _delta)

	# interact 트리거 우선 — 계단 앵커 위 컷신(폭파·희생)이 빠른 이동에
	# 가로막히면 진행이 영영 막힌다(2026-09-05 실측: 방문층 2개부터 blast 불발).
	if triggers != null and interact_edge:
		var icells := front_cells()
		# 계단 위에서는 발밑 앵커도 본다 — 판정이 몸 앞만 봐서 계단 위
		# SPACE가 트리거에 안 닿았다. 앵커 한정이라 오발사 없음(셋 다 앵커).
		if gate != null and gate.is_travel_anchor(player.mover.grid_pos):
			for c in Placement.body_cells(player.mover.grid_pos):
				if not icells.has(c):
					icells.append(c)
		if triggers.try_interact(icells):
			return

	# 계단 위 SPACE → 빠른 이동(Q5). 트리거·NPC 다음 — 앵커라도 앞의 사건이 먼저다.
	if interact_edge and gate != null and gate.is_travel_anchor(player.mover.grid_pos):
		if fast_travel.open_for(GameState.current_floor):
			return

	var npc := _npc_in_front()
	if npc != null:
		_prompt.show_at("%s   SPACE" % npc.display_name, npc.position + Vector2(0, -46))
		_focus.show_cells(npc.body_cells())
		# 접근 반응 — 말을 걸기 전부터 플레이어를 쳐다본다(이동 중에는 손대지 않음).
		if not npc._is_wandering:
			npc.face_towards(player.mover.grid_pos)
		if interact_edge:
			_start_dialogue(npc)
		return

	var walker := _walker_in_front()
	if walker != null and not walker.sequence_id.is_empty():
		_prompt.show_at("%s   SPACE" % walker.display_name, walker.position + Vector2(0, -46))
		_focus.show_cells(Placement.body_cells(walker.cell))
		if interact_edge:
			_start_walker_dialogue(walker)
		return

	# 원작 ATT 대화 마커 — 맵 그림에 붙은 말 걸 수 있는 자리(TalkTargets 참조).
	# NPC 다음, 상자 앞이다: NPC는 우리가 세운 액터라 더 구체적이고, 상자는
	# 사거리가 한 칸 더 넓어(chest_cells) 뒤에 두어야 가까운 것이 먼저 잡힌다.
	var talk_cell := _talk_in_front()
	if talk_cell.x >= 0:
		var talk_attr := runtime.attr_at(talk_cell)
		_prompt.show_at(
			"%s   SPACE" % TalkTargets.display_name(talk_attr),
			Vector2(talk_cell.x + 0.5, talk_cell.y) * MapDefinition.TILE_PX - Vector2(0, 26)
		)
		_focus.show_cells([talk_cell])
		if interact_edge:
			_start_talk(talk_attr)
		return

	# 상자 상호작용
	var chest := _chest_in_front()
	if chest.x >= 0:
		_prompt.show_at(
			tr("UI_FIELD_OPEN"),
			Vector2(chest.x + 0.5, chest.y) * MapDefinition.TILE_PX - Vector2(0, 26)
		)
		# **어느 상자가 열리는지 보여 준다.** 나란히 놓인 상자 앞에서는 알약만으로
		# 대상을 알 수 없었다(덩어리 판정과 같은 _chest_group을 그대로 쓴다).
		_focus.show_cells(_chest_group(chest, runtime.attr_at(chest)))
		if interact_edge:
			_open_chest(chest)
		return

	# 계단 행선 — 앵커 위에 서면 윗층/아랫층·목적지를 알약에 (원작 타일은 동결이라 런타임 표시).
	if gate != null:
		var stair_label := gate.anchor_label(player.mover.grid_pos, GameState.current_floor)
		if stair_label.is_empty() and gate.is_travel_anchor(player.mover.grid_pos):
			stair_label = tr("UI_STAIRS_DEAD")
		if not stair_label.is_empty():
			_prompt.show_at(stair_label, player.position + Vector2(0, -46))
			return

	# 잠긴/막힌 계단 안내 — 다른 상호작용이 없을 때만 (우선순위 최하).
	if Time.get_ticks_msec() / 1000.0 < _stairs_hint_until and not _stairs_hint_text.is_empty():
		_prompt.show_at(_stairs_hint_text, player.position + Vector2(0, -46))
		return
	_prompt.visible = false
	_focus.clear()


## 잠긴 계단에서 아래키 — 무반응 대신 이유를 보여 준다.
func _on_stairs_locked() -> void:
	_stairs_hint_until = Time.get_ticks_msec() / 1000.0 + STAIRS_HINT_SECS
	_stairs_hint_text = tr("UI_STAIRS_LOCKED")


## 막힌 계단에서 아래키 — 현 층에서는 어디로도 이어지지 않는다.
func _on_stairs_dead() -> void:
	_stairs_hint_until = Time.get_ticks_msec() / 1000.0 + STAIRS_HINT_SECS
	_stairs_hint_text = tr("UI_STAIRS_DEAD")


## 문 통과 연출 — TransitionGate가 3칸 점프 직전에 부른다(연출만, 판정은 게이트의 몫).
func play_door_fx(anchor: Vector2i, dir: Vector2i, hold: float) -> void:
	if fx == null or renderer == null:
		return
	fx.door_open(renderer, anchor, dir, hold)
	# 문 그림 뒤로 들어갔다 반대편에서 나온다 — 이동 자체는 원작대로 3칸 점프다.
	fx.actor_through_door(player, hold)


## 대사 시퀀스의 op 스텝 — shop과 set_flags. 구판은 op이 실행되지 않았다.
##
## **set_flags를 여기서 처리하지 않으면 대사가 세우는 플래그가 통째로 죽는다.**
## 컷신(CutscenePlayer)에는 있고 대사에는 없어서, dialogue_sequences.json이 적어 둔
## set_flags가 "알 수 없는 시퀀스 op"로 버려지고 있었다(2026-08-29 발견).
func _on_dialogue_op(op_name: String, _args: Dictionary) -> void:
	match op_name:
		"shop":
			player.mover.enabled = false
			shop.open()
		"set_flags":
			for k: String in _args:
				GameState.set_flag(k, _args[k])
			player.mover.enabled = true
		_:
			push_warning("알 수 없는 시퀀스 op: %s" % op_name)
			player.mover.enabled = true


func _on_fast_travel_chosen(floor_no: int) -> void:
	_prompt.visible = false
	gate.fast_travel(floor_no, player.mover.grid_pos)


## 상자 ATT 범위 — 150~184 아이템 상자, 198 MEET(몬스터), 199 EMPTY(빈 상자).
## 구판은 150~184만 봐서 전 층 상자 184덩어리 중 **109덩어리(198/199)가 조사 자체 불가**였다.
const CHEST_MIN := 150
const CHEST_MAX := 186
const CHEST_MEET := 198
## 열린 상자 오브젝트 id — 원작 `check_item()`이 넣는 값 그대로(왼쪽 153 / 오른쪽 154).
const OPEN_CHEST_LEFT := 153
const OPEN_CHEST_RIGHT := 154
const CHEST_EMPTY := 199


func _is_chest(a: int) -> bool:
	return (a >= CHEST_MIN and a <= CHEST_MAX) or a == CHEST_MEET or a == CHEST_EMPTY


## 조사 대상 판정은 **런타임 ATT**로 한다. 원본을 읽으면 이미 연 상자가 계속 상자로
## 보여 재개봉이 되고, 같은 줄 뒤쪽 상자를 가린다(MapRuntime.attr_at 주석 참고).
## 앞에 말 걸 수 있는 원작 마커가 있는가. 사거리는 정면 판정 그대로 —
## 원작 Talk()도 몸 바로 앞 한 줄만 봤다(상자만 한 칸 더 본다).
func _talk_in_front() -> Vector2i:
	for c in front_cells():
		if TalkTargets.has(runtime.attr_at(c)):
			return c
	return Vector2i(-9, -9)


## 원작 마커 대화 시작 — 대사는 @t 원문 그대로(TalkTargets가 반복 횟수를 센다).
func _start_talk(attr: int) -> void:
	var steps: Array = TalkTargets.steps_for(attr)
	if steps.is_empty():
		return
	player.mover.enabled = false
	_trigger_seq_active = true
	_prompt.visible = false
	dialogue_box.start(StringName("talk_%d" % attr), steps)


## 상자는 정면보다 **한 칸 더** 본다 — 아이템 마커가 상자 윗칸에 있어서다.
## 근거와 사거리는 InteractProbe.chest_cells에 적었다(원작 check_item 비대칭).
func _chest_in_front() -> Vector2i:
	for c in chest_cells():
		if _is_chest(runtime.attr_at(c)):
			return c
	return Vector2i(-9, -9)


## 원작 상자는 여러 셀에 같은 ATT 값으로 깔린다(가로 2셀이 표준).
## 한 셀만 비우면 나머지 셀이 그대로 상자로 남아 같은 상자를 두 번 열 수 있다 —
## 붙어 있는 같은 값 셀을 통째로 소비한다.
##
## ATT → 실제 아이템은 items.json의 legacy_ref(원작 ITEM_STRUCT 인덱스 매핑)가 정한다.
## 구판은 `chest_%d` 이벤트만 쏘고 **아무것도 주지 않았다** — 표는 있는데 안 썼다.
func _open_chest(cell: Vector2i) -> void:
	var attr := runtime.attr_at(cell)
	var group := _chest_group(cell, attr)
	# 연출을 먼저 띄우고(원래 그림을 복제한다) 그 다음 그림을 지운다 — 순서가 바뀌면
	# 복제할 그림이 이미 없다.
	if fx != null and renderer != null:
		fx.chest_open(renderer, group)
	for c in group:
		runtime.set_override_attr(c, 1)  # 빈 상자 처리
		GameState.set_chest_override(c, 1)  # 세이브 유지 대상
	_draw_opened_chest(group)
	_focus.clear()
	EventBus.item_obtained.emit(StringName("chest_%d" % attr))

	if attr == CHEST_MEET:
		# 원작 MEET — 상자를 열면 몬스터가 튀어나온다 (기습 인카운터).
		AudioManager.play_sfx(&"sfx_encounter")
		_show_pickup_popup(tr("UI_FIELD_AMBUSH"))
		var species := Database.encounter_species(GameState.current_floor)
		if not species.is_empty():
			_trigger_encounter(str(species[0]["id"]), false, true)
		return

	var item_id := Database.legacy_item(attr)
	if attr == CHEST_EMPTY or item_id.is_empty():
		AudioManager.play_sfx(&"sfx_menu_move")
		_show_pickup_popup(tr("UI_FIELD_EMPTY"))
		return

	var def := Database.get_item(item_id)
	AudioManager.play_sfx(&"sfx_item_get")
	# money 계열은 소지품이 아니라 골드로 — ItemEffects가 판정한다.
	if ItemEffects.on_acquire(item_id, 1):
		GameState.inventory.add(item_id, 1)
		_show_pickup_popup(tr("UI_FIELD_GOT_ITEM") % str(def.get("name_ko", item_id)))
	else:
		_show_pickup_popup("%s" % str(def.get("name_ko", item_id)))


## 같은 ATT 값으로 4방향 인접한 셀 덩어리 = 상자 하나.
func _chest_group(start: Vector2i, attr: int) -> Array[Vector2i]:
	var seen: Dictionary = {start: true}
	var stack: Array[Vector2i] = [start]
	var out: Array[Vector2i] = [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n := c + d
			if seen.has(n) or runtime.attr_at(n) != attr:
				continue
			seen[n] = true
			out.append(n)
			stack.append(n)
	return out


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
	renderer = MapRenderer.new()
	add_child(renderer)
	renderer.build(runtime)
	_restore_opened_chests()
	# 착지 보정 — 계단/빠른 이동 앵커가 그 층에서 막혀 있을 수 있다(층마다 지형이 다르다).
	var landing := _nearest_body_spot(new_anchor)
	player.attach_map(runtime, landing if landing.x >= 0 else new_anchor)
	GameState.mark_visited(GameState.current_floor)
	_encounter_grace = ENCOUNTER_GRACE
	minimap.build(def)
	# 층에 매인 것들을 새 층 것으로 교체한다. 구판은 맵만 갈아끼워
	# 이전 층의 NPC·몬스터가 그대로 서 있고 트리거도 옛 층 것이 돌았다.
	_despawn_npcs()
	_despawn_walkers()
	_spawn_npcs()  # NPC 통행 오버라이드가 먼저 서야 몬스터가 그 자리를 피한다
	# **워커도 다시 세운다.** 구판은 여기서 _despawn_walkers()만 하고 다시 세우지
	# 않아, 계단을 한 번 오르내리면 배경 보행자가 그 판 내내 사라졌다(2026-09-06).
	# 13차 세션이 전 층에 워커 대사를 붙여 놓았는데 첫 층에서만 만날 수 있었다.
	_spawn_walkers()
	if enemy_manager != null:
		enemy_manager.spawn_for_floor(
			GameState.current_floor, runtime, self, new_anchor, _actor_anchors()
		)
	if triggers != null:
		triggers.load_for_floor(GameState.current_floor)
	_talking_npc = null
	_prompt.visible = false
	if _focus != null:
		_focus.clear()


## 이미 연 상자는 그림도 없어야 한다 — 맵을 다시 지으면 정의(원본)에서 그리므로
## 열린 상자가 되살아난 것처럼 보인다. 오버라이드가 남긴 기록으로 그림을 다시 지운다.
func _restore_opened_chests() -> void:
	if renderer == null:
		return
	# 열린 상자는 가로로 짝을 이룬다. 저장된 칸들을 y별로 모아 x순으로 늘어놓아야
	# 왼쪽/오른쪽 그림이 제자리에 간다 — 사전 순서를 그대로 믿으면 안 된다.
	var rows := {}
	for cell: Vector2i in GameState.chest_overrides_for(GameState.current_floor):
		var row: Array = rows.get(cell.y, [])
		row.append(cell)
		rows[cell.y] = row
	for y: Variant in rows:
		var row: Array = rows[y]
		row.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
		var run: Array = []
		for cell: Vector2i in row:
			if not run.is_empty() and cell.x != Vector2i(run[run.size() - 1]).x + 1:
				_draw_opened_chest(run)
				run = []
			run.append(cell)
		if not run.is_empty():
			_draw_opened_chest(run)


## 열린 상자 그림. **원작은 상자를 지우지 않고 열린 상자로 바꾼다** —
## `GOODITEM.C:check_item()`이 ATT를 1로 만든 다음 `OBJ[x]=153; OBJ[x+1]=154`를
## 넣는다. 우리는 그림을 통째로 지워서 상자가 흔적도 없이 사라졌다(2026-08-29
## 유저 지적). 열린 상자가 남아야 "여긴 이미 열었다"가 화면에 보인다.
func _draw_opened_chest(cells: Array) -> void:
	if renderer == null:
		return
	for i in cells.size():
		var cell: Vector2i = cells[i]
		# 짝이 아닌 나머지 칸(세로로 붙은 덩어리 등)은 왼쪽 그림으로 채운다.
		renderer.set_object(cell, OPEN_CHEST_RIGHT if i % 2 == 1 else OPEN_CHEST_LEFT)


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
	# 이미 점유된 셀: 플레이어 몸 + 먼저 배치된 NPC들 — 서로 겹치거나 플레이어 위에 서지 않게.
	var taken: Dictionary = {}
	for c in Placement.body_cells(player.mover.grid_pos):
		taken[c] = true

	for n: Dictionary in raw.get("npcs", []):
		var desired := Vector2i(int(n["pos"][0]), int(n["pos"][1]))
		var spot := Placement.find_spot(runtime, desired, taken)
		var cell: Vector2i = spot["anchor"]
		var relaxed := int(spot["relaxed"])
		if relaxed >= 3:
			push_warning("NPC 배치 실패(원위치 사용): %s @%s" % [n["id"], desired])
		elif relaxed > 0:
			push_warning("NPC 배치 제약 완화(%d): %s %s -> %s" % [relaxed, n["id"], desired, cell])
		var tint_arr: Array = n.get("tint", [1.0, 1.0, 1.0])
		var wander_range := int(n.get("wander_range", 0))
		var npc := NpcEntity.new()
		add_child(npc)
		npc.setup(
			StringName(str(n["id"])),
			str(n["name"]),
			StringName(str(n["sequence_id"])),
			cell,
			Color(tint_arr[0], tint_arr[1], tint_arr[2]),
			n.get("sequence_variants", []),
			wander_range,
			runtime,
			n.get("repeat_sequence_id", null)
		)
		npcs.append(npc)
		# 고정 액터는 실체가 있어야 한다 — 통과해 지나가지 못하게 몸 셀을 막는다.
		# Placement가 문간과 길목을 피해 자리를 골랐으므로 통로는 끊기지 않는다.
		for c in npc.body_cells():
			taken[c] = true
			runtime.set_override_attr(c, 1)


## 배경 보행자 — 대화 상대와 **다른 종류의 존재**다(WalkerEntity 주석 참고).
## 길을 막지 않으므로 통행 오버라이드도 건드리지 않는다: 그래서 이 함수는
## NPC 배치와 달리 자리 다툼을 하지 않는다.
## 이 층에 서 있는 액터(고정 NPC + 배회 워커)의 **앵커** — EnemyManager가 "NPC가 사는
## 방"을 스폰에서 빼는 데 쓴다. 상자에서 나오는 NPC는 액터가 아니라 여기 없다.
func _actor_anchors() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for n: NpcEntity in npcs:
		out.append(n.cell)
	for w: WalkerEntity in walkers:
		out.append(w.cell)
	return out


func _spawn_walkers() -> void:
	var path := "res://data/maps/walkers_f%d.json" % GameState.current_floor
	if not FileAccess.file_exists(path):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("보행자 파일 파싱 실패: %s" % path)
		return
	for w: Dictionary in Dictionary(raw).get("walkers", []):
		var legs: Array = []
		for leg: Dictionary in w.get("pattern", []):
			legs.append(
				{"dir": _dir_of(str(leg.get("dir", ""))), "steps": int(leg.get("steps", 0))}
			)
		var walker := WalkerEntity.new()
		add_child(walker)
		walker.setup(
			StringName(str(w.get("id", ""))),
			StringName(str(w.get("sprite", ""))),
			Vector2i(int(w["pos"][0]), int(w["pos"][1])),
			legs,
			runtime,
			str(w.get("name", "")),
			StringName(str(w.get("sequence_id", ""))),
			w.get("sequence_variants", []),
			w.get("repeat_sequence_id", null)
		)
		walkers.append(walker)


func _dir_of(name: String) -> Vector2i:
	match name:
		"up":
			return Vector2i.UP
		"down":
			return Vector2i.DOWN
		"left":
			return Vector2i.LEFT
		"right":
			return Vector2i.RIGHT
	return Vector2i.ZERO


func _despawn_walkers() -> void:
	for w in walkers:
		if is_instance_valid(w):
			w.queue_free()
	walkers.clear()


func _despawn_npcs() -> void:
	for npc in npcs:
		if is_instance_valid(npc):
			npc.queue_free()
	npcs.clear()


func get_npc(npc_id: String) -> NpcEntity:
	for npc in npcs:
		if npc.npc_id == StringName(npc_id):
			return npc
	return null


## 구판은 좌/하 방향만 한 칸 더 멀리 봐서(x−2 · y+3), 왼쪽과 아래에 붙은
## 상자·NPC를 조사할 수 없었다. 이제 네 방향 모두 몸에 맞닿은 셀을 본다.
## 조사 판정 셀 — 판정 모양은 InteractProbe가 정본이다(도구도 같은 것을 물어본다).
## 이름은 그대로 둔다: 트리거·NPC·상자가 전부 이 이름으로 이 함수를 부른다.
func front_cells() -> Array[Vector2i]:
	return InteractProbe.probe_cells(player.mover, player.mover.grid_pos, player.facing_vector())


## 상자 조사 사거리 — 정면 + (위를 볼 때) 한 칸 더. 근거는 InteractProbe.chest_cells.
func chest_cells() -> Array[Vector2i]:
	return InteractProbe.chest_cells(player.mover, player.mover.grid_pos, player.facing_vector())


func _npc_in_front() -> NpcEntity:
	for c in front_cells():
		for npc in npcs:
			if npc.occupies(c):
				return npc
	return null


func _walker_in_front() -> WalkerEntity:
	for c in front_cells():
		for w in walkers:
			if is_instance_valid(w) and w.occupies(c):
				return w
	return null


func _start_dialogue(npc: NpcEntity) -> void:
	_talking_npc = npc
	player.mover.enabled = false
	_prompt.visible = false
	npc.face_towards(player.mover.grid_pos)
	npc.set_talking(true)
	# **지금 상태에 맞는 대사**를 고른다 — 두 번째로 찾아가면 다른 말을 할 수 있다.
	var seq := npc.resolve_sequence()
	var steps: Array = Database.sequence(seq)
	if steps.is_empty():
		push_warning("빈 시퀀스: %s" % seq)
		npc.set_talking(false)
		player.mover.enabled = true
		return
	dialogue_box.start(seq, steps)


func _start_walker_dialogue(walker: WalkerEntity) -> void:
	_talking_walker = walker
	player.mover.enabled = false
	_prompt.visible = false
	walker.face_towards(player.mover.grid_pos)
	walker.set_talking(true)
	var seq := walker.resolve_sequence()
	var steps: Array = Database.sequence(seq)
	if steps.is_empty():
		push_warning("빈 시퀀스: %s" % seq)
		walker.set_talking(false)
		player.mover.enabled = true
		return
	dialogue_box.start(seq, steps)


func _on_dialogue_finished(_seq_id: StringName) -> void:
	if _talking_npc != null:
		_talking_npc.set_talking(false)
		player.mover.enabled = true
		_talking_npc = null
	elif _talking_walker != null:
		_talking_walker.set_talking(false)
		player.mover.enabled = true
		_talking_walker = null
	elif _trigger_seq_active:
		_trigger_seq_active = false
		player.mover.enabled = true


## ---- 컷신 / 트리거 (Phase 7) ----


func _play_cutscene(cutscene_id: StringName) -> void:
	if player == null:
		return
	player.mover.enabled = false
	_prompt.visible = false
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
func _trigger_encounter(enemy_id: String, advantage: bool = false, ambush: bool = false) -> void:
	AudioManager.play_sfx(&"sfx_encounter")
	var edef := Database.get_enemy_def(StringName(enemy_id))
	GameState.pending_encounter = {
		"enemies": [enemy_id],
		# first_win_flag(Q_F1_START 등) — 승리 시 BattleSceneController가 세팅
		"on_win_flag": str(edef.get("first_win_flag", "")),
		"advantage": advantage,
		"ambush": ambush,
	}
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


func get_player() -> PlayerEntity:
	return player


func get_runtime() -> MapRuntime:
	return runtime


## 스폰 좌표 결정. 세이브 복원·디버그 텔레포트의 착지 좌표가 최우선 —
## 몸이 안 들어가면 나선 탐색으로 가장 가까운 유효 앵커로 보정한다.
## 구판은 **셀 하나만** 통행 검사해서, f4처럼 (9,9)는 뚫려 있고 (10,9)가 벽인 층에서
## 몸의 오른쪽 절반이 벽에 박힌 채 스폰됐고 그 층 전체가 이동 불가였다.
func find_spawn(_def: MapDefinition) -> Vector2i:
	for candidate: Vector2i in [GameState.player_cell, SPAWN_DEFAULT]:
		if candidate.x < 0:
			continue
		var spot := _nearest_body_spot(candidate)
		if spot.x >= 0:
			if spot != candidate:
				push_warning("스폰 보정: %s -> %s" % [candidate, spot])
			return spot
	push_error("2x2 몸이 들어가는 스폰을 찾지 못함")
	return SPAWN_DEFAULT


## 2×2 몸이 통째로 들어가는 가장 가까운 앵커(체비셰프 나선). 없으면 (-1,-1).
func _nearest_body_spot(cell: Vector2i) -> Vector2i:
	for r in range(0, SEARCH_RADIUS + 1):
		for c: Vector2i in Placement.ring(cell, r):
			if Placement.body_fits(runtime, c):
				return c
	return Vector2i(-1, -1)
