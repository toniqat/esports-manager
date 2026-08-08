class_name TeamDraft
extends Control

# Initial 5-pilot team selection. Each role 0..4 must be filled exactly once.
# Swaps preserve the invariant "every team has 5 pilots, one per role".

@onready var _gm: Node = get_node("/root/GameManager")

var _view: TeamDraftView = null


# Called by SeasonHub right before showing the draft screen, after
# init_season() has populated the pilot pool. Idempotent.
func ensure_view() -> void:
	if _view != null:
		return
	_view = TeamDraftView.new()
	add_child(_view)


# Pool layout for the draft grid: 5 roles × 8 candidates, ranked by total stats
# (descending) inside each role. Returns Array of
# {pilot: PlayerData, role: int, rank: int}.
func get_pool_grid() -> Array:
	var pool: Array = _gm.season_state["all_pilots"]
	var by_role: Dictionary = {0: [], 1: [], 2: [], 3: [], 4: []}
	for p_raw in pool:
		var p := p_raw as PlayerData
		by_role[int(p.role)].append(p)
	var entries: Array = []
	for r in 5:
		var arr: Array = by_role[r]
		arr.sort_custom(_compare_by_stats)
		for i in arr.size():
			entries.append({"pilot": arr[i], "role": r, "rank": i})
	return entries


func _compare_by_stats(a: PlayerData, b: PlayerData) -> bool:
	return _total_stats(a) > _total_stats(b)


func _total_stats(p: PlayerData) -> int:
	return p.laning + p.mechanics + p.gamesense + p.teamfight + p.mental


# Validate a draft selection: 5 pilot ids, one per role 0..4, all distinct,
# all present in the pool. Returns "" on success, or an error string.
func validate_draft(pilot_ids: Array) -> String:
	if pilot_ids.size() != 5:
		return "Must pick exactly 5 pilots (got %d)" % pilot_ids.size()
	var pool: Array = _gm.season_state["all_pilots"]
	var by_id: Dictionary = {}
	for p in pool:
		by_id[p.id] = p
	var seen_roles: Dictionary = {}
	for pid in pilot_ids:
		if not by_id.has(pid):
			return "Unknown pilot id: %s" % str(pid)
		var r: int = int(by_id[pid].role)
		if seen_roles.has(r):
			return "Duplicate role %d" % r
		seen_roles[r] = true
	return ""


# Apply a validated draft. For each picked pilot p (from team t_p), swap
# the team-0 pilot of the same role with p, sending the displaced pilot
# back to team t_p. Returns "" on success or error string.
func apply_draft(pilot_ids: Array) -> String:
	var err := validate_draft(pilot_ids)
	if err != "":
		return err

	var pool: Array = _gm.season_state["all_pilots"]
	var by_id: Dictionary = {}
	for p in pool:
		by_id[p.id] = p

	# Map role -> current team-0 pilot id for fast lookup
	var team0_by_role: Dictionary = {}
	for p in pool:
		if p.team_id == 0:
			team0_by_role[p.role] = p.id

	for pid in pilot_ids:
		var picked: PlayerData = by_id[pid]
		if picked.team_id == 0:
			continue   # already on team 0
		var displaced_id: int = team0_by_role[picked.role]
		var displaced: PlayerData = by_id[displaced_id]
		var src_team: int = picked.team_id
		picked.team_id = 0
		displaced.team_id = src_team

	_rebuild_rosters_from_pool()
	return ""


func _rebuild_rosters_from_pool() -> void:
	var rosters: Dictionary = {}
	for t in _gm.TEAM_COUNT:
		rosters[t] = []
	for p in _gm.season_state["all_pilots"]:
		rosters[p.team_id].append(p.id)
	_gm.season_state["team_rosters"] = rosters
