extends SceneTree
## 사용법: godot --headless --path . --script tools/validate.gd
## 콘텐츠 참조 검사 — _shared/schemas 계약 + 교차 참조(대사 키·안무·아이템·컷신).
## 규칙 문서: docs/02_design/05_toolchain_editors.md §2. exit 0=통과 / 1=오류.

const DATA := "res://data/"
const KNOWN_OPS := [
	"dialogue",
	"wait",
	"fade_in",
	"fade_out",
	"shake",
	"sfx",
	"bgm",
	"set_flags",
	"grant_item",
	"grant_skill",
	"recover",
	"craft",
	"damage",
	"blackout",
	"illustration",
	"minigame_quiz",
	"minigame_battery",
	"change_scene",
	"actor_move",
	"start_battle",
	"choice",
	"shop",
	"end"
]
const KNOWN_CHANNELS := ["sprite", "fx", "camera", "screen", "audio", "logic"]
const KNOWN_TRIGGER_TYPES := ["zone", "interact", "auto"]

var _errors: Array[String] = []
var _dialogue: Dictionary
## 대화 마커 사슬 검사 — 요구하는 플래그 ↔ 세우는 플래그.
var _talk_needed: Dictionary = {}
var _talk_sets: Dictionary = {}
var _sequences: Dictionary = {}
var _item_ids: Dictionary = {}
var _audio_ids: Dictionary = {}  # "bgm/xxx", "sfx/xxx", "voice/xxx"


