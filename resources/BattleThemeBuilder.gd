@tool
extends EditorScript

# `resources/BattleTheme.tres` 를 다시 만든다 — 스크립트 편집기에서 이 파일을 열고
# File → Run (Ctrl+Shift+X). 헤드리스로는 `BattleThemeBuilderCli.gd` 를 쓴다.
#
# 만드는 일은 전부 `BattleTheme.build_theme()` 이 한다(색 · 스타일박스의 정본이
# `BattleTheme.gd` 하나이도록). 이 파일은 그 결과를 저장하는 입구일 뿐이다.


func _run() -> void:
	if BattleTheme.save_theme() == OK:
		print("BattleTheme: saved ", BattleTheme.THEME_PATH)
		EditorInterface.get_resource_filesystem().scan()
