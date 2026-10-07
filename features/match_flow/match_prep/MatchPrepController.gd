extends Node

# MatchFlow PREP step — the pre-match scouting sheet shown before BAN_PICK.
# Opponent on top (same side as the ban/pick screen), own team below. How much
# of the opponent is visible follows the analysis reveal rule
# (`OpponentIntel` — tier 0 name/role … tier 3 pilot cards); the own team is
# always fully visible. When analysis is delegated an analyst note sits above
# the opponent rows. Pressing "경기 시작" emits phase_finished.
#
# The screen itself is `MatchPrepView.tscn` (white outgame paper, scroll, bottom
# bar) — this controller only creates it under `_mf.canvas`, fills it and frees
# it when the player moves on.

signal phase_finished(result: Dictionary)

@onready var _mf: MatchFlow = get_parent() as MatchFlow

var _view: MatchPrepView


# Called by MatchFlow with the resolved player + enemy rosters and the
# enemy team display name.
func enter(player_roster: Array, enemy_roster: Array, player_team_name: String, enemy_team_name: String) -> void:
	_view = MatchPrepView.create()
	_mf.canvas.add_child(_view)
	_view.fill(_mf.gm.season_state, player_roster, enemy_roster, player_team_name, enemy_team_name)
	_view.start_pressed.connect(_on_start_pressed)


func _on_start_pressed() -> void:
	if _view != null:
		_view.queue_free()
		_view = null
	phase_finished.emit({})
