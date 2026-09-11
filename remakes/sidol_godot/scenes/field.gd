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
## 층 조명 — 어두운 층(F0)에서만 톤을 낮추고 액터에 광원을 단다. 밝은 층에서는 아무 일도 안 한다.
var lighting: FloorLighting
## 안개가 기록할 범위를 정하는 주체. 맵 가장자리에서는 limit이 걸려 주인공이
## 화면 복판에 없으므로, 주인공이 아니라 **카메라**에게 물어야 한다.
var _cam: Camera2D
var _prompt: InteractPrompt
var _focus: InteractFocus
var _plates: DoorPlates
## 소품 덧층 — 원본 맵 3층은 바이트 일치로 잠겨 있어 소품을 거기 쓸 수 없다.
## data/maps/props_f*.json을 읽어 ATT만 덧씌운다(chest_overrides와 같은 기구의 정적 판).
var _props: PropsLayer
var _coord_label: Label
var _coord_layer: CanvasLayer
var fx: FieldFx
var renderer: MapRenderer
## 맵아트 최소 움직임 — 타일 교체 애니메이터(표가 비면 no-op). bind는 renderer.build 직후.
var tile_animator: MapTileAnimator
## 맵 때·벽장식 오버레이 — 층 분위기 오염+장식. bind는 renderer.build 직후.
var dressing_overlay: MapDressingOverlay
var _talking_npc: NpcEntity
var _talking_walker: WalkerEntity
## 말풍선 기록(세션 한정) — 첫 조우 "!"와 새 대사 "!"를 한 번씩만 띄우기 위함.
## _emoted_first: 배우 id → true(첫 "!"를 이미 봄). _emoted_seq: 배우 id → 마지막으로 본 시퀀스.
var _emoted_first: Dictionary = {}
var _emoted_seq: Dictionary = {}
## 말풍선 셀 앵커(맵아트 인물용) — 몸이 없어 프롬프트 좌표에 띄운다.
var _emote_anchor: Node2D = null
var _trigger_seq_active := false
var _prev_states := {}
## 잠긴/막힌 계단 안내 — stairs_locked/dead 신호 시각+문구. 1.2초간 플레이어 머리 위에 유지.
var _stairs_hint_until := 0.0
var _stairs_hint_text := ""
const STAIRS_HINT_SECS := 1.2
## 필드 진입 직후 접촉 무시 시간(초) — 전투에서 돌아오자마자 옆에 선 몬스터에게
## 다시 끌려가는 사고를 막는다(Q6 현대 편의). 스폰 안전거리로도 못 막는 경우가 있다.
var _encounter_grace := 0.0
## 안개를 마지막으로 넓힌 자리 — 칸이 바뀔 때만 다시 센다.
## 매 프레임 돌리면 21×21칸 × Bresenham을 초당 60번 하게 된다.
var _fog_cell := Vector2i(-9999, -9999)


## 코드 주입(action_press)과 실입력 모두에서 안정적인 엣지 검출.
func _edge(action: StringName) -> bool:
	var now := Input.is_action_pressed(action)
	var was: bool = bool(_prev_states.get(action, false))
	_prev_states[action] = now
	return now and not was


