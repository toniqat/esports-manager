extends Node

# MatchFlow PREP step — the pre-match scouting sheet shown before BAN_PICK.
# Opponent on top (same side as the ban/pick screen), own team below. How much
# of the opponent is visible follows the analysis reveal rule
# (`OpponentIntel` — tier 0 name/role … tier 3 pilot cards); the own team is
# always fully visible. When analysis is delegated an analyst note sits above
# the opponent rows. Pressing "경기 시작" emits phase_finished.
#
# The screen itself is `UI_View_MatchPrepView.tscn` (white outgame paper, scroll, bottom
# bar) — this controller only creates it under `_mf.canvas`, fills it and frees
# it when the player moves on.

signal phase_finished(result: Dictionary)

@onready var _mf: MatchFlow = get_parent() as MatchFlow

var _view: MatchPrepView


# Called by MatchFlow with the resolved player + enemy rosters, the team display
# names and the enemy team id (its analysis rank, `IntelResearch.rank`, sets the reveal tier).
func enter(player_roster: Array, enemy_roster: Array, player_team_name: String, enemy_team_name: String,
		enemy_team_id: int = -1) -> void:
	_view = MatchPrepView.create()
	_mf.canvas.add_child(_view)
	_view.fill(_mf.gm.season_state, player_roster, enemy_roster, player_team_name, enemy_team_name,
			enemy_team_id)
	_view.start_pressed.connect(_on_start_pressed)
	# Saturday prep (split): this button leads to the ban/pick, not to the match.
	if _mf.is_prep_only():
		_view.set_start_text(Loc.t(L.MATCH_FLOW_PREP_TO_BAN_PICK))


func _on_start_pressed() -> void:
	if _view != null:
		_view.queue_free()
		_view = null
	phase_finished.emit({})
