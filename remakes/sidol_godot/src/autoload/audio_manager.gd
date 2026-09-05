extends Node
## BGM/SFX/Voice 버스 제어 — 원작 sound_box/play_music/Voice_Say 대체.
## 버스: Master/BGM/SFX/Voice (default_bus_layout.tres).
## 파일 규약: res://assets/audio/<bgm|sfx|voice>/<id>.ogg 또는 .wav
## 파일 부재 시 조용히 스킵(에셋 배치 전 단계 허용) — 동일 ID 반복 경고 억제.

const AUDIO_DIR := "res://assets/audio"
const SFX_POOL_SIZE := 6
const EXTENSIONS := [".ogg", ".wav"]

var _bgm_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _cache := {}
var _missing := {}
var _current_bgm := &""

# 동적 오디오: 저역통과 필터(LPF) & 절차적 효과음
var _bgm_lpf: AudioEffectLowPassFilter
var _bgm_lpf_idx := -1
var _lpf_tween: Tween
var _heartbeat_player: AudioStreamPlayer
var _heartbeat_stream: AudioStreamWAV
var _break_cue_stream: AudioStreamWAV
var _shatter_stream: AudioStreamWAV
var _is_low_hp := false
var _heartbeat_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 일시정지 중에도 BGM 유지(PauseMenu)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = &"BGM"
	_bgm_player.finished.connect(_on_bgm_finished)
	add_child(_bgm_player)

	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = &"Voice"
	add_child(_voice_player)

	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_sfx_pool.append(p)

	_setup_bgm_filter()
	_setup_procedural_streams()


func play_sfx(sfx_id: StringName) -> void:
	var stream := _load_stream("sfx", sfx_id)
	if stream == null:
		return
	var player := _free_sfx_player()
	player.stream = stream
	player.play()


func play_bgm(bgm_id: StringName) -> void:
	if _current_bgm == bgm_id and _bgm_player.playing:
		return
	var stream := _load_stream("bgm", bgm_id)
	if stream == null:
		return
	_current_bgm = bgm_id
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_bgm_player.stream = stream
	_bgm_player.play()


func stop_bgm() -> void:
	_current_bgm = &""
	_bgm_player.stop()
	set_low_hp_warning(false)


func _process(delta: float) -> void:
	if _is_low_hp:
		_heartbeat_timer -= delta
		if _heartbeat_timer <= 0.0:
			_heartbeat_timer = 0.85
			play_heartbeat()


func _setup_bgm_filter() -> void:
	var bus_idx := AudioServer.get_bus_index(&"BGM")
	if bus_idx >= 0:
		for i in AudioServer.get_bus_effect_count(bus_idx):
			if AudioServer.get_bus_effect(bus_idx, i) is AudioEffectLowPassFilter:
				_bgm_lpf = AudioServer.get_bus_effect(bus_idx, i) as AudioEffectLowPassFilter
				_bgm_lpf_idx = i
				break
		if _bgm_lpf == null:
			_bgm_lpf = AudioEffectLowPassFilter.new()
			_bgm_lpf.cutoff_hz = 20500.0
			_bgm_lpf.resonance = 0.5
			AudioServer.add_bus_effect(bus_idx, _bgm_lpf)
			_bgm_lpf_idx = AudioServer.get_bus_effect_count(bus_idx) - 1


func _setup_procedural_streams() -> void:
	_heartbeat_player = AudioStreamPlayer.new()
	_heartbeat_player.bus = &"SFX"
	add_child(_heartbeat_player)

	_heartbeat_stream = _build_heartbeat_stream()
	_break_cue_stream = _build_break_cue_stream()
	_shatter_stream = _build_shatter_stream()


