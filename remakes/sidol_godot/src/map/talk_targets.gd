class_name TalkTargets
## 원작 ATT 대화 마커 — 맵의 ATT 값이 곧 대화 상대다.
##
## 왜 생겼나(2026-08-30): 원작 `Talk()`은 플레이어 앞 칸의 **ATT 값으로 대화 상대를
## 분기**했다(`GOODITEM.C:1150`) — 11=학생, 75=홍보, 97/98=벽 그림, 99=아무 도움 안
## 되는 사람 …. 맵은 원본과 바이트 일치라 그 마커가 전부 살아 있고, 대사 원문(@t)도
## 229줄이 이미 `dialogue.json`에 들어와 있었다. **읽는 코드만 0줄이었다.**
## 전 층 실측 192칸 · 21종이 그렇게 죽어 있었다(이 저장소의 지배적 결함 중 최대 규모).
##
## NPC(`npcs_f*.json`)와는 다른 층이다 — NPC는 우리가 세운 2×2 액터고, 이쪽은
## **맵 그림에 붙은 말 걸 수 있는 자리**다. 그래서 조사 순서도 NPC 다음, 상자 앞이다.

const PATH := "res://data/maps/talk_targets.json"

static var _targets: Dictionary = {}  # int(ATT) -> Dictionary
static var _loaded := false
## 몇 번째 말 걸기인가 — 원작 `Talk_pRIGHT_F`의 `static count`에 대응한다.
## 세션 동안만 산다(세이브에 넣지 않는다) — 원작도 프로세스 수명이었다.
static var _talk_counts: Dictionary = {}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_warning("대화 마커 표 없음: %s" % PATH)
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("대화 마커 표 파싱 실패: %s" % PATH)
		return
	var doc: Dictionary = raw
	for key: String in doc.get("targets", {}):
		_targets[int(key)] = doc["targets"][key]


## ATT 값 → 대상 정의(없으면 빈 사전).
static func find(attr: int) -> Dictionary:
	_load()
	return _targets.get(attr, {})


## 지금 이 ATT에 말을 걸 수 있는가. **표에 있다는 것만으로는 부족하다** —
## 조건 전에는 아예 말이 없는 대상이 있어서(원작 `Talk_ELIN_F`에 else가 없다),
## 그때 프롬프트만 뜨고 눌러도 아무 일이 없으면 고장으로 읽힌다.
static func has(attr: int) -> bool:
	var t := find(attr)
	return not t.is_empty() and not _texts_now(t).is_empty()


## 지금 상태에서 나올 대사 목록(카운터를 건드리지 않는다).
##
## 조건부 대상은 원작 `v_Howa` 분기의 자리다 — 플래그가 서면 다른(또는 비로소 있는)
## 대사가 나온다. 원작에서 조건 전 대사가 있던 대상(FELIN)은 `texts`가 그 대사이고,
## 없던 대상(ELIN)은 `texts`가 비어 있다.
static func _texts_now(t: Dictionary) -> Array:
	var flag := str(t.get("requires_flag", ""))
	if not flag.is_empty() and GameState.has_flag(flag):
		var unlocked: Array = t.get("flag_texts", [])
		if not unlocked.is_empty():
			return unlocked
	return t.get("texts", [])


## 이 대상에게 지금 말을 걸면 나올 대사 스텝. 반복 횟수를 여기서 센다.
##
## `repeat_after`가 있으면 그 횟수째에 다른 대사가 나온다 — 원작 오른쪽 그림이
## 다섯 번을 참아 준 사람에게 "당신의 인내력에 감탄 했소."라고 하는 그 분기다.
static func steps_for(attr: int) -> Array:
	var t := find(attr)
	if t.is_empty():
		return []
	var texts := _texts_now(t)
	if texts.is_empty():
		return []

	var count := int(_talk_counts.get(attr, 0)) + 1
	_talk_counts[attr] = count
	var after := int(t.get("repeat_after", 0))
	if after > 0 and count % after == 0:
		var alt: Array = t.get("repeat_texts", [])
		if not alt.is_empty():
			texts = alt
	var speaker := str(t.get("name", ""))
	var out: Array = []
	for key: String in texts:
		out.append({"speaker": speaker, "text": key})
	return out


static func display_name(attr: int) -> String:
	return str(find(attr).get("name", ""))


## 새 게임·불러오기 — 반복 카운터를 비운다.
static func reset_counts() -> void:
	_talk_counts.clear()
