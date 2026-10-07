extends Node

# Viewer is only mentioned in this comment

func go() -> void:
	get_tree().change_scene_to_file("res://scenes/Battle.tscn")
	var s := "# not a comment Hud"

func peek(b: BattleScreen) -> void:
	pass

func skin() -> void:
	Theme.new()

func scroll() -> void:
	Scroll.new()
