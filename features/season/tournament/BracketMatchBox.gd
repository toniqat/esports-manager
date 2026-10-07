class_name BracketMatchBox
extends Panel

# One match box of a bracket screen — slot title + week on top, team A / team B below.
# Shared by `BracketView` (`UI_Comp_BracketMatchBox.tscn`, 4-team playoff) and `IntlBracketView`
# (`UI_Comp_IntlMatchBox.tscn`, smaller fonts / tighter insets for the 8-team INTL bracket).
#
# **Layout lives in the scene** (label insets, font sizes; the box size is set by the
# instance in the bracket screen's scene). This script fills text and paints the data
# colours: team colours (player = amber, winner = green, loser / TBD = faint) and the
# border (player's match = amber 3px, decided = green 2px, otherwise `BORDER` 2px). The
# border is data, so the `StyleBoxFlat` is built here — no theme variation carries it.

## Slot title shown top-left — an l10n key (`season.slot.*`, "4강 1경기", "결승" …) set per instance
## in the screen scene; translated here.
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
	%Slot.text = Loc.t(slot_title) if slot_title != "" else ""  # l10n-dynamic: season.slot.*
	if UiPreview.is_standalone(self):
		_fill_preview()


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
	%Date.text = Loc.t(L.TERM_WEEK_NTH, {"n": int(m.get("phase_week", 0))})

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


## F6 단독 실행 미리보기 — 내 팀이 이긴 4강 경기 (`resources/UiPreview.gd`).
## 두 아이템 씬(`UI_Comp_BracketMatchBox.tscn` · `UI_Comp_IntlMatchBox.tscn`) 모두 이 스크립트라 같은 값이 뜬다.
func _fill_preview() -> void:  # l10n-ignore
	UiPreview.stage(self)
	if slot_title == "":
		slot_title = L.SEASON_SLOT_SF_1
		%Slot.text = Loc.t(slot_title)
	var names: Dictionary = {0: "레드 팰컨즈  (RF)", 3: "아이언 웨일즈  (IW)"}
	show_match({"team_a": 0, "team_b": 3, "winner": 0, "played": true, "phase_week": 5},
			0, func(team_id: int) -> String: return String(names.get(team_id, "Team %d" % team_id)))
