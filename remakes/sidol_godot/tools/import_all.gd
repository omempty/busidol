extends SceneTree
## 사용법: godot --headless --path . --script tools/import_all.gd
## data/** JSON 검증 및 파생 리소스 생성. Phase 0은 골격만 — 단계별 채움:
##   Phase 2: maps TMJ → TileSet/MapDefinition 빌드
##   Phase 3: dialogue.json 로드검증(@t 불변/@c 대역)
##   Phase 4: items/enemies/growth/skills 테이블 임포트


func _initialize() -> void:
	print("[import_all] start")
	print("[import_all] done(stub) - 0 errors")
	quit(0)
