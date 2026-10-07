class_name BanPickPortrait
extends Control

# One **pilot portrait** of a team block (`BanPickTeamBlock`): a sunk back plate (shows as-is
# when there is no image — INTL teams / standalone run), the face crop, a side-coloured rim,
# the `기벽 n` badge (my pilots, season run) and a transparent tap button (assign step only).
#
# **Layout lives in `BanPickPortrait.tscn`.** The crop is data: an eye band during ban/pick,
# the bust once the assign step makes the portrait row tall (`BanPickController`). The rim
# colour is the side colour and the badge fill the quirk grade colour, so both StyleBoxes are
# built here / by the controller.

var back: ColorRect = null
var face: TextureRect = null
var rim: Panel = null
## `기벽 n` pill (bottom-right). Optional — deleting it hides the quirk badge.
var quirk_badge: Panel = null
var quirk_label: Label = null
var hit: Button = null


func _ready() -> void:
	back = %Back
	face = %Face
	rim = %Rim
	quirk_badge = get_node_or_null("%QuirkBadge") as Panel
	quirk_label = get_node_or_null("%QuirkLabel") as Label
	hit = %Hit


## Side colour of the rim — shape = theme variation `BanPickPortraitRim` (2px, transparent fill).
func setup(side_col: Color) -> void:
	var sb := OutgameTheme.variation_box(&"BanPickPortraitRim")
	sb.border_color = side_col
	rim.add_theme_stylebox_override("panel", sb)
