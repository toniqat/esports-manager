class_name MechUpgradeRow
extends HBoxContainer

# One mech upgrade step in `MechDetailPanel` (§15 A) — `Lv3` · what it does · 해금 / 잠김.
# **Layout is owned by `UI_Comp_MechUpgradeRow.tscn`** (column widths, font sizes); the
# description wraps, so a long step grows the row. Code only puts the texts and the data
# colours: unlocked = level in `ACCENT_TEXT`, state in `POSITIVE`; locked = everything
# `TEXT_FAINT`; unknown state (`unlocked` absent — enemy without analysis, no run) = plain.

const SCENE_PATH: String = "res://features/match_flow/ban_pick/UI_Comp_MechUpgradeRow.tscn"


static func create() -> MechUpgradeRow:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MechUpgradeRow


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## `row` — `{level: int, text: String, unlocked: bool (optional)}`.
func fill(row: Dictionary) -> void:
	var lv: Label = %Level
	var txt: Label = %Text
	var st: Label = %State
	lv.text = MechMastery.level_name(int(row.get("level", 0)))
	txt.text = String(row.get("text", ""))
	if not row.has("unlocked"):
		st.text = ""
		lv.add_theme_color_override("font_color", OutgameTheme.TEXT)
		txt.add_theme_color_override("font_color", OutgameTheme.TEXT_SUB)
		return
	var on: bool = bool(row["unlocked"])
	st.text = Loc.t(L.MATCH_MECH_DETAIL_UPGRADE_OPEN if on else L.MATCH_MECH_DETAIL_UPGRADE_LOCKED)
	lv.add_theme_color_override("font_color", OutgameTheme.ACCENT_TEXT if on else OutgameTheme.TEXT_FAINT)
	txt.add_theme_color_override("font_color", OutgameTheme.TEXT if on else OutgameTheme.TEXT_FAINT)
	st.add_theme_color_override("font_color", OutgameTheme.POSITIVE if on else OutgameTheme.TEXT_FAINT)


## F6 preview — Juggernaut's Lv3 step (passive) unlocked.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var steps: Array = MechUpgrades.steps(0)
	var text: String = MechUpgrades.step_text(steps[0]) if not steps.is_empty() else "—"
	fill({"level": 3, "text": text, "unlocked": true})
