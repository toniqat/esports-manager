extends Node

# ── Match Context (populated by MatchFlow, consumed by BattleSim) ─────────────
# Empty (active=false) when running BattleSim standalone — BattleSim falls back
# to ROLE_STATS in that case.
var match_ctx: Dictionary = {
	"active": false,
	"player_roster": [],       # Array[PlayerData], one per role 0..4 (assigned_mech set)
	"enemy_roster":  [],       # Array[PlayerData], one per role 0..4 (assigned_mech set)
	"jungle_start_dir": GameEnums.JungleStartDir.LEFT,
	"player_side":   GameEnums.DraftSide.BLUE,
	"banned_mech_ids": [],     # Array[int]
	"all_mechs":      [],      # Array[MechData]
}


func reset_match_ctx() -> void:
	match_ctx = {
		"active": false,
		"player_roster": [],
		"enemy_roster":  [],
		"jungle_start_dir": GameEnums.JungleStartDir.LEFT,
		"player_side":   GameEnums.DraftSide.BLUE,
		"banned_mech_ids": [],
		"all_mechs":      [],
	}


# ── Season State (populated by Season hub, persists across MatchFlow→BattleSim) ─
# A whole campaign lives here: pilot pool, calendar, current phase, league
# standings, training schedules. Reset at game-over or new game.
const TEAM_COUNT: int = 8
const PLAYOFF_TEAMS: int = 4

var season_state: Dictionary = {
	"active": false,
	"year": 1,
	"month": 12,                  # campaign starts in December
	"day": 1,
	"weekday": 0,                 # 0=Mon ... 6=Sun
	"current_phase": GameEnums.SeasonPhase.PRESEASON,
	"phase_week": 1,              # week index inside current phase
	"player_team_id": 0,
	"all_pilots": [],             # Array[PlayerData] — full 40-pilot pool, loaded from DB
	"team_meta": [],              # Array[{id, name, short_name}] indexed by team_id
	"team_rosters": {},           # team_id (int) -> Array[int] of pilot ids
	"league_standings": {},       # team_id (int) -> {"wins": int, "losses": int}
	"match_schedule": [],         # Array of {phase, year, month, day, weekday, round, team_a, team_b, played, winner}
	"training_schedule": {},      # pilot_id (int) -> Array[7] of GameEnums.TrainingType
	"tournament_stage": GameEnums.TournamentStage.LEAGUE,
	"phase_results": {},          # SeasonPhase -> {made_playoffs:bool, champion:int, intl_played:bool, intl_champion:int}
	# Active player match in flight across Season → MatchFlow → BattleSim → Season.
	# null when no match is being played. Shape:
	#   {schedule_idx: int, enemy_team_id: int, winner_side: int, source: String}
	# source: "league" (match_schedule entry), "playoff" (current_tournament.bracket entry),
	#   or "intl" (current_tournament.bracket — same shape, different bootstrap path).
	# winner_side: -1 = match not yet resolved, 0 = player team, 1 = enemy team.
	"pending_match": null,
	# Active playoff bracket inside the current league phase (Phase 7) OR active
	# INTL bracket during an *_INTL phase (Phase 8). null during regular-season
	# weeks. Shape:
	#   {type, phase_at_start, stage, bracket: Array}
	# Each bracket entry: {slot, round, team_a, team_b, year, month, day, weekday, played, winner}.
	# Playoff: 3 slots (0=SF1, 1=SF2, 2=F). INTL: 7 slots (0..3=QF, 4..5=SF, 6=F).
	"current_tournament": null,
	# Phase 8 — INTL pool. Loaded once at init_season(). 4 virtual external-region
	# teams (id 100..103) with 5 pilots each (id 100..119). Used to seed the INTL
	# bracket (4 league qualifiers + 4 INTL teams = 8) and to draft enemy rosters
	# in MatchFlow when the opponent is an INTL team.
	"intl_team_meta": [],         # Array[{id, name, short_name}] (4 entries, sorted by id)
	"intl_pilots": [],            # Array[PlayerData] (20 entries)
	# Mid-match resume snapshot. Non-null only between the pre-ban-pick save
	# (MatchFlow entry) and the post-match save (return to Season). Lets the
	# title-screen "이어하기" path drop the player back into MatchFlow at the
	# right phase. Shape:
	#   {phase: int (MatchPhase.BAN_PICK or LAUNCH),
	#    player_side: int,
	#    banned_mech_ids: Array[int],
	#    player_picked_mech_ids: Array[int],
	#    enemy_picked_mech_ids: Array[int],
	#    player_assigned_mech_ids: Array[int] (5, sorted by role 0..4),
	#    enemy_assigned_mech_ids: Array[int] (5, sorted by role 0..4),
	#    jungle_start_dir: int}
	# Only `phase` and `player_side` are required at BAN_PICK; the other fields
	# are filled in at the post-gambit save.
	"match_resume": null,
}


