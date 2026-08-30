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


## 지금 상태에서 고를 분기(카운터를 건드리지 않는다).
##
## 원작 대화 상대들은 **말을 걸어서 켜지는 상태 변수**를 갖고 있었다 —
## `Talk_Nam_F`가 `v_Hong = 1`을 세우면 홍교수가 모교수 이야기를 더 해 주고
## (`@t39` "남교수한테 들어서"), `Talk_HowaJo_F` case 1이 `v_Howa = 2`를 세우면
## 실습 조교·앨린·팰린이 비로소 힌트를 준다. **대화가 대화를 여는 사슬**이다.
##
## `variants`는 그 상태 머신을 그대로 옮긴 것이다 — 앞에서부터 조건이 맞는 첫 갈래를
## 쓴다(진행이 많이 된 갈래를 앞에 둔다). 조건이 다 안 맞으면 `texts`가 기본이다.
static func _branch(t: Dictionary) -> Dictionary:
	for v: Dictionary in t.get("variants", []):
		var flag := str(v.get("requires_flag", ""))
		if flag.is_empty() or GameState.has_flag(flag):
			return v
	return t


static func _texts_now(t: Dictionary) -> Array:
	return _branch(t).get("texts", [])


## 이 대상에게 지금 말을 걸면 나올 대사 스텝. 반복 횟수를 여기서 센다.
##
## `repeat_after`가 있으면 그 횟수째에 다른 대사가 나온다 — 원작 오른쪽 그림이
## 다섯 번을 참아 준 사람에게 "당신의 인내력에 감탄 했소."라고 하는 그 분기다.
static func steps_for(attr: int) -> Array:
	var t := find(attr)
	if t.is_empty():
		return []
	var branch := _branch(t)
	var texts: Array = branch.get("texts", [])
	if texts.is_empty():
		return []

	# **이 대화가 다음 대화를 연다.** 원작 상태 변수(v_Hong·v_Howa·v_HowaJo)의 자리 —
	# 말을 끝까지 들으면 다른 사람이 할 말이 생긴다. 플래그는 세이브에 실린다.
	var sets := str(branch.get("sets_flag", ""))
	if not sets.is_empty():
		GameState.set_flag(sets, true)

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
