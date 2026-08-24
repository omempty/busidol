@tool
extends EditorPlugin
## Event Editor v0 — 하단 패널에서 컷신(cutscenes/*.json) 스텝 열람·수정·저장.
## v0 범위: 컷신 스텝 목록 편집(op 선택 + args JSON). 트리거/시각 편집은 v1.

const CUTSCENES_DIR := "res://data/cutscenes"

var _dock: VBoxContainer
var _file_opt: OptionButton
var _tree: Tree
var _op_edit: LineEdit
var _args_edit: LineEdit
var _status_lbl: Label

# 현재 편집 대상: 파일 경로 → 파싱된 컷신
var _path := ""
var _data := {}
var _sel_idx := -1


func _enter_tree() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "EventEditor"

	var top := HBoxContainer.new()
	_file_opt = OptionButton.new()
	_file_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_opt.item_selected.connect(_on_file_selected)
	top.add_child(_file_opt)
	var reload_btn := Button.new()
	reload_btn.text = "다시 읽기"
	reload_btn.pressed.connect(_refresh_files)
	top.add_child(reload_btn)
	_dock.add_child(top)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_step_selected)
	_dock.add_child(_tree)

	var edit_row := HBoxContainer.new()
	edit_row.add_child(_make_label("op"))
	_op_edit = LineEdit.new()
	_op_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_row.add_child(_op_edit)
	_dock.add_child(edit_row)

	var args_row := HBoxContainer.new()
	args_row.add_child(_make_label("args(JSON)"))
	_args_edit = LineEdit.new()
	_args_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	args_row.add_child(_args_edit)
	_dock.add_child(args_row)

	var btn_row := HBoxContainer.new()
	var apply_btn := Button.new()
	apply_btn.text = "스텝 적용"
	apply_btn.pressed.connect(_on_apply_step)
	btn_row.add_child(apply_btn)
	var add_btn := Button.new()
	add_btn.text = "스텝 추가"
	add_btn.pressed.connect(_on_add_step)
	btn_row.add_child(add_btn)
	var del_btn := Button.new()
	del_btn.text = "스텝 삭제"
	del_btn.pressed.connect(_on_delete_step)
	btn_row.add_child(del_btn)
	var save_btn := Button.new()
	save_btn.text = "저장"
	save_btn.pressed.connect(_on_save)
	btn_row.add_child(save_btn)
	_dock.add_child(btn_row)

	_status_lbl = Label.new()
	_status_lbl.text = ""
	_dock.add_child(_status_lbl)

	add_control_to_bottom_panel(_dock, "Event Editor")
	_refresh_files()


func _exit_tree() -> void:
	remove_control_from_bottom_panel(_dock)
	_dock.queue_free()


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _refresh_files() -> void:
	_file_opt.clear()
	var dir := DirAccess.open(CUTSCENES_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".json"):
			_file_opt.add_item(f)


func _on_file_selected(idx: int) -> void:
	_path = "%s/%s" % [CUTSCENES_DIR, _file_opt.get_item_text(idx)]
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if typeof(raw) != TYPE_DICTIONARY:
		_status("파싱 실패: %s" % _path)
		_data = {}
		_tree.clear()
		return
	_data = raw
	_sel_idx = -1
	_rebuild_tree()
	_status("로드됨: %s (%d steps)" % [_path, (_data.get("steps", []) as Array).size()])


func _rebuild_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var steps: Array = _data.get("steps", [])
	for i in steps.size():
		var it := _tree.create_item(root)
		it.set_text(0, "%02d  %s  %s" % [i + 1, str(steps[i].get("op", "")),
				str(steps[i].get("args", ""))])


func _on_step_selected() -> void:
	var sel := _tree.get_selected()
	if sel == null:
		return
	_sel_idx = sel.get_index()
	var step: Dictionary = (_data.get("steps", []) as Array)[_sel_idx]
	_op_edit.text = str(step.get("op", ""))
	_args_edit.text = JSON.stringify(step.get("args", {}))


func _on_apply_step() -> void:
	if _sel_idx < 0 or _data.is_empty():
		return
	var step: Dictionary = (_data.get("steps", []) as Array)[_sel_idx]
	step["op"] = _op_edit.text.strip_edges()
	var parsed: Variant = JSON.parse_string(_args_edit.text) if \
			not _args_edit.text.strip_edges().is_empty() else {}
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_status("args가 JSON 객체여야 합니다")
		return
	if parsed != null and (parsed as Dictionary).is_empty():
		step.erase("args")
	else:
		step["args"] = parsed
	_rebuild_tree()
	_status("스텝 %d 적용" % (_sel_idx + 1))


func _on_add_step() -> void:
	if _data.is_empty():
		return
	var steps: Array = _data.get("steps", [])
	steps.append({"op": "wait", "seconds": 1.0})
	_data["steps"] = steps
	_sel_idx = steps.size() - 1
	_rebuild_tree()
	_status("스텝 추가")


func _on_delete_step() -> void:
	if _sel_idx < 0 or _data.is_empty():
		return
	var steps: Array = _data.get("steps", [])
	if _sel_idx < steps.size():
		steps.remove_at(_sel_idx)
	_sel_idx = -1
	_rebuild_tree()
	_status("스텝 삭제")


func _on_save() -> void:
	if _path.is_empty() or _data.is_empty():
		return
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		_status("쓰기 실패: %s" % _path)
		return
	f.store_string(JSON.stringify(_data, "  ", false) + "\n")
	f.close()
	_status("저장됨: %s" % _path)
	EditorInterface.get_resource_filesystem().scan()


func _status(text: String) -> void:
	if _status_lbl != null:
		_status_lbl.text = text
	print("[EventEditor] ", text)
