class_name BattleEnemyPhase
extends RefCounted
## 적 턴 실행 — 일반 공격·텔레그래프+회피 페이즈 시퀀스.
## 씬 컨트롤러의 표현 계층 위임분(로직 판정은 DamageCalculator).


## 종별 특수 행동 — 통상공격 대신 상태이상을 건다. 반환: 걸었는가.
##
## **왜 생겼나(2026-09-06).** 그 전까지 적 행동은 통상공격 1종뿐이었다. 그래서
## `attach_effect` 호출자가 전부 플레이어 쪽이었고, 상비약 5종(진통 파스·해열제·
## 신경 안정제·미네랄 워터·집중 음료)과 상태이상 시스템이 통째로 사문화였다 —
## **막을 것이 없으니 살 이유도 없었다.** 적이 걸기 시작하면 그 5종이 살아난다.
##
## 확률·종류는 monsters.json의 종별 `special`이 정한다(코드에 값을 두지 않는다).
## dot 피해량은 적 AP에서 뽑는다 — 층이 올라가면 지속 피해도 같이 아파진다.
static func try_special(
	attacker: Combatant,
	player: Combatant,
	enemy_id: String,
	presenter: BattlePresenter,
	rng: RandomNumberGenerator
) -> bool:
	var edef := Database.get_enemy_def(StringName(enemy_id))
	var spec: Dictionary = edef.get("special", {})
	if spec.is_empty():
		return false
	if rng.randf() > float(spec.get("chance", 0.0)):
		return false
	# 상태 저항(신경 안정제)이 걸려 있으면 attach_effect가 조용히 튕겨 낸다 —
	# 그래도 턴은 소모된다. 저항을 산 보람이 그 자리다.
	if player.has_status_resist():
		BattleLog.push(
			TranslationServer.translate("UI_BLOG_STATUS_RESIST") % attacker.display_name,
			BattleLog.Kind.ACCENT
		)
		presenter.show_player_note(TranslationServer.translate("UI_BATTLE_STATUS_RESISTED"))
		return true
	var kind := StringName(str(spec.get("kind", "")))
	var turns := int(spec.get("turns", 3))
	var magnitude := maxi(1, attacker.attack_stat() / 12)
	player.attach_effect({"kind": kind, "turns": turns, "magnitude": magnitude})
	presenter.play_enemy_anim(presenter.target_index, "attack")
	presenter.enemy_lunge(presenter.target_index)
	var key := "UI_BLOG_ENEMY_PARALYZE" if kind == &"paralysis" else "UI_BLOG_ENEMY_DOT"
	BattleLog.push(
		TranslationServer.translate(key) % [attacker.display_name, magnitude], BattleLog.Kind.DAMAGE
	)
	presenter.hurt_flash(presenter.player_sprite)
	presenter.play_screen_kf({"shake": 3.0, "flash": "#a855f7", "a": 0.22})
	return true


## 일반 공격 — 첫 생존 적의 턴(원작 공식: (Power + rnd(10)) / 6).
static func regular_attack(
	attacker: Combatant, player: Combatant, presenter: BattlePresenter
) -> void:
	var raw := DamageCalculator.enemy_hit(attacker.attack_stat(), EnemyManager.rng)
	var actual: int = player.take_damage(raw)
	# 적 시트에 attack 행이 있으면 그 동작으로 때린다(없으면 기존 연출 그대로).
	presenter.play_enemy_anim(presenter.target_index, "attack")
	presenter.enemy_lunge(presenter.target_index)
	presenter.show_damage_number(actual, true)
	BattleLog.push(
		TranslationServer.translate("UI_BLOG_ENEMY_HIT") % [attacker.display_name, actual],
		BattleLog.Kind.DAMAGE
	)
	presenter.hurt_flash(presenter.player_sprite)
	# 원작은 피격도 대형 컷이었다(DEF 시퀀스) — 시트가 없으면 조용히 건너뛴다.
	presenter.play_cut("player_hurt")
	# 아군 타격과 같은 등급화 — 피해 비례 shake + 임팩트 히트스톱.
	presenter.play_screen_kf({"shake": minf(3.0 + float(maxi(actual, 0)) / 8.0, 7.0)})
	if actual > 0:
		presenter.hitstop()


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
		BattleLog.push(
			TranslationServer.translate("UI_BLOG_DODGE_HIT") % [hits, actual], BattleLog.Kind.DAMAGE
		)
		presenter.hurt_flash(presenter.player_sprite)
		presenter.play_screen_kf({"shake": 3, "flash": "#ff3333", "a": 0.25})
	if hits == 0:
		presenter.play_cut("player_dodge")  # 무피격 = 완전 회피 — 원작 D 시퀀스 자리
	print("[battle] dodge phase done: hits=%d dmg=%d" % [hits, actual])
	return hits
