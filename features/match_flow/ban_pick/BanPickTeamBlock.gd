class_name BanPickTeamBlock
extends VBoxContainer

# A **team block** of the ban/pick screen — ban row (team name · `BAN` · 2 chips), 5 mech
# slots, 5 pilot portraits. Both blocks are authored inline in `BanPickView.tscn`
# (`%EnemyBlock` top, `%PlayerBlock` bottom); the bottom one is the top one **in mirrored
# child order**, so this script finds its rows by name, not by index.
#
# The player block also holds the assign-step rows (`AssignGap` + `Hint`, hidden during
# ban/pick): `set_assign_layout` shows them and makes the portrait row tall (bust crops).
# The block is anchored to the bottom and grows upward, so it keeps its bottom edge.

var side_label: Label = null
var ban_chips: Array = []      # Array[BanPickBanChip]
var mech_slots: Array = []     # Array[BanPickMechSlot] — seat order
var portraits: Array = []      # Array[BanPickPortrait] — seat order
var portrait_row: Control = null
## Assign-step rows (player block only; null in the enemy block).
var hint: Label = null
var assign_gap: Control = null


func _ready() -> void:
	side_label = get_node("BanRow/SideLabel") as Label
	for c in get_node("BanRow").get_children():
		if c is BanPickBanChip:
			ban_chips.append(c)
	for c in get_node("MechRow").get_children():
		if c is BanPickMechSlot:
			mech_slots.append(c)
	portrait_row = get_node("PortraitRow") as Control
	for c in portrait_row.get_children():
		if c is BanPickPortrait:
			portraits.append(c)
	hint = get_node_or_null("Hint") as Label
	assign_gap = get_node_or_null("AssignGap") as Control


## Assign step: the portrait row becomes `portrait_h` tall and the hint line appears.
func set_assign_layout(portrait_h: float) -> void:
	portrait_row.custom_minimum_size.y = portrait_h
	if assign_gap != null:
		assign_gap.visible = true
	if hint != null:
		hint.visible = true
