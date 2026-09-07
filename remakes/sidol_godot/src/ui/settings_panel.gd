class_name SettingsPanel
extends Control
## 설정 UI — 볼륨 4버스·연출속도·아트모드·글자크기·흔들림·몬스터 밀도·난이도·화면·조작법.
## 변경 즉시 적용+파일 저장. 타이틀과 일시정지 메뉴가 공용.
## 키보드: ↑↓ 행 이동, ←→ 값 변경, 확인=조작법 보기, Esc 닫기.

signal closed
signal controls_requested

## 표시 문자열은 전부 data/l10n/ui.csv — 여기 있는 것은 번역 키다(const는 tr()을 못 담는다).
const SPEED_KEYS := ["UI_OPT_SPEED_NORMAL", "UI_OPT_SPEED_FAST", "UI_OPT_SPEED_SKIP"]
const ART_KEYS := ["UI_ART_LEGACY", "UI_ART_REMAKE"]
const TEXT_KEYS := ["UI_OPT_TEXT_SMALL", "UI_OPT_TEXT_NORMAL", "UI_OPT_TEXT_LARGE"]
const SHAKE_KEYS := ["UI_OPT_ON", "UI_OPT_OFF"]
## Q6 — 접촉이 곧 강제 전투라 밀도가 곧 피로도. 없음은 탐험/시나리오 전용 모드.
const DENSITY_KEYS := [
	"UI_OPT_DENSITY_NONE", "UI_OPT_DENSITY_LOW", "UI_OPT_DENSITY_NORMAL", "UI_OPT_DENSITY_HIGH"
]
const DIFFICULTY_KEYS := ["UI_OPT_DIFF_EASY", "UI_OPT_DIFF_NORMAL", "UI_OPT_DIFF_HARD"]
const SCREEN_KEYS := ["UI_OPT_SCREEN_WINDOW", "UI_OPT_SCREEN_FULL"]
const VSYNC_KEYS := ["UI_OPT_ON", "UI_OPT_OFF"]
const LANGUAGE_KEYS := ["UI_OPT_LANG_KO", "UI_OPT_LANG_EN"]
const VOLUME_KEYS := [
	"UI_SETTINGS_MASTER_VOL", "UI_SETTINGS_BGM_VOL", "UI_SETTINGS_SFX_VOL", "UI_SETTINGS_VOICE_VOL"
]
const VOLUME_STEP := 0.1
## 대사 타이핑 속도(§1.2) — 전투 연출 속도(SPEED_KEYS)와 **다른 축**이라 키도 나눈다.
const TEXT_SPEED_KEYS := [
	"UI_OPT_TSPEED_SLOW", "UI_OPT_TSPEED_NORMAL", "UI_OPT_TSPEED_FAST", "UI_OPT_TSPEED_INSTANT"
]
## 글자 크기·흔들림 바로 뒤에 붙인다 — 읽기·접근성 항목끼리 모여 있어야 찾는다.
const ROW_TEXT_SPEED := 8
const ROW_DIALOGUE_AUTO := 9
const ROW_COLORBLIND := 10
## 지도 안개 — 몬스터 밀도 바로 위. 둘 다 "탐험이 얼마나 고될 것인가"를 정하는 축이라
## 같이 모아 둔다. 끄면 예전처럼 층 전체가 한 번에 보인다.
const ROW_FOG := 11
const ROW_DENSITY := 12
const ROW_DIFFICULTY := 13
const ROW_SCREEN := 14
const ROW_VSYNC := 15
const ROW_LANGUAGE := 16
const ROW_CONTROLS := 17
const ROW_COUNT := 18

var _rows: Array[Label] = []
var _values: Array[Label] = []
var _cursors: Array[Label] = []
var _index := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh()


