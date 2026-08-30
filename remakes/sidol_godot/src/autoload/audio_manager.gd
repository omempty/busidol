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


func _load_stream(kind: String, id: StringName) -> AudioStream:
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
	print("[audio] 파일 없음(스킵): %s" % key)
	return null
