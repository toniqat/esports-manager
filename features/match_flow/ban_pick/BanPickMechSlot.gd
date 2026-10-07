class_name BanPickMechSlot
extends Control

# One **mech slot** of a team block (`BanPickTeamBlock`) — the square mech portrait filling the
# frame, a name band at the bottom, and the mastery / quirk tags in the top-left corner.
#
# **Layout lives in `BanPickMechSlot.tscn`.** The controller fills it (`BanPickController.
# _refresh_side_block`). The frame's shape is the theme variation `BanPickMechSlotFrame`; its
# border is the **side colour** (data), so `setup` takes a per-instance copy
# (`OutgameTheme.variation_box`) and puts the colour in.
#
# `frame` and `hit` are siblings on purpose: during the assign intro the enemy's frames slide to
# another seat (`_play_enemy_reassign`) while the tap button stays on its own seat.

var frame: Panel = null
var art: TextureRect = null
var band: ColorRect = null
var name_label: Label = null
## Mastery tag (top-left). Optional — deleting it in the scene hides mastery on slots.
var mtag: Panel = null
var mtag_label: Label = null
## Quirk tag (under the mastery tag). Optional, like `mtag`.
var qtag: Panel = null
var qtag_label: Label = null
## Transparent tap button over the slot (enemy slots in the assign step).
var hit: Button = null

## Per-instance frame style — `_refresh_side_block` / the drag highlight recolour it in place.
var style: StyleBoxFlat = null
var side_col: Color = Color.WHITE
## Seat (screen order 0..4) this slot stands for.
var seat: int = -1


func _ready() -> void:
	frame = %Frame
	art = %Art
	band = %Band
	name_label = %NameLabel
	mtag = get_node_or_null("%MTag") as Panel
	mtag_label = get_node_or_null("%MTagLabel") as Label
	qtag = get_node_or_null("%QTag") as Panel
	qtag_label = get_node_or_null("%QTagLabel") as Label
	hit = %Hit


## Side colour + seat. The empty-seat look (sunk fill, faded side border) — refreshes recolour it.
func setup(col: Color, seat_idx: int) -> void:
	side_col = col
	seat = seat_idx
	style = OutgameTheme.variation_box(&"BanPickMechSlotFrame")
	style.border_color = col.lerp(OutgameTheme.SURFACE, 0.55)
	frame.add_theme_stylebox_override("panel", style)
	if qtag != null:
		qtag.add_theme_stylebox_override("panel",
				OutgameTheme.flat_style(QuirkSystem.grade_color(2), 8))
