class_name IntelResearch
extends RefCounted

# ── Research kind handler: `intel` (§16) ──
# Opponent research for the `intel` facility (전력 분석실). Target = a team of the competition
# I am playing in right now (`field`: the INTL bracket while I am in it, else the league), my
# next opponent first; completion raises `season_state.intel_rank["<team_id>"]` by one (0..`MAX_RANK`,
# kept for the whole run). The rank is the opponent's reveal tier on every intel screen
# (`OpponentIntel.tier_for`, MatchFlow PREP · ban/pick · league team detail); own team = MAX_RANK.
# Owner: agent E (intel-research). The four static handler signatures are dispatched by
# `ResearchSystem`. Contract: `features/season/facility/README.md` "Kind handlers".

const MAX_RANK: int = 3


## Targets offered for `row`: the field's teams below `MAX_RANK` (next opponent first).
static func targets(state: Dictionary, _row: Dictionary) -> Array:
	var out: Array = []
	var next_id: int = next_opponent(state)
	for raw in field(state):
		var tid: int = int(raw)
		var r: int = rank(state, tid)
		if r >= MAX_RANK:
			continue
		out.append({"id": str(tid), "label": Loc.t(
				L.RESEARCH_INTEL_TARGET_NEXT if tid == next_id else L.RESEARCH_INTEL_TARGET,
				{"team": team_short(tid), "rank": r, "max": MAX_RANK})})
	return out


## "" when `row` may be researched now (some team below `MAX_RANK`), else the block reason.
static func row_available(state: Dictionary, row: Dictionary) -> String:
	if targets(state, row).is_empty():
		return Loc.t(L.RESEARCH_INTEL_BLOCK_NO_TARGET)
	return ""


## Completed research on `target` (a team id) → its rank + 1 (cap `MAX_RANK`).
static func on_complete(state: Dictionary, _row: Dictionary, target: String) -> Dictionary:
	if not target.is_valid_int():
		return {"text_key": "", "args": {}}
	var tid: int = int(target)
	var r: int = mini(MAX_RANK, rank(state, tid) + 1)
	var ranks: Dictionary = state.get("intel_rank", {}) if state.get("intel_rank") is Dictionary else {}
	ranks[str(tid)] = r
	state["intel_rank"] = ranks
	return {"text_key": L.RESEARCH_INTEL_NOTE_RANK_UP, "args": {"team": team_short(tid), "rank": r}}


## Facility screen body: one card per field team (rank, progress, `분석` button), next opponent first.
static func make_body(state: Dictionary, _fid: String) -> Control:
	var body := IntelResearchBody.create()
	body.fill(state)
	return body


## Analysis rank 0..`MAX_RANK` of `team_id` (own team = `MAX_RANK`). Replaces `StaffSystem.analysis_tier`.
static func rank(state: Dictionary, team_id: int) -> int:
	if team_id == int(state.get("player_team_id", -1)):
		return MAX_RANK
	return clampi(int((state.get("intel_rank", {}) as Dictionary).get(str(team_id), 0)), 0, MAX_RANK)


# ── Field ─────────────────────────────────────────────────────────────────────
## Team ids of the competition I play in now, without my team, my next opponent first:
## the current tournament bracket while I am in it (INTL: league top 4 + INTL teams;
## playoffs: the league), else every league team.
static func field(state: Dictionary) -> Array:
	var pid: int = int(state.get("player_team_id", -1))
	var ids: Array = []
	var bracket: Array = _bracket(state)
	if _has_team(bracket, pid) and _tournament_type(state) == "INTL":
		for raw in bracket:
			var m: Dictionary = raw
			for k in ["team_a", "team_b"]:
				var t: int = int(m.get(k, -1))
				if t >= 0 and t != pid and not ids.has(t):
					ids.append(t)
	else:
		for t in _league_count(state):
			if t != pid:
				ids.append(t)
	var next_id: int = next_opponent(state)
	if ids.has(next_id):
		ids.erase(next_id)
		ids.push_front(next_id)
	return ids


## My next unplayed opponent: the current tournament bracket first, then the league schedule; -1 none.
static func next_opponent(state: Dictionary) -> int:
	var pid: int = int(state.get("player_team_id", -1))
	for list in [_bracket(state), state.get("match_schedule", [])]:
		for raw in (list as Array):
			var m: Dictionary = raw
			if bool(m.get("played", false)):
				continue
			var a: int = int(m.get("team_a", -1))
			var b: int = int(m.get("team_b", -1))
			if a == pid and b >= 0:
				return b
			if b == pid and a >= 0:
				return a
	return -1


## Team short name (league or INTL) via `GameManager.team_short_name`; the id outside a game.
static func team_short(team_id: int) -> String:
	var gm: Node = _gm()
	return String(gm.team_short_name(team_id)) if gm != null else str(team_id)


## Team full name via `GameManager.team_name`; the id outside a game.
static func team_full(team_id: int) -> String:
	var gm: Node = _gm()
	return String(gm.team_name(team_id)) if gm != null else str(team_id)


# ── Internals ─────────────────────────────────────────────────────────────────
static func _bracket(state: Dictionary) -> Array:
	var t: Variant = state.get("current_tournament", null)
	if t is Dictionary:
		return (t as Dictionary).get("bracket", [])
	return []


static func _tournament_type(state: Dictionary) -> String:
	var t: Variant = state.get("current_tournament", null)
	return String((t as Dictionary).get("type", "")) if t is Dictionary else ""


static func _has_team(bracket: Array, team_id: int) -> bool:
	for raw in bracket:
		var m: Dictionary = raw
		if int(m.get("team_a", -1)) == team_id or int(m.get("team_b", -1)) == team_id:
			return true
	return false


static func _league_count(state: Dictionary) -> int:
	var gm: Node = _gm()
	if gm != null:
		return int(gm.TEAM_COUNT)
	return (state.get("league_standings", {}) as Dictionary).size()


static func _gm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("GameManager")
