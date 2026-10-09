extends Node

# Headless run simulator (T2 · docs/outgame_dev_plan.md §8 #5, §14.0).
#
# Plays N whole runs through the real season code — `GameManager.start_run`,
# a live `Season.tscn` (SeasonHub + CalendarSystem + LeagueManager +
# TournamentManager + InternationalTournament + TrainingBoard), coach training
# (`TrainingBoard.auto_arrange` + `apply_day_training` Mon–Fri), the hub's own
# match-day / week-end functions — and settles each run with the pure
# `RunResult.build_result`. Prints the distributions and, with `--out`, writes
# one CSV row per run (raw counts, so the score formula can be re-solved offline).
#
# **Never writes user://.** Runs are test runs and `season_state.run_over` is set
# right after `start_run`, so every `SeasonHub.autosave` is skipped and
# `RunResult.settle_current_run` (profile write + run file delete) is never
# called — the sim does its own `RunStats.finalize_phase` + `build_result`.
#
# Player matches skip MatchFlow / BattleSim: the outcome is the same weighted coin
# the AI-vs-AI matches use (`InternationalTournament.team_avg_stat` ratio), with the
# player's side multiplied by `--edge` (a stand-in for the player's card play / ban
# pick skill; 1.0 = plays like the AI). Stats rows are zeros like the cheat result
# (`MatchFlow._cheat_finish`); the match MVP is a random pilot of the winning side.
#
# Not simulated: press conference answers, mental incidents / evening sessions,
# finance / staff decisions (defaults stay), manager traits (test run = none),
# mastery from matches (no mech assignment).
#
# Usage (args after `--`, all optional):
#   godot --headless --path <project> res://features/meta/run_result/sim/RunSim.tscn -- \
#       --runs=200 --edge=1.6 --seed=1 --level=0 --out=C:/tmp/t2_runs.csv
#   --runs   number of runs (default 200)
#   --edge   player win-odds multiplier (default 1.0)
#   --seed   global RNG seed for match coins / setups (default 1; roster deal still uses run_seed)
#   --level  pilot level of my five (default 0; rank = stars — test run, `pilot_levels`)
#   --team   fixed team id (default: random 0..7 per run)
#   --scenario  fixed scenario id (default: random per run)
#   --no-coach  leave the training board empty (default course) instead of the coach layout
#   --out    CSV path for per-run rows (default: none)

const SEASON_SCENE: String = "res://scenes/Season.tscn"
const MAX_WEEKS: int = 80   # safety stop — a full campaign is ~50 weeks

var _opt: Dictionary = {
	"runs": 200, "edge": 1.0, "seed": 1, "level": 0, "team": -1, "scenario": -1,
	"coach": true, "out": "",
}
var _rows: Array = []


func _ready() -> void:
	_parse_args()
	_run_all.call_deferred()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s == "--no-coach":
			_opt["coach"] = false
			continue
		if not s.begins_with("--") or s.find("=") < 0:
			continue
		var k: String = s.substr(2, s.find("=") - 2)
		var v: String = s.substr(s.find("=") + 1)
		match k:
			"runs", "seed", "level", "team", "scenario":
				_opt[k] = int(v)
			"edge":
				_opt[k] = float(v)
			"out":
				_opt[k] = v


func _run_all() -> void:
	await get_tree().process_frame
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		push_error("RunSim: GameManager autoload missing")
		get_tree().quit(1)
		return
	gm.use_test_run = true
	seed(int(_opt["seed"]))
	var starters: Dictionary = _starters_by_role(gm)
	var t0: int = Time.get_ticks_msec()
	for i in int(_opt["runs"]):
		var row: Dictionary = await _one_run(gm, starters)
		if row.is_empty():
			continue
		row["run"] = i
		_rows.append(row)
		if (i + 1) % 20 == 0:
			print("RunSim: %d / %d runs (%.1fs)" % [i + 1, int(_opt["runs"]),
					(Time.get_ticks_msec() - t0) / 1000.0])
	gm.reset_season_state()
	_report()
	if String(_opt["out"]) != "":
		_write_csv(String(_opt["out"]))
	get_tree().quit(0)


# role → [pilot ids with players.starter = 1] (the 10 pilots a new profile owns).
func _starters_by_role(gm: Node) -> Dictionary:
	var out: Dictionary = {}
	var db := SQLite.new()
	db.path = gm.db_path()
	db.verbosity_level = SQLite.QUIET
	if db.open_db():
		db.query("SELECT id, role FROM players WHERE starter = 1 AND is_mob = 0 ORDER BY id")
		for r in db.query_result:
			var role: int = int(r["role"])
			if not out.has(role):
				out[role] = []
			(out[role] as Array).append(int(r["id"]))
		db.close_db()
	return out


