class_name MinionData
extends RefCounted

const MINION_SPAWN_COUNT := 30

var team: int
var lane: int
var count: int        = MINION_SPAWN_COUNT
var grid_pos: Vector2i
var waypoint_idx: int = 0
var alive: bool       = true
