@tool
class_name Waypoint
extends Node2D

const _TILESET_PATH := "res://resources/images/tiles/hexa-tileset.png"
const _TILE_W := 128.0
const _TILE_H := 128.0
# Row 3 (y=384): col0=None | col1=Left | col2=Center | col3=Right
const _ROW_Y := 384.0

## Tile coordinates on the hex grid. Changing this in the Inspector snaps the
## node to the center of the target tile in the editor viewport.
@export var tile_coords: Vector2i = Vector2i.ZERO:
	set(v):
		tile_coords = v
		_snap_to_tile()

## Lane this waypoint belongs to. Controls the sprite and is read by FieldLoader at runtime.
@export var lane: GameEnums.Lane = GameEnums.Lane.LEFT:
	set(v):
		lane = v
		_update_sprite()

## Step order within the lane (0 = first waypoint after HQ). Lower ids are visited first.
@export var waypoint_id: int = 0

## Optional blueprint resource for additional metadata.
@export var data: WaypointData:
	set(v):
		if data != null and data.changed.is_connected(_on_data_changed):
			data.changed.disconnect(_on_data_changed)
		data = v
		if data != null:
			data.changed.connect(_on_data_changed)
		_update_sprite()


func _ready() -> void:
	_snap_to_tile()
	_update_sprite()


## Snaps this node's position to the center of tile_coords on the Tiles TileMapLayer.
## Path assumes: BattleField/WaypointLayer/Waypoint (this node).
func _snap_to_tile() -> void:
	if not is_inside_tree():
		return
	var tm: TileMapLayer = get_node_or_null("../../Tiles") as TileMapLayer
	if tm == null:
		return
	var local_on_tm := tm.map_to_local(tile_coords)
	var global_pos := tm.to_global(local_on_tm)
	position = get_parent().to_local(global_pos)


## Updates the Sprite2D texture and region_rect based on data.lane.
func _update_sprite() -> void:
	if not is_inside_tree():
		return
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	sprite.texture = load(_TILESET_PATH)
	sprite.region_enabled = true
	sprite.region_rect = _get_region_rect()


## Computes the atlas region_rect from lane.
## Row 3 (y=384): col0=None, col1=Left, col2=Center, col3=Right (each 128×128).
func _get_region_rect() -> Rect2:
	match lane:
		GameEnums.Lane.LEFT:
			return Rect2(_TILE_W, _ROW_Y, _TILE_W, _TILE_H)
		GameEnums.Lane.CENTER:
			return Rect2(2.0 * _TILE_W, _ROW_Y, _TILE_W, _TILE_H)
		GameEnums.Lane.RIGHT:
			return Rect2(3.0 * _TILE_W, _ROW_Y, _TILE_W, _TILE_H)
		_:
			return Rect2(0.0, _ROW_Y, _TILE_W, _TILE_H)


func _on_data_changed() -> void:
	_update_sprite()
