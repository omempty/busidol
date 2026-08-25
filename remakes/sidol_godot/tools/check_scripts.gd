extends SceneTree
## 전체 GDScript 로드 검사 — 파스 불가 스크립트 탐지(잠복 파서 에러 조기 발견).
## 근거: species_brain.gd 사례 — 런타임 경로가 없으면 파스 에러가 검증망을 통과한다.
## 실행: godot --headless --path . --script res://tools/check_scripts.gd  (exit 0=PASS)

const DIRS := [
	"res://src",
	"res://src/autoload",
	"res://scenes",
	"res://tests",
	"res://tools",
]


func _initialize() -> void:
	var bad := 0
	for dir in DIRS:
		for f in _collect(dir):
			var s: Variant = load(f)
			var g := s as GDScript
			if s == null or g == null or not g.can_instantiate():
				bad += 1
	print("[check_scripts] done broken=%d" % bad)
	quit(1 if bad > 0 else 0)


func _collect(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var full := dir_path + "/" + f
		if d.current_is_dir() and not f.begins_with("."):
			out.append_array(_collect(full))
		elif f.ends_with(".gd"):
			out.append(full)
		f = d.get_next()
	return out
