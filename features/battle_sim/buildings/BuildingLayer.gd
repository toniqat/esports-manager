@tool
extends Node2D

const _BUILDING_SCENE := preload("res://resources/Building.tscn")

@export_tool_button("Add Building")
var _add_btn: Callable = _add_building


func _add_building() -> void:
	var b: Node2D = _BUILDING_SCENE.instantiate()
	add_child(b)
	b.owner = get_tree().edited_scene_root
