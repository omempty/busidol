class_name UiProbe
extends RefCounted
## UI 감사 프루브 — 화면 밖 잘림(onscreen), 텍스트 오버플로, 몬스터 한글 표기명 검사.
##
## 실제 회귀 근거(2026-08-26):
## - P0-01: 전투 커맨드 메뉴가 800, 380에 배치되어 "도망" 버튼이 540 뷰포트 밖으로 잘림
## - P0-02: 몬스터 display_name이 누락되어 "Vulgar", "Mad eye" 등 id 폴백으로 표기됨

const VIEWPORT_DEFAULT := Vector2(960, 540)


## Control 노드들이 뷰포트 사각형 안에 완전히 들어오는지 검사한다.
static func check_onscreen(
	rep: AuditReport,
	root: Node,
	vp_rect: Rect2 = Rect2(Vector2.ZERO, VIEWPORT_DEFAULT),
	label: String = ""
) -> void:
	var out_of_bounds: Array[String] = []
	_scan_control_bounds(root, vp_rect, out_of_bounds)
	var what := label if not label.is_empty() else "%s 하위 Control" % root.name
	if out_of_bounds.is_empty():
		rep.ok("UI 화면 내 배치", "%s 뷰포트 내 수용" % what)
	else:
		for msg: String in out_of_bounds:
			rep.fail("UI 화면 이탈", "%s — %s" % [what, msg])


static func _scan_control_bounds(node: Node, vp_rect: Rect2, out_list: Array[String]) -> void:
	# ScrollContainer 안쪽은 내용이 넘치는 게 정상이고 실제로는 잘려 보인다 —
	# 컨테이너 자신만 검사하고 하위는 내려가지 않는다(오탐 제거).
	if node is ScrollContainer:
		_check_one(node as Control, vp_rect, out_list)
		return
	if node is Control:
		_check_one(node as Control, vp_rect, out_list)
	for child: Node in node.get_children():
		_scan_control_bounds(child, vp_rect, out_list)


static func _check_one(c: Control, vp_rect: Rect2, out_list: Array[String]) -> void:
	if not (c.is_visible_in_tree() and c.size.x > 0 and c.size.y > 0):
		return
	var g_rect := c.get_global_rect()
	# 오차 허용 1px
	if (
		g_rect.position.x < vp_rect.position.x - 1.0
		or g_rect.position.y < vp_rect.position.y - 1.0
		or g_rect.end.x > vp_rect.end.x + 1.0
		or g_rect.end.y > vp_rect.end.y + 1.0
	):
		out_list.append("%s (%s) rect=%s > vp=%s" % [c.name, c.get_class(), g_rect, vp_rect.size])


## Label 텍스트의 최소 크기가 부모 크기를 넘쳐 잘리는지 검사한다.
static func check_text_overflow(rep: AuditReport, root: Node) -> void:
	var overflowed: Array[String] = []
	_scan_text_overflow(root, overflowed)
	if overflowed.is_empty():
		rep.ok("텍스트 오버플로", "%s 라벨 텍스트 잘림 없음" % root.name)
	else:
		for msg: String in overflowed:
			rep.warn("텍스트 오버플로", msg)


static func _scan_text_overflow(node: Node, out_list: Array[String]) -> void:
	if node is Label:
		var lbl := node as Label
		if lbl.is_visible_in_tree() and not lbl.autowrap_mode:
			var min_sz := lbl.get_minimum_size()
			var parent := lbl.get_parent()
			if parent is Control and not (parent is Container):
				var p_ctrl := parent as Control
				if p_ctrl.size.x > 0 and min_sz.x > p_ctrl.size.x + 4.0:
					out_list.append(
						"%s '%s' (폭 %d > 부모 %d)" % [lbl.name, lbl.text, min_sz.x, p_ctrl.size.x]
					)
	for child: Node in node.get_children():
		_scan_text_overflow(child, out_list)


## 전 몬스터 및 보스에 대해 display_name이 id 폴백(영문 Capitalize)이 아닌지 검사한다.
static func check_display_names(rep: AuditReport) -> void:
	var table := JsonUtil.load_dict("res://data/monsters.json", "UiProbe")
	var fallback_species: Array[String] = []
	var checked_count := 0

	var species_dict: Dictionary = table.get("species", {})
	for sid: String in species_dict:
		var def: Dictionary = Database.get_enemy_def(sid)
		var dname := str(def.get("display_name", ""))
		var fallback := sid.replace("_", " ").capitalize()
		checked_count += 1
		if dname.is_empty() or dname == fallback:
			fallback_species.append("%s (display_name=%s)" % [sid, dname])

	var bosses_dict: Dictionary = table.get("bosses", {})
	for bid: String in bosses_dict:
		var def: Dictionary = Database.get_enemy_def(bid)
		var dname := str(def.get("display_name", ""))
		var fallback := bid.replace("_", " ").capitalize()
		checked_count += 1
		if dname.is_empty() or dname == fallback:
			fallback_species.append("[보스] %s (display_name=%s)" % [bid, dname])

	if fallback_species.is_empty():
		rep.ok("몬스터 표기명", "%d종 전원 한글 display_name 보유" % checked_count)
	else:
		for msg: String in fallback_species:
			rep.warn("몬스터 이름 id 폴백", msg)
