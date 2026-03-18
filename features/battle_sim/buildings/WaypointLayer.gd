@tool
extends Node2D

const _WAYPOINT_SCENE := preload("res://resources/Waypoint.tscn")

@export_tool_button("Add Waypoint")
var _add_btn: Callable = _add_waypoint


func _add_waypoint() -> void:
	var w: Node2D = _WAYPOINT_SCENE.instantiate()
	add_child(w)
	w.owner = get_tree().edited_scene_root
