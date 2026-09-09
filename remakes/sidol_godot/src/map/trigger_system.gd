class_name TriggerSystem
extends Node
## 이벤트 트리거 — zone(셀 진입) / interact(전방 SPACE) / auto(층 진입 즉시).
## 데이터: data/maps/triggers_f<층>.json (docs/02_design/05_toolchain_editors.md §3.1 준용)
## 발동 결과는 시그널로 통지 — 씬(field)이 컷신·대화를 실행한다.

signal cutscene_requested(cutscene_id: StringName)
signal sequence_requested(sequence_id: StringName)

const AUTO_TICK_DELAY := 0.2  # auto 판정을 첫 물리 프레임에 몰아주지 않기 위한 지연

## 반복 zone 트리거(once:false)의 재무장 규칙에 쓰는 "없음" 표식 — 맵 밖 좌표.
##
## ## 반복 zone은 **한 칸에 한 번**만 쏜다 — 서 있는 동안 매 틱이 아니다
##
## 발동하면 컷신이 조작을 통째로 쥔다(field._physics_process가 `is_running()`에서 return).
## 그래서 매 틱 쏘면 플레이어는 그 칸에서 **한 걸음도 못 나가고** 컷신이 끝난 다음 틱에
## 또 맞는다 — 사람이든 도구든 영영 갇힌다. 2026-09-08 자동 주행 실측: F2 스파크
## 함정칸 (36,9)에 올라선 뒤 **190초 동안 40걸음**, 그 뒤 모든 목표가 「한 걸음이
## 나가지 않았다」로 실패해 F3~F5에 못 갔다. 같은 꼴이 셋이었다 —
## `f2_spark_zap` · `f3_fog_choke` · `f4_volt_zap`(백로그 §1.2 한 묶음).
##
## **초 단위 쿨다운으로는 못 막는다**(같은 날 실측: 1.0초를 넣고도 그대로 갇혔다).
## 주행은 `Engine.time_scale=120`으로 도는데 컷신 동안에는 tick이 아예 안 불리므로,
## 쿨다운이 재는 "자유 시간" 1초는 물리 두 틱(스케일 델타 0.5초/틱)밖에 안 된다 —
## 도구가 키를 누를 프레임이 오기 전에 이미 재무장이 끝난다. 시간으로 재는 한
## 배속에 따라 안전선이 흔들린다.
##
## 그래서 기준을 **플레이어가 움직였는가**로 바꾼다. 움직이려면 조작권이 있어야 하므로
## 배속과 무관하게 "빠져나갈 수 있음"이 보장된다. 함정칸을 걸어서 지나가면 밟는 칸마다
## 한 번씩 맞고, 밖으로 나갔다 다시 들어오면 또 맞는다(통행료는 그대로다).
const INVALID_CELL := Vector2i(-9999, -9999)

var _triggers: Array = []
var _fired: Dictionary = {}
## 트리거 id → 마지막으로 발동시킨 플레이어 앵커. 반복 zone 트리거의 재무장 판정에 쓴다.
## 그 칸을 벗어나면 지운다(다시 밟으면 또 맞아야 하므로).
var _fired_cell: Dictionary = {}
var _elapsed := 0.0
var _auto_checked := false


func load_for_floor(floor_no: int) -> void:
	_triggers.clear()
	_fired.clear()
	_fired_cell.clear()
	_auto_checked = false
	var path := "res://data/maps/triggers_f%d.json" % floor_no
	if not FileAccess.file_exists(path):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("트리거 파일 파싱 실패: %s" % path)
		return
	_triggers = raw.get("triggers", [])


## zone/auto 트리거 — 매물리틱에 플레이어 셀과 함께 호출.
##
## **한 틱에 하나만 발동한다.** 여러 개를 한 번에 쏘면 뒤엣것의 컷신 요청은
## CutscenePlayer가 "중복 재생 무시"로 버리는데 done_flag는 이미 켜져 다시는 안 나온다.
## 앞 트리거의 done_flag가 뒤 트리거의 requires_flag인 연쇄에서 바로 그 일이 난다 —
## F5의 치료(Q_F5_BOSS_CURE)→보스 등장 연쇄가 통째로 사라졌다(2026-08-29 층 훑기 실측).
func tick(player_cell: Vector2i, delta: float) -> void:
	_elapsed += delta
	var auto_armed := _auto_checked
	_auto_checked = true
	for t: Dictionary in _triggers:
		if _consumed(t):
			continue
		match str(t.get("type", "")):
			"auto":
				if auto_armed and _elapsed > AUTO_TICK_DELAY:
					_fire(t)
					return
			"zone":
				var zid := str(t.get("id", ""))
				if not _in_zone(t, player_cell):
					_fired_cell.erase(zid)  # 밖으로 나갔다 — 다시 밟으면 또 맞는다
				elif _fired_cell.get(zid, INVALID_CELL) != player_cell:
					_fired_cell[zid] = player_cell
					_fire(t)
					return


