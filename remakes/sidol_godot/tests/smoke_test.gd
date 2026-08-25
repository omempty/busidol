extends Node
## 헤드리스 스모크 — 부팅 + 오토로드 존재 확인. 실행:
##   godot --headless --path . res://tests/smoke.tscn
## 종료코드 0=PASS / 1=FAIL

const REQUIRED_AUTOLOADS := [
	"InputBootstrap",
	"EventBus",
	"GameState",
	"Database",
	"AudioManager",
	"SceneRouter",
	"SettingsManager",
	"SaveManager",
]


func _ready() -> void:
	var failures: Array[String] = []
	for autoload_name in REQUIRED_AUTOLOADS:
		if get_node_or_null(NodePath("/root/" + autoload_name)) == null:
			failures.append(autoload_name)
	if failures.is_empty():
		print("[smoke] PASS - %d autoloads ok" % REQUIRED_AUTOLOADS.size())
		get_tree().quit(0)
	else:
		push_error("[smoke] FAIL missing: " + ", ".join(failures))
		get_tree().quit(1)
