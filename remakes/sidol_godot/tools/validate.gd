extends SceneTree
## 사용법: godot --headless --path . --script tools/validate.gd
## 콘텐츠 참조 검사(플래그 ID·대사 @t/@c 대역·액터 참조). Validator 규칙은
## docs/02_design/05_toolchain_editors.md §2 기준. Phase 0은 골격만.


func _initialize() -> void:
	print("[validate] start")
	print("[validate] done(stub) - 0 errors")
	quit(0)
