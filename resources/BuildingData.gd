class_name BuildingData
extends Resource

@export var building_name: String = ""
@export var tower_level: GameEnums.TowerLevel = GameEnums.TowerLevel.LEVEL_1:
	set(v):
		tower_level = v
		emit_changed()
@export var max_hp: int = 100
@export var defense: int = 0
@export var production_rate: int = 0
@export var owner_id: int = -1
