class_name BuildingRegistry
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim

# Vector2i (tile_coords) → Building
var _registry: Dictionary = {}


func _ready() -> void:
	_registry.clear()
	var layer: Node = _bs.get_node_or_null("BattleField/BuildingLayer")
	if layer == null:
		return
	for child in layer.get_children():
		if child is Building:
			register(child as Building)


# ─── Public API ───────────────────────────────────────────────────────────────

func register(building: Building) -> void:
	_registry[building.tile_coords] = building


func unregister(building: Building) -> void:
	_registry.erase(building.tile_coords)


func get_at(coords: Vector2i) -> Building:
	return _registry.get(coords, null)


func has_building_at(coords: Vector2i) -> bool:
	return _registry.has(coords)


func get_all() -> Array:
	return _registry.values()


func get_all_owned_by(owner_id: int) -> Array:
	return _registry.values().filter(
		func(b: Building) -> bool: return b.current_owner_id == owner_id
	)
