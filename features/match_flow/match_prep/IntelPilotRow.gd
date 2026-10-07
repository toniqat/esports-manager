class_name IntelPilotRow
extends MarginContainer

# One pilot of an `IntelView` (an `OpponentIntel.build()` row): portrait · role · name · total,
# six stat cells, then the mech line (tier >= 2) and the card line (tier 3).
#
# **Layout lives in `IntelPilotRow.tscn`.** The root is a MarginContainer so `%Back` (the card)
# and `Content` overlap and the row is exactly as tall as `Content`. This script only fills `%`
# nodes and applies the data-driven looks, none of which are theme variations: the card's left
# bar + role name take the role colour (`OutgameTheme.lead_bar_style`), the stat value font
# size follows the reveal tier, hidden values / total switch to `FaintLabel`.

const SCENE_PATH: String = "res://features/match_flow/match_prep/IntelPilotRow.tscn"
const PORTRAIT: float = 76.0
## Stat value font size — exact numbers · ranges (`60~69`) · `?`.
const FONT_EXACT: int = 28
const FONT_RANGE: int = 19
const FONT_HIDDEN: int = 26


static func create() -> IntelPilotRow:
	return (load(SCENE_PATH) as PackedScene).instantiate() as IntelPilotRow


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## `row` = one entry of `OpponentIntel.build()["rows"]`.
func fill(row: Dictionary) -> void:
	var role_col: Color = OutgameTheme.ROLE_COLORS[clampi(int(row["role"]), 0, 4)]
	(%Back as Panel).add_theme_stylebox_override(&"panel",
			OutgameTheme.lead_bar_style(role_col, 14))
	var slot: Control = %Portrait
	for c in slot.get_children():
		c.queue_free()
	OutgameTheme.add_round_portrait(slot, PilotImages.face_for(int(row["pilot_id"])),
			Vector2.ZERO, PORTRAIT, role_col)

	var shown: bool = bool(row["show_stats"])
	var exact: bool = bool(row["exact"])
	%Role.text = String(row["role_label"])
	%Role.add_theme_color_override(&"font_color", role_col)
	%Name.text = String(row["name"])
	%Total.text = "합계 %s" % row["total_text"]
	%Total.theme_type_variation = &"CaptionLabel" if shown else &"FaintLabel"

	var stats: Array = row["stats"]
	var cells: Array = (%Stats as Node).get_children()
	for i in cells.size():
		var cell := cells[i] as Control
		cell.visible = i < stats.size()
		if not cell.visible:
			continue
		var c: Dictionary = stats[i]
		(cell.get_node("Key") as Label).text = String(c["label"])
		var v := cell.get_node("Value") as Label
		v.text = String(c["text"])
		v.theme_type_variation = &"BodyLabel" if shown else &"FaintLabel"
		v.add_theme_font_size_override(&"font_size",
				FONT_EXACT if exact else (FONT_RANGE if shown else FONT_HIDDEN))

	var show_mechs: bool = bool(row["show_mechs"])
	var show_cards: bool = bool(row["show_cards"])
	%MechLine.visible = show_mechs
	%CardLine.visible = show_cards
	%ExtraPad.visible = show_mechs or show_cards
	if show_mechs:
		var parts: Array = []
		for raw in (row["mechs"] as Array):
			parts.append(String((raw as Dictionary)["text"]))
		%MechText.text = " · ".join(parts) if not parts.is_empty() else "정보 없음"
	if show_cards:
		var names: Array = row["cards"]
		%CardText.text = " · ".join(names) if not names.is_empty() else "정보 없음"


## F6 단독 실행 미리보기 — 2단계(정확한 스탯 + 주력 메크, 카드 없음) 미드 한 줄. 손으로 적은 값.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var keys: Array = ["전명", "전회", "교명", "교회", "공성", "체성"]
	var vals: Array = [90, 90, 92, 88, 90, 86]
	var stats: Array = []
	for i in keys.size():
		stats.append({"label": keys[i], "text": str(vals[i]), "value": vals[i]})
	fill({
		"pilot_id": 2, "name": "Shunguang", "role": GameEnums.Role.ASSASSIN, "role_label": "미드",
		"show_stats": true, "exact": true, "stats": stats, "total_text": "536",
		"show_mechs": true, "mechs": [{"mech_id": 0, "name": "Headsman", "text": "Headsman 능숙"},
				{"mech_id": 0, "name": "Reaper", "text": "Reaper 능숙"}],
		"show_cards": false, "cards": [],
	})
