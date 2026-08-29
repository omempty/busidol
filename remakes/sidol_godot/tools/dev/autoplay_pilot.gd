extends RefCounted
## 자동 주행의 손 — 게임에 입력을 흘려보내고 걸음 하나를 끝까지 지켜본다.
##
## 게임은 입력을 **두 경로**로 읽는다. 한쪽만 흉내 내면 조용히 안 눌린다.
##   폴링   field·PlayerEntity·TransitionGate — `Input.is_action_pressed()`
##   이벤트 전투 UI·선택지·미니게임          — `_input`/`_unhandled_input`
## 그래서 누를 때 `Input.action_press`와 `InputEventAction`을 **함께** 보낸다.
##
## 눌림은 반드시 짝이 맞아야 한다. InputEventAction은 뗄 때까지 액션 상태를 눌린
## 채로 남기므로, 안 떼면 다음 목표부터 플레이어가 한 방향으로 계속 걷는다.

## 한 걸음을 기다릴 물리 프레임 상한. 보행은 0.16초(GridMover.STEP_TIME)면 끝나지만
## 문 슬라이드·층 전환 페이드가 겹치면 훨씬 길어진다.
const STEP_FRAMES := 400
## 보행이 멎기를 기다릴 상한. 버퍼 체인이 한 걸음 더 나가는 경우가 있다.
const STILL_FRAMES := 120
## 몇 프레임에 한 번 누를 것인가 — 매 프레임 누르면 선택지가 순식간에 지나간다.
const BEAT := 4

var tree: SceneTree
var run_log: RefCounted  # AutoplayLog — 전투 수를 여기서 센다

var _held: Array[StringName] = []
var _beat := 0
var _battle_id := 0


func _init(scene_tree: SceneTree, run_log_in: RefCounted) -> void:
	tree = scene_tree
	run_log = run_log_in


# ---------------------------------------------------------------------------
# 화면 시중 — 드라이버가 매 프레임 부른다
# ---------------------------------------------------------------------------


## 사람이라면 눌렀을 것을 대신 눌러 준다. **여기서 막힌 화면을 풀어 주지 않으면
## 주행이 한 자리에서 멈춘다** — 멈추는 것이 가장 나쁘다.
func attend(scene: Node) -> void:
	settle()
	_beat += 1
	if _beat % BEAT != 0:
		return
	if scene == null or not scene.is_inside_tree():
		return
	if scene is BattleSceneController:
		_attend_battle(scene as BattleSceneController)
		return
	if scene.has_method("get_runtime"):
		_attend_field(scene as Node2D)
		return
	# **모르는 씬에서는 뒤로 나간다.** 크레딧룸·엔딩 콘솔처럼 필드를 통째로 대신하는
	# 씬이 열리면 도구는 여기서 영영 기다렸다(2026-08-29: HP실에 들어간 주행이 22초에
	# 「더 갈 곳이 없다」로 끝났다). 사람이라면 취소를 눌러 돌아왔을 자리다.
	pulse(&"cancel")


## 전투 — 커맨드 1번(공격)만 반복한다. 결과 패널은 스스로 닫힌다.
func _attend_battle(battle: BattleSceneController) -> void:
	if battle.get_instance_id() != _battle_id:
		_battle_id = battle.get_instance_id()
		run_log.battles += 1
	pulse(&"battle_slot_1")


func _attend_field(field: Node2D) -> void:
	var cutscene: CutscenePlayer = field.cutscene_player
	if cutscene != null and cutscene.is_running():
		_attend_cutscene(cutscene)
		return
	if field.dialogue_box != null and field.dialogue_box.is_open:
		pulse(&"interact")
		return
	if field.inventory_panel != null and field.inventory_panel.visible:
		pulse(&"cancel")
		return
	if field.fast_travel != null and field.fast_travel.is_open():
		pulse(&"cancel")
		return
	if field.shop != null and field.shop.is_open():
		pulse(&"cancel")


## 컷신 — 대사는 스스로 넘어간다(auto_advance). 선택지·미니게임만 눌러 준다.
## 미니게임은 정답을 모르므로 **커서를 돌리며 확정**을 반복한다.
func _attend_cutscene(cutscene: CutscenePlayer) -> void:
	for child in cutscene.get_children():
		if child is QuizMinigame and (child as QuizMinigame).is_active():
			pulse(&"interact" if _beat % (BEAT * 2) == 0 else &"move_down")
			return
		if child is BatteryCircuitMinigame and (child as BatteryCircuitMinigame).is_active():
			# 세 손이 다 필요하다: 칸 옮기기·전압 바꾸기·**레버 올리기**. 레버(interact)를
			# 안 누르면 목표 전압에 닿는 조합이 아예 안 나온다 — 이 미니게임은 정답에서만
			# 끝나고 빠져나갈 길이 없어서 도구가 영영 갇혔다(2026-08-29 f4 훑기).
			var hands: Array[StringName] = [&"move_right", &"move_down", &"interact"]
			pulse(hands[(_beat / BEAT) % hands.size()])
			return
		if child is Control and child.has_signal("picked"):
			pulse(&"interact")
			return


