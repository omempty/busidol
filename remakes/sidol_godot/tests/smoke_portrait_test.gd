extends Node
## 초상·표정 배선 스모크 — 화자 이름으로 초상을 찾고, 표정이 **다른 칸**을 가리키는가.
## 실행: godot --headless --path . res://tests/smoke_portrait.tscn   (exit 0=PASS)
##
## 왜 있나(2026-09-09): 초상 16종이 표정 3칸씩 그려져 설치돼 있는데, 대사 데이터가
## `expr`을 한 번도 지정하지 않아 **0번 칸만** 나왔다. 그림값의 2/3이 사문화였다.
## 게다가 화자 이름이 스펙 `name`과 달라(멍청 조교 vs 화공과 조교) 초상 자체가 안 뜬
## 종도 있었다. 둘 다 코드를 읽어서는 안 보이고 화면에서만 드러난다.

const EXPECT_SPEAKER := "멍청 조교"
const EXPECT_ASSET := "npc_tutor_dumb"


func _ready() -> void:
	var failures: Array[String] = []

	get_tree().create_timer(20.0).timeout.connect(
		func() -> void:
			push_error("[smoke_portrait] WATCHDOG timeout")
			get_tree().quit(1)
	)

	# 1) 화자 이름 → 초상. 배치명이 스펙 name과 달라도 speaker_aliases로 이어져야 한다.
	var got := PortraitLibrary.resolve(EXPECT_SPEAKER)
	if got != EXPECT_ASSET:
		failures.append("resolve('%s') = '%s' (기대 '%s')" % [EXPECT_SPEAKER, got, EXPECT_ASSET])

	# 2) 표정 이름 → 칸 번호. 스펙 expressions 순서가 곧 칸 순서다.
	var exprs := ["", "apologetic", "confused"]
	var cols: Array[int] = []
	for e in exprs:
		cols.append(PortraitLibrary.expression_index(EXPECT_ASSET, e))
	if cols != [0, 1, 2]:
		failures.append("표정→칸이 %s (기대 [0, 1, 2])" % [cols])

	# 3) 실제 텍스처가 **서로 다른 칸**을 가리키는가. 여기까지 와야 화면이 바뀐다.
	var xs: Array[float] = []
	for e in exprs:
		var tex := PortraitLibrary.texture_for(EXPECT_SPEAKER, e)
		if tex == null:
			failures.append("texture_for('%s') 가 null" % e)
			continue
		xs.append(tex.region.position.x)
	if xs.size() == 3 and (xs[0] == xs[1] or xs[1] == xs[2]):
		failures.append("표정이 달라도 같은 칸을 가리킨다: %s" % [xs])

	# 4) 대사 데이터가 표정을 **실제로 쓰는가**. 안 쓰면 그림의 2/3이 사문화다.
	var used := _expr_steps()
	if used == 0:
		failures.append("대사 스텝 중 expr을 지정한 것이 0개 — 초상 2·3칸이 사문화다")
	else:
		print("[smoke_portrait] expr을 쓰는 대사 스텝 %d개" % used)

	if failures.is_empty():
		print("[smoke_portrait] PASS — 화자→초상→표정 칸이 이어진다")
		get_tree().quit(0)
	else:
		for f in failures:
			push_error("[smoke_portrait] " + f)
		get_tree().quit(1)


## dialogue_sequences.json에서 expr을 지정한 스텝 수.
func _expr_steps() -> int:
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/dialogue_sequences.json")
	)
	if typeof(raw) != TYPE_DICTIONARY:
		return 0
	var data: Dictionary = raw
	var seqs: Variant = data.get("sequences", data)
	if typeof(seqs) != TYPE_DICTIONARY:
		return 0
	var n := 0
	for key in seqs as Dictionary:
		var seq: Variant = (seqs as Dictionary)[key]
		var steps: Variant = seq.get("steps", []) if typeof(seq) == TYPE_DICTIONARY else seq
		if typeof(steps) != TYPE_ARRAY:
			continue
		for st in steps as Array:
			if (
				typeof(st) == TYPE_DICTIONARY
				and not str((st as Dictionary).get("expr", "")).is_empty()
			):
				n += 1
	return n
