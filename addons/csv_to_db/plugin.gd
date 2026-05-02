@tool
extends EditorPlugin

const CSV_DIR = "res://data/csv/"
const DB_PATH = "res://data/game.db"

# Required columns and primary key per table
const SCHEMAS: Dictionary = {
	"pilots":      {"req": ["id","name","abbrev","hp","atk","heal"],           "pk": "id"},
	"cards":       {"req": ["id","name","cost","effect_type","value"],          "pk": "id"},
	"game_config": {"req": ["key","value"],                                     "pk": "key"},
	"lane_config": {"req": ["lane_id","name","max_pilots","mid_col","mid_row"], "pk": "lane_id"},
	"players":     {"req": ["id","team_id","name","role","laning","mechanics","gamesense","teamfight","mental"], "pk": "id"},
	"mechs":       {"req": ["id","name","hp","atk","heal","move_range"],        "pk": "id"},
}

# SQLite column definitions per table
const TABLE_DEFS: Dictionary = {
	"pilots": {
		"id":     {"data_type": "int", "primary_key": true, "not_null": true},
		"name":   {"data_type": "text", "not_null": true},
		"abbrev": {"data_type": "text", "not_null": true},
		"hp":     {"data_type": "int",  "not_null": true},
		"atk":    {"data_type": "int",  "not_null": true},
		"heal":   {"data_type": "int",  "not_null": true},
	},
	"cards": {
		"id":          {"data_type": "int",  "primary_key": true, "not_null": true},
		"name":        {"data_type": "text", "not_null": true},
		"cost":        {"data_type": "int",  "not_null": true},
		"effect_type": {"data_type": "text", "not_null": true},
		"value":       {"data_type": "int",  "not_null": true},
	},
	"game_config": {
		"key":   {"data_type": "text", "primary_key": true, "not_null": true},
		"value": {"data_type": "text", "not_null": true},
	},
	"lane_config": {
		"lane_id":    {"data_type": "int",  "primary_key": true, "not_null": true},
		"name":       {"data_type": "text", "not_null": true},
		"max_pilots": {"data_type": "int",  "not_null": true},
		"mid_col":    {"data_type": "int",  "not_null": true},
		"mid_row":    {"data_type": "int",  "not_null": true},
	},
	"players": {
		"id":        {"data_type": "int",  "primary_key": true, "not_null": true},
		"team_id":   {"data_type": "int",  "not_null": true},
		"name":      {"data_type": "text", "not_null": true},
		"role":      {"data_type": "int",  "not_null": true},
		"laning":    {"data_type": "int",  "not_null": true},
		"mechanics": {"data_type": "int",  "not_null": true},
		"gamesense": {"data_type": "int",  "not_null": true},
		"teamfight": {"data_type": "int",  "not_null": true},
		"mental":    {"data_type": "int",  "not_null": true},
	},
	"mechs": {
		"id":         {"data_type": "int",  "primary_key": true, "not_null": true},
		"name":       {"data_type": "text", "not_null": true},
		"hp":         {"data_type": "int",  "not_null": true},
		"atk":        {"data_type": "int",  "not_null": true},
		"heal":       {"data_type": "int",  "not_null": true},
		"move_range": {"data_type": "int",  "not_null": true},
	},
}


func _enter_tree() -> void:
	add_tool_menu_item("Rebuild game.db", _rebuild_db)


func _exit_tree() -> void:
	remove_tool_menu_item("Rebuild game.db")


func _rebuild_db() -> void:
	print("=== Rebuild game.db: starting ===")

	# ── Step 1: Parse and validate all CSV files ──────────────────────────────
	var all_data: Dictionary = {}   # table_name → Array of Dicts
	var errors: Array = []

	for table_name in SCHEMAS.keys():
		var csv_path: String = CSV_DIR + table_name + ".csv"
		var result = _parse_csv(csv_path, table_name, SCHEMAS[table_name])
		if result is String:
			errors.append(result)
		else:
			all_data[table_name] = result

	if not errors.is_empty():
		push_error("=== game.db NOT rebuilt — validation errors: ===")
		for e in errors:
			push_error("  " + e)
		return

	# ── Step 2: Open DB, drop old tables, insert fresh data ──────────────────
	var db := SQLite.new()
	db.path = DB_PATH
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_error("Rebuild game.db: failed to open " + DB_PATH)
		return

	for table_name in SCHEMAS.keys():
		# IF EXISTS keeps the first run quiet when a new table was just added.
		db.query("DROP TABLE IF EXISTS " + table_name)
		db.create_table(table_name, TABLE_DEFS[table_name])
		var rows: Array = all_data[table_name]
		for row in rows:
			db.insert_row(table_name, row)
		print("  ✓ %s — %d rows" % [table_name, rows.size()])

	db.close_db()
	print("=== game.db rebuilt successfully at %s ===" % DB_PATH)


# Returns Array of Dicts on success, or an error String on failure.
func _parse_csv(path: String, table_name: String, schema: Dictionary) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Missing CSV: %s" % path

	var header_line: String = file.get_line().strip_edges()
	var headers: Array = header_line.split(",")
	# Trim whitespace from header names
	for i in headers.size():
		headers[i] = (headers[i] as String).strip_edges()

	# Validate required columns
	var req_cols: Array = schema["req"]
	for col in req_cols:
		if not col in headers:
			file.close()
			return "Table '%s': missing required column '%s' in %s" % [table_name, col, path]

	var pk_col: String = schema["pk"]
	var pk_index: int = headers.find(pk_col)

	var rows: Array = []
	var seen_pks: Dictionary = {}

	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty():
			continue
		var values: Array = line.split(",")
		# Pad or trim to match header count
		while values.size() < headers.size():
			values.append("")
		var row: Dictionary = {}
		for i in headers.size():
			row[headers[i]] = (values[i] as String).strip_edges()

		# Duplicate PK check
		var pk_val: String = row[pk_col]
		if pk_val in seen_pks:
			file.close()
			return "Table '%s': duplicate primary key '%s' = '%s' in %s" % [table_name, pk_col, pk_val, path]
		seen_pks[pk_val] = true

		# Cast numeric columns using TABLE_DEFS
		var col_defs: Dictionary = TABLE_DEFS[table_name]
		for col_name in col_defs.keys():
			if col_name in row:
				var dtype: String = col_defs[col_name]["data_type"]
				if dtype == "int":
					row[col_name] = int(row[col_name])
				elif dtype == "real":
					row[col_name] = float(row[col_name])
				# text stays as String

		rows.append(row)

	file.close()
	return rows
