extends Node
## 탄막 탄 텍스처 캡처 — 외부팩 탄이 도형 대신 그려지는지 눈으로 확인한다.
## 실행: godot --path . --resolution 960x540 res://tools/dev/dodge_probe.tscn
## 산출: user://battle_anim/dodge_probe.png (창 모드 필요)
const OUT := "user://battle_anim/dodge_probe.png"


func _ready() -> void:
	var dodge := DodgePhase.new()
	add_child(dodge)
	(
		dodge
		. start(
			999.0,
			{
				"patterns":
				[
					{"pattern_id": "p0", "type": "radial", "count": 12, "interval": 0.4},
					{"pattern_id": "p1", "type": "rain", "count": 6, "interval": 0.3},
					{"pattern_id": "p2", "type": "aimed", "count": 3, "interval": 0.5},
				]
			}
		)
	)
	for i in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.save_png(OUT) != OK:
		push_error("[dodge_probe] 저장 실패")
		get_tree().quit(1)
		return
	print("[dodge_probe] done → %s (tex=%s)" % [OUT, str(dodge._ext_tex.keys())])
	get_tree().quit(0)
