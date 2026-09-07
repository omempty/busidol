extends Node
## 현대 액션 RPG 적 AI 기동 및 인지 시스템 검증:
##   1) 전방 120도 시야각(Vision Cone)
##   2) 격자 시선 차폐(Line-of-Sight Bresenham)
##   3) 근접 청각(Hearing) 및 거리 인지
##   4) 플레이어 2칸 이내 1틱 전조 멈칫(Hesitation)
##   5) 슬롯 기반 포위(Flanking) 목표 추적
##   6) 전투 진입 시 선제 기습(Advantage) 및 피격(Ambush) 연동
## 실행: godot --headless --path . res://tests/smoke_ai_perception.tscn   (exit 0=PASS)

const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const PerceptionProbe := preload("res://src/core/ai/perception_probe.gd")
const TIMEOUT := 4.0

## 적 선제 턴을 기다리는 상한(프레임). 4초쯤이면 연출이 아무리 느려도 끝난다.
const AMBUSH_FRAMES := 240


func _ready() -> void:
	var failures: Array[String] = []

	# --- 1) 전방 120도 시야각(Vision Cone) 검증 ---
	var enemy_cell := Vector2i(10, 10)
	var facing_down := Vector2i.DOWN

	# 정면 (각도 0도) -> 시야각 내
	if not PerceptionProbe.in_vision_cone(enemy_cell, facing_down, Vector2i(10, 15), 120.0):
		failures.append("정면 타겟이 시야각 내로 판정되지 않음")

	# 전방 대각선 (각도 ~26도) -> 시야각 내
	if not PerceptionProbe.in_vision_cone(enemy_cell, facing_down, Vector2i(12, 14), 120.0):
		failures.append("전방 대각선 타겟이 시야각 내로 판정되지 않음")

	# 직각 측면 (각도 90도) -> 시야각 밖
	if PerceptionProbe.in_vision_cone(enemy_cell, facing_down, Vector2i(15, 10), 120.0):
		failures.append("측면 90도 타겟이 시야각 120도 내로 오탐됨")

	# 완전 후방 (각도 180도) -> 시야각 밖
	if PerceptionProbe.in_vision_cone(enemy_cell, facing_down, Vector2i(10, 5), 120.0):
		failures.append("후방 타겟이 시야각 내로 오탐됨")
	print("[smoke_ai] 1. 시야각(Vision Cone) 검증 완료")

	# --- 2) 격자 시선 차폐(Line-of-Sight) 검증 ---
	var wall_map := {Vector2i(10, 12): false}  # (10,12)에 벽 존재
	var passable_fn := func(c: Vector2i) -> bool: return wall_map.get(c, true)

	# 벽이 없을 때 LOS 통과
	if not PerceptionProbe.has_line_of_sight(enemy_cell, Vector2i(10, 11), passable_fn):
		failures.append("장애물 없는 경로의 시선 차폐 검사 실패")

	# 벽이 사이에 있을 때 LOS 차단
	if PerceptionProbe.has_line_of_sight(enemy_cell, Vector2i(10, 14), passable_fn):
		failures.append("벽에 가려진 경로의 시선 차폐 미차단")
	print("[smoke_ai] 2. 시선 차폐(Line-of-Sight) 검증 완료")

	# --- 3) 종합 인지 판정(can_perceive) 검증 ---
	# (a) 등 뒤라도 2칸 이내 초근접은 청각으로 감지
	var behind_close := Vector2i(10, 9)
	if not PerceptionProbe.can_perceive(enemy_cell, facing_down, behind_close, 6, 2, passable_fn):
		failures.append("등 뒤 1칸 초근접 청각 감지 실패")

	# (b) 등 뒤 3칸(청각 밖)은 감지 불가 (기습 허용)
	var behind_far := Vector2i(10, 7)
	if PerceptionProbe.can_perceive(enemy_cell, facing_down, behind_far, 6, 2, passable_fn):
		failures.append("등 뒤 3칸 미감지 거리에서 오감지")

	# (c) 전방 4칸(시야각 내, 장애물 없음) 감지 성공
	var front_clear := Vector2i(10, 14)
	var empty_passable := func(_c: Vector2i) -> bool: return true
	if not PerceptionProbe.can_perceive(enemy_cell, facing_down, front_clear, 6, 2, empty_passable):
		failures.append("전방 시야 내 플레이어 감지 실패")

	# (d) 어그로 반경(6칸) 초과 시 감지 불가
	var out_of_range := Vector2i(10, 18)
	if PerceptionProbe.can_perceive(enemy_cell, facing_down, out_of_range, 6, 2, empty_passable):
		failures.append("어그로 반경 초과 플레이어 오감지")
	print("[smoke_ai] 3. 청각/시각/거리 종합 인지 검증 완료")

	# --- 4) ChaseAI 공격 전조 및 멈칫(Hesitation) 검증 ---
	var chase_ai := ChaseAI.new()
	var rng := RandomNumberGenerator.new()
	var dummy_entity := EnemyEntity.new()
	add_child(dummy_entity)
	dummy_entity.setup(&"hellcop", enemy_cell, Color.WHITE)

	var ctx := {
		"self_cell": enemy_cell,
		"player_cell": Vector2i(10, 12),  # 거리 2칸
		"target_cell": Vector2i(10, 12),
		"facing": facing_down,
		"is_passable_cell": empty_passable,
		"passable": empty_passable,
		"occupied": {},
		"rng": rng,
		"enemy_entity": dummy_entity,
	}
	# 첫 번째 decide: 2칸 진입 시 1틱 전조 멈칫 (ZERO 반환)
	var step1: Vector2i = chase_ai.decide(ctx)
	if step1 != Vector2i.ZERO:
		failures.append("2칸 거리 진입 시 1틱 멈칫하지 않고 즉시 이동함: %s" % step1)
	if not chase_ai.is_alerted():
		failures.append("ChaseAI 어그로 상태 미전환")

	# 두 번째 decide: 멈칫 종료 후 쇄도 이동
	var step2: Vector2i = chase_ai.decide(ctx)
	if step2 != Vector2i.DOWN:
		failures.append("멈칫 후 플레이어를 향한 돌진 이동 실패: %s" % step2)
	print("[smoke_ai] 4. 공격 전조 및 완급 조절(Hesitation) 검증 완료")

	# --- 5) 다중 적 플랭킹(Flanking Slot) 목표 추적 검증 ---
	var flank_slot := Vector2i(8, 12)  # 플레이어 좌측 측면
	var flank_ctx := {
		"self_cell": Vector2i(8, 8),
		"player_cell": Vector2i(10, 12),
		"target_cell": flank_slot,  # 플랭킹 슬롯 지정
		"facing": facing_down,
		"is_passable_cell": empty_passable,
		"passable": empty_passable,
		"occupied": {},
		"rng": rng,
		"enemy_entity": dummy_entity,
	}
	var flank_ai := ChaseAI.new()
	var flank_step: Vector2i = flank_ai.decide(flank_ctx)
	# (8,8)에서 (8,12)를 향하므로 아래로 이동해야 함
	if flank_step != Vector2i.DOWN:
		failures.append("플랭킹 슬롯 지정 시 슬롯을 향한 이동 실패: %s" % flank_step)
	print("[smoke_ai] 5. 플랭킹 슬롯 추적 기동 검증 완료")
	dummy_entity.queue_free()

	# --- 6) 전투 선제 기습(Advantage) 및 적 기습(Ambush) 시스템 검증 ---
	# (a) Advantage: 적 브레이크 게이지 1 적용
	GameState.reset()
	GameState.player_stats["hp"] = 50
	GameState.player_stats["ap"] = 30
	GameState.pending_encounter = {
		"enemies": ["c_bug"],
		"advantage": true,
		"ambush": false,
	}
	var battle_adv: BattleSceneController = BATTLE_SCENE.instantiate()
	add_child(battle_adv)
	await get_tree().process_frame
	await get_tree().process_frame

	if battle_adv.enemies.is_empty() or battle_adv.enemies[0].break_gauge != 1:
		failures.append(
			(
				"선제 기습(Advantage) 시 적 브레이크 게이지 1 미부여: %d"
				% (battle_adv.enemies[0].break_gauge if not battle_adv.enemies.is_empty() else -1)
			)
		)
	battle_adv.queue_free()

	# (b) Ambush: 적 선제 턴 시작
	GameState.pending_encounter = {
		"enemies": ["c_bug"],
		"advantage": false,
		"ambush": true,
	}
	var battle_ambush: BattleSceneController = BATTLE_SCENE.instantiate()
	add_child(battle_ambush)

	# 기습이 성립했는가 = **적이 선제 턴을 실제로 소비했는가.**
	#
	# HP만 보면 안 된다. `_enemy_act`는 `try_special`이 붙으면 통상 공격을 건너뛴다
	# (`battle_scene_controller.gd:554`). 마비 5종은 **12% 확률**로 그 길을 타고
	# (`monsters.json` species/*/special), 그 판에서는 HP가 50 그대로다. 그래서 코드가
	# 멀쩡한데도 관문이 여덟 판에 한 번꼴로 빨개졌다 — 2026-09-07 실측: 관문 묶음에서
	# `HP 50 -> 50` 실패, 단독 재실행 3회는 3회 모두 40대.
	# 원래 주석이 적어 둔 의도("HP가 50 미만이거나 **턴이 진행되었는지**")를 코드가 절반만
	# 구현하고 있었다.
	#
	# 상태이상 보유로 대신 판정할 수는 없다. 마비는 `turns: 1`이라 같은 `_resolve_turn`의
	# `_tick_effects()`에서 곧바로 지워져, 이 자리에 왔을 땐 이미 없다(실측: 확률을 1.0으로
	# 올려 강제 재현하니 `HP 50 -> 50` · `has_paralysis()` false). **그건 이 테스트가 아니라
	# 전투 쪽 결함이다** — 별건으로 남긴다(HANDOFF 15차 §다음 세션).
	var waited := await _await_until(
		func() -> bool:
			return battle_ambush.player_combatant.hp < 50 or battle_ambush.controller.turn_count > 0
	)
	var player_hp: int = battle_ambush.player_combatant.hp
	print(
		(
			"[smoke_ai] 적 기습 시 플레이어 HP 50 -> %d · 턴 %d (%d프레임 대기)"
			% [player_hp, battle_ambush.controller.turn_count, waited]
		)
	)
	if waited < 0:
		failures.append("적 기습(Ambush) 시 적 선제 턴 미발동 — 피해도 턴 진행도 없다(%d프레임 대기)" % AMBUSH_FRAMES)
	battle_ambush.queue_free()
	print("[smoke_ai] 6. 선제 기습 및 피격 전투 연동 검증 완료")

	_finish(failures)


## 조건이 설 때까지 기다리고 **걸린 프레임 수**를 돌려준다(못 서면 -1).
##
## 원래 이 자리는 `await process_frame`을 두 번 하고 곧바로 단정했다. 지금 기습은 동기로
## 끝나므로(실측 0프레임) 그것만으로도 돌긴 했지만, 연출 하나만 비동기가 되어도 조용히
## 깨지는 자리다 — **시간이 아니라 결과를 기다린다.**
##
## 걸린 프레임 수를 같이 찍는다. 0에서 커지면 전투 연출이 어딘가 비동기로 바뀐 것이라
## 그 자체가 보고할 값이다.
func _await_until(cond: Callable, max_frames: int = AMBUSH_FRAMES) -> int:
	for i in max_frames:
		if cond.call():
			return i
		await get_tree().process_frame
	return -1


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("[smoke_ai] PASS — 현대 액션 RPG 적 AI 기동 및 인지 전 항목 정상")
		get_tree().quit(0)
	else:
		push_error("[smoke_ai] FAIL: " + "; ".join(failures))
		get_tree().quit(1)
