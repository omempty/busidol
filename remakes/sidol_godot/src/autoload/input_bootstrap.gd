extends Node
## InputMap을 런타임에 등록한다(project.godot [input] 대신 코드 등록).
## 근거: docs/02_design/02_godot_architecture.md §6 — 게임 코드는 액션명만 사용.
## 게임패드 매핑은 Phase 9(설정 화면)에서 추가.

const ACTIONS := {
	&"move_up": [KEY_UP, KEY_W],
	&"move_down": [KEY_DOWN, KEY_S],
	&"move_left": [KEY_LEFT, KEY_A],
	&"move_right": [KEY_RIGHT, KEY_D],
	&"interact": [KEY_SPACE, KEY_Z],
	&"menu": [KEY_ENTER],
	&"cancel": [KEY_ESCAPE],
	&"minimap": [KEY_M],
	&"inventory": [KEY_I],
}


func _ready() -> void:
	for action: StringName in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: Key in ACTIONS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	print("[input_bootstrap] %d actions registered" % ACTIONS.size())