## interact 트리거 — 전방 셀 목록과 대조. 소비했으면 true.
func try_interact(front_cells: Array[Vector2i]) -> bool:
	for t: Dictionary in _triggers:
		if _consumed(t) or str(t.get("type", "")) != "interact":
			continue
		var cells := _trigger_cells(t)
		for c in front_cells:
			if c in cells:
				_fire(t)
				return true
	return false


func _consumed(t: Dictionary) -> bool:
	if bool(t.get("once", true)) and _fired.has(str(t["id"])):
		return true
	# done_flag 규약(triggers_f*.json 주석): 설정된 플래그면 재발동 없음
	var done := str(t.get("done_flag", ""))
	if not done.is_empty() and GameState.has_flag(done):
		return true
	# guard_flag — **읽기만 하는 done_flag.** 발동 결과가 실패할 수 있는 트리거는
	# 완료 표시를 여기서 세우면 안 된다: _fire는 컷신을 돌리기 **전에** done_flag를
	# 세우므로, 재료가 없어 중단된 컷신도 완료로 남는다(f5_cure가 그랬다 — 해독제
	# 없이 치료가 끝난 것으로 처리돼 보스전이 열렸다, 2026-08-29 자동 주행 실측).
	# 그런 트리거는 컷신 쪽(craft op)이 성공했을 때만 플래그를 세우고, 여기서는
	# 그 플래그를 재발동 금지 조건으로 읽기만 한다.
	var guard := str(t.get("guard_flag", ""))
	if not guard.is_empty() and GameState.has_flag(guard):
		return true
	# requires_flag는 문자열 하나 또는 목록이다. **목록이면 전부 서 있어야 한다** —
	# 퀴즈맨 게이트처럼 앞선 두 사건(드래그·앨린)이 모두 끝나야 열리는 문이 있다.
	if not GameState.has_all_flags(t.get("requires_flag")):
		return true
	return false


func _trigger_cells(t: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for a: Variant in t.get("cells", []):
		out.append(Vector2i(int(a[0]), int(a[1])))
	return out


## zone 판정은 **플레이어 2×2 몸**으로 한다 — 넘어오는 cell은 좌상단 앵커 하나다.
##
## 구판은 `c == cell` 완전 일치라, 몸으로 트리거 칸을 밟고 서 있어도 앵커가
## 정확히 그 칸일 때만 발동했다. 트리거 칸 하나를 덮을 수 있는 앵커는 최대 4개이므로
## 발동 자리가 4분의 1로 좁아진 셈이고, 실제로 유저가 "특정 위치에서만 발현된다"고
## 지적한 직접 원인이다(2026-09-06 실측: 전 층 zone 8종의 발동 앵커 합 7 → 21).
## interact 트리거는 `try_interact`가 정면 셀 목록으로 따로 판정하므로 영향이 없고,
## auto 트리거는 이 함수를 거치지 않는다. `_fired`·`done_flag`·`once` 규약은 `_consumed`가
## 그대로 지키므로 넓힌 것은 "발동 자리"뿐, 발동 횟수가 아니다.
func _in_zone(t: Dictionary, cell: Vector2i) -> bool:
	var cells := _trigger_cells(t)
	if cells.is_empty():
		return false
	for c in Placement.body_cells(cell):
		if c in cells:
			return true
	return false


func _fire(t: Dictionary) -> void:
	_fired[str(t["id"])] = true
	var done := str(t.get("done_flag", ""))
	if not done.is_empty():
		GameState.set_flag(done, true)
	var action: Dictionary = t.get("action", {})
	if action.has("cutscene"):
		cutscene_requested.emit(StringName(str(action["cutscene"])))
	elif action.has("sequence"):
		sequence_requested.emit(StringName(str(action["sequence"])))
