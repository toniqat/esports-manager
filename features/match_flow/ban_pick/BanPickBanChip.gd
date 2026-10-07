class_name BanPickBanChip
extends Panel

# One **ban chip** of a team block's ban row — a small square mech portrait (dimmed by
# `BAN_TINT`) with a red ✕. Empty = only the frame. Layout + style in `BanPickBanChip.tscn`;
# `BanPickController._refresh_side_block` sets the texture / ✕ (and the AI's faint preview).

var art: TextureRect = null
var x_label: Label = null


func _ready() -> void:
	art = %Art
	x_label = %XLabel