func _make_setup(gm: Node, starters: Dictionary) -> Dictionary:
	var base: Dictionary = gm.default_run_setup(0)
	var team: int = int(_opt["team"])
	if team < 0:
		team = randi() % int(gm.TEAM_COUNT)
	var scenarios: Array = RunRules.scenarios()
	var scen: int = int(_opt["scenario"])
	if scen < 0 and not scenarios.is_empty():
		scen = int((scenarios[randi() % scenarios.size()] as Dictionary)["id"])
	var ids: Array = []
	var levels: Dictionary = {}
	for r in GameEnums.Role.size():
		var pool: Array = starters.get(r, [])
		var pid: int = int(pool[randi() % pool.size()]) if not pool.is_empty() \
				else int((base["pilot_ids"] as Array)[r])
		ids.append(pid)
		levels[str(pid)] = int(_opt["level"])
	base["team_id"] = team
	base["scenario"] = scen
	base["pilot_ids"] = ids
	base["pilot_levels"] = levels
	return base


func _one_run(gm: Node, starters: Dictionary) -> Dictionary:
	gm.reset_season_state()
	# A random starter lineup can break the scenario's salary cap — redraw the
	# lineup (team / scenario kept) a few times before giving up on this run.
	var setup: Dictionary = _make_setup(gm, starters)
	var err: String = gm.start_run(setup)
	var tries: int = 0
	while err != "" and tries < 30:
		tries += 1
		var again: Dictionary = _make_setup(gm, starters)
		again["team_id"] = setup["team_id"]
		again["scenario"] = setup["scenario"]
		err = gm.start_run(again)
	if err != "":
		push_warning("RunSim: start_run failed — " + err)
		return {}
	var s: Dictionary = gm.season_state
	s["run_over"] = true   # no autosave, no settle_current_run → user:// untouched

	var hub: SeasonHub = (load(SEASON_SCENE) as PackedScene).instantiate() as SeasonHub
	add_child(hub)
	var board: TrainingBoard = hub.get_node("TrainingBoard") as TrainingBoard
	var weeks: int = 0
	while hub._run_end_screen < 0 and weeks < MAX_WEEKS:
		weeks += 1
		if bool(_opt["coach"]):
			board.auto_arrange()
		board.reset_week_progress()
		s["week_day_log"] = {}
		for day in CalendarSystem.DAYS_PER_WEEK:
			s["week_day"] = day
			if CalendarSystem.is_training_day(day):
				(s["week_day_log"] as Dictionary)[day] = board.apply_day_training(day)
			var md: int = CalendarSystem.matchday_of(day)
			if md < 0:
				continue
			if hub.has_player_match_on_day(day):
				_play_player_match(gm, hub, md)
			hub._resolve_ai_for_matchday(md)
			if hub._run_end_screen >= 0:
				break
		if hub._run_end_screen >= 0:
			break
		hub._end_week()

	var outcome: String = RunResult.OUTCOME_CLEAR if hub._run_end_screen == SeasonHub.Screen.ENDING \
			else RunResult.OUTCOME_FAIL
	if hub._run_end_screen < 0:
		push_warning("RunSim: run hit MAX_WEEKS without an end — settled as fail")
	RunStats.finalize_phase(s, int(s.get("current_phase", 0)))
	var res: Dictionary = RunResult.build_result(s, outcome, true)
	await get_tree().process_frame   # let the hub's deferred end-screen routing run before freeing
	hub.queue_free()
	await get_tree().process_frame

	var pexp: Dictionary = res.get("pilot_exp", {})
	var pexp_sum: int = 0
	for k in pexp.keys():
		pexp_sum += int(pexp[k])
	var matches: int = ((s.get("run_stats", {}) as Dictionary).get("matches", []) as Array).size()
	return {
		"team": int(res["team_id"]), "scenario": int(res["scenario"]),
		"outcome": outcome, "phase_reached": int(res["phase_reached"]),
		"phases_cleared": int(res["phases_cleared"]), "wins": int(res["wins"]),
		"losses": int(res["losses"]), "matches": matches, "titles": int(res["titles"]),
		"weeks": weeks, "score": int(res["score"]),
		"outgame": int((res["currency"] as Dictionary)["outgame"]),
		"levelup": int((res["currency"] as Dictionary)["levelup"]),
		"rank_stone": int((res["currency"] as Dictionary).get("rank_stone", 0)),
		"manager_exp": int(res["manager_exp"]), "pass_exp": int(res["pass_exp"]),
		"pilot_exp_avg": float(pexp_sum) / maxf(1.0, float(pexp.size())),
	}


