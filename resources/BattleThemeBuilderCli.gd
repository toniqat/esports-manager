extends SceneTree

# `resources/BattleTheme.tres` 를 헤드리스로 다시 만든다:
#   Godot --headless --path . -s res://resources/BattleThemeBuilderCli.gd
# 에디터 안에서는 `BattleThemeBuilder.gd` 를 File → Run. 둘 다
# `BattleTheme.save_theme()` 하나를 부른다.


func _initialize() -> void:
	var err: Error = BattleTheme.save_theme()
	if err == OK:
		print("BattleTheme: saved ", BattleTheme.THEME_PATH)
	quit(0 if err == OK else 1)
