extends SceneTree
## 사용법: godot --headless --path . --script tools/validate.gd
## 콘텐츠 참조 검사 — _shared/schemas 계약 + 교차 참조(대사 키·안무·아이템·컷신).
## 규칙 문서: docs/02_design/05_toolchain_editors.md §2. exit 0=통과 / 1=오류.

const DATA := "res://data/"
const KNOWN_OPS := ["dialogue", "wait", "fade_in", "fade_out", "shake", "sfx",
		"bgm", "set_flags", "grant_item", "craft", "minigame_quiz",
		"actor_move", "start_battle", "end"]
const KNOWN_CHANNELS := ["sprite", "fx", "camera", "screen", "audio", "logic"]
const KNOWN_TRIGGER_TYPES := ["zone", "interact", "auto"]

var _errors: Array[String] = []
var _dialogue: Dictionary = {}
var _sequences: Dictionary = {}
var _item_ids: Dictionary = {}


func _initialize() -> void:
	print("[validate] start")
	_dialogue = _load_json(DATA + "dialogue.json") as Dictionary
	_sequences = (_load_json(DATA + "dialogue_sequences.json")
			as Dictionary).get("sequences", {})
	var items: Dictionary = _load_json(DATA + "items.json") as Dictionary
	for it: Dictionary in items.get("items", []):
		_item_ids[str(it["id"])] = true

	_validate_battle_moves()
	_validate_cutscenes()
	_validate_triggers()
	_validate_skills_choreography()
	_validate_credits()

	if _errors.is_empty():
		print("[validate] done - 0 errors")
		quit(0)
	else:
		for e in _errors:
			push_error("[validate] " + e)
		print("[validate] done - %d errors" % _errors.size())
		quit(1)


# ---- battle_moves ----

func _validate_battle_moves() -> void:
	var dir := DirAccess.open(DATA + "battle_moves")
	if dir == null:
		_err("battle_moves 디렉터리 없음")
		return
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var mv: Dictionary = _load_json(DATA + "battle_moves/" + f) as Dictionary
		if mv.is_empty():
			_err("battle_moves/%s 파싱 실패" % f)
			continue
		var stem := f.trim_suffix(".json")
		if str(mv.get("id", "")) != stem:
			_err("battle_moves/%s id 불일치(%s)" % [f, mv.get("id")])
		if float(mv.get("length", 0)) <= 0.0:
			_err("battle_moves/%s length 누락/무효" % f)
		var channels: Dictionary = mv.get("channels", {})
		for ch: String in channels:
			if not ch in KNOWN_CHANNELS:
				_err("battle_moves/%s 알 수 없는 채널 '%s'" % [f, ch])
			for kf: Dictionary in channels[ch]:
				if float(kf.get("t", -1)) < 0.0:
					_err("battle_moves/%s 채널 %s t 누락" % [f, ch])


# ---- cutscenes ----

func _validate_cutscenes() -> void:
	var dir := DirAccess.open(DATA + "cutscenes")
	if dir == null:
		_err("cutscenes 디렉터리 없음")
		return
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var cs: Dictionary = _load_json(DATA + "cutscenes/" + f) as Dictionary
		if cs.is_empty():
			_err("cutscenes/%s 파싱 실패" % f)
			continue
		if str(cs.get("id", "")) != f.trim_suffix(".json"):
			_err("cutscenes/%s id 불일치" % f)
		for step: Dictionary in cs.get("steps", []):
			_validate_step(f, step)


func _validate_step(file: String, step: Dictionary) -> void:
	var op := str(step.get("op", ""))
	if not op in KNOWN_OPS:
		_err("cutscenes/%s 알 수 없는 op '%s'" % [file, op])
	match op:
		"dialogue":
			for dstep: Dictionary in step.get("steps", []):
				if not _text_exists(str(dstep.get("text", ""))):
					_err("cutscenes/%s 대사 키 없음: %s" %
							[file, dstep.get("text")])
		"sfx":
			pass  # SFX ID는 Phase 8 오디오 확보 후 검사
		"minigame_quiz":
			var mg := "%sminigames/%s.json" % [DATA, step.get("id", "")]
			if not FileAccess.file_exists(mg):
				_err("cutscenes/%s 미니게임 없음: %s" % [file, mg])
		"start_battle":
			for eid: String in step.get("enemies", []):
				pass  # 적 ID 존재는 Database 로드 규칙상 느슨 허용(보스/floor 병합)
		"craft":
			var args: Dictionary = step.get("args", {})
			for section: String in ["requires", "grant"]:
				for item_id: String in (args.get(section, {}) as Dictionary):
					if not _item_ids.has(item_id):
						_err("cutscenes/%s craft 아이템 없음: %s" %
								[file, item_id])
	# dialogue/wait 등 나머지 op는 런타임 기본값으로 안전


# ---- triggers_f*.json ----

func _validate_triggers() -> void:
	var dir := DirAccess.open(DATA + "maps")
	if dir == null:
		return
	for f in dir.get_files():
		if not f.begins_with("triggers_") or not f.ends_with(".json"):
			continue
		var raw: Dictionary = _load_json(DATA + "maps/" + f) as Dictionary
		for t: Dictionary in raw.get("triggers", []):
			if str(t.get("id", "")) == "":
				_err("%s 트리거 id 누락" % f)
			if not str(t.get("type", "")) in KNOWN_TRIGGER_TYPES:
				_err("%s/%s 알 수 없는 type" % [f, t.get("id")])
			var action: Dictionary = t.get("action", {})
			if action.has("cutscene"):
				var cs_path := "%scutscenes/%s.json" % [DATA, action["cutscene"]]
				if not FileAccess.file_exists(cs_path):
					_err("%s/%s 컷신 없음: %s" % [f, t.get("id"),
							action["cutscene"]])
			elif action.has("sequence"):
				if not _sequences.has(str(action["sequence"])):
					_err("%s/%s 시퀀스 없음: %s" % [f, t.get("id"),
							action["sequence"]])
			else:
				_err("%s/%s action에 cutscene/sequence 없음" % [f, t.get("id")])


# ---- skills.json choreography_id ----

func _validate_skills_choreography() -> void:
	var skills: Dictionary = _load_json(DATA + "skills.json") as Dictionary
	for s: Dictionary in skills.get("skills", []):
		var cid := str(s.get("choreography_id", ""))
		if cid == "":
			continue
		if not FileAccess.file_exists("%sbattle_moves/%s.json" % [DATA, cid]):
			_err("skill '%s' 안무 없음: %s" % [s.get("id"), cid])


# ---- credits.json text_key ----

func _validate_credits() -> void:
	var cr: Dictionary = _load_json(DATA + "credits.json") as Dictionary
	for c: Dictionary in cr.get("ending_cards", []):
		if not _text_exists(str(c.get("text_key", ""))):
			_err("credits 카드 '%s' 대사 키 없음: %s" %
					[c.get("id"), c.get("text_key")])


# ---- 공통 ----

func _text_exists(key: String) -> bool:
	if key == "":
		return false
	return _dialogue.has(key)


func _err(msg: String) -> void:
	_errors.append(msg)


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_err("파일 없음: " + path)
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if raw == null:
		_err("JSON 파싱 실패: " + path)
	return raw
