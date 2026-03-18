class_name WaypointData
extends Resource

@export var lane: GameEnums.Lane = GameEnums.Lane.LEFT:
	set(v):
		lane = v
		emit_changed()
@export var waypoint_id: int = 0:
	set(v):
		waypoint_id = v
		emit_changed()