func _initialize() -> void:
	print("[validate] start")
	_dialogue = _load_json(DATA + "dialogue.json") as Dictionary
	_sequences = (_load_json(DATA + "dialogue_sequences.json") as Dictionary).get("sequences", {})
	var items: Dictionary = _load_json(DATA + "items.json") as Dictionary
	for it: Dictionary in items.get("items", []):
		_item_ids[str(it["id"])] = true
	_load_audio_spec()
	_validate_battle_moves()
	_validate_cutscenes()
	_validate_triggers()
	_validate_map_locks()
	_validate_skills_choreography()
	_validate_credits()
	_validate_minigames()
	_validate_sprite_specs()
	_validate_status_effects()
	_validate_legacy_ref()
	_validate_item_reachability()
	_validate_skill_grants()
	_validate_l10n()
	_validate_story_bonus()
	_validate_battle_rules()
	_validate_keyart()
	_validate_talk_targets()

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
				if ch == "audio" and kf.has("sfx"):
					if not _audio_ids.has("sfx/" + str(kf["sfx"])):
						_err("battle_moves/%s SFX 스펙 없음: %s" % [f, kf["sfx"]])


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
					_err("cutscenes/%s 대사 키 없음: %s" % [file, dstep.get("text")])
		"sfx":
			if not _audio_ids.has("sfx/" + str(step.get("id", ""))):
				_err("cutscenes/%s SFX 스펙 없음: %s" % [file, step.get("id")])
		"bgm":
			if not _audio_ids.has("bgm/" + str(step.get("id", ""))):
				_err("cutscenes/%s BGM 스펙 없음: %s" % [file, step.get("id")])
		"minigame_quiz":
			var mg := "%sminigames/%s.json" % [DATA, step.get("id", "")]
			if not FileAccess.file_exists(mg):
				_err("cutscenes/%s 미니게임 없음: %s" % [file, mg])
		"minigame_battery":
			var mb := "%sminigames/%s.json" % [DATA, step.get("id", "")]
			if not FileAccess.file_exists(mb):
				_err("cutscenes/%s 미니게임 없음: %s" % [file, mb])
		"change_scene":
			var sp := str(step.get("path", ""))
			if not sp.begins_with("res://") or not FileAccess.file_exists(sp):
				_err("cutscenes/%s 씬 경로 없음: %s" % [file, sp])
		"start_battle":
			for eid: String in step.get("enemies", []):
				pass  # 적 ID 존재는 Database 로드 규칙상 느슨 허용(보스/floor 병합)
		"choice":
			var cargs: Dictionary = step.get("args", {})
			for opt: Dictionary in cargs.get("options", []) as Array:
				if not _text_exists(str(opt.get("text", ""))):
					_err("cutscenes/%s 선택지 텍스트 없음: %s" % [file, opt.get("text")])
				for sub: Dictionary in opt.get("steps", []) as Array:
					_validate_step(file, sub)
		"craft":
			var args: Dictionary = step.get("args", {})
			for section: String in ["requires", "grant"]:
				for item_id: String in args.get(section, {}) as Dictionary:
					if not _item_ids.has(item_id):
						_err("cutscenes/%s craft 아이템 없음: %s" % [file, item_id])
		"damage":
			var dargs: Dictionary = step.get("args", {})
			if int(dargs.get("amount", 0)) <= 0:
				_err("cutscenes/%s damage amount 누락/무효(>0이어야)" % file)
			var protect := str(dargs.get("protect_item", ""))
			if not protect.is_empty() and not _item_ids.has(protect):
				_err("cutscenes/%s damage protect_item 없음: %s" % [file, protect])
			var dsfx := str(dargs.get("sfx", ""))
			if not dsfx.is_empty() and not _audio_ids.has("sfx/" + dsfx):
				_err("cutscenes/%s damage SFX 스펙 없음: %s" % [file, dsfx])
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
			var kind := str(t.get("type", ""))
			if not kind in KNOWN_TRIGGER_TYPES:
				_err("%s/%s 알 수 없는 type" % [f, t.get("id")])
			# 좌표 스키마는 `cells` 하나다(02_design/05 §3.1). `pos` 같은 다른 이름으로
			# 적으면 TriggerSystem이 못 읽어 **조용히 발동하지 않는다** — 실제로 F2 포스터
			# 퀘스트가 그렇게 죽어 F3~F5로 갈 수 없었다(2026-08-29 자동 주행 실측).
			if kind != "auto" and (t.get("cells", []) as Array).is_empty():
				_err("%s/%s type=%s인데 cells가 없다(발동 좌표 없음)" % [f, t.get("id"), kind])
			if t.has("pos"):
				_err("%s/%s 좌표 키는 cells다 — pos는 아무도 읽지 않는다" % [f, t.get("id")])
			var action: Dictionary = t.get("action", {})
			if action.has("cutscene"):
				var cs_path := "%scutscenes/%s.json" % [DATA, action["cutscene"]]
				if not FileAccess.file_exists(cs_path):
					_err("%s/%s 컷신 없음: %s" % [f, t.get("id"), action["cutscene"]])
			elif action.has("sequence"):
				if not _sequences.has(str(action["sequence"])):
					_err("%s/%s 시퀀스 없음: %s" % [f, t.get("id"), action["sequence"]])
			else:
				_err("%s/%s action에 cutscene/sequence 없음" % [f, t.get("id")])
			# 반복 zone의 재무장은 **시간이 아니라 플레이어 이동**으로 판정한다
			# (TriggerSystem.INVALID_CELL 주석 — 초 단위 쿨다운은 배속에서 무너졌다).
			# 그래서 `cooldown_sec` 같은 키를 적어 두면 **아무도 안 읽는다** =
			# 이 저장소의 지배적 결함(사문화 데이터)이 여기서 재발한 것이다.
			if t.has("cooldown_sec"):
				_err("%s/%s cooldown_sec는 아무도 읽지 않는다 — 재무장은 이동 기준이다" % [f, t.get("id")])


# ---- maps/locks_f*.json (전자잠금) ----


## 전자잠금 표 — `TransitionGate._load_locks`/`_door_locked`/`eject_cell_for`가 읽는 계약을
## 그대로 검사한다. 이 표가 어긋나면 **아무 증상 없이 그냥 안 잠긴다**(문이 평소처럼 열린다).
## 화면에 나타나는 것이 없으므로 여기서 안 잡으면 아무도 못 잡는 유형이다.
func _validate_map_locks() -> void:
	var dir := DirAccess.open(DATA + "maps")
	if dir == null:
		return
	for f in dir.get_files():
		if not f.begins_with("locks_f") or not f.ends_with(".json"):
			continue
		var raw: Dictionary = _load_json(DATA + "maps/" + f) as Dictionary
		if raw.is_empty():
			_err("maps/%s 파싱 실패" % f)
			continue
		var locks: Array = raw.get("locks", [])
		if locks.is_empty():
			_err("maps/%s locks가 비었다 — 파일만 있고 잠그는 문이 없다" % f)
		for lock: Dictionary in locks:
			_validate_one_lock(f, lock)