func _ready() -> void:
	var def := MapDefinition.load_from_json("res://data/maps/f%d.json" % GameState.current_floor)
	runtime = MapRuntime.new(def)
	# 소품 먼저, 상자 나중 — 같은 칸이 겹치면 플레이 결과(열린 상자)가 이겨야 한다.
	_props = PropsLayer.load_floor(GameState.current_floor)
	_props.apply_to(runtime)
	_apply_chest_overrides()

	renderer = MapRenderer.new()
	add_child(renderer)
	renderer.build(runtime)
	_restore_opened_chests()
	tile_animator = MapTileAnimator.new()
	add_child(tile_animator)
	tile_animator.bind_floor(GameState.current_floor, renderer)
	dressing_overlay = MapDressingOverlay.new()
	add_child(dressing_overlay)
	dressing_overlay.bind_floor(GameState.current_floor, runtime)

	fx = FieldFx.new()
	add_child(fx)
	lighting = FloorLighting.new()
	add_child(lighting)

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
	_cam = cam

	add_child(HudV0.new())

	minimap = MinimapLayer.new()
	add_child(minimap)
	minimap.build(runtime)
	minimap.track(player)

	gate = TransitionGate.new()
	add_child(gate)
	gate.setup(self)
	gate.stairs_locked.connect(_on_stairs_locked)
	gate.stairs_dead.connect(_on_stairs_dead)
	gate.door_locked.connect(_on_stairs_locked)
	# 잠긴 방 안 세이브 귀환 — 정전 한복판에 저장하면 밝은 층에 잠긴 방이라 꺼낸다.
	_eject_from_locked_room()

	dialogue_box = DialogueBox.new()
	add_child(dialogue_box)
	dialogue_box.finished.connect(_on_dialogue_finished)
	dialogue_box.op_requested.connect(_on_dialogue_op)

	enemy_manager = EnemyManager.new()
	add_child(enemy_manager)
	# 나중에 태어난 몬스터도 빛을 받아야 한다 — 이 배선이 없으면 첫 무리만 빛나고
	# 리스폰된 놈은 어두운 층에서 통째로 안 보인다.
	enemy_manager.enemy_spawned.connect(_on_enemy_spawned)
	enemy_manager.enemy_warped.connect(_on_enemy_warped)

	_prompt = InteractPrompt.new()
	add_child(_prompt)

	_focus = InteractFocus.new()
	add_child(_focus)

	_plates = DoorPlates.new()
	add_child(_plates)
	_plates.setup(GameState.current_floor)

	# 획득 알림 — GameState.acquired를 듣는다. 컷신도 필드의 자식이라 컷신 안에서
	# 준 것도 여기로 뜬다.
	add_child(AcquireToast.new())

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
		GameState.current_floor,
		runtime,
		self,
		player.mover.grid_pos,
		_actor_anchors(),
		_npc_anchors()
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
	# 주의: 자식 순서는 cancel 우선권을 **주지 않는다**. `_unhandled_input`은 뒤쪽
	# 형제부터 받으므로 뒤에 붙는 PauseMenu가 먼저 집는다(이 줄의 옛 주석이 반대로
	# 적혀 있었다). 우선권은 PauseMenu._other_modal_open()이 판단한다.
	add_child(inventory_panel)

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

	# **액터가 전부 선 뒤에 켠다.** 조명은 각 액터의 자식으로 붙으므로
	# 순서가 뒤집히면 그 시점에 없던 액터가 어둠에 묻힌다.
	lighting.apply(GameState.current_floor, _lit_actors())
	# 층에 들어선 자리는 바로 밝힌다 — 열자마자 새까만 지도를 보여 주지 않는다.
	_reveal_fog()