func reset_season_state() -> void:
	season_state = {
		"active": false,
		"year": 1,
		"month": 12,
		"day": 1,
		"weekday": 0,
		"current_phase": GameEnums.SeasonPhase.PRESEASON,
		"phase_week": 1,
		"player_team_id": 0,
		"all_pilots": [],
		"team_meta": [],
		"team_rosters": {},
		"league_standings": {},
		"match_schedule": [],
		"training_schedule": {},
		"tournament_stage": GameEnums.TournamentStage.LEAGUE,
		"phase_results": {},
		"pending_match": null,
		"current_tournament": null,
		"intl_team_meta": [],
		"intl_pilots": [],
		"match_resume": null,
	}


# Loads the 40-pilot pool, builds per-team rosters keyed by team_id, primes
# empty league standings + default training schedules. Returns "" on success
# or an error string. Caller (Season hub) is responsible for marking active.
func init_season(player_team_id: int = 0) -> String:
	reset_season_state()
	var data := load_match_data()
	if data.has("error"):
		return data["error"]
	var pilots: Array = data["players"]
	if pilots.size() != TEAM_COUNT * 5:
		return "Expected %d pilots, got %d — rebuild game.db" % [TEAM_COUNT * 5, pilots.size()]

	season_state["all_pilots"] = pilots
	season_state["player_team_id"] = player_team_id
	season_state["team_meta"] = _load_team_meta()
	var intl: Dictionary = _load_intl_pool()
	season_state["intl_team_meta"] = intl["teams"]
	season_state["intl_pilots"]    = intl["pilots"]

	# Build team_rosters
	var rosters: Dictionary = {}
	for t in TEAM_COUNT:
		rosters[t] = []
	for p in pilots:
		rosters[p.team_id].append(p.id)
	season_state["team_rosters"] = rosters

	# Empty league standings
	var standings: Dictionary = {}
	for t in TEAM_COUNT:
		standings[t] = {"wins": 0, "losses": 0}
	season_state["league_standings"] = standings

	# Default training schedule: all REST. Detailed defaults filled later by
	# TrainingScheduler when the player enters the training screen.
	var sched: Dictionary = {}
	for p in pilots:
		var week: Array = []
		for d in 7:
			week.append(GameEnums.TrainingType.REST)
		sched[p.id] = week
	season_state["training_schedule"] = sched

	season_state["active"] = true
	return ""


# Loads players + mechs from game.db. Returns {"players": Array[PlayerData], "mechs": Array[MechData]}.
# On failure returns {"error": String}.
func load_match_data() -> Dictionary:
	var db := SQLite.new()
	db.path = "res://data/game.db"
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		return {"error": "Cannot open res://data/game.db"}

	db.query("SELECT * FROM players ORDER BY team_id, role")
	if db.query_result.is_empty():
		db.close_db()
		return {"error": "players table empty — rebuild game.db"}
	var players: Array = []
	for row in db.query_result:
		players.append(PlayerData.new(
			int(row["id"]), row["name"], int(row["role"]), int(row["team_id"]),
			int(row["laning"]), int(row["mechanics"]), int(row["gamesense"]),
			int(row["teamfight"]), int(row["mental"])))

	db.query("SELECT * FROM mechs ORDER BY id")
	if db.query_result.is_empty():
		db.close_db()
		return {"error": "mechs table empty — rebuild game.db"}
	var mechs: Array = []
	for row in db.query_result:
		mechs.append(MechData.new(
			int(row["id"]), row["name"],
			int(row["hp"]), int(row["atk"]),
			int(row.get("presence", 4)), int(row.get("speed", 70))))

	db.close_db()
	return {"players": players, "mechs": mechs}


# Loads the 8-team metadata list from game.db. Returns an Array indexed by
# team_id (0..7) of {id, name, short_name} dicts. Falls back to a synthesized
# placeholder list if the table is missing (e.g. before first Rebuild game.db).
func _load_team_meta() -> Array:
	var fallback: Array = []
	for t in TEAM_COUNT:
		fallback.append({"id": t, "name": "Team %d" % t, "short_name": "T%d" % t})

	var db := SQLite.new()
	db.path = "res://data/game.db"
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		return fallback

	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='teams'")
	if db.query_result.is_empty():
		db.close_db()
		return fallback

	db.query("SELECT * FROM teams ORDER BY id")
	if db.query_result.is_empty():
		db.close_db()
		return fallback

	var meta: Array = fallback.duplicate(true)
	for row in db.query_result:
		var tid: int = int(row["id"])
		if tid >= 0 and tid < meta.size():
			meta[tid] = {
				"id":         tid,
				"name":       String(row["name"]),
				"short_name": String(row["short_name"]),
			}
	db.close_db()
	return meta