func _validate_one_lock(file: String, lock: Dictionary) -> void:
	var id := str(lock.get("id", ""))
	if id.is_empty():
		_err("maps/%s 잠금 id 누락" % file)
	var door: Array = lock.get("door", [])
	if door.size() != 2:
		_err("maps/%s/%s door는 ATT 9 두 칸이다(현재 %d개)" % [file, id, door.size()])
	else:
		# TransitionGate._try_door는 (x, row)·(x+1, row) **가로 두 칸**만 본다.
		# 세로로 적으면 어떤 문도 못 맞춰 잠금이 통째로 사문화된다.
		var a := Vector2i(int(door[0][0]), int(door[0][1]))
		var b := Vector2i(int(door[1][0]), int(door[1][1]))
		if absi(a.x - b.x) != 1 or a.y != b.y:
			_err("maps/%s/%s door 두 칸이 가로로 안 붙었다: %s %s" % [file, id, str(a), str(b)])
	var interior: Array = lock.get("interior", [])
	if interior.size() != 4 or int(interior[2]) <= 0 or int(interior[3]) <= 0:
		_err("maps/%s/%s interior는 [x,y,w,h]이고 w·h가 양수여야 한다" % [file, id])
		return
	var exit_arr: Array = lock.get("exit", [])
	if exit_arr.size() != 2:
		_err("maps/%s/%s exit는 [x,y]다" % [file, id])
		return
	# exit가 방 안이면 「갇힘 탈출」이 제자리걸음이 된다 — 세이브 귀환이 영영 갇힌다.
	var ex := Vector2i(int(exit_arr[0]), int(exit_arr[1]))
	var x0 := int(interior[0])
	var y0 := int(interior[1])
	if ex.x >= x0 and ex.y >= y0 and ex.x < x0 + int(interior[2]) and ex.y < y0 + int(interior[3]):
		_err("maps/%s/%s exit가 interior 안이다 — 갇힘 탈출이 제자리걸음이 된다" % [file, id])


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
			_err("credits 카드 '%s' 대사 키 없음: %s" % [c.get("id"), c.get("text_key")])


# ---- minigames/*.json ----


func _validate_minigames() -> void:
	var dir := DirAccess.open(DATA + "minigames")
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var mg: Dictionary = _load_json(DATA + "minigames/" + f) as Dictionary
		if mg.is_empty():
			continue
		var qs: Array = mg.get("questions", [])
		if not qs.is_empty():  # 퀴즈형
			for i in qs.size():
				var q: Dictionary = qs[i]
				var choices: Array = q.get("choices", [])
				var ans := int(q.get("answer", -1))
				if not _key_or_text(str(q.get("q", ""))):
					_err("minigames/%s Q%d 질문 비어있음" % [f, i + 1])
				if ans < 0 or ans >= choices.size():
					_err("minigames/%s Q%d answer 범위 이탈(%d/%d)" % [f, i + 1, ans, choices.size()])
				for ch: Variant in choices:
					if not _key_or_text(str(ch)):
						_err("minigames/%s Q%d 선택지 비어있음" % [f, i + 1])
		elif mg.has("target_voltage"):  # 회로 퍼즐형
			if int(mg.get("target_voltage", 0)) <= 0:
				_err("minigames/%s target_voltage 무효" % f)
			if int(mg.get("slots", 0)) <= 0 or int(mg.get("lever_max", 0)) <= 0:
				_err("minigames/%s slots/lever_max 무효" % f)
			var dens: Array = mg.get("denominations", [])
			if dens.is_empty() or int(dens[0]) <= 0:
				_err("minigames/%s denominations 무효" % f)
		else:
			_err("minigames/%s questions/target_voltage 둘 다 없음" % f)


## 대사 키(@t/@c → dialogue.json 조회) 또는 원문 텍스트 모두 허용
func _key_or_text(s: String) -> bool:
	if s == "":
		return false
	return true if not s.begins_with("@") else _dialogue.has(s)


# ---- 오디오 스펙 (assets/spec/audio/*.json) ----


func _load_audio_spec() -> void:
	for kind: String in ["bgm", "sfx", "voice"]:
		var path := "res://assets/spec/audio/%s.json" % kind
		if not FileAccess.file_exists(path):
			push_warning("[validate] 오디오 스펙 대기: %s" % path)
			continue
		var raw: Variant = _load_json(path)
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		for t: Dictionary in (raw as Dictionary).get("tracks", []):
			_audio_ids["%s/%s" % [kind, t.get("id", "")]] = true


