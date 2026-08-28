extends SceneTree
## 초상 배선 확인 — PortraitLibrary가 화자 이름으로 설치된 초상을 찾는가.
## 일회성 점검이 아니라 남겨 둔다: 초상은 "설치해도 코드가 안 읽는" 사문화 유형의
## 재발 지점이라, 파일이 있는데 화면에 안 뜨는 상태를 이 스크립트가 즉시 드러낸다.
## 실행: godot --headless --path . --script tools/dev/portrait_check.gd


func _init() -> void:
	var installed := PortraitLibrary.installed_count()
	print("[portrait_check] 설치된 초상 %d종" % installed)
	for speaker in ["여학생", "npc_girl", "화공과 교수", "없는사람"]:
		var asset_id := PortraitLibrary.resolve(speaker)
		var tex := PortraitLibrary.texture_for(speaker, "worried")
		print(
			(
				"  %-10s -> id='%s' 텍스처=%s"
				% [
					speaker,
					asset_id,
					(
						(
							"%dx%d @x%d"
							% [tex.region.size.x, tex.region.size.y, tex.region.position.x]
						)
						if tex != null
						else "없음"
					)
				]
			)
		)
	quit(0)
