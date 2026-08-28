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
	# 전투 단축키 — 메뉴를 커서로 훑지 않고 바로 고른다(턴제의 반복 조작 비용을 줄인다).
	# 이동이 WASD라 문자 단축키는 그 바깥(Q·E·R)에서만 고른다.
	&"battle_slot_1": [KEY_1, KEY_KP_1],
	&"battle_slot_2": [KEY_2, KEY_KP_2],
	&"battle_slot_3": [KEY_3, KEY_KP_3],
	&"battle_slot_4": [KEY_4, KEY_KP_4],
	&"battle_slot_5": [KEY_5, KEY_KP_5],
	&"battle_slot_6": [KEY_6, KEY_KP_6],
	&"battle_slot_7": [KEY_7, KEY_KP_7],
	&"battle_slot_8": [KEY_8, KEY_KP_8],
	&"battle_slot_9": [KEY_9, KEY_KP_9],
	&"battle_target_prev": [KEY_Q],
	&"battle_target_next": [KEY_E],
	&"battle_repeat": [KEY_R],
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
