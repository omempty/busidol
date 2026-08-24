extends Node
## 볼륨/연출속도/키매핑 저장 — 원작 WVISUAL/SPEED/gitar() 대체. 파일 입출력은 Phase 9.

enum EffectSpeed { NORMAL, FAST, SKIP }

var effect_speed: EffectSpeed = EffectSpeed.NORMAL


func load_settings() -> void:
	push_warning("SettingsManager.load_settings() 미구현(Phase 9)")