func _physics_process(_delta: float) -> void:
	if player == null:
		return

	GameState.player_cell = player.mover.grid_pos
	if player.mover.grid_pos != _fog_cell:
		_reveal_fog()

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

	# 주목 — 3칸 안에 들어온 고정 NPC가 플레이어를 본다(멀리서 알아보는 느낌).
	# 랜덤 둘러보기와 겹치지 않게 notice()가 look 타이머를 갱신한다. 대화·배회 중 제외.
	if player != null and player.mover != null:
		for n: NpcEntity in npcs:
			var dd: Vector2i = (n.cell - player.mover.grid_pos).abs()
			if maxi(dd.x, dd.y) <= 3:
				n.notice(player.mover.grid_pos)

	var npc := _npc_in_front()
	if npc != null:
		_prompt.show_at("%s   SPACE" % npc.display_name, npc.position + Vector2(0, -46))
		_focus.show_cells(npc.body_cells())
		# 접근 반응 — 말을 걸기 전부터 플레이어를 쳐다본다(이동 중에는 손대지 않음).
		if not npc._is_wandering:
			npc.face_towards(player.mover.grid_pos)
		_maybe_emote(String(npc.npc_id), npc, npc.peek_sequence())
		if interact_edge:
			_start_dialogue(npc)
		return

	var walker := _walker_in_front()
	if walker != null and not walker.sequence_id.is_empty():
		_prompt.show_at("%s   SPACE" % walker.display_name, walker.position + Vector2(0, -46))
		_focus.show_cells(Placement.body_cells(walker.cell))
		_maybe_emote(String(walker.walker_id), walker, walker.peek_sequence())
		if interact_edge:
			_start_walker_dialogue(walker)
		return

	# 원작 ATT 대화 마커 — 맵 그림에 붙은 말 걸 수 있는 자리(TalkTargets 참조).
	# NPC 다음, 상자 앞이다: NPC는 우리가 세운 액터라 더 구체적이고, 상자는
	# 사거리가 한 칸 더 넓어(chest_cells) 뒤에 두어야 가까운 것이 먼저 잡힌다.
	var talk_cell := _talk_in_front()
	if talk_cell.x >= 0:
		var talk_attr := runtime.attr_at(talk_cell)
		var talk_pos := (
			Vector2(talk_cell.x + 0.5, talk_cell.y) * MapDefinition.TILE_PX - Vector2(0, 26)
		)
		_prompt.show_at("%s   SPACE" % TalkTargets.display_name(talk_attr), talk_pos)
		_focus.show_cells([talk_cell])
		_maybe_emote_cell(talk_attr, talk_pos)
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

	# 소품 조사 — **상자·원작 마커 다음 순위**. 소품 ATT는 0/1/2뿐이라 앞의 판정과 겹치지
	# 않지만, 알약은 하나뿐이라 순서가 곧 우선순위다. 원작에 있던 것이 먼저 잡혀야 한다.
	var prop_cell := _prop_in_front()
	if prop_cell.x >= 0:
		var prop := _props.prop_at(prop_cell)
		_prompt.show_at(
			"%s   SPACE" % String(prop.get("name_ko", "")),
			Vector2(prop_cell.x + 0.5, prop_cell.y) * MapDefinition.TILE_PX - Vector2(0, 26)
		)
		# 어느 소품인지 몸 전체를 비춘다 — 그림이 아직 없어서(obj 아틀라스 미납품)
		# 지금은 이 하이라이트가 소품의 유일한 시각 단서다.
		_focus.show_cells(PropsLayer.cells_of(prop))
		if interact_edge:
			_start_inspect(prop)
		return

	# 계단 행선 — 앵커 위에 서면 윗층/아랫층·목적지를 알약에 (원작 타일은 동결이라 런타임 표시).
	if gate != null:
		var stair_label := gate.anchor_label(player.mover.grid_pos, GameState.current_floor)
		if stair_label.is_empty() and gate.is_travel_anchor(player.mover.grid_pos):
			stair_label = tr("UI_STAIRS_DEAD")
		if not stair_label.is_empty():
			var can_fast: bool = false
			for f: int in GameState.visited_list():
				if f != GameState.current_floor:
					can_fast = true
					break
			if can_fast:
				stair_label += "   " + tr("UI_STAIRS_FAST_KEYS")
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


## 대사 시퀀스의 op 스텝 — shop·set_flags·grant_skill. 구판은 op이 실행되지 않았다.
##
## **set_flags를 여기서 처리하지 않으면 대사가 세우는 플래그가 통째로 죽는다.**
## 컷신(CutscenePlayer)에는 있고 대사에는 없어서, dialogue_sequences.json이 적어 둔
## set_flags가 "알 수 없는 시퀀스 op"로 버려지고 있었다(2026-08-29 발견).
##
## **한 시퀀스에서 실행되는 op 스텝은 하나뿐이다.** DialogueBox._load_step()이 op 스텝을
## 만나면 `close()`를 먼저 부르고 그 다음에 op_requested를 쏜다 — 대화가 그 자리에서
## 끝나므로 op 뒤에 붙인 스텝은 대사든 op이든 영영 실행되지 않는다(2026-09-06 확인).
## 그래서 grant_skill은 **flag 인자를 같이 받는다**: 화공과 교수 대면처럼 "플래그를
## 세우면서 스킬도 준다"를 한 스텝으로 표현해야 하기 때문이다. 인자 이름은 craft op이
## 쓰는 「성공 시 세우는 플래그 하나」 규약(args.flag)을 그대로 따른다 — SelfCheck의
## 플래그 setter 수집기가 읽는 이름도 그것이라, 게이트가 이 플래그를 계속 본다.
## DialogueBox를 고쳐 op 스텝 뒤를 이어 재생하게 만드는 편이 정공법이지만, 그쪽은
## 컷신·상점·NPC가 모두 얹혀 있는 종료 경로라 이번 범위에서는 건드리지 않았다.
func _on_dialogue_op(op_name: String, _args: Dictionary) -> void:
	match op_name:
		"shop":
			player.mover.enabled = false
			shop.open()
		"set_flags":
			for k: String in _args:
				GameState.set_flag(k, _args[k])
			player.mover.enabled = true
		"grant_skill":
			# CutscenePlayer._execute의 grant_skill과 같은 동작(GameState.grant_skill).
			var flag := str(_args.get("flag", ""))
			if not flag.is_empty():
				GameState.set_flag(flag, true)
			var skid := StringName(str(_args.get("skill", "")))
			if GameState.grant_skill(skid):
				print("[dialogue] 스킬 습득: %s" % skid)
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