func _build_heartbeat_stream() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.85
	var total_samples := int(dur * float(rate))
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	for i in total_samples:
		var t := float(i) / float(rate)
		var sample_f := 0.0
		# 1st pulse (lub)
		if t < 0.20:
			var env := sin(clampf(t / 0.025, 0.0, 1.0) * PI * 0.5) * exp(-t / 0.065)
			sample_f += sin(2.0 * PI * 58.0 * t) * env * 0.85
		# 2nd pulse (dub)
		elif t >= 0.22 and t < 0.42:
			var dt := t - 0.22
			var env := sin(clampf(dt / 0.02, 0.0, 1.0) * PI * 0.5) * exp(-dt / 0.055)
			sample_f += sin(2.0 * PI * 72.0 * dt) * env * 0.65
		var sample_i := clampi(int(sample_f * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, sample_i)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	return stream


func _build_break_cue_stream() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.42
	var total_samples := int(dur * float(rate))
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	for i in total_samples:
		var t := float(i) / float(rate)
		var env := sin(clampf(t / 0.015, 0.0, 1.0) * PI * 0.5) * exp(-t / 0.12)
		var freq1 := 880.0 * (1.0 + t * 0.35)
		var freq2 := 1320.0 * (1.0 + t * 0.35)
		var sample_f := (sin(2.0 * PI * freq1 * t) * 0.5 + sin(2.0 * PI * freq2 * t) * 0.35) * env
		var sample_i := clampi(int(sample_f * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, sample_i)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	return stream


func _build_shatter_stream() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.35
	var total_samples := int(dur * float(rate))
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in total_samples:
		var t := float(i) / float(rate)
		var env := exp(-t / 0.06)
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t / 0.02) * 0.6
		var ring := sin(2.0 * PI * 1760.0 * t) * 0.4 + sin(2.0 * PI * 2640.0 * t) * 0.3
		var sample_f := (ring + noise) * env
		var sample_i := clampi(int(sample_f * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, sample_i)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	return stream


## 빈사 경고 모드 (LPF 음악 감쇠 + 심장 박동 활성화)
func set_low_hp_warning(enabled: bool) -> void:
	if _is_low_hp == enabled:
		return
	_is_low_hp = enabled
	if _bgm_lpf != null:
		if _lpf_tween != null and _lpf_tween.is_valid():
			_lpf_tween.kill()
		_lpf_tween = create_tween()
		var target_hz := 750.0 if enabled else 20500.0
		_lpf_tween.tween_property(_bgm_lpf, "cutoff_hz", target_hz, 0.4)

	if enabled:
		_heartbeat_timer = 0.05
	else:
		if _heartbeat_player != null and _heartbeat_player.playing:
			_heartbeat_player.stop()


func play_heartbeat() -> void:
	if _heartbeat_player == null:
		return
	var stream := _load_stream("sfx", &"heartbeat", true)
	if stream == null:
		stream = _heartbeat_stream
	if stream != null:
		_heartbeat_player.stream = stream
		_heartbeat_player.play()


func play_break_cue() -> void:
	var stream := _load_stream("sfx", &"break_cue", true)
	if stream == null:
		stream = _break_cue_stream
	if stream != null:
		var player := _free_sfx_player()
		player.stream = stream
		player.play()


func play_break_shatter() -> void:
	var stream := _load_stream("sfx", &"break_shatter", true)
	if stream == null:
		stream = _shatter_stream
	if stream != null:
		var player := _free_sfx_player()
		player.stream = stream
		player.play()


## 원작 보이스 재생. **성공 여부를 돌려준다** — 미설치일 때 호출부가 AI 효과음으로
## 폴백할 수 있어야 한다(원본 VOC는 저장소 밖에서 변환해 넣는 것이라 없을 수 있다).
## 변환: tools/convert/voc_convert.py
func play_voice(voice_id: StringName) -> bool:
	var stream := _load_stream("voice", voice_id)
	if stream == null:
		return false
	_voice_player.stream = stream
	_voice_player.play()
	return true


func set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))


func _on_bgm_finished() -> void:
	if not _current_bgm.is_empty():
		_bgm_player.play()  # 시맨틱 루프 — 임포트 루프 플래그와 무관하게 이어 재생


func _free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_pool:
		if not p.playing:
			return p
	return _sfx_pool[0]  # 풀 고갈 시 가장 오래된 것 대체


func _load_stream(kind: String, id: StringName, silent: bool = false) -> AudioStream:
	var key := "%s/%s" % [kind, id]
	if _cache.has(key):
		return _cache[key]
	if _missing.has(key):
		return null
	for ext: String in EXTENSIONS:
		var path := "%s/%s/%s%s" % [AUDIO_DIR, kind, id, ext]
		if ResourceLoader.exists(path):
			var s: AudioStream = load(path)
			_cache[key] = s
			return s
	_missing[key] = true
	if not silent:
		print("[audio] 파일 없음(스킵): %s" % key)
	return null