# ---- 스프라이트 스펙 구조 검사 (assets/spec/sprites/*.json) ----


func _validate_sprite_specs() -> void:
	var dir := DirAccess.open("res://assets/spec/sprites")
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var spec: Dictionary = _load_json("res://assets/spec/sprites/" + f) as Dictionary
		if spec.is_empty():
			continue
		var stem := f.trim_suffix(".json")
		if str(spec.get("asset_id", "")) != stem:
			_err("sprites/%s asset_id 불일치" % f)
		if str(spec.get("kind", "")) == "tileset":
			continue  # 타일셋은 grid/애니 구조가 다름(필수 타일 목록만 존재)
		var grid: Dictionary = spec.get("grid", {})
		var cell: Dictionary = spec.get("cell", {})
		var cols := int(grid.get("cols", 0))
		var rows := int(grid.get("rows", 0))
		if cols <= 0 or rows <= 0 or int(cell.get("w", 0)) <= 0:
			_err("sprites/%s grid/cell 무효" % f)
			continue
		for anim_name: String in spec.get("animations", {}):
			var a: Dictionary = spec["animations"][anim_name]
			if int(a.get("row", -1)) >= rows or int(a.get("row", -1)) < 0:
				_err("sprites/%s 애니 '%s' row 범위 이탈" % [f, anim_name])
			if int(a.get("frames", 0)) > cols:
				_err("sprites/%s 애니 '%s' frames > cols" % [f, anim_name])
		# 패킹 결과물은 소프트 체크(미생성 = Phase 8 진행 중)
		var packed := "res://assets/sprites/%s.png" % stem
		if not FileAccess.file_exists(packed):
			push_warning("[validate] 패킹 대기: assets/sprites/%s.png" % stem)


# ---- 공통 ----


## grant_skill이 실재하는 스킬 id를 가리키는가 + starting 목록도 유효한가.
func _validate_skill_grants() -> void:
	var raw: Dictionary = _load_json(DATA + "skills.json") as Dictionary
	var ids: Dictionary = {}
	for sk: Dictionary in raw.get("skills", []):
		ids[str(sk.get("id", ""))] = true
	for sid: Variant in raw.get("starting", []):
		if not ids.has(str(sid)):
			_err("skills.json starting의 '%s'가 skills[]에 없음" % str(sid))
	for f in DirAccess.get_files_at(DATA + "cutscenes"):
		var text := FileAccess.get_file_as_string(DATA + "cutscenes/" + f)
		if not text.contains("grant_skill"):
			continue
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		_scan_grant_skill((parsed as Dictionary).get("steps", []), f, ids)


func _scan_grant_skill(steps: Array, file: String, ids: Dictionary) -> void:
	for st: Dictionary in steps:
		if str(st.get("op", "")) == "grant_skill":
			var sid := str((st.get("args", {}) as Dictionary).get("skill", ""))
			if not ids.has(sid):
				_err("%s grant_skill '%s' — skills.json에 없는 스킬" % [file, sid])
		if st.has("steps"):
			_scan_grant_skill(st["steps"], file, ids)


## 아이템에 획득 경로가 있는가 — 상자(legacy_ref)·상점·컷신 셋 중 하나.
## 만들어 놓고 줄 방법이 없으면 데이터가 조용히 사문화된다(2026-08-27 실측 14종).
## 경고 티어: 서사 진행상 아직 배치 전인 것이 정상일 수 있어 FAIL이 아니다.
func _validate_item_reachability() -> void:
	var raw: Dictionary = _load_json(DATA + "items.json") as Dictionary
	var reachable: Dictionary = {}
	for key: String in raw.get("legacy_ref", {}):
		if key.is_valid_int():
			reachable[str((raw["legacy_ref"] as Dictionary)[key])] = true
	var shops: Dictionary = _load_json(DATA + "shops.json") as Dictionary
	for shop: Dictionary in (shops.get("shops", {}) as Dictionary).values():
		for iid: String in shop.get("stock", []):
			reachable[iid] = true
	for f in DirAccess.get_files_at(DATA + "cutscenes"):
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(DATA + "cutscenes/" + f)
		)
		if typeof(parsed) == TYPE_DICTIONARY:
			_scan_item_grants((parsed as Dictionary).get("steps", []), reachable)

	var orphans: Array[String] = []
	for it: Dictionary in raw.get("items", []):
		var iid := str(it["id"])
		if reachable.has(iid):
			continue
		orphans.append("%s(%s)" % [iid, str(it.get("name_ko", ""))])
	if not orphans.is_empty():
		print("[validate] 경고 — 획득 경로 없는 아이템 %d종: %s" % [orphans.size(), ", ".join(orphans)])