# Loads the 4 INTL teams + 20 INTL pilots from game.db. Returns
# {"teams": Array[{id,name,short_name}], "pilots": Array[PlayerData]}.
# On any failure (tables missing, empty, etc.) returns a synthesized fallback
# pool so the campaign is still playable before the first Rebuild game.db.
func _load_intl_pool() -> Dictionary:
	var fallback: Dictionary = _synth_intl_pool()
	var db := SQLite.new()
	db.path = "res://data/game.db"
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		return fallback

	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='intl_teams'")
	if db.query_result.is_empty():
		db.close_db()
		return fallback
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='intl_players'")
	if db.query_result.is_empty():
		db.close_db()
		return fallback

	db.query("SELECT * FROM intl_teams ORDER BY id")
	if db.query_result.is_empty():
		db.close_db()
		return fallback
	var teams: Array = []
	for row in db.query_result:
		teams.append({
			"id":         int(row["id"]),
			"name":       String(row["name"]),
			"short_name": String(row["short_name"]),
		})

	db.query("SELECT * FROM intl_players ORDER BY team_id, role")
	if db.query_result.is_empty():
		db.close_db()
		return fallback
	var pilots: Array = []
	for row in db.query_result:
		pilots.append(PlayerData.new(
			int(row["id"]), row["name"], int(row["role"]), int(row["team_id"]),
			int(row["laning"]), int(row["mechanics"]), int(row["gamesense"]),
			int(row["teamfight"]), int(row["mental"])))
	db.close_db()
	return {"teams": teams, "pilots": pilots}


# Synthesized 4-team / 20-pilot INTL pool (avg stat ~80, mild tier spread).
# Used only when the intl_* tables are missing — a real campaign reads from DB.
func _synth_intl_pool() -> Dictionary:
	var role_names: Array = ["Top", "Jng", "Mid", "Sup", "Adc"]
	var team_names: Array = [
		{"id": 100, "name": "Intl Alpha",  "short_name": "IA"},
		{"id": 101, "name": "Intl Bravo",  "short_name": "IB"},
		{"id": 102, "name": "Intl Charlie","short_name": "IC"},
		{"id": 103, "name": "Intl Delta",  "short_name": "ID"},
	]
	var tier_avg: Array = [86, 80, 78, 72]   # one tier per team, descending
	var pilots: Array = []
	var pid: int = 100
	for ti in 4:
		var avg: int = tier_avg[ti]
		for r in 5:
			pilots.append(PlayerData.new(pid, "%s %s" % [team_names[ti]["short_name"], role_names[r]],
					r, team_names[ti]["id"],
					avg, avg, avg, avg, avg))
			pid += 1
	return {"teams": team_names, "pilots": pilots}


# ── Save System ──────────────────────────────────────────────────────────────
# Set by TitleScreen when the player picks a slot. SaveSystem.save_slot uses
# this on every phase-boundary auto-save. -1 means "no slot" (e.g. running
# Season.tscn directly from the editor) — auto-save becomes a no-op.
var active_save_slot: int = -1


# ── Card Pool (used by CardPhaseManager in battle sim) ────────────────────────
# Each entry mirrors a row from the cards table. CardPhaseManager pulls 6 random
# entries per pilot at match start, wraps each in a CardData instance, and tags
# it with the owning PilotData (시전자 rule).
var card_pool_bs: Array = []  # Array of {id,name,cost,uses,cast_method,target,cast_range,area,keyword,effect,description,scope,pool}


func _ready() -> void:
	_load_card_pool_bs()


func _load_card_pool_bs() -> void:
	var db := SQLite.new()
	db.path = "res://data/game.db"
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_error("GameManager: cannot open data/game.db")
		return
	db.query("SELECT * FROM cards ORDER BY id")
	for row in db.query_result:
		card_pool_bs.append({
			"id":          int(row["id"]),
			"name":        String(row["name"]),
			"cost":        int(row["cost"]),
			"uses":        int(row["uses"]),
			"cast_method": String(row["cast_method"]),
			"target":      String(row["target"]),
			"cast_range":  int(row["cast_range"]),
			"area":        int(row["area"]),
			"keyword":     String(row["keyword"]),
			"effect":      String(row["effect"]),
			"description": String(row["description"]),
			# scope / pool are read with defaults so a game.db built before these
			# columns existed still loads — every card just reads as "any / in pool".
			"scope":       String(row.get("scope", "any")),
			"pool":        int(row.get("pool", 1)),
		})
	db.close_db()
	print("GameManager: card pool loaded — %d cards" % card_pool_bs.size())