# The player's match on matchday `md`, resolved without MatchFlow — same lookup as
# `SeasonHub._launch_player_match_on_day`, result fed through the hub's normal
# consume path (`_consume_pending_match_result`: RunStats · finance · bracket signals).
func _play_player_match(gm: Node, hub: SeasonHub, md: int) -> void:
	var s: Dictionary = gm.season_state
	var pid: int = int(s["player_team_id"])
	var intl: InternationalTournament = hub.get_node("InternationalTournament") as InternationalTournament
	var tm: TournamentManager = hub.get_node("TournamentManager") as TournamentManager
	var source: String = hub._find_player_match_source(md)
	var idx: int = -1
	var enemy: int = -1
	match source:
		"intl":
			idx = intl.find_player_match_on_day_idx(md)
		"playoff":
			idx = tm.find_player_match_on_day_idx(md)
		"league":
			var sched: Array = s["match_schedule"]
			for i in sched.size():
				var m: Dictionary = sched[i]
				if bool(m["played"]) or int(m["phase"]) != int(s["current_phase"]) \
						or int(m["phase_week"]) != int(s["phase_week"]) \
						or int(m.get("matchday", 0)) != md:
					continue
				if int(m["team_a"]) == pid or int(m["team_b"]) == pid:
					idx = i
					enemy = SeasonHub._other_team(m, pid)
					break
	if idx < 0:
		return
	if source != "league":
		enemy = SeasonHub._other_team((s["current_tournament"]["bracket"] as Array)[idx], pid)

	var a: float = intl.team_avg_stat(pid) * float(_opt["edge"])
	var b: float = intl.team_avg_stat(enemy)
	var won: bool = randf() * (a + b) < a if a + b > 0.0 else true
	var winner_side: int = 0 if won else 1

	var rows: Array = []
	var side_ids: Array = [[], []]
	for side in 2:
		var team_id: int = pid if side == 0 else enemy
		var pool: Array = s.get("intl_pilots", []) if team_id >= 100 else s.get("all_pilots", [])
		for raw in pool:
			var pd := raw as PlayerData
			if pd == null or pd.team_id != team_id:
				continue
			(side_ids[side] as Array).append(pd.id)
			rows.append({"pilot_id": pd.id, "side": side, "role": pd.role,
					"k": 0, "d": 0, "a": 0, "dmg": 0, "taken": 0, "care": 0,
					"turret": 0, "score": 0.0, "obj": 0, "obj_turns": []})
	var winners: Array = side_ids[winner_side]
	var mvp: int = int(winners[randi() % winners.size()]) if not winners.is_empty() else -1
	s["pending_match"] = {
		"source": source, "schedule_idx": idx, "enemy_team_id": enemy,
		"winner_side": winner_side, "pilot_stats": rows, "mvp_pilot_id": mvp,
	}
	hub._consume_pending_match_result()


