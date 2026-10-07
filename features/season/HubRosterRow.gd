class_name HubRosterRow
extends Panel

# One roster row of `HubView` (face · role · name · TOTAL · trust chip + gauge · stat strip).
#
# **Layout lives in `HubRosterRow.tscn`** (fixed 190 tall, width from the hub's body column).
# This script only fills `%` nodes and paints the data-driven colours, none of which are theme
# variations: the left bar + role name take the role colour (`OutgameTheme.lead_bar_style`),
# the trust chip / gauge fill take the trust band colour (`HubView.trust_color`).
# `HubView.tscn` places five instances; the hub binds them in seat order.

const SCENE_PATH: String = "res://features/season/HubRosterRow.tscn"


static func create() -> HubRosterRow:
	return (load(SCENE_PATH) as PackedScene).instantiate() as HubRosterRow


## Role of this seat (`GameEnums.Role`) — row colour, role name and the stat captions.
func set_role(role: int) -> void:
	var col: Color = OutgameTheme.ROLE_COLORS[role]
	add_theme_stylebox_override("panel", OutgameTheme.lead_bar_style(col, 16))
	%Role.text = OutgameTheme.ROLE_NAMES[role]
	%Role.add_theme_color_override("font_color", col)
	var cols: Array = %Stats.get_children()
	for s in cols.size():
		(cols[s].get_node("Key") as Label).text = \
				String(PlayerData.STAT_SHORT[s]) if s < PlayerData.STAT_SHORT.size() else ""


## Fills the row with `p` (null = empty seat). `trust` / `trust_max` are only read when `p` is set.
func show_pilot(p: PlayerData, trust: int = 0, trust_max: int = 1) -> void:
	var cols: Array = %Stats.get_children()
	%TrustChip.visible = p != null
	%TrustGauge.visible = p != null
	if p == null:
		%Name.text = "—"
		%Total.text = ""
		%Face.texture = null
		for c in cols:
			(c.get_node("Value") as Label).text = ""
		return
	%Name.text = p.name
	%Face.texture = PilotImages.face_for(p.id)
	%Total.text = "TOTAL %d" % p.stat_total()
	for s in cols.size():
		var v: String = ""
		if s < PlayerData.STAT_KEYS.size():
			v = "%d" % int(p.get(PlayerData.STAT_KEYS[s]))
		(cols[s].get_node("Value") as Label).text = v
	var col: Color = HubView.trust_color(trust)
	%TrustText.text = "신뢰 %d" % trust
	var chip: Panel = %TrustChip
	chip.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(col, int(chip.custom_minimum_size.y * 0.5)))
	var fill: Panel = %TrustFill
	fill.anchor_right = clampf(float(trust) / maxf(1.0, float(trust_max)), 0.0, 1.0)
	fill.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(col, int((%TrustGauge as Control).custom_minimum_size.y * 0.5)))