## 정면의 **조사 가능한** 소품 칸. 규약은 _talk_in_front와 같다(실패는 (-9,-9)).
##
## "조사 가능한"이 조건인 이유: requires_flag가 안 선 소품은 대사가 지금 상태와 어긋나므로
## 대상에서 뺀다(PropsLayer.inspect_steps 주석). 알약이 떴는데 눌러도 아무 말이 없는 것보다
## 애초에 안 뜨는 쪽이 낫다.
func _prop_in_front() -> Vector2i:
	if _props == null:
		return Vector2i(-9, -9)
	for c in front_cells():
		var prop := _props.prop_at(c)
		if prop.is_empty():
			continue
		if PropsLayer.inspect_steps(prop, GameState.flags).is_empty():
			continue
		return c
	return Vector2i(-9, -9)


## 소품 조사 — 원작 마커 대화(_start_talk)와 **같은 길**을 쓴다.
## 끝나는 처리도 그쪽과 같다: _trigger_seq_active를 세우면 _on_dialogue_finished가 이동을 되돌린다.
func _start_inspect(prop: Dictionary) -> void:
	var steps: Array = PropsLayer.inspect_steps(prop, GameState.flags)
	if steps.is_empty():
		return
	player.mover.enabled = false
	_trigger_seq_active = true
	_prompt.visible = false
	dialogue_box.start(StringName("prop_%s" % String(prop.get("id", "?"))), steps)


## 이 층의 소품 덧층 — 관문(world_audit)이 조사 도달성을 재는 데 쓴다.
func props_layer() -> PropsLayer:
	return _props


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
	# 축하 연출(스파클)은 내용물이 있을 때만 — 빈 상자·기습에 금빛이 터지면
	# 거짓 보상 신호가 된다. 뚜껑 팝(물리 동작)은 항상 나간다.
	var item_probe := Database.legacy_item(attr)
	var is_reward := attr != CHEST_MEET and attr != CHEST_EMPTY and not item_probe.is_empty()
	# 연출을 먼저 띄우고(원래 그림을 복제한다) 그 다음 그림을 지운다 — 순서가 바뀌면
	# 복제할 그림이 이미 없다.
	if fx != null and renderer != null:
		fx.chest_open(renderer, group, is_reward)
	for c in group:
		runtime.set_override_attr(c, 1)  # 빈 상자 처리
		GameState.set_chest_override(c, 1)  # 세이브 유지 대상
	_draw_opened_chest(group)
	_focus.clear()
	EventBus.item_obtained.emit(StringName("chest_%d" % attr))
	# 개봉음 — 열리는 순간에. 내용물음(획득·동전·기습)은 아래 분기에서 겹친다.
	AudioManager.play_sfx(&"sfx_chest_open")

	if attr == CHEST_MEET:
		# 원작 MEET — 상자를 열면 몬스터가 튀어나온다 (기습 인카운터).
		# 축하 연출이 아니라 위협 연출: 뚜껑이 날아가고 검은 연기가 뿜는다.
		# 장면이 즉시 바뀌면 경고가 스치듯 사라지므로 0.75초 공포 박자를 둔다.
		AudioManager.play_sfx(&"sfx_encounter")
		if fx != null and renderer != null:
			fx.chest_ambush(renderer, group)
		_show_pickup_popup(tr("UI_FIELD_AMBUSH"), null, Color(1.0, 0.35, 0.25))
		_kick_camera()
		await get_tree().create_timer(0.75).timeout
		var species := Database.encounter_species(GameState.current_floor)
		if not species.is_empty():
			_trigger_encounter(str(species[0]["id"]), false, true)
		return

	var item_id := Database.legacy_item(attr)
	if attr == CHEST_EMPTY or item_id.is_empty():
		AudioManager.play_sfx(&"sfx_menu_move")
		_show_pickup_popup(tr("UI_FIELD_EMPTY"), null, Color(0.75, 0.75, 0.8))
		return

	var def := Database.get_item(item_id)
	var icon := ItemIcons.texture(def)
	var is_money := str(def.get("kind", "")) == "money"
	# money 계열은 소지품이 아니라 골드로 — ItemEffects가 판정한다(단일 창구).
	if ItemEffects.on_acquire(item_id, 1):
		AudioManager.play_sfx(&"sfx_item_get")
		GameState.inventory.add(item_id, 1)
		GameState.acquired.emit(&"item", item_id, 1)
		_show_pickup_popup(
			tr("UI_FIELD_GOT_ITEM") % str(def.get("name_ko", item_id)), icon, Color(1.0, 0.95, 0.8)
		)
	else:
		# 돈은 무음이었고 글자만 떴다 — 동전음 + 동전 분수 + 금빛 팝업으로.
		AudioManager.play_sfx(&"sfx_coin")
		_show_pickup_popup(str(def.get("name_ko", item_id)), icon, Color(1.0, 0.84, 0.3))
		if is_money:
			_spawn_coin_burst(icon)


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