# ── Report ───────────────────────────────────────────────────────────────────
func _report() -> void:
	var n: int = _rows.size()
	if n == 0:
		print("RunSim: no runs")
		return
	print("")
	print("=== RunSim: %d runs · edge %.2f · level %d · coach %s · seed %d ===" % [
			n, float(_opt["edge"]), int(_opt["level"]), str(_opt["coach"]), int(_opt["seed"])])
	var phase_hist: Dictionary = {}
	var clears: int = 0
	for r in _rows:
		var key: String = "clear" if String(r["outcome"]) == "clear" else str(int(r["phase_reached"]))
		phase_hist[key] = int(phase_hist.get(key, 0)) + 1
		if String(r["outcome"]) == "clear":
			clears += 1
	print("phase_reached (fail) / clear:")
	for k in ["0", "1", "2", "3", "4", "5", "clear"]:
		var c: int = int(phase_hist.get(k, 0))
		print("  %-6s %4d  %5.1f%%" % [k, c, 100.0 * c / n])
	for f in ["phases_cleared", "phase_reached", "wins", "losses", "matches", "titles", "weeks",
			"score", "outgame", "levelup", "rank_stone", "manager_exp", "pass_exp", "pilot_exp_avg"]:
		var vals: Array = []
		for r in _rows:
			vals.append(float(r[f]))
		vals.sort()
		print("  %-15s mean %8.2f  p10 %7.1f  p50 %7.1f  p90 %7.1f  max %7.1f" % [
				f, _mean(vals), _pct(vals, 0.1), _pct(vals, 0.5), _pct(vals, 0.9), vals.back()])
	# clear-run averages (if any) — the "clear score ≈ 5× average" check.
	if clears > 0:
		var cs: Array = []
		var cw: Array = []
		for r in _rows:
			if String(r["outcome"]) == "clear":
				cs.append(float(r["score"]))
				cw.append(float(r["wins"]))
		print("  clear runs: %d · mean score %.1f · mean wins %.1f" % [clears, _mean(cs), _mean(cw)])
	# Targets (§14.0) with the current const values, on two bases:
	#   "avg run" = runs that **failed at phase 1 or 2** — the plan's "average run
	#   (phase 1~2 reached)", the basis the constants are solved on (docs/run_balance.md);
	#   "all"     = every simulated run (the expected pace of this --edge player).
	var avg_rows: Array = []
	for r in _rows:
		if String(r["outcome"]) != "clear" and int(r["phase_reached"]) in [1, 2]:
			avg_rows.append(r)
	var mgr25: int = _manager_exp_at(ConstTable.int_of("PRESTIGE_LEVEL"))
	var pass_need: int = (ConstTable.int_of("PASS_MAX_LEVEL") - 1) * ConstTable.int_of("PASS_EXP_PER_LEVEL")
	# Pilot target = the rank-1 ladder (Lv0 → level cap of rank 1; EXP restarts every rank).
	var pmax: int = RunRules.level_cap(1)
	print("targets (current consts) — avg run n=%d / all n=%d:" % [avg_rows.size(), n])
	for basis in [["avg run", avg_rows], ["all", _rows]]:
		var rows: Array = basis[1]
		if rows.is_empty():
			continue
		var m_score: float = _mean(_col("score", rows))
		print("  [%s] mean score %.1f" % [basis[0], m_score])
		print("    outgame / GACHA_PILOT_PRICE      = %.2f   (target ≈ 1)" % [
				_mean(_col("outgame", rows)) / maxf(1.0, ConstTable.num("GACHA_PILOT_PRICE"))])
		print("    runs to manager Lv%d (%d exp)  = %.1f   (target ≈ 40)" % [
				ConstTable.int_of("PRESTIGE_LEVEL"), mgr25, mgr25 / maxf(0.001, _mean(_col("manager_exp", rows)))])
		print("    runs to pass Lv%d (%d exp)      = %.1f   (target ≈ 7)" % [
				ConstTable.int_of("PASS_MAX_LEVEL"), pass_need, pass_need / maxf(0.001, _mean(_col("pass_exp", rows)))])
		print("    runs to pilot Lv%d (%d exp)     = %.1f   (target ≈ 15)" % [
				pmax, RunRules.exp_required(pmax), RunRules.exp_required(pmax) / maxf(0.001, _mean(_col("pilot_exp_avg", rows)))])
		if clears > 0:
			var cs: Array = []
			for r in _rows:
				if String(r["outcome"]) == "clear":
					cs.append(float(r["score"]))
			print("    clear score / mean score         = %.2f   (target ≈ 5)" % [_mean(cs) / maxf(0.001, m_score)])


func _manager_exp_at(level: int) -> int:
	var db := SQLite.new()
	db.path = GameDb.path()
	db.verbosity_level = SQLite.QUIET
	var out: int = 0
	if db.open_db():
		db.query("SELECT exp_required FROM manager_levels WHERE level = %d" % level)
		if not db.query_result.is_empty():
			out = int(db.query_result[0]["exp_required"])
		db.close_db()
	return out


func _col(f: String, rows: Array = []) -> Array:
	var out: Array = []
	for r in (rows if not rows.is_empty() else _rows):
		out.append(float(r[f]))
	return out


static func _mean(vals: Array) -> float:
	if vals.is_empty():
		return 0.0
	var t: float = 0.0
	for v in vals:
		t += float(v)
	return t / vals.size()


static func _pct(sorted_vals: Array, q: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	return float(sorted_vals[clampi(int(floor(q * (sorted_vals.size() - 1))), 0, sorted_vals.size() - 1)])


func _write_csv(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("RunSim: cannot write %s" % path)
		return
	var cols: Array = ["run", "team", "scenario", "outcome", "phase_reached", "phases_cleared",
			"wins", "losses", "matches", "titles", "weeks", "score", "outgame", "levelup",
			"rank_stone", "manager_exp", "pass_exp", "pilot_exp_avg"]
	f.store_line(",".join(cols))
	for r in _rows:
		var vals: PackedStringArray = []
		for c in cols:
			vals.append(str(r[c]))
		f.store_line(",".join(vals))
	f.close()
	print("RunSim: wrote %d rows → %s" % [_rows.size(), path])
