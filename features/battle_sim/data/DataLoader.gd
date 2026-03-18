extends Node

# Emitted if any step of DB loading fails. BattleSim shows an error screen.
signal data_load_failed(reason: String)

# ── Output properties (empty until load_data() succeeds) ─────────────────────
var game_cfg:    Dictionary = {}  # key(String) → value(String)
var pilot_stats: Dictionary = {}  # role_id(int) → {name, abbrev, hp, atk, heal}
var lane_cfg:    Array      = []  # lane_id(int) → {name, max_pilots, mid_col, mid_row}


# Called by BattleSim._ready() after signal is connected.
# Returns true on success, false on any failure (signal is also emitted).
func load_data() -> bool:
	var db := SQLite.new()
	db.path = "res://data/game.db"
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		data_load_failed.emit("Cannot open res://data/game.db — run the CSV→DB import tool first.")
		return false

	var ok: bool = true
	ok = ok and _load_game_cfg(db)
	ok = ok and _load_pilots(db)
	ok = ok and _load_lane_cfg(db)
	db.close_db()

	if not ok:
		data_load_failed.emit("One or more game_db tables failed to load. Check the DB import.")
		return false

	print("DataLoader: loaded OK — pilots:%d cfg_keys:%d lanes:%d" % [
		pilot_stats.size(), game_cfg.size(), lane_cfg.size()])
	return true


func _load_game_cfg(db: SQLite) -> bool:
	db.query("SELECT * FROM game_config")
	if db.query_result.is_empty():
		data_load_failed.emit("game_config table is empty or missing.")
		return false
	for row in db.query_result:
		game_cfg[row["key"]] = row["value"]
	return true


func _load_pilots(db: SQLite) -> bool:
	db.query("SELECT * FROM pilots ORDER BY id")
	if db.query_result.is_empty():
		data_load_failed.emit("pilots table is empty or missing.")
		return false
	for row in db.query_result:
		var rid: int = int(row["id"])
		pilot_stats[rid] = {
			"name":   row["name"],
			"abbrev": row["abbrev"],
			"hp":     int(row["hp"]),
			"atk":    int(row["atk"]),
			"heal":   int(row["heal"]),
		}
	return true


func _load_lane_cfg(db: SQLite) -> bool:
	db.query("SELECT * FROM lane_config ORDER BY lane_id")
	if db.query_result.is_empty():
		data_load_failed.emit("lane_config table is empty or missing.")
		return false
	lane_cfg.clear()
	for row in db.query_result:
		lane_cfg.append({
			"name":       row["name"],
			"max_pilots": int(row["max_pilots"]),
			"mid_col":    int(row["mid_col"]),
			"mid_row":    int(row["mid_row"]),
		})
	return true
