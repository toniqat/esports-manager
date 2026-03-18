@tool
class_name Building
extends Node2D

signal hp_changed(old_hp: int, new_hp: int)
signal owner_changed(old_owner: int, new_owner: int)
signal building_destroyed()

# hexa-tileset.png layout: 4 cols × 3 rows, each cell 128×128 px
# Row 0 (y=0):   tile background colors — ignored for buildings
# Row 1 (y=128): Ally HQ | Enemy HQ | Ally T2 | Enemy T2
# Row 2 (y=256): Ally T1 | Enemy T1 | ...
# team 1 = Ally (blue, even cols), team 2 = Enemy (red, odd cols)
const _TILESET_PATH := "res://resources/images/tiles/hexa-tileset.png"
const _TILE_W := 128.0
const _TILE_H := 128.0

## Tile coordinates on the hex grid. Changing this in the Inspector snaps the
## node to the center of the target tile in the editor viewport.
@export var tile_coords: Vector2i = Vector2i.ZERO:
	set(v):
		tile_coords = v
		_snap_to_tile()

## The level/type of building — determines which column group in the atlas is used.
@export var tower_level: GameEnums.TowerLevel = GameEnums.TowerLevel.HQ:
	set(v):
		tower_level = v
		_update_sprite()

## Team number: 1 = Ally (blue), 2 = Enemy (red). Controls atlas column parity.
@export var team: int = 1:
	set(v):
		team = v
		_update_sprite()

## Lane this building belongs to. Used by FieldLoader and combat systems.
@export var lane: GameEnums.Lane = GameEnums.Lane.NONE

## Static blueprint data — set in the Inspector, do not modify at runtime.
@export var data: BuildingData:
	set(v):
		if data != null and data.changed.is_connected(_on_data_changed):
			data.changed.disconnect(_on_data_changed)
		data = v
		if data != null:
			data.changed.connect(_on_data_changed)
		_update_sprite()

# ─── Runtime state (not @export — mutable during gameplay) ───────────────────
var current_hp: int = 0
var current_owner_id: int = -1
var is_active: bool = false


func _ready() -> void:
	_snap_to_tile()
	_update_sprite()
	if data:
		current_hp = data.max_hp
		current_owner_id = data.owner_id
		is_active = true


## Snaps this node's position to the center of tile_coords on the Tiles TileMapLayer.
## Path assumes: BattleField/BuildingLayer/Building (this node).
func _snap_to_tile() -> void:
	if not is_inside_tree():
		return
	var tm: TileMapLayer = get_node_or_null("../../Tiles") as TileMapLayer
	if tm == null:
		return
	var local_on_tm := tm.map_to_local(tile_coords)
	var global_pos := tm.to_global(local_on_tm)
	position = get_parent().to_local(global_pos)


## Updates the Sprite2D texture and region_rect based on building_type and team.
func _update_sprite() -> void:
	if not is_inside_tree():
		return
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	sprite.texture = load(_TILESET_PATH)
	sprite.region_enabled = true
	sprite.region_rect = _get_region_rect()


## Computes the atlas region_rect from tower_level and team.
## Atlas layout (each cell 128×128):
##   Row 1 (y=128): [Ally HQ] [Enemy HQ] [Ally T2] [Enemy T2]
##   Row 2 (y=256): [Ally T1] [Enemy T1] ...
## team 1 = Ally → even column; team 2 = Enemy → odd column.
func _get_region_rect() -> Rect2:
	var is_enemy := team == 2
	match tower_level:
		GameEnums.TowerLevel.HQ:
			var x := 1.0 * _TILE_W if is_enemy else 0.0
			return Rect2(x, _TILE_H, _TILE_W, _TILE_H)
		GameEnums.TowerLevel.LEVEL_2:
			var x := 3.0 * _TILE_W if is_enemy else 2.0 * _TILE_W
			return Rect2(x, _TILE_H, _TILE_W, _TILE_H)
		_:  # LEVEL_1
			var x := 1.0 * _TILE_W if is_enemy else 0.0
			return Rect2(x, 2.0 * _TILE_H, _TILE_W, _TILE_H)


func _on_data_changed() -> void:
	_update_sprite()


# ─── Public runtime API ───────────────────────────────────────────────────────

func take_damage(amount: int) -> void:
	if not is_active:
		return
	var mitigation := data.defense if data else 0
	var old_hp := current_hp
	current_hp = max(0, current_hp - max(0, amount - mitigation))
	hp_changed.emit(old_hp, current_hp)
	if current_hp <= 0:
		is_active = false
		building_destroyed.emit()


func set_building_owner(new_owner: int) -> void:
	var old_owner := current_owner_id
	current_owner_id = new_owner
	owner_changed.emit(old_owner, new_owner)


func heal(amount: int) -> void:
	if not is_active or not data:
		return
	var old_hp := current_hp
	current_hp = min(data.max_hp, current_hp + amount)
	if current_hp != old_hp:
		hp_changed.emit(old_hp, current_hp)