func _build() -> void:
	var frame := ModalFrame.new()
	frame.setup("UI_SETTINGS_TITLE", "UI_SETTINGS_HINT", Vector2(440, 0))
	frame.dismissed.connect(func() -> void: closed.emit())
	add_child(frame)
	# 항목이 17행까지 늘어 기본 간격(6)으로는 패널이 540 뷰포트를 넘는다
	# (2026-08-30 world_audit이 582px로 잡았다). 행 간격을 좁혀 담는다 —
	# 더 늘어나면 스크롤로 바꿔야 하고, 넘치는 순간 관문이 다시 잡는다.
	frame.body.add_theme_constant_override("separation", 1)

	for i in range(ROW_COUNT):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		frame.body.add_child(row)

		# 커서 자리를 고정 폭으로 분리 — 구판은 "> "를 글자 앞에 붙여 행이 좌우로 튀었다.
		var cursor := HudTheme.label("", 15, HudTheme.ACCENT)
		cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cursor.custom_minimum_size = Vector2(14, 0)
		row.add_child(cursor)
		_cursors.append(cursor)

		var name_lbl := HudTheme.label("", 15, HudTheme.TEXT)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.custom_minimum_size = Vector2(190, 0)
		row.add_child(name_lbl)

		var val_lbl := HudTheme.label("", 15, HudTheme.TEXT_MUTED)
		val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)

		_rows.append(name_lbl)
		_values.append(val_lbl)
		_bind_mouse(row, i)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		closed.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"move_up"):
		_move(-1)
	elif event.is_action_pressed(&"move_down"):
		_move(1)
	elif event.is_action_pressed(&"move_left"):
		_adjust(-1)
	elif event.is_action_pressed(&"move_right"):
		_adjust(1)
	elif (
		event.is_action_pressed(&"cancel")
		or (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)
		)
	):
		closed.emit()
	elif (
		event.is_action_pressed(&"interact")
		or event.is_action_pressed(&"ui_accept")
		or event.is_action_pressed(&"menu")
		or (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and (
				event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_Z]
				or event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_Z]
			)
		)
	):
		if _index == ROW_CONTROLS:
			controls_requested.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _move(dir: int) -> void:
	_index = wrapi(_index + dir, 0, _rows.size())
	_refresh()


## 마우스 — 행에 올리면 선택, 좌클릭/휠↑은 값 +1, 우클릭/휠↓은 −1.
## 값이 순환형(←→)이라 클릭 한 번에 한 칸씩 도는 것이 키보드와 같은 뜻이 된다.
func _bind_mouse(row: Control, idx: int) -> void:
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.mouse_entered.connect(
		func() -> void:
			_index = idx
			_refresh()
	)
	row.gui_input.connect(
		func(e: InputEvent) -> void:
			if not (e is InputEventMouseButton and e.pressed):
				return
			_index = idx
			# 람다 안의 다중 패턴 match는 gdformat 파서가 못 읽는다(관문이 잡았다).
			var b: int = e.button_index
			if b == MOUSE_BUTTON_LEFT or b == MOUSE_BUTTON_WHEEL_UP:
				_adjust(1)
			elif b == MOUSE_BUTTON_RIGHT or b == MOUSE_BUTTON_WHEEL_DOWN:
				_adjust(-1)
			else:
				_refresh()
	)


func _adjust(dir: int) -> void:
	match _index:
		0, 1, 2, 3:
			var bus: StringName = SettingsManager.BUSES[_index]
			SettingsManager.set_volume(bus, SettingsManager.get_volume(bus) + dir * VOLUME_STEP)
		4:
			var values: Array = SettingsManager.EffectSpeed.values()
			var idx: int = values.find(SettingsManager.effect_speed)
			var next_v: Variant = values[wrapi(idx + dir, 0, values.size())]
			SettingsManager.effect_speed = next_v
		5:
			var values: Array = SettingsManager.ArtMode.values()
			var idx: int = values.find(SettingsManager.art_mode)
			var next_v: Variant = values[wrapi(idx + dir, 0, values.size())]
			SettingsManager.art_mode = next_v
		6:
			var values: Array = SettingsManager.TextSize.values()
			var idx: int = values.find(SettingsManager.text_size)
			var next_v: Variant = values[wrapi(idx + dir, 0, values.size())]
			SettingsManager.text_size = next_v
		7:
			SettingsManager.screen_shake = not SettingsManager.screen_shake
		ROW_TEXT_SPEED:
			var values: Array = SettingsManager.TextSpeed.values()
			var idx: int = values.find(SettingsManager.text_speed)
			var next_v: Variant = values[wrapi(idx + dir, 0, values.size())]
			SettingsManager.text_speed = next_v
		ROW_DIALOGUE_AUTO:
			SettingsManager.dialogue_auto = not SettingsManager.dialogue_auto
		ROW_COLORBLIND:
			SettingsManager.colorblind_patterns = not SettingsManager.colorblind_patterns
		ROW_FOG:
			SettingsManager.fog_of_war = not SettingsManager.fog_of_war
		ROW_DENSITY:
			var values: Array = SettingsManager.EncounterDensity.values()
			var idx: int = values.find(SettingsManager.encounter_density)
			var next_v: Variant = values[wrapi(idx + dir, 0, values.size())]
			SettingsManager.encounter_density = next_v
		ROW_DIFFICULTY:
			var values: Array = SettingsManager.Difficulty.values()
			var idx: int = values.find(SettingsManager.difficulty)
			var next_v: Variant = values[wrapi(idx + dir, 0, values.size())]
			SettingsManager.difficulty = next_v
		ROW_SCREEN:
			var values: Array = SettingsManager.ScreenMode.values()
			var idx: int = values.find(SettingsManager.screen_mode)
			var next_v: Variant = values[wrapi(idx + dir, 0, values.size())]
			SettingsManager.screen_mode = next_v
		ROW_VSYNC:
			SettingsManager.vsync = not SettingsManager.vsync
		ROW_LANGUAGE:
			var values: Array = SettingsManager.Language.values()
			var idx: int = values.find(SettingsManager.language)
			var next_v: Variant = values[wrapi(idx + dir, 0, values.size())]
			SettingsManager.language = next_v
	SettingsManager.save_settings()
	_refresh()