## 컷신 명령열에서 "실제로 지급하는" op만 골라 담는다 — grant_item.item · craft.grant 키.
## 파일 전체 문자열 포함으로 세면 craft.requires나 주석의 단순 언급도 통과해 버려
## "쓰기만 하고 주지는 않는" 아이템이 사문화된 채 숨는다.
func _scan_item_grants(steps: Array, reachable: Dictionary) -> void:
	for st: Dictionary in steps:
		var args: Dictionary = st.get("args", {})
		match str(st.get("op", "")):
			"grant_item":
				reachable[str(args.get("item", ""))] = true
			"craft":
				for gid: String in args.get("grant", {}) as Dictionary:
					reachable[gid] = true
		for opt: Dictionary in args.get("options", []) as Array:
			_scan_item_grants(opt.get("steps", []), reachable)
		if st.has("steps"):
			_scan_item_grants(st["steps"], reachable)


## 상자 ATT ↔ 아이템 매핑이 실재하는 id를 가리키는가.
## 2026-08-27 실측: 35개 중 11개가 개명 뒤 따라가지 않아 깨져 있었다(상자를 열어도 빈손).
func _validate_legacy_ref() -> void:
	var raw: Dictionary = _load_json(DATA + "items.json") as Dictionary
	var ids: Dictionary = {}
	for it: Dictionary in raw.get("items", []):
		ids[str(it["id"])] = true
	for key: String in raw.get("legacy_ref", {}):
		if not key.is_valid_int():
			continue
		var target := str((raw["legacy_ref"] as Dictionary)[key])
		if not ids.has(target):
			_err("legacy_ref[%s] -> '%s' — items.json에 없는 id(상자가 빈손이 된다)" % [key, target])


## 스킬의 status_effects id가 정의돼 있고, 그 kind를 Combatant가 실제로 아는지.
## 2026-08-26 실측 결함: 'burn'·'buff_damage_taken_50'을 kind로 그대로 넘겨
## 매칭이 안 돼 두 효과가 조용히 무효였다. 이름만 맞으면 통과하던 구멍이라 명시 검사한다.
func _validate_status_effects() -> void:
	const KNOWN_KINDS := [
		"dot", "buff_damage_taken", "paralysis", "buff_attack", "buff_status_resist"
	]
	var raw: Dictionary = _load_json(DATA + "skills.json") as Dictionary
	var defs: Dictionary = raw.get("status_effect_defs", {})
	for eid: String in defs:
		var kind := str((defs[eid] as Dictionary).get("kind", ""))
		if not KNOWN_KINDS.has(kind):
			_err(
				(
					"status_effect_defs['%s'].kind='%s' — Combatant가 모르는 종류(%s 중 하나여야)"
					% [eid, kind, ", ".join(KNOWN_KINDS)]
				)
			)
	for sk: Dictionary in raw.get("skills", []):
		for eid: String in sk.get("status_effects", []):
			if not defs.has(eid):
				_err(
					(
						"skills['%s'].status_effects의 '%s'가 status_effect_defs에 없음"
						% [str(sk.get("id", "?")), eid]
					)
				)


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