## 기습 카메라 킥 — 0.3초간 ±6px로 흔들렸다 복귀한다.
## 카메라는 offset ZERO 기준(스무딩 없음)이라 복귀값이 고정이다.
func _kick_camera() -> void:
	if _cam == null:
		return
	var tw := create_tween().set_parallel(true)
	for i in 5:
		(
			tw
			. tween_property(_cam, "offset", Vector2(randf_range(-6, 6), randf_range(-6, 6)), 0.06)
			. set_delay(0.06 * i)
		)
	tw.chain().tween_property(_cam, "offset", Vector2.ZERO, 0.08)


## 획득 팝업 — 상자 위로 아이콘+문구가 바운스로 솟아올랐다 페이드아웃한다.
## 구판은 외곽선 없는 14px 라벨이라 배경에 묻혔다(특히 밝은 바닥).
## 이제 외곽선+그림자 + 팝 스케일 + 상승으로 읽힌다. 돈은 금빛 + 동전 분수.
func _show_pickup_popup(
	text: String, icon: Texture2D = null, tint: Color = Color(1.0, 0.9, 0.3)
) -> void:
	var anchor := player.position + Vector2(0, -64)
	var box := CenterContainer.new()
	box.size = Vector2(240, 80)
	box.position = anchor + Vector2(-120, -80)
	box.z_index = 60
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(vbox)
	if icon != null:
		var rect := TextureRect.new()
		rect.texture = icon
		rect.custom_minimum_size = Vector2(26, 26)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(rect)
	var popup := Label.new()
	popup.text = text
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.add_theme_font_size_override("font_size", 17)
	popup.add_theme_color_override("font_color", tint)
	popup.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	popup.add_theme_constant_override("outline_size", 5)
	popup.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	popup.add_theme_constant_override("shadow_offset_x", 1)
	popup.add_theme_constant_override("shadow_offset_y", 2)
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(popup)
	# 바운스 팝(스케일) + 상승 — 트윈은 박스에 묶어 씬 전환에 같이 죽는다.
	box.pivot_offset = box.size * 0.5
	box.scale = Vector2.ONE * 0.6
	var tw := box.create_tween().set_parallel(true)
	tw.tween_property(box, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	(
		tw
		. tween_property(box, "position:y", box.position.y - 34, 1.0)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tw.chain().tween_interval(0.15)
	tw.tween_property(box, "modulate:a", 0.0, 0.35)
	tw.tween_callback(box.queue_free)


## 동전 분수 — 돈 상자 전용. 아이콘 8개를 위로 뿜어 중력으로 떨군다.
## 수십 개 쏟아붓는 풀 분수는 과하다(팝업·개봉음·스파클과 겹친다) — 맛만 본다.
func _spawn_coin_burst(icon: Texture2D) -> void:
	if icon == null:
		return
	var at := player.position + Vector2(0, -40)
	for i in 8:
		var coin := Sprite2D.new()
		coin.texture = icon
		coin.scale = Vector2.ONE * (0.38 + randf() * 0.16)
		coin.position = at + Vector2(randf_range(-6, 6), 0)
		coin.z_index = 61
		add_child(coin)
		var peak := at + Vector2(randf_range(-46, 46), randf_range(-72, -42))
		var land := at + Vector2(randf_range(-62, 62), randf_range(6, 20))
		var ctw := coin.create_tween()
		(
			ctw
			. tween_property(coin, "position", peak, 0.26)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
			. set_delay(0.03 * i)
		)
		ctw.tween_property(coin, "position", land, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(
			Tween.EASE_IN
		)
		ctw.tween_property(coin, "modulate:a", 0.0, 0.2)
		ctw.tween_callback(coin.queue_free)


## 층 전환 후 맵 재구축 — TransitionGate가 페이드 중 호출 (new_anchor = 도착 앵커).
func rebuild_floor(new_anchor: Vector2i) -> void:
	var def := MapDefinition.load_from_json("res://data/maps/f%d.json" % GameState.current_floor)
	runtime = MapRuntime.new(def)
	# 소품 먼저, 상자 나중 — 같은 칸이 겹치면 플레이 결과(열린 상자)가 이겨야 한다.
	_props = PropsLayer.load_floor(GameState.current_floor)
	_props.apply_to(runtime)
	_apply_chest_overrides()
	for child in get_children():
		if child is MapRenderer:
			child.queue_free()
	renderer = MapRenderer.new()
	add_child(renderer)
	renderer.build(runtime)
	_restore_opened_chests()
	if tile_animator != null:
		tile_animator.bind_floor(GameState.current_floor, renderer)
	if dressing_overlay != null:
		dressing_overlay.bind_floor(GameState.current_floor, runtime)
	# 착지 보정 — 계단/빠른 이동 앵커가 그 층에서 막혀 있을 수 있다(층마다 지형이 다르다).
	var landing := _nearest_body_spot(new_anchor)
	player.attach_map(runtime, landing if landing.x >= 0 else new_anchor)
	GameState.mark_visited(GameState.current_floor)
	_encounter_grace = ENCOUNTER_GRACE
	minimap.build(runtime)
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
			GameState.current_floor, runtime, self, new_anchor, _actor_anchors(), _npc_anchors()
		)
	if triggers != null:
		triggers.load_for_floor(GameState.current_floor)
	# 층이 바뀌면 조명도 그 층 것으로. 액터를 다시 세운 **뒤**여야 한다.
	if lighting != null:
		lighting.apply(GameState.current_floor, _lit_actors())
	_fog_cell = Vector2i(-9999, -9999)
	_reveal_fog()
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
		# 데이터 계약 idle_anim을 실제 연출로 옮긴다(NpcEntity.IDLE_ANIMS).
		# setup() 뒤에 부르는 이유: 관문·스크린샷 도구가 나중에 idle_motion을 직접 꺼도
		# 그쪽이 이기게 하기 위함이다.
		npc.set_idle_anim(StringName(str(n.get("idle_anim", NpcEntity.DEFAULT_IDLE_ANIM))))
		npcs.append(npc)
		if wander_range > 0:
			npc.step_landed.connect(_on_npc_step_landed)
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
## 지금 **화면에 비치고 있는 칸**을 지도에 새긴다.
##
## 시선 차폐를 걸지 않는 이유는 FogOfWar 주석에 있다 — 이 게임은 탑다운 타일뷰라
## 카메라 사각형 안은 벽 너머까지 전부 그려진다. 화면에 보이는 방을 지도가
## "안 가봤다"고 우기면 그건 안개가 아니라 거짓말이다.
func _reveal_fog() -> void:
	if player == null or runtime == null:
		return
	_fog_cell = player.mover.grid_pos
	if not _fog_active():
		return
	var found := GameState.fog.reveal_rect(
		GameState.current_floor, runtime.definition, visible_cell_rect()
	)
	if not found.is_empty() and minimap != null:
		minimap.on_revealed()


## 이 층에 지금 안개가 끼는가 — **어두운 층에서만**(FloorLighting.is_dark).
## 설정에서 끄면 어느 층이든 예전처럼 층 전체가 한 번에 보인다.
func _fog_active() -> bool:
	return SettingsManager.fog_of_war and FloorLighting.is_dark(GameState.current_floor)


## 잠긴 전자잠금 방 안에 서서 깨어나면 밖으로 꺼낸다(정전 중 세이브 귀환).
## 복구는 분전반 자리에서만 일어나 그 순간 방 안에 있을 수 없으므로, 여기가 유일한 감금 경로다.
func _eject_from_locked_room() -> void:
	if gate == null or player == null:
		return
	var exit := gate.eject_cell_for(player.mover.grid_pos)
	if exit.x < 0:
		return
	push_warning("잠긴 방 안 착지 — 밖으로 꺼냄: %s -> %s" % [player.mover.grid_pos, exit])
	player.mover.grid_pos = exit
	player.position = GridMover.block_center(exit)


## 런타임 정전 토글 — 컷신 blackout op이 이 문으로 들어온다.
## 켜면 비상등+번개+안개, 끄면(분전반 복구) 그 층 지도를 전부 밝힌다(보상).
func set_blackout(enabled: bool) -> void:
	if lighting == null:
		return
	if enabled:
		if fx != null:
			fx.lightning_flash()
		lighting.set_blackout_enabled(GameState.current_floor, true, _lit_actors())
	else:
		lighting.set_blackout_enabled(GameState.current_floor, false, _lit_actors())
		if runtime != null:
			GameState.fog.reveal_all(GameState.current_floor, runtime)
	if minimap != null:
		minimap.on_revealed()


## 지금 화면이 덮고 있는 칸 범위. 감사 도구도 이것을 물어 "화면만큼만 밝혔는가"를 잰다.
func visible_cell_rect() -> Rect2i:
	var px := get_viewport_rect().size
	var center := player.position
	if _cam != null:
		px /= _cam.zoom
		# limit이 걸린 가장자리까지 반영된 실제 화면 중심이다.
		center = _cam.get_screen_center_position()
	var top_left := center - px * 0.5
	var t := float(MapDefinition.TILE_PX)
	var c0 := Vector2i(floori(top_left.x / t), floori(top_left.y / t))
	var c1 := Vector2i(ceili((top_left.x + px.x) / t), ceili((top_left.y + px.y) / t))
	return Rect2i(c0, c1 - c0)


## 조명을 받을 액터 전부 — 플레이어 · 몬스터 · NPC · 배경 보행자.
## 상점(식당 아가씨)도 NPC다. 어둠에 묻혀 안 보이는 상점은 없는 상점이다.
func _lit_actors() -> Array[Node2D]:
	var out: Array[Node2D] = []
	if player != null:
		out.append(player)
	for n: NpcEntity in npcs:
		out.append(n)
	for w: WalkerEntity in walkers:
		out.append(w)
	if enemy_manager != null:
		for e: EnemyEntity in enemy_manager.enemies:
			out.append(e)
	return out


func _on_enemy_spawned(e: EnemyEntity) -> void:
	if lighting != null:
		lighting.attach(e)


## 적 워프(잠복 출현·순간이동) — 사라진 자리·나타난 자리에 먼지를 뿜는다.
## 없으면 D웜의 burrow가 순간이동 버그처럼 보인다(2026-09-10 유저 지적).
func _on_enemy_warped(from_cell: Vector2i, to_cell: Vector2i) -> void:
	if fx != null:
		fx.enemy_warp_puff(from_cell, to_cell)


## 반경 배제용 — **고정 NPC만**. 워커는 돌아다니므로 곁을 비워도 스스로 다가간다.
func _npc_anchors() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for n: NpcEntity in npcs:
		out.append(n.cell)
	return out


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
		# enabled:false면 스킵 — 파일럿 중단·계절 이벤트 같은 킬 스위치.
		if not bool(w.get("enabled", true)):
			continue
		var legs: Array = []
		for leg: Dictionary in w.get("pattern", []):
			legs.append(
				{"dir": _dir_of(str(leg.get("dir", ""))), "steps": int(leg.get("steps", 0))}
			)
		var walker := WalkerEntity.new()
		add_child(walker)
		walker.foe_source = enemy_manager
		var tint_arr: Array = w.get("tint", [1.0, 1.0, 1.0])
		var tint := Color(
			float(tint_arr[0]) if tint_arr.size() > 0 else 1.0,
			float(tint_arr[1]) if tint_arr.size() > 1 else 1.0,
			float(tint_arr[2]) if tint_arr.size() > 2 else 1.0
		)
		walker.setup(
			StringName(str(w.get("id", ""))),
			StringName(str(w.get("sprite", ""))),
			Vector2i(int(w["pos"][0]), int(w["pos"][1])),
			legs,
			runtime,
			str(w.get("name", "")),
			StringName(str(w.get("sequence_id", ""))),
			w.get("sequence_variants", []),
			w.get("repeat_sequence_id", null),
			tint
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


## 말풍선 — 첫 조우 "…"와 새 대사 "?"를 세션당 한 번씩만 띄운다.
## 빨간 "!"는 괴물 위험 전용이라 대화에 쓰지 않는다(EmoteBubble 어휘 분리 참조).
## seq는 지금 고를 대사(대화 시작 시 기록한 것과 다르면 = 플래그로 새 말이 생겼다).
func _maybe_emote(actor_key: String, actor: Node2D, seq: StringName) -> void:
	if actor_key.is_empty():
		return
	if not _emoted_first.has(actor_key):
		_emoted_first[actor_key] = true
		_emoted_seq[actor_key] = String(seq)
		EmoteBubble.pop(actor, "...", EmoteBubble.COLOR_SPOT)
		return
	if String(_emoted_seq.get(actor_key, "")) != String(seq):
		_emoted_seq[actor_key] = String(seq)
		EmoteBubble.pop(actor, "?", EmoteBubble.COLOR_NEWINFO)


## 배회 착지 — 발걸음 먼지. 조용히 미끄러지면 유령처럼 보인다.
func _on_npc_step_landed(cell: Vector2i) -> void:
	if fx != null:
		fx.step_puff(cell)


## 맵아트 인물(타일 대화점) 말풍선 — 몸이 없어 셀 좌표 앵커에 띄운다.
## 첫 조우 "…" + 갈래 변경(새 정보) "?" — 빨간 "!"는 괴물 위험 전용이라 쓰지 않는다.
func _maybe_emote_cell(attr: int, at: Vector2) -> void:
	var key := "att_%d" % attr
	var bkey := TalkTargets.branch_key(attr)
	if not _emoted_first.has(key):
		_emoted_first[key] = true
		_emoted_seq[key] = bkey
		_pop_cell_emote(at, "...", EmoteBubble.COLOR_SPOT)
	elif not bkey.is_empty() and String(_emoted_seq.get(key, "")) != bkey:
		_emoted_seq[key] = bkey
		_pop_cell_emote(at, "?", EmoteBubble.COLOR_NEWINFO)


## 셀 앵커 — 말풍선 하나가 붙는 가벼운 자리. 프롬프트는 단일 대상이라 하나로 충분하다.
func _pop_cell_emote(at: Vector2, glyph: String, color: Color) -> void:
	if _emote_anchor == null or not is_instance_valid(_emote_anchor):
		_emote_anchor = Node2D.new()
		add_child(_emote_anchor)
	_emote_anchor.position = at + Vector2(0, -24)
	EmoteBubble.pop(_emote_anchor, glyph, color)


func _start_dialogue(npc: NpcEntity) -> void:
	_talking_npc = npc
	player.mover.enabled = false
	_prompt.visible = false
	npc.face_towards(player.mover.grid_pos)
	npc.set_talking(true)
	# **지금 상태에 맞는 대사**를 고른다 — 두 번째로 찾아가면 다른 말을 할 수 있다.
	var seq := npc.resolve_sequence()
	_emoted_seq[String(npc.npc_id)] = String(seq)
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
	_emoted_seq[String(walker.walker_id)] = String(seq)
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
