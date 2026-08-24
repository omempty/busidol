class_name ChoreographyRunner
extends Node
## battle_moves JSON 채널 타임라인 재생 — 공격/회피/피격 안무 실행기.
## 각 채널(sprite/fx/camera/screen/audio/logic)의 키프레임을 시간순으로 처리.

signal move_finished(move_id: StringName)

var _active := false
var _elapsed := 0.0
var _length := 0.0
var _current_move := {}
var _fired_indices := {}   # channel -> set of fired keyframe indices


func play(move_data: Dictionary, presenter: BattlePresenter) -> void:
	if _active:
		return
	_current_move = move_data
	_length = float(move_data.get("length", 1.0))
	_elapsed = 0.0
	_active = true
	_fired_indices.clear()
	presenter.on_move_start(move_data)


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
			pass  # AnimatedSprite2D 애니 전환 — Presenter에서 처리
		"fx":
			pass  # 이펙트 스폰 — Presenter에서 처리
		"camera":
			if kf.has("shake"):
				pass  # Presenter에 위임
		"audio":
			pass  # AudioManager.play_sfx()
		"logic":
			if kf.has("apply_damage") and kf["apply_damage"]:
				pass  # DamageCalculator 호출은 외부에서 바인딩


## 정적 헬퍼: JSON에서 ChoreographyRunner용 데이터 로드
static func load_move(path: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if typeof(raw) == TYPE_DICTIONARY else {}