## 원작 ATT 대화 마커 표 검사 — 대사 키가 실재하는가, 맵에 실제로 그 ATT가 있는가.
##
## 이 표는 **맵의 ATT 값에 기대어 산다.** 키를 잘못 적으면 말은 걸리는데 빈 창이 뜨고,
## 맵에 없는 ATT를 적으면 영영 안 불린다 — 둘 다 화면에서는 조용해서 안 드러난다.
func _validate_talk_targets() -> void:
	var path := "res://data/maps/talk_targets.json"
	if not FileAccess.file_exists(path):
		_err("대화 마커 표 없음: %s" % path)
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		_err("대화 마커 표 파싱 실패: %s" % path)
		return
	# 맵에 실제로 깔린 ATT 값 모으기
	var used: Dictionary = {}
	for floor_idx in range(0, 6):
		var mp := "res://data/maps/f%d.json" % floor_idx
		if not FileAccess.file_exists(mp):
			continue
		var mraw: Variant = JSON.parse_string(FileAccess.get_file_as_string(mp))
		if typeof(mraw) != TYPE_DICTIONARY:
			continue
		for row: Array in (mraw as Dictionary)["layers"]["attr"]:
			for v: int in row:
				used[v] = int(used.get(v, 0)) + 1

	var targets: Dictionary = (raw as Dictionary).get("targets", {})
	var placed := 0
	_talk_needed = {}
	_talk_sets = {}
	for key: String in targets:
		var att := int(key)
		var t: Dictionary = targets[key]
		# 조건부 대상은 `texts`가 비어 있을 수 있다 — 원작에서 조건 전에 아무 말도
		# 안 하던 대상이다(Talk_ELIN_F에 else가 없다). 그때는 variants가 있어야 한다.
		var texts: Array = t.get("texts", []) + t.get("repeat_texts", [])
		# 사슬 검사 — variants가 요구하는 플래그를 **누군가는 세워야 한다.**
		# 아무도 안 세우면 그 갈래는 영영 안 나온다(마커는 살아 있는데 대사는 죽는다).
		for v: Dictionary in t.get("variants", []):
			texts += v.get("texts", []) as Array
			var need := str(v.get("requires_flag", ""))
			if not need.is_empty():
				_talk_needed[need] = att
			if (v.get("texts", []) as Array).is_empty():
				_err("대화 마커 ATT %d: variants에 대사 없는 갈래가 있다" % att)
		var sets_all: Array = [str(t.get("sets_flag", ""))]
		for v2: Dictionary in t.get("variants", []):
			sets_all.append(str(v2.get("sets_flag", "")))
		for sf: String in sets_all:
			if not sf.is_empty():
				_talk_sets[sf] = att
		if texts.is_empty():
			_err("대화 마커 ATT %d: 어느 조건에서도 대사가 없다" % att)
		for tk: String in texts:
			if not _dialogue.has(tk):
				_err("대화 마커 ATT %d가 쓰는 대사 키 %s가 dialogue.json에 없음" % [att, tk])
		if not used.has(att):
			_err("대화 마커 ATT %d(%s)가 어느 맵에도 없다" % [att, str(t.get("id", ""))])
		else:
			placed += int(used[att])
	# 요구만 하고 아무도 안 세우는 플래그 — 그 갈래는 영영 안 나온다.
	for need: String in _talk_needed:
		if not _talk_sets.has(need):
			_err("대화 마커 ATT %d가 요구하는 플래그 '%s'를 세우는 곳이 없다" % [int(_talk_needed[need]), need])
	# 잡담 은행 — 역할 풀이 가리키는 대사 키도 dialogue.json에 있어야 한다.
	# 본문이 끊기면 빈 줄이 나와 고장으로 읽힌다(마커 검사와 같은 등급).
	var chatter_raw: Variant = _load_json(DATA + "chatter.json")
	var chatter_n := 0
	if typeof(chatter_raw) == TYPE_DICTIONARY:
		for role: String in (chatter_raw as Dictionary).get("roles", {}):
			for ck: Variant in ((chatter_raw as Dictionary)["roles"] as Dictionary)[role]:
				chatter_n += 1
				if not _dialogue.has(str(ck)):
					_err("잡담 은행 역할 %s가 쓰는 대사 키 %s가 dialogue.json에 없음" % [role, ck])
	print(
		(
			"[validate] 대화 마커 %d종 · 맵에 깔린 칸 %d개 · 사슬 플래그 %d개 · 잡담 %d줄"
			% [targets.size(), placed, _talk_sets.size(), chatter_n]
		)
	)


