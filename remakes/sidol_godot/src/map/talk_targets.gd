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


static func has(attr: int) -> bool:
	return not find(attr).is_empty()


## 이 대상에게 지금 말을 걸면 나올 대사 스텝. 반복 횟수를 여기서 센다.
##
## `repeat_after`가 있으면 그 횟수째에 다른 대사가 나온다 — 원작 오른쪽 그림이
## 다섯 번을 참아 준 사람에게 "당신의 인내력에 감탄 했소."라고 하는 그 분기다.
static func steps_for(attr: int) -> Array:
	var t := find(attr)
	if t.is_empty():
		return []
	var count := int(_talk_counts.get(attr, 0)) + 1
	_talk_counts[attr] = count
	var texts: Array = t.get("texts", [])
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
