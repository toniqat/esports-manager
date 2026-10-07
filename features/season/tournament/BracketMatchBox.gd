class_name BracketMatchBox
extends Panel

# One match box of a bracket screen — slot title + week on top, team A / team B below.
# Shared by `BracketView` (`BracketMatchBox.tscn`, 4-team playoff) and `IntlBracketView`
# (`IntlMatchBox.tscn`, smaller fonts / tighter insets for the 8-team INTL bracket).
#
# **Layout lives in the scene** (label insets, font sizes; the box size is set by the
# instance in the bracket screen's scene). This script fills text and paints the data
# colours: team colours (player = amber, winner = green, loser / TBD = faint) and the
# border (player's match = amber 3px, decided = green 2px, otherwise `BORDER` 2px). The
# border is data, so the `StyleBoxFlat` is built here — no theme variation carries it.

## Slot title shown top-left ("4강 1경기", "결승" …) — set per instance in the screen scene.
@export var slot_title: String = ""
## Corner radius of the box (the playoff boxes are rounder than the INTL ones).
@export var corner_radius: int = 8

var _style: StyleBoxFlat


func _ready() -> void:
	_style = StyleBoxFlat.new()
	_style.bg_color = OutgameTheme.SURFACE
	_style.border_color = OutgameTheme.BORDER
	_style.set_border_width_all(2)
	OutgameTheme.set_corner_radius(_style, corner_radius)
	_style.shadow_color = OutgameTheme.SHADOW
	_style.shadow_size = 6
	_style.shadow_offset = Vector2(0, 3)
	add_theme_stylebox_override("panel", _style)
	%Slot.text = slot_title


## `m` = one bracket entry (`{team_a, team_b, winner, played, phase_week}`), empty = keep
## the box blank. `team_text` maps a team id (≥ 0) to its display name.
func show_match(m: Dictionary, pid: int, team_text: Callable) -> void:
	if m.is_empty():
		%TeamA.text = ""
		%TeamB.text = ""
		%Date.text = ""
		return
	var ta: int = int(m["team_a"])
	var tb: int = int(m["team_b"])
	var winner: int = int(m["winner"])
	var played: bool = bool(m["played"])

	%TeamA.text = "— TBD —" if ta < 0 else String(team_text.call(ta))
	%TeamB.text = "— TBD —" if tb < 0 else String(team_text.call(tb))
	%Date.text = "%d주차" % int(m.get("phase_week", 0))

	# Winner / loser color treatment.
	(%TeamA as Label).add_theme_color_override("font_color", team_color(ta, pid, played, winner))
	(%TeamB as Label).add_theme_color_override("font_color", team_color(tb, pid, played, winner))

	# Border: gold when player participates, green when match decided.
	if ta == pid or tb == pid:
		_style.border_color = OutgameTheme.ACCENT
		_style.set_border_width_all(3)
	elif played:
		_style.border_color = OutgameTheme.POSITIVE
		_style.set_border_width_all(2)
	else:
		_style.border_color = OutgameTheme.BORDER
		_style.set_border_width_all(2)


static func team_color(team_id: int, pid: int, played: bool, winner: int) -> Color:
	if team_id < 0:
		return OutgameTheme.TEXT_FAINT
	if played:
		if team_id == winner:
			return OutgameTheme.ACCENT_TEXT if team_id == pid else OutgameTheme.POSITIVE
		return OutgameTheme.TEXT_FAINT
	return OutgameTheme.ACCENT_TEXT if team_id == pid else OutgameTheme.TEXT
