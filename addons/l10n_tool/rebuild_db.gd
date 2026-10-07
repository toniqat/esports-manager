extends SceneTree

# 헤드리스 Rebuild game.db (+ 끝에 l10n build dev):
#   godot --headless --path . --script res://addons/l10n_tool/rebuild_db.gd

func _initialize() -> void:
	var err: String = load("res://addons/csv_to_db/csv_to_db.gd").new().call("rebuild")
	if err != "":
		printerr(err)
	quit(1 if err != "" else 0)
