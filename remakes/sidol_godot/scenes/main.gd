extends Node
## 루트 씬 — 부팅 후 필드로 전환.


func _ready() -> void:
	print("[boot] main ready")
	get_tree().change_scene_to_file("res://scenes/field.tscn")
