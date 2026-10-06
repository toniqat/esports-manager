extends Node

# MatchFlow PREP step — the pre-match scouting sheet shown before BAN_PICK.
# Opponent on top (same side as the ban/pick screen), own team below. How much
# of the opponent is visible follows the analysis reveal rule
# (`OpponentIntel` — tier 0 name/role … tier 3 pilot cards); the own team is
# always fully visible. When analysis is delegated an analyst note sits above
# the opponent rows. Pressing "경기 시작" emits phase_finished.
#
# White outgame paper (`OutgameTheme`), body in a vertical scroll that ends at
# the bottom action bar (`OutgameTheme.add_bottom_bar`).

signal phase_finished(result: Dictionary)

@onready var _mf: MatchFlow = get_parent() as MatchFlow

const SIDE: float = 40.0
const BODY_TOP: float = 136.0
const SCROLLBAR_ROOM: float = 16.0   # rows stop short of the scroll bar

var _panel: Panel


# Called by MatchFlow with the resolved player + enemy rosters and the
# enemy team display name.
func enter(player_roster: Array, enemy_roster: Array, player_team_name: String, enemy_team_name: String) -> void:
	_build_ui(player_roster, enemy_roster, player_team_name, enemy_team_name)


func _build_ui(player_roster: Array, enemy_roster: Array, player_team_name: String, enemy_team_name: String) -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", OutgameTheme.flat_style(OutgameTheme.BG, 0))
	_mf.canvas.add_child(_panel)
	# Push the whole sheet below the notch, then fill the vacated strip with the
	# same paper colour (`docs/mobile_safe_area.md`).
	ScreenMetrics.indent_to_safe_top(_panel)
	ScreenMetrics.backfill_top(_panel, OutgameTheme.BG)

	var w: float = ScreenMetrics.vp_w() - SIDE * 2.0
	# Title centred — the editor-only cheat button sits at the top-left corner.
	UiHelpers.mk_label(_panel, "경기 준비", 48, OutgameTheme.TEXT,
			Vector2(SIDE, 24), Vector2(w, 60), HORIZONTAL_ALIGNMENT_CENTER)
	UiHelpers.mk_label(_panel, "%s  vs  %s" % [player_team_name, enemy_team_name], 26,
			OutgameTheme.TEXT_SUB, Vector2(SIDE, 86), Vector2(w, 34), HORIZONTAL_ALIGNMENT_CENTER)

	var scroll_h: float = OutgameTheme.bottom_bar_top() - BODY_TOP - 12.0
	var vs: Dictionary = OutgameTheme.add_vscroll(_panel, Vector2(SIDE, BODY_TOP),
			Vector2(w, scroll_h))
	var body: Control = vs["body"]

	var state: Dictionary = _mf.gm.season_state
	w -= SCROLLBAR_ROOM
	var y: float = 0.0
	y = _add_team_section(body, y, w, "상대 팀 · %s" % enemy_team_name,
			OpponentIntel.build(state, enemy_roster, false))
	y += 18.0
	y = _add_team_section(body, y, w, "내 팀 · %s" % player_team_name,
			OpponentIntel.build(state, player_roster, true))
	body.custom_minimum_size.y = y + 16.0

	var bar: Array = OutgameTheme.add_bottom_bar(_panel, [
		{"text": "경기 시작", "style": "primary", "font": 34},
	])
	(bar[0] as Button).pressed.connect(_on_start_pressed)


func _add_team_section(body: Control, y0: float, w: float, title: String, intel: Dictionary) -> float:
	var y: float = y0
	UiHelpers.mk_label(body, title, 28, OutgameTheme.TEXT, Vector2(0, y), Vector2(w, 38))
	y += 46.0
	y += IntelView.add_tier_header(body, Vector2(0, y), w, intel)
	y += IntelView.add_analyst_note(body, Vector2(0, y), w, intel)
	y += IntelView.add_rows(body, Vector2(0, y), w, intel)
	return y


func _on_start_pressed() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null
	phase_finished.emit({})
