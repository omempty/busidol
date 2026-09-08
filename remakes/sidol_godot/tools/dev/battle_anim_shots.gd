extends Node
## 전투 **동작** 캡처 — 정지 화면이 아니라 움직이는 순간을 프레임으로 남긴다.
##
## `ui_shots`는 `battle_idle` 한 장만 찍는다. 그래서 원작 전투 대형 시트를 이식하고도
## **돌진이 실제로 화면을 가로지르는지 · 특수 공격이 다른 그림을 쓰는지 · 빈사·사망
## 포즈가 뜨는지**를 눈으로 확인할 방법이 없었다. 관문(`smoke_battle_test.gd` §8)은
## "행이 재생되는가"까지만 보고 화면에 무엇이 그려졌는지는 못 본다.
##
## 원작 근거는 `WARMODE.C` — 프레임 0 평상 · 1 빈사(HP≤15) · 2 사망 · 3 공격(x=100→−50
## 슬라이드) · 4·5 피격 반응(`EnemyAvoid`가 무작위로 고름).
##
## 실행: godot --path . --resolution 960x540 res://tools/dev/battle_anim_shots.tscn -- [종id]
##       (창 모드 필요 — 헤드리스는 뷰포트 텍스처가 비어 나온다)
## 산출: user://battle_anim/*.png

const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const OUT_DIR := "user://battle_anim"
## 돌진은 0.34초 + 복귀 0.2초다. 그 사이를 고르게 훑어야 "가로지른다"가 보인다.
const CHARGE_STEPS := 10
const CHARGE_GAP_FRAMES := 4

var _shots := 0


func _ready() -> void:
	# 헤드리스는 뷰포트 텍스처가 비어 나오는데 frame_post_draw 대기가 영원히
	# 안 풀려 프로세스가 끝나지 않는다(2026-09-08 실측: 300초 타임아웃).
	# 빈 PNG를 양산하느니 들어가기 전에 끝낸다 — 이 도구는 창 모드 전용이다.
	if DisplayServer.get_name() == "headless":
		print("[battle_anim] skip — 창 모드 필요 (헤드리스는 빈 화면만 나온다)")
		get_tree().quit(0)
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var args := OS.get_cmdline_user_args()
	var eid := str(args[0]) if args.size() > 0 else "hellcop"

	GameState.reset()
	GameState.player_stats["hp"] = 50
	GameState.player_stats["ap"] = 30
	GameState.pending_encounter = {"enemies": [eid], "on_win_flag": ""}
	var battle: BattleSceneController = BATTLE_SCENE.instantiate()
	add_child(battle)
	await _settle(8)

	if battle.enemies.is_empty():
		push_error("[battle_anim] 적 생성 실패: %s" % eid)
		get_tree().quit(1)
		return
	var foe: Combatant = battle.enemies[0]
	# 캡처 도중 적이 죽어 승리 전환되면 씬이 사라진다 — HP를 넉넉히 준 뒤 마지막에 낮춘다.
	foe.max_hp = 9999
	foe.hp = 9999
	var pres: BattlePresenter = battle._presenter
	var spr: Sprite2D = pres.enemy_sprites[0] if not pres.enemy_sprites.is_empty() else null
	print(
		(
			"[battle_anim] %s · 대형시트=%s · 배율 %.2f"
			% [eid, str(spr != null and spr.has_meta(&"battle_sheet")), spr.scale.y if spr else 0.0]
		)
	)

	await _shot("%s_1_idle" % eid)

	# --- 통상 공격 — 원작 돌진(x=100 → −50)이 화면을 가로지르는가 ---
	pres.play_enemy_anim(0, "attack")
	pres.enemy_lunge(0)
	pres.origin_attack_fx()  # 돌진 뒤 섬광 + 에너지파(발사 종만) — WARMODE.C:599-625
	for i in CHARGE_STEPS:
		await _settle(CHARGE_GAP_FRAMES)
		await _shot("%s_2_attack_%d" % [eid, i])

	await _settle(30)

	# --- 특수 공격 — 원작에 없는 개념이라 돌진(프레임 3)을 재사용, 이펙트로 가른다 ---
	pres.play_enemy_anim(0, "special")
	pres.enemy_lunge(0)
	for i in CHARGE_STEPS:
		await _settle(CHARGE_GAP_FRAMES)
		await _shot("%s_3_special_%d" % [eid, i])

	await _settle(30)

	# --- 피격 — 원작 EnemyAvoid(프레임 4·5 무작위) + AttackEffect 스파크 ---
	pres.hurt_flash(spr)
	for i in 3:
		await _settle(CHARGE_GAP_FRAMES)
		await _shot("%s_35_hurt_%d" % [eid, i])
	await _settle(30)

	# --- 주인공 원작 대형 컷 — 임팩트 순간에만 터진다(공격 3종을 돌아가며) ---
	for k in 3:
		pres.play_origin_player_cut()
		for i in 4:
			await _settle(3)
			await _shot("%s_37_playercut_%d_%d" % [eid, k, i])
		await _settle(24)

	# --- 빈사 — 원작 규칙(HP 낮으면 포즈가 갈린다)이 사는가 ---
	foe.hp = int(float(foe.max_hp) * 0.2)
	await _settle(20)
	await _shot("%s_4_wounded" % eid)

	# --- 사망 ---
	foe.hp = 0
	await _settle(20)
	await _shot("%s_5_death" % eid)

	print("[battle_anim] done - %d장 → %s" % [_shots, OUT_DIR])
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	if img.save_png(path) != OK:
		push_error("[battle_anim] 저장 실패 %s" % path)
		return
	_shots += 1
	print("[battle_anim] %s" % name)
