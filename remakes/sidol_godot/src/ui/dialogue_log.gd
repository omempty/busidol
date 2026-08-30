class_name DialogueLog
## 대화 로그(히스토리) 저장소 — 04_uiux §1.2 "대화 로그(히스토리) 열람".
##
## 왜 생겼나(2026-08-30): 2026-08-29에 컷신 대사를 사람이 넘기도록 바꾸면서
## **한 번 넘기면 되돌릴 방법이 없어졌다.** 실수로 연타하면 그 장면의 정보를 잃는다
## (퀘스트 단서가 대사에만 있는 구간이 많다).
##
## 필드 대화창과 컷신 대사창이 **같은 저장소**에 쌓는다 — 플레이어에게는 한 흐름이라
## 두 벌로 나누면 "방금 그 말"을 어느 창에서 봤는지 기억해야 한다.
## 세이브에는 넣지 않는다(세션 안에서만 유효한 읽기 보조).

## 보관 상한 — 넘치면 오래된 것부터 버린다. 한 층을 도는 동안의 대사가 200줄을
## 넘지 않는다(자동 주행 실측 최대 대사 10건 × 6줄).
const CAPACITY := 200

static var _lines: Array[Dictionary] = []


static func push(speaker: String, text: String) -> void:
	if text.strip_edges().is_empty():
		return
	_lines.append({"speaker": speaker, "text": text})
	if _lines.size() > CAPACITY:
		_lines = _lines.slice(_lines.size() - CAPACITY)


static func lines() -> Array[Dictionary]:
	return _lines


static func is_empty() -> bool:
	return _lines.is_empty()


## 새 게임·불러오기 등 이야기 흐름이 끊길 때 비운다.
static func clear() -> void:
	_lines.clear()
