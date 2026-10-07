extends SceneTree

# `resources/OutgameTheme.tres` 를 헤드리스로 다시 만든다:
#   Godot --headless --path . -s res://resources/OutgameThemeBuilderCli.gd
# 에디터 안에서는 `OutgameThemeBuilder.gd` 를 File → Run. 둘 다
# `OutgameTheme.save_theme()` 하나를 부른다.


func _initialize() -> void:
	var err: Error = OutgameTheme.save_theme()
	if err == OK:
		print("OutgameTheme: saved ", OutgameTheme.THEME_PATH)
	quit(0 if err == OK else 1)
