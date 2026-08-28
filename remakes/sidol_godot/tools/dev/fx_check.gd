extends SceneTree
## 전투 이펙트 배선 확인 — 스펙·시트·무브가 서로 가리키고 있는가.
##
## 왜 남기나: 이펙트는 "데이터는 있는데 코드가 안 읽는" 사문화가 나기 쉬운 자리다.
## 2026-08-28 이전 상태가 정확히 그랬다 — battle_moves의 fx 채널은 있는데 그림이 없어
## 전부 점 파티클 하나로 떨어졌고, 아무 관문도 그걸 보고하지 않았다.
##
## 이 스크립트가 보는 것:
##   ① effect_specs.json의 종마다 시트가 설치돼 있는가(없으면 파티클 폴백임을 알린다)
##   ② 설치된 시트가 계약 크기(열×128 × 행×128)와 메타 JSON을 갖췄는가
##   ③ battle_moves가 부르는 effect 토큰이 스펙에 있는가(오타 = 조용한 폴백)
##
## 실행: godot --headless --path . --script tools/dev/fx_check.gd
## 종료코드 0=이상 없음 / 1=계약 불일치·미등록 토큰

const SPECS := "res://data/effect_specs.json"
const CUT_SPECS := "res://data/battle_cut_specs.json"
const CUT_DIR := "res://assets/battle_cuts/"
const MOVES_DIR := "res://data/battle_moves/"
const FX_DIR := "res://assets/effects/"
const CELL := 128


func _init() -> void:
	var fail := 0
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPECS))
	if typeof(raw) != TYPE_DICTIONARY:
		print("[fx_check] effect_specs.json 파싱 실패")
		quit(1)
		return
	var specs: Dictionary = raw
	var known: Dictionary = {}
	var installed := 0
	print("[fx_check] 이펙트 종")
	for sp: Dictionary in specs.get("species", []):
		var fx_id := str(sp.get("id", ""))
		known[fx_id] = true
		var anims: Dictionary = sp.get("animations", {})
		var play: Dictionary = anims.get("play", {})
		var cols := int(play.get("frames", 1))
		var png := FX_DIR + fx_id + ".png"
		if not ResourceLoader.exists(png):
			print("  [pend] %-12s 시트 미납품 — 점 파티클 폴백" % fx_id)
			continue
		installed += 1
		var tex: Texture2D = load(png)
		var want := Vector2i(cols * CELL, CELL)
		var got := Vector2i(int(tex.get_width()), int(tex.get_height()))
		if got != want:
			print("  [FAIL] %-12s 크기 %s — 계약 %s" % [fx_id, got, want])
			fail += 1
			continue
		if not FileAccess.file_exists(FX_DIR + fx_id + ".json"):
			print("  [FAIL] %-12s 메타 JSON 없음 — install_delivery.py가 만든다" % fx_id)
			fail += 1
			continue
		print("  [ok]   %-12s %dx%d · %d프레임" % [fx_id, got.x, got.y, cols])

	print("[fx_check] battle_moves의 effect 토큰")
	var dir := DirAccess.open(MOVES_DIR)
	if dir != null:
		for f in dir.get_files():
			if not f.ends_with(".json"):
				continue
			var mv: Variant = JSON.parse_string(FileAccess.get_file_as_string(MOVES_DIR + f))
			if typeof(mv) != TYPE_DICTIONARY:
				continue
			var channels: Dictionary = (mv as Dictionary).get("channels", {})
			for kf: Dictionary in channels.get("fx", []):
				var token := str(kf.get("effect", "hit_spark"))
				if not known.has(token):
					print("  [FAIL] %s -> '%s' 은 effect_specs.json에 없다(조용한 폴백)" % [f, token])
					fail += 1
	print("[fx_check] 전투 대형 컷")
	var cut_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CUT_SPECS))
	var cut_installed := 0
	var cut_total := 0
	if typeof(cut_raw) == TYPE_DICTIONARY:
		for sp: Dictionary in (cut_raw as Dictionary).get("species", []):
			cut_total += 1
			var cut_id := str(sp.get("id", ""))
			var cell := int(sp.get("sheet_cell", 512))
			var frames := int(
				(sp.get("animations", {}) as Dictionary).get("play", {}).get("frames", 1)
			)
			if not ResourceLoader.exists(CUT_DIR + cut_id + ".png"):
				print("  [pend] %-22s 미납품 — 컷 없이 기존 연출" % cut_id)
				continue
			cut_installed += 1
			var ctex: Texture2D = load(CUT_DIR + cut_id + ".png")
			var cwant := Vector2i(frames * cell, cell)
			var cgot := Vector2i(int(ctex.get_width()), int(ctex.get_height()))
			if cgot != cwant:
				print("  [FAIL] %-22s 크기 %s — 계약 %s" % [cut_id, cgot, cwant])
				fail += 1
			else:
				print("  [ok]   %-22s %dx%d · %d프레임" % [cut_id, cgot.x, cgot.y, frames])
	print(
		(
			"[fx_check] 이펙트 %d/%d종 · 대형 컷 %d/%d종 · 불일치 %d건"
			% [installed, known.size(), cut_installed, cut_total, fail]
		)
	)
	quit(1 if fail > 0 else 0)