# ---------------------------------------------------------------------------
# 입력
# ---------------------------------------------------------------------------


func press(action: StringName) -> void:
	Input.action_press(action)
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func release(action: StringName) -> void:
	Input.action_release(action)
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)


## 코루틴을 쌓을 수 없는 자리(드라이버의 tick)에서 쓰는 한 박자 누름.
## 누른 것은 **다음 tick 첫머리의 settle()** 이 뗀다 — 그 사이 한 프레임이
## 통째로 눌린 상태로 지나가므로 폴링 쪽도 놓치지 않는다.
func pulse(action: StringName) -> void:
	if not _held.is_empty():
		return
	press(action)
	_held.append(action)


func settle() -> void:
	for action: StringName in _held:
		release(action)
	_held.clear()


## 눌렀다 뗀다(await 가능한 자리용). 물리 프레임을 끼워 폴링 쪽에 보인다.
func tap(action: StringName) -> void:
	press(action)
	await tree.physics_frame
	await tree.physics_frame
	release(action)
	await tree.process_frame


## 한 걸음. **좌표는 걸음이 시작될 때 바뀐다**(GridMover.try_step) — 도착까지 키를
## 쥐고 있으면 버퍼 체인이 한 걸음 더 나간다. 그래서 좌표가 바뀌는 즉시 뗀다.
##
## **보행이 멎기를 기다리지 않는다.** 걸음마다 멈춰 서면 트윈(0.16초)이 끝날 때까지
## 노는데, 그것이 주행 시간의 3분의 2였다(2026-08-29 실측: 걸음당 물리 50프레임 중 34).
## 다음 걸음을 바로 눌러 두면 GridMover의 버퍼 체인이 이어 받는다 — 사람이 방향키를
## 쥔 채 걷는 것과 같다. 멈춰 세워야 하는 자리(조사 직전)에서는 `still()`을 따로 부른다.
##
## `want` 를 따로 받는 것은 **문 통과** 때문이다. 문은 한 번 눌러 3칸을 건너뛰고
## (TransitionGate._try_door) 그동안 조작이 잠긴다 — 걸음과 같은 자로 재면
## "조작이 잠겼으니 실패"로 접어 버린다. 그때는 `patient` 로 기다린다.
## 반환: 실제로 그 칸에 섰는가.
func step_to(player: PlayerEntity, dir: Vector2i, want: Vector2i, patient: bool) -> bool:
	var from := player.mover.grid_pos
	var action := action_for(dir)
	press(action)
	var arrived := false
	for _i in STEP_FRAMES:
		await tree.physics_frame
		run_log.step_frames += 1
		if not is_instance_valid(player) or not player.is_inside_tree():
			break  # 전투 전환 등으로 필드가 사라졌다
		var here: Vector2i = player.mover.grid_pos
		if here == want:
			arrived = true
			break
		if here != from:
			break  # 문·계단이 다른 곳으로 데려갔다 — 부른 쪽이 다시 길을 짠다
		if not patient and not player.mover.enabled:
			break  # 컷신이 조작을 가져갔다
	release(action)
	return arrived


## 막힌 칸을 향해 밀어 방향만 돌린다(조사 자세). 통행 가능한 칸이면 걸어 들어가므로
## 부르는 쪽이 **막힌 칸에만** 쓴다.
func face(player: PlayerEntity, dir: Vector2i) -> void:
	var action := action_for(dir)
	press(action)
	await tree.physics_frame
	await tree.physics_frame
	release(action)
	await tree.process_frame


## 보행이 멎을 때까지.
func still(player: PlayerEntity) -> void:
	for _i in STILL_FRAMES:
		if not is_instance_valid(player) or not player.is_inside_tree():
			return
		if not player.mover.moving:
			return
		await tree.physics_frame
		run_log.still_frames += 1


func action_for(dir: Vector2i) -> StringName:
	if dir.x < 0:
		return &"move_left"
	if dir.x > 0:
		return &"move_right"
	if dir.y < 0:
		return &"move_up"
	return &"move_down"
