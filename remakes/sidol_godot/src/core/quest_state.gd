class_name QuestState
extends RefCounted
## 퀘스트 진행 상태 — **로그 패널과 HUD 트래커의 단일 출처.**
##
## 왜 따로 뒀나(2026-09-06). 둘이 각자 판정하고 있었고, 그래서 트래커는 퀘스트를 아예
## 안 보고 **층 번호로만** 문구를 골랐다. 그 탓에 `ui.csv`의 `UI_TRACKER_F1`이
## "3층 화공과 사고 조사"였다 — F1에 서 있는데 3층을 가리켰다(유저가 길을 잃을 만하다).
## 층이 아니라 **사슬**이 답이다: quests_v2.json의 `requires`를 따라가면
## "지금 할 수 있는 것"이 하나로 정해진다.
##
## 상태 셋:
##   DONE      플래그가 섰다
##   ACTIVE    아직인데 선행이 전부 끝났다 — **지금 할 수 있는 것**
##   LOCKED    선행이 남았다

enum Status { DONE, ACTIVE, LOCKED }

const QUESTS_PATH := "res://data/quests_v2.json"


static func all() -> Array:
	if not FileAccess.file_exists(QUESTS_PATH):
		push_warning("quests 데이터 없음: %s" % QUESTS_PATH)
		return []
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(QUESTS_PATH))
	if typeof(raw) != TYPE_DICTIONARY:
		push_warning("quests 파싱 실패")
		return []
	return (raw as Dictionary).get("quests", [])


## `requires`는 문자열 하나일 수도 배열일 수도 있다(데이터 실측). 둘 다 받는다.
static func requires_of(q: Dictionary) -> Array:
	var req: Variant = q.get("requires", [])
	if req == null:
		return []
	if req is Array:
		return req
	var s := str(req)
	return [] if s.is_empty() else [s]


static func status_of(q: Dictionary) -> Status:
	if GameState.has_flag(str(q.get("id", ""))):
		return Status.DONE
	for r: Variant in requires_of(q):
		if not GameState.has_flag(str(r)):
			return Status.LOCKED
	return Status.ACTIVE


## 지금 할 수 있는 퀘스트들 — 데이터 순서(= 시나리오 순서)를 그대로 쓴다.
static func active() -> Array:
	var out: Array = []
	for q: Dictionary in all():
		if status_of(q) == Status.ACTIVE:
			out.append(q)
	return out


## HUD 트래커 한 줄. 할 수 있는 것이 여럿이면 **첫 번째**(사슬에서 가장 이른 것)를 쓴다.
## 하나도 없으면(전부 완료) 기본 문구로 떨어진다.
static func tracker_line() -> String:
	var act := active()
	if act.is_empty():
		return TranslationServer.translate("UI_TRACKER_DEFAULT")
	var q: Dictionary = act[0]
	var name_ko := str(q.get("name", ""))
	var desc := str(q.get("description", ""))
	if desc.is_empty():
		return name_ko
	return "%s — %s" % [name_ko, desc]