## UI 문자열 ↔ 번역표(data/l10n/ui.csv) 양방향 대조.
## 한쪽만 검사하면 반쪽이 조용히 죽는다: 키만 있고 표에 없으면 화면에 키가 그대로 뜨고,
## 표에만 있고 코드가 안 쓰면 번역 비용만 남는 사문화 데이터가 된다(2026-08-27 교훈).
func _validate_l10n() -> void:
	var path := "res://data/l10n/ui.csv"
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh == null:
		_err("l10n 표 없음: %s" % path)
		return
	var header: PackedStringArray = fh.get_csv_line()
	var table: Dictionary = {}
	var blanks: Array[String] = []
	while not fh.eof_reached():
		var row: PackedStringArray = fh.get_csv_line()
		if row.size() < 2 or row[0].is_empty():
			continue
		table[row[0]] = true
		for col in range(1, header.size()):
			if col >= row.size() or row[col].strip_edges().is_empty():
				blanks.append("%s[%s]" % [row[0], header[col]])
	fh.close()

	var used: Dictionary = {}
	var re := RegEx.create_from_string('"(UI_[A-Z0-9_]+)"')
	for f in _gd_files("res://src") + _gd_files("res://scenes"):
		for m in re.search_all(FileAccess.get_file_as_string(f)):
			used[m.get_string(1)] = f

	for key: String in used:
		if not table.has(key):
			_err("%s가 쓰는 번역 키 '%s'가 ui.csv에 없음" % [str(used[key]).get_file(), key])
	var unused: Array[String] = []
	for key2: String in table:
		if not used.has(key2):
			unused.append(key2)
	if not unused.is_empty():
		print("[validate] 경고 — 아무 데서도 안 쓰는 번역 키 %d개: %s" % [unused.size(), ", ".join(unused)])
	if not blanks.is_empty():
		print("[validate] 경고 — 번역 빈칸 %d개: %s" % [blanks.size(), ", ".join(blanks)])


## 디렉터리 아래 .gd 전부(재귀).
func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	for d in DirAccess.get_directories_at(dir_path):
		out += _gd_files(dir_path + "/" + d)
	for f in DirAccess.get_files_at(dir_path):
		if f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
	return out


## 스토리 보너스 EXP가 실재 퀘스트 플래그를 가리키는가 + 성장에서 차지하는 몫은 얼마인가.
## 이 표는 2026-08-28까지 **아무도 읽지 않는 사문화 데이터**였다(지급 경로 자체가 없었다).
## 이제 성장의 60%가량이 여기서 나오므로, 오타 하나가 곧 "그 층만 노가다"가 된다.
func _validate_story_bonus() -> void:
	var growth: Dictionary = _load_json(DATA + "growth.json") as Dictionary
	var table: Dictionary = growth.get("story_bonus_exp", {})
	var quests: Dictionary = _load_json(DATA + "quests_v2.json") as Dictionary
	var ids: Dictionary = {}
	for q: Dictionary in quests.get("quests", []):
		ids[str(q.get("id", ""))] = true
	var total := 0
	for key: String in table:
		if key.begins_with("_"):
			continue
		if not ids.has(key):
			_err("growth.json story_bonus_exp의 '%s'가 quests_v2.json에 없는 퀘스트" % key)
		total += int(table[key])
	var levels: Array = growth.get("levels", [])
	var max_accum := 0
	for e: Dictionary in levels:
		max_accum = maxi(max_accum, int(e.get("exp_accum", 0)))
	if max_accum > 0:
		var share := 100.0 * float(total) / float(max_accum)
		print("[validate] 스토리 보너스 %d EXP — 만렙 요구치 %d의 %.0f%%" % [total, max_accum, share])


## 전투 규칙 수치가 제 범위에 있는가 — 도망이 항상 성공(1.0)하거나 영영 실패(0.0)하면
## 규칙이 있으나 마나다. 0~1 확률 필드와 상·하한 순서를 본다.
func _validate_battle_rules() -> void:
	var rules: Dictionary = (_load_json(DATA + "battle_rules.json") as Dictionary).get("flee", {})
	if rules.is_empty():
		_err("battle_rules.json에 flee 규칙이 없음")
		return
	for key: String in [
		"base_chance",
		"per_failure_bonus",
		"low_hp_bonus",
		"low_hp_at",
		"floor_penalty",
		"min_chance",
		"max_chance"
	]:
		if not rules.has(key):
			_err("battle_rules.json flee.%s 누락" % key)
			continue
		var v := float(rules[key])
		if v < 0.0 or v > 1.0:
			_err("battle_rules.json flee.%s가 0~1 밖: %s" % [key, v])
	if float(rules.get("min_chance", 0.0)) >= float(rules.get("max_chance", 1.0)):
		_err("battle_rules.json flee.min_chance가 max_chance 이상")
	_validate_defeat_rules()


