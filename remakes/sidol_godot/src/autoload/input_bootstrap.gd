extends Node
## InputMap을 런타임에 등록한다(project.godot [input] 대신 코드 등록).
## 근거: docs/02_design/02_godot_architecture.md §6 — 게임 코드는 액션명만 사용.
##
## 키보드와 게임패드를 **같은 액션 이름에 겹쳐** 등록한다(04_uiux §4 "게임패드 전면 지원").
## 게임 코드는 어느 쪽으로 들어왔는지 몰라도 되고, 04_uiux §1.3·§1.4가 전제하는
## "패드 지원"도 이 표 하나로 성립한다. 리매핑 UI는 05_polish_roadmap §5.8 별건.

const ACTIONS := {
	&"move_up": [KEY_UP, KEY_W],
	&"move_down": [KEY_DOWN, KEY_S],
	&"move_left": [KEY_LEFT, KEY_A],
	&"move_right": [KEY_RIGHT, KEY_D],
	&"run": [KEY_SHIFT],
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
	# 탭 전환 — 캐릭터 메뉴 4탭(04_uiux §1.3). 전투 대상 전환과 같은 키(Q·E)지만
	# 두 화면은 동시에 뜨지 않는다. 액션을 나눠 두면 각 화면이 제 뜻으로 읽는다.
	&"tab_prev": [KEY_Q],
	&"tab_next": [KEY_E],
}

## 게임패드 버튼 — 키보드와 같은 액션에 얹는다. Xbox 배치 기준(Godot 표준 매핑이
## PS/닌텐도 패드를 같은 상수로 정규화한다). 전투 슬롯 1~9는 패드에 남는 버튼이 없어
## 커서 이동으로 대신한다(Q/E = 숄더, R = X).
const PAD_BUTTONS := {
	&"move_up": [JOY_BUTTON_DPAD_UP],
	&"move_down": [JOY_BUTTON_DPAD_DOWN],
	&"move_left": [JOY_BUTTON_DPAD_LEFT],
	&"move_right": [JOY_BUTTON_DPAD_RIGHT],
	&"interact": [JOY_BUTTON_A],
	&"cancel": [JOY_BUTTON_B],
	&"menu": [JOY_BUTTON_START],
	&"inventory": [JOY_BUTTON_Y],
	&"minimap": [JOY_BUTTON_BACK],
	&"battle_target_prev": [JOY_BUTTON_LEFT_SHOULDER],
	&"battle_target_next": [JOY_BUTTON_RIGHT_SHOULDER],
	# 필드 달리기 — 전투 와 화면이 겹치지 않아 같은 숄더를 쓴다(Q·E 선례).
	&"run": [JOY_BUTTON_RIGHT_SHOULDER],
	&"battle_repeat": [JOY_BUTTON_X],
	&"tab_prev": [JOY_BUTTON_LEFT_SHOULDER],
	&"tab_next": [JOY_BUTTON_RIGHT_SHOULDER],
}

## 왼쪽 스틱 — [축, 부호]. 그리드 이동이라 세기는 안 쓰고 데드존만 넘으면 한 칸이다.
const PAD_AXES := {
	&"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	&"move_down": [JOY_AXIS_LEFT_Y, 1.0],
	&"move_left": [JOY_AXIS_LEFT_X, -1.0],
	&"move_right": [JOY_AXIS_LEFT_X, 1.0],
}
## 스틱을 살짝 기울인 것으로 칸이 넘어가면 안 된다 — 기본 0.5보다 둔하게 잡는다.
const STICK_DEADZONE := 0.6


func _ready() -> void:
	for action: StringName in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: Key in ACTIONS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

	var pad_events := 0
	for action2: StringName in PAD_BUTTONS:
		for button: JoyButton in PAD_BUTTONS[action2]:
			var be := InputEventJoypadButton.new()
			be.button_index = button
			InputMap.action_add_event(action2, be)
			pad_events += 1
	for action3: StringName in PAD_AXES:
		var spec: Array = PAD_AXES[action3]
		var me := InputEventJoypadMotion.new()
		me.axis = spec[0]
		me.axis_value = spec[1]
		InputMap.action_add_event(action3, me)
		InputMap.action_set_deadzone(action3, STICK_DEADZONE)
		pad_events += 1

	print("[input_bootstrap] %d actions registered (패드 %d)" % [ACTIONS.size(), pad_events])
