extends Node
## 볼륨/연출속도/키매핑 저장 — 원작 WVISUAL/SPEED/gitar() 대체. 파일 입출력은 Phase 9.

enum EffectSpeed { NORMAL, FAST, SKIP }
## 아트 모드 — LEGACY: 원작 도트 세트(_original) / REMAKE: 신규 생성 세트(_remake)
enum ArtMode { LEGACY, REMAKE }

var effect_speed: EffectSpeed = EffectSpeed.NORMAL
var art_mode: ArtMode = ArtMode.LEGACY


func load_settings() -> void:
	push_warning("SettingsManager.load_settings() 미구현(Phase 9)")
