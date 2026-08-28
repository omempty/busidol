extends Node
## 전투 이펙트·대화 초상 배선 스모크 — **에셋이 코드에 실제로 닿는지**만 본다.
##
## 왜 이 관문이 생겼나(2026-08-28): 이 저장소의 지배적 결함은 "데이터는 있는데 코드가
## 안 읽는" 사문화다. 이펙트와 초상이 정확히 그 상태였다 — 이펙트는 스펙도 그림도 없이
## 점 파티클 하나로 모든 속성을 그렸고, 초상은 스펙 16종·의뢰 파이프라인까지 있는데
## 화면에 띄우는 코드가 0곳이었다. 두 경로를 여기서 상시 감시한다.
##
## 에셋 유무에 관계없이 통과해야 한다(미납품은 폴백이 정답이다). 잡는 것은 **배선 파손**:
## 시트가 있는데 안 뜨거나, 폴백이 죽거나, 초상 조회가 크래시하는 경우.
##
## 실행: godot --headless --path . res://tests/smoke_fx.tscn   (exit 0=PASS)
##
## 2026-08-28 추가: 전투 대형 컷(원작의 리미티드 애니메이션 자리)도 같은 이유로 감시한다.


func _ready() -> void:
	var failures: Array[String] = []

	get_tree().create_timer(30.0).timeout.connect(
		func() -> void:
			push_error("[smoke_fx] WATCHDOG timeout")
			get_tree().quit(1)
	)

	var root := Node2D.new()
	add_child(root)
	var presenter := BattlePresenter.new()
	root.add_child(presenter)
	presenter.setup(root)
	presenter.build_sprites(["c_bug"] as Array[String])
	await get_tree().process_frame

	# ① 시트 이펙트 — 설치돼 있으면 스프라이트 노드가 뜨고 프레임이 진행돼야 한다.
	var installed := _installed_effect()
	if installed.is_empty():
		print("[smoke_fx] 설치된 이펙트 시트 없음 — 폴백 경로만 검사한다")
	else:
		var before := root.get_child_count()
		presenter.play_fx_kf({"effect": installed, "at_actor": "target"})
		var spr := _effect_sprite(root)
		if spr == null:
			failures.append("%s 시트가 있는데 이펙트 노드가 생기지 않았다" % installed)
		else:
			var at := spr.texture as AtlasTexture
			var x0 := int(at.region.position.x)
			presenter._advance_effects(0.2)
			var x1 := int(at.region.position.x)
			print(
				(
					"[smoke_fx] %s 노드 %d->%d · region.x %d->%d"
					% [installed, before, root.get_child_count(), x0, x1]
				)
			)
			if x1 <= x0:
				failures.append("%s 프레임이 진행되지 않았다(region.x %d->%d)" % [installed, x0, x1])

	# ② 미납품 이펙트 — 파티클 폴백이 살아 있어야 한다(예외 없이 노드가 하나 는다).
	var before_fb := root.get_child_count()
	presenter.play_fx_kf({"effect": "__missing_effect__", "at_actor": "target"})
	if root.get_child_count() <= before_fb:
		failures.append("미납품 이펙트에서 파티클 폴백이 뜨지 않았다")
	else:
		print("[smoke_fx] 폴백 파티클 OK (%d -> %d)" % [before_fb, root.get_child_count()])

	# ③ 전투 대형 컷 — 설치돼 있으면 컷이 뜨고 작은 액터가 숨어야 한다. 없으면 false.
	var cut := _installed_cut()
	if cut.is_empty():
		if presenter.play_cut("__missing_cut__"):
			failures.append("미납품 컷인데 play_cut이 true를 돌려줬다")
		else:
			print("[smoke_fx] 설치된 대형 컷 없음 — 미납품 시 기존 연출 유지 확인")
	else:
		var actor := presenter.player_sprite
		if not presenter.play_cut(cut):
			failures.append("%s 시트가 있는데 컷이 재생되지 않았다" % cut)
		elif actor != null and actor.visible:
			failures.append("컷이 뜨는 동안 작은 액터가 숨지 않았다")
		else:
			print("[smoke_fx] 컷 %s 재생 · 작은 액터 숨김 OK" % cut)

	# ④ 대화 초상 — 조회가 크래시하지 않고, 설치본이 있으면 셀 텍스처가 나와야 한다.
	var n_portraits := PortraitLibrary.installed_count()
	var missing_tex := PortraitLibrary.texture_for("있을 리 없는 화자", "normal")
	if missing_tex != null:
		failures.append("없는 화자에 초상이 나왔다")
	print("[smoke_fx] 설치된 초상 %d종" % n_portraits)
	if n_portraits > 0:
		var ok := false
		for id in _installed_portraits():
			var tex := PortraitLibrary.texture_for(id, "")
			if tex != null and tex.region.size.x == PortraitLibrary.CELL:
				ok = true
				print("[smoke_fx] 초상 %s 셀 %dx%d" % [id, tex.region.size.x, tex.region.size.y])
				break
		if not ok:
			failures.append("설치된 초상이 있는데 셀 텍스처를 못 만들었다")

	_finish(failures)


## 설치된 이펙트 id 하나(없으면 "").
func _installed_effect() -> String:
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/effect_specs.json")
	)
	if typeof(raw) != TYPE_DICTIONARY:
		return ""
	for sp: Dictionary in (raw as Dictionary).get("species", []):
		var fx_id := str(sp.get("id", ""))
		if ResourceLoader.exists("res://assets/effects/%s.png" % fx_id):
			return fx_id
	return ""


## 설치된 대형 컷 id 하나(없으면 "").
func _installed_cut() -> String:
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/battle_cut_specs.json")
	)
	if typeof(raw) != TYPE_DICTIONARY:
		return ""
	for sp: Dictionary in (raw as Dictionary).get("species", []):
		var cut_id := str(sp.get("id", ""))
		if ResourceLoader.exists("res://assets/battle_cuts/%s.png" % cut_id):
			return cut_id
	return ""


func _installed_portraits() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://assets/spec/portraits/")
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(f.get_basename())
	return out


## 이펙트 스프라이트는 z_index 50으로 붙는다(액터 위).
func _effect_sprite(root: Node2D) -> Sprite2D:
	for c in root.get_children():
		if c is Sprite2D and (c as Sprite2D).z_index == 50:
			return c
	return null


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("[smoke_fx] PASS")
		get_tree().quit(0)
		return
	for f in failures:
		push_error("[smoke_fx] FAIL %s" % f)
	get_tree().quit(1)
