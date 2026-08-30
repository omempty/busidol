class_name BattleLog
## 전투 로그 저장소 — 04_uiux §1.4 "배틀 로그 사이드패널".
##
## 왜 생겼나(2026-08-30): 데미지 팝과 상태 칩은 **그 순간에만** 뜬다. 연출 속도를
## ×2·스킵으로 두면(설정에 있다) 무슨 일이 있었는지 읽을 새가 없고, 여러 적이
## 동시에 맞으면 팝이 겹친다. 지나간 턴을 되짚을 자리가 없었다.
##
## DialogueLog와 같은 꼴(static 링버퍼) — 전투는 씬 전환이라 노드에 담으면 사라진다.
## 전투 시작마다 비운다(이전 판의 줄이 남으면 첫 화면부터 거짓말이 된다).

const CAPACITY := 40

## 줄 종류 — 색으로 훑어 읽게 한다. 색만으로 구분하지 않도록 말머리도 다르다(Q9와 같은 방침).
enum Kind { TURN, ACTION, DAMAGE, ACCENT, RESULT }

static var _lines: Array[Dictionary] = []


static func push(text: String, kind: Kind = Kind.ACTION) -> void:
	if text.strip_edges().is_empty():
		return
	_lines.append({"text": text, "kind": int(kind)})
	if _lines.size() > CAPACITY:
		_lines = _lines.slice(_lines.size() - CAPACITY)


## 최근 n줄(오래된 것 → 새것 순).
static func tail(n: int) -> Array[Dictionary]:
	if _lines.size() <= n:
		return _lines
	return _lines.slice(_lines.size() - n)


static func lines() -> Array[Dictionary]:
	return _lines


static func clear() -> void:
	_lines.clear()


static func color_of(kind: int) -> Color:
	match kind:
		int(Kind.TURN):
			return HudTheme.TEXT_MUTED
		int(Kind.DAMAGE):
			return HudTheme.HP_LOW
		int(Kind.ACCENT):
			return HudTheme.BREAK_ON
		int(Kind.RESULT):
			return HudTheme.ACCENT
		_:
			return HudTheme.TEXT


## 말머리 — 색을 못 보는 사람도 종류를 읽을 수 있어야 한다(Q9).
static func mark_of(kind: int) -> String:
	match kind:
		int(Kind.TURN):
			return "―"
		int(Kind.DAMAGE):
			return "!"
		int(Kind.ACCENT):
			return "*"
		int(Kind.RESULT):
			return "="
		_:
			return "·"
