class_name ChoreographyRunner
extends Node
## battle_moves JSON 채널 타임라인 재생 — 공격/회피/피격 안무 실행기.
## 각 채널(sprite/fx/camera/screen/audio/logic)의 키프레임을 시간순으로 처리하며,
## 실제 연출은 BattlePresenter에 위임한다(로직↔연출 분리).
## 데이터 계약: docs/02_design/05_toolchain_editors.md §5.1

signal move_finished(move_id: StringName)
signal damage_frame   ## logic 채널 apply_damage=true 키프레임 — 컨트롤러가 데미지 판정

const MOVES_DIR := "res://data/battle_moves"

var _active := false
var _elapsed := 0.0
var _length := 0.0
var _current_move := {}
var _fired_indices := {}   # channel_keyframe_key -> true
var _presenter: BattlePresenter


func bind_presenter(presenter: BattlePresenter) -> void:
	_presenter = presenter


func play(move_data: Dictionary) -> void:
	if _active:
		return
	if move_data.is_empty():
		move_finished.emit(&"")
		return
	_current_move = move_data
	_length = float(move_data.get("length", 1.0))
	_elapsed = 0.0
	_active = true
	_fired_indices.clear()
	if _presenter != null:
		_presenter.on_move_start(move_data)


func play_by_id(move_id: StringName) -> void:
	play(load_move_by_id(move_id))


func is_playing() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	var channels: Dictionary = _current_move.get("channels", {})
	for ch_name: String in channels:
		var keyframes: Array = channels[ch_name]
		for kf_idx in keyframes.size():
			var kf_key := "%s_%d" % [ch_name, kf_idx]
			if _fired_indices.has(kf_key):
				continue
			var kf: Dictionary = keyframes[kf_idx]
			if _elapsed >= float(kf.get("t", 0)):
				_fired_indices[kf_key] = true
				_execute_channel(ch_name, kf)
	if _elapsed >= _length:
		_active = false
		move_finished.emit(StringName(str(_current_move.get("id", ""))))


func _execute_channel(ch_name: String, kf: Dictionary) -> void:
	match ch_name:
		"sprite":
			if _presenter != null:
				_presenter.play_sprite_kf(kf)
		"fx":
			if _presenter != null:
				_presenter.play_fx_kf(kf)
		"camera":
			if _presenter != null:
				_presenter.play_camera_kf(kf)
		"screen":
			if _presenter != null:
				_presenter.play_screen_kf(kf)
		"audio":
			AudioManager.play_sfx(StringName(str(kf.get("sfx", ""))))
		"logic":
			if kf.has("apply_damage") and bool(kf["apply_damage"]):
				damage_frame.emit()


## 정적 헬퍼: JSON에서 ChoreographyRunner용 데이터 로드
static func load_move(path: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


## 인스턴스 헬퍼: res://data/battle_moves/<id>.json 로드 (없으면 빈 Dict)
func load_move_by_id(move_id: StringName) -> Dictionary:
	if str(move_id).is_empty():
		return {}
	var path := "%s/%s.json" % [MOVES_DIR, move_id]
	if not FileAccess.file_exists(path):
		push_warning("battle_moves 없음: %s" % path)
		return {}
	return load_move(path)