func _refresh() -> void:
	for i in range(4):
		var bus: StringName = SettingsManager.BUSES[i]
		_set_row(i, tr(VOLUME_KEYS[i]), "%d%%" % roundi(SettingsManager.get_volume(bus) * 100))
	_set_row(4, tr("UI_SETTINGS_SPEED"), tr(SPEED_KEYS[int(SettingsManager.effect_speed)]))
	_set_row(5, tr("UI_SETTINGS_ART"), tr(ART_KEYS[int(SettingsManager.art_mode)]))
	_set_row(6, tr("UI_SETTINGS_TEXT_SIZE"), tr(TEXT_KEYS[int(SettingsManager.text_size)]))
	_set_row(7, tr("UI_SETTINGS_SHAKE"), tr(SHAKE_KEYS[0 if SettingsManager.screen_shake else 1]))
	_set_row(
		ROW_TEXT_SPEED,
		tr("UI_SETTINGS_TEXT_SPEED"),
		tr(TEXT_SPEED_KEYS[int(SettingsManager.text_speed)])
	)
	_set_row(
		ROW_DIALOGUE_AUTO,
		tr("UI_SETTINGS_DIALOGUE_AUTO"),
		tr(SHAKE_KEYS[0 if SettingsManager.dialogue_auto else 1])
	)
	_set_row(
		ROW_COLORBLIND,
		tr("UI_SETTINGS_COLORBLIND"),
		tr(SHAKE_KEYS[0 if SettingsManager.colorblind_patterns else 1])
	)
	_set_row(ROW_FOG, tr("UI_SETTINGS_FOG"), tr(SHAKE_KEYS[0 if SettingsManager.fog_of_war else 1]))
	_set_row(
		ROW_DENSITY,
		tr("UI_SETTINGS_DENSITY"),
		tr(DENSITY_KEYS[int(SettingsManager.encounter_density)])
	)
	_set_row(
		ROW_DIFFICULTY,
		tr("UI_SETTINGS_DIFFICULTY"),
		tr(DIFFICULTY_KEYS[int(SettingsManager.difficulty)])
	)
	_set_row(
		ROW_SCREEN, tr("UI_SETTINGS_SCREEN"), tr(SCREEN_KEYS[int(SettingsManager.screen_mode)])
	)
	_set_row(ROW_VSYNC, tr("UI_SETTINGS_VSYNC"), tr(VSYNC_KEYS[0 if SettingsManager.vsync else 1]))
	_set_row(
		ROW_LANGUAGE, tr("UI_SETTINGS_LANGUAGE"), tr(LANGUAGE_KEYS[int(SettingsManager.language)])
	)
	_set_row(ROW_CONTROLS, tr("UI_SETTINGS_CONTROLS"), tr("UI_SETTINGS_CONTROLS_HINT"))


func _set_row(i: int, text: String, value_text: String) -> void:
	var selected := i == _index
	_cursors[i].text = "▶" if selected else ""
	_rows[i].text = text
	# 값은 좌우 화살표로 바꾼다는 것을 선택된 행에서만 드러낸다.
	_values[i].text = ("‹ %s ›" % value_text) if selected else value_text
	_rows[i].add_theme_color_override("font_color", HudTheme.ACCENT if selected else HudTheme.TEXT)
	_values[i].add_theme_color_override(
		"font_color", HudTheme.TEXT if selected else HudTheme.TEXT_MUTED
	)
