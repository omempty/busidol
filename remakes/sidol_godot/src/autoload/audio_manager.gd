extends Node
## BGM/SFX/Voice 버스 제어 — 원작 sound_box/play_music/Voice_Say 대체.
## 재생 구현은 Phase 8(AI 생성 오디오 확보 후). 버스 레이아웃: Master/BGM/SFX/Voice.


func play_sfx(sfx_id: StringName) -> void:
	push_warning("AudioManager.play_sfx() 미구현(Phase 8): %s" % sfx_id)


func play_bgm(bgm_id: StringName) -> void:
	push_warning("AudioManager.play_bgm() 미구현(Phase 8): %s" % bgm_id)


func play_voice(voice_id: StringName) -> void:
	push_warning("AudioManager.play_voice() 미구현(Phase 8): %s" % voice_id)
