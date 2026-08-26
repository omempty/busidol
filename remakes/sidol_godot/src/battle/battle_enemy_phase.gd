class_name BattleEnemyPhase
extends RefCounted
## 적 턴 실행 — 일반 공격·텔레그래프+회피 페이즈 시퀀스.
## 씬 컨트롤러의 표현 계층 위임분(로직 판정은 DamageCalculator).


## 일반 공격 — 첫 생존 적의 턴(원작 공식: (Power + rnd(10)) / 6).
static func regular_attack(
	attacker: Combatant, player: Combatant, presenter: BattlePresenter
) -> void:
	var raw := DamageCalculator.enemy_hit(attacker.ap, EnemyManager.rng)
	var actual: int = player.take_damage(raw)
	presenter.show_damage_number(actual, true)
	presenter.hurt_flash(presenter.player_sprite)
	presenter.play_screen_kf({"shake": 3})


## 텔레그래프 + 회피 페이즈 시퀀스 — 피격 횟수 × dodge_damage_per_hit 를
## 플레이어 피해로 환산한다. 반환: hits.
static func dodge_sequence(
	dodge: DodgePhase, edef: Dictionary, presenter: BattlePresenter, ui: BattleUI, player: Combatant
) -> int:
	var cfg: Dictionary = edef["dodge_phase"]
	ui.set_turn_text("!! 이상 신호 감지 !!")
	presenter.play_telegraph(str(cfg.get("telegraph", "flash_red_0.8s")))
	var tree := Engine.get_main_loop() as SceneTree
	await tree.create_timer(0.8).timeout
	ui.set_turn_text("!! 피하라 !!")
	dodge.visible = true
	dodge.start(maxf(float(cfg.get("duration", 4.0)), 0.5), cfg)
	var hits: int = await dodge.phase_complete
	dodge.stop()
	dodge.visible = false

	var per_hit := maxi(int(edef.get("dodge_damage_per_hit", 3)), 0)
	var actual: int = player.take_damage(hits * per_hit)
	if actual > 0:
		presenter.show_damage_number(actual, true)
		presenter.hurt_flash(presenter.player_sprite)
		presenter.play_screen_kf({"shake": 3, "flash": "#ff3333", "a": 0.25})
	print("[battle] dodge phase done: hits=%d dmg=%d" % [hits, actual])
	return hits
