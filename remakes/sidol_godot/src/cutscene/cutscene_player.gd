class_name CutscenePlayer
extends CanvasLayer
## 컷신 재생기 — 순차 명령열 해석. 에디터 프리뷰와 동일 클래스 사용.
## docs/02_design/05_toolchain_editors.md §4 참조.

signal finished(cutscene_id: StringName)

var _steps: Array = []
var _idx := 0
var _running := false
var _cutscene_id := &""


func play(config: Dictionary) -> void:
	_cutscene_id = StringName(str(config.get("id", "")))
	_steps = config.get("steps", [])
	_idx = 0
	_running = true
	visible = true
	_execute_next()


func stop() -> void:
	_running = false
	visible = false


func _execute_next() -> void:
	if not _running or _idx >= _steps.size():
		_running = false
		finished.emit(_cutscene_id)
		return
	var step: Dictionary = _steps[_idx]
	_idx += 1
	match str(step.get("op", "")):
		"actor_move":
			pass   # TODO(Phase 7): 액터 경로 이동
		"dialogue":
			pass   # TODO: DialogueRunner 연동
		"fade_in":
			pass
		"fade_out":
			pass
		"shake":
			pass
		"bgm":
			pass
		"start_battle":
			pass
		"wait":
			pass
	_execute_next()   # MVP: 동기 실행 (비동기 op는 await 필요)


func is_running() -> bool:
	return _running