## 패배 대가 스키마 — 기본값 + 난이도별 오버라이드 + 연패 자비.
## 빠진 키·난이도는 기본값으로 떨어지므로(코드 폴백) 여기서는 범위·형식만 본다.
func _validate_defeat_rules() -> void:
	var defeat: Dictionary = (_load_json(DATA + "battle_rules.json") as Dictionary).get(
		"defeat", {}
	)
	if defeat.is_empty():
		_err("battle_rules.json에 defeat 규칙이 없음")
		return
	for key: String in ["hp_ratio", "money_loss"]:
		if not defeat.has(key):
			_err("battle_rules.json defeat.%s 누락" % key)
		elif float(defeat[key]) < 0.0 or float(defeat[key]) > 1.0:
			_err("battle_rules.json defeat.%s가 0~1 밖: %s" % [key, defeat[key]])
	for diff: String in defeat.get("by_difficulty", {}) as Dictionary:
		if diff not in ["easy", "normal", "hard"]:
			_err("battle_rules.json defeat.by_difficulty 알 수 없는 난이도: %s" % diff)
			continue
		var preset: Dictionary = (defeat["by_difficulty"] as Dictionary)[diff]
		for key: String in ["hp_ratio", "money_loss"]:
			if preset.has(key) and (float(preset[key]) < 0.0 or float(preset[key]) > 1.0):
				_err("battle_rules.json defeat.by_difficulty.%s.%s가 0~1 밖" % [diff, key])
	var mercy: Dictionary = defeat.get("mercy", {})
	if not mercy.is_empty():
		if int(mercy.get("streak", 2)) < 2:
			_err("battle_rules.json defeat.mercy.streak는 2 이상(첫 패배부터 자비면 대가가 없음)")
		if typeof(mercy.get("waive_money", true)) != TYPE_BOOL:
			_err("battle_rules.json defeat.mercy.waive_money는 bool")


## 컷신 illustration op ↔ 키아트 스펙·납품물 대조.
##
## 두 티어로 나눈다: **오타는 오류**(스펙에 없는 id를 가리키면 영영 안 뜬다),
## **미납품은 경고**(그림이 데이터보다 늦게 오는 것이 정상 순서다).
## op만 만들어 두고 아무 컷신도 쓰지 않으면 그것대로 사문화이므로 사용처 수도 보고한다.
func _validate_keyart() -> void:
	var spec_dir := "res://assets/spec/keyart"
	var specs: Dictionary = {}
	for f in DirAccess.get_files_at(spec_dir):
		if f.ends_with(".json"):
			specs[f.trim_suffix(".json")] = true

	var used: Dictionary = {}
	for f in DirAccess.get_files_at(DATA + "cutscenes"):
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(DATA + "cutscenes/" + f)
		)
		if typeof(parsed) == TYPE_DICTIONARY:
			_scan_illustration((parsed as Dictionary).get("steps", []), f, specs, used)

	var missing_art: Array[String] = []
	for art_id: String in used:
		if not FileAccess.file_exists("res://assets/keyart/%s.png" % art_id):
			missing_art.append(art_id)
	if not missing_art.is_empty():
		print(
			(
				"[validate] 경고 — 컷신이 쓰는데 아직 납품되지 않은 키아트 %d종: %s"
				% [missing_art.size(), ", ".join(missing_art)]
			)
		)
	var unused: Array[String] = []
	for spec_id: String in specs:
		if not used.has(spec_id):
			unused.append(spec_id)
	if not unused.is_empty():
		print(
			"[validate] 경고 — 스펙만 있고 어느 컷신도 쓰지 않는 키아트 %d종: %s" % [unused.size(), ", ".join(unused)]
		)


func _scan_illustration(steps: Array, file: String, specs: Dictionary, used: Dictionary) -> void:
	for st: Dictionary in steps:
		var args: Dictionary = st.get("args", {})
		if str(st.get("op", "")) == "illustration":
			var art_id := str(args.get("id", ""))
			if not art_id.is_empty():
				if not specs.has(art_id):
					_err("%s illustration '%s' — assets/spec/keyart에 없는 키아트" % [file, art_id])
				used[art_id] = true
		for opt: Dictionary in args.get("options", []) as Array:
			_scan_illustration(opt.get("steps", []), file, specs, used)
		if st.has("steps"):
			_scan_illustration(st["steps"], file, specs, used)
