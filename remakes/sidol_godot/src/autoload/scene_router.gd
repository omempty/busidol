extends Node
## Title/Field/Battle/Cutscene 씬 전환+페이드 — 원작 WarMode() 진입·복귀 패턴 대체.

const SCENES := {
	&"title": "res://scenes/title.tscn",
	&"field": "res://scenes/field.tscn",
	&"battle": "res://scenes/battle.tscn",
}


func goto(scene_key: StringName) -> void:
	push_warning("SceneRouter.goto() 미구현(Phase 1): %s" % scene_key)
