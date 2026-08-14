@tool
extends RefCounted

# CSV → game.db 변환 로직 본체.
#
# EditorPlugin(`plugin.gd`) 에서 분리해 둔 이유: EditorPlugin 은 에디터 밖에서
# 인스턴스화할 수 없어서(`Class 'EditorPlugin' can only be instantiated by
# editor`), 로직이 그 안에 있으면 DB 를 헤드리스로 다시 만들 수 없다. 순수
# RefCounted 로 빼 두면 두 경로가 **같은 코드**를 쓴다:
#
#   에디터  : Project → Tools → Rebuild game.db  (plugin.gd 가 호출)
#   CLI     : godot --headless --path <proj> --script <SceneTree 스크립트>
#             안에서 load("res://addons/csv_to_db/csv_to_db.gd").new().rebuild()
#
# 테이블을 추가할 때는 SCHEMAS 와 TABLE_DEFS 양쪽에 항목을 넣는다.

const CSV_DIR = "res://data/csv/"
const DB_PATH = "res://data/game.db"

# Required columns and primary key per table
const SCHEMAS: Dictionary = {
	"pilots":      {"req": ["id","name","abbrev","hp","atk","heal"],           "pk": "id"},
	"cards":       {"req": ["id","name","cost","uses","cast_method","target","cast_range","area","keyword","effect","description","scope","pool","card_type","card_cat"], "pk": "id"},
	"game_config": {"req": ["key","value"],                                     "pk": "key"},
	"lane_config": {"req": ["lane_id","name","max_pilots","mid_col","mid_row"], "pk": "lane_id"},
	"players":     {"req": ["id","team_id","name","role","laning","mechanics","gamesense","teamfight","mental"], "pk": "id"},
	"mechs":       {"req": ["id","name","hp","atk","presence","speed"],         "pk": "id"},
	"teams":       {"req": ["id","name","short_name"],                          "pk": "id"},
	"intl_teams":   {"req": ["id","name","short_name"],                         "pk": "id"},
	"intl_players": {"req": ["id","team_id","name","role","laning","mechanics","gamesense","teamfight","mental"], "pk": "id"},
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
		"uses":        {"data_type": "int",  "not_null": true},
		"cast_method": {"data_type": "text", "not_null": true},
		"target":      {"data_type": "text", "not_null": true},
		"cast_range":  {"data_type": "int",  "not_null": true},
		"area":        {"data_type": "int",  "not_null": true},
		"keyword":     {"data_type": "text", "not_null": true},
		"effect":      {"data_type": "text", "not_null": true},
		"description": {"data_type": "text", "not_null": true},
		# 시전자 제약: any = 누구나, lane = 레인 파일럿 전용, jungle = 정글러 전용.
		# CardPhaseManager._deal_team_deck 가 스타터 덱을 돌릴 때 참조한다.
		"scope":       {"data_type": "text", "not_null": true},
		# 1 = 랜덤 카드풀에 포함, 0 = 제외(메크 고유 카드 등 별도 경로로만 지급).
		"pool":        {"data_type": "int",  "not_null": true},
		# 카드가 메크에 붙는가(mech) 파일럿에 붙는가(pilot). 파일럿마다 메크 3장
		# + 파일럿 3장을 받는 덱 구성의 1차 분류다.
		"card_type":   {"data_type": "text", "not_null": true},
		# 파일럿 카드의 하위 분류 — lane / draw / jungle / common. 메크 카드는 "-".
		# common 은 라인전 슬롯과 정글 슬롯 **양쪽** 후보에 들어간다(복귀).
		"card_cat":    {"data_type": "text", "not_null": true},
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
		"id":       {"data_type": "int",  "primary_key": true, "not_null": true},
		"name":     {"data_type": "text", "not_null": true},
		"hp":       {"data_type": "int",  "not_null": true},
		"atk":      {"data_type": "int",  "not_null": true},
		# 존재감 — 전투 개시 시 타겟 어그로 가중치. 근접 메크 4, 원거리 메크 2.
		"presence": {"data_type": "int",  "not_null": true},
		# 속도(40~100) — 교전 아레나의 ATB 게이지 충전 속도. 높을수록 자기 차례가
		# 빨리 돌아온다. 전장(턴제)에서는 읽지 않는다.
		"speed":    {"data_type": "int",  "not_null": true},
	},
	"teams": {
		"id":         {"data_type": "int",  "primary_key": true, "not_null": true},
		"name":       {"data_type": "text", "not_null": true},
		"short_name": {"data_type": "text", "not_null": true},
	},
	"intl_teams": {
		"id":         {"data_type": "int",  "primary_key": true, "not_null": true},
		"name":       {"data_type": "text", "not_null": true},
		"short_name": {"data_type": "text", "not_null": true},
	},
	"intl_players": {
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
}


# 전체 CSV 를 검증하고 game.db 를 다시 만든다. 성공하면 빈 문자열, 실패하면
# 사람이 읽을 수 있는 오류 문자열을 돌려준다(어느 CSV 의 어느 컬럼인지 포함).
# 검증은 **전부 통과할 때만** 쓰기로 넘어간다 — 반쯤 갱신된 DB 를 남기지 않는다.
func rebuild(verbose: bool = true) -> String:
	if verbose:
		print("=== Rebuild game.db: starting ===")

	# ── Step 1: Parse and validate all CSV files ──────────────────────────────
	var all_data: Dictionary = {}   # table_name → Array of Dicts
	var errors: Array = []

	for table_name in SCHEMAS.keys():
		var csv_path: String = CSV_DIR + table_name + ".csv"
		var result = parse_csv(csv_path, table_name, SCHEMAS[table_name])
		if result is String:
			errors.append(result)
		else:
			all_data[table_name] = result

	if not errors.is_empty():
		return "game.db NOT rebuilt — validation errors:\n  " + "\n  ".join(errors)

	# ── Step 2: Open DB, drop old tables, insert fresh data ──────────────────
	var db := SQLite.new()
	db.path = DB_PATH
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		return "Rebuild game.db: failed to open " + DB_PATH

	for table_name in SCHEMAS.keys():
		# IF EXISTS keeps the first run quiet when a new table was just added.
		db.query("DROP TABLE IF EXISTS " + table_name)
		db.create_table(table_name, TABLE_DEFS[table_name])
		var rows: Array = all_data[table_name]
		for row in rows:
			db.insert_row(table_name, row)
		if verbose:
			print("  ✓ %s — %d rows" % [table_name, rows.size()])

	db.close_db()
	if verbose:
		print("=== game.db rebuilt successfully at %s ===" % DB_PATH)
	return ""


# Returns Array of Dicts on success, or an error String on failure.
func parse_csv(path: String, table_name: String, schema: Dictionary) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Missing CSV: %s" % path

	var header_line: String = file.get_line().strip_edges()
	var headers: Array = split_csv_line(header_line)
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

	var rows: Array = []
	var seen_pks: Dictionary = {}

	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty():
			continue
		var values: Array = split_csv_line(line)
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


# Splits one CSV line into fields. Handles double-quoted fields (so descriptions
# may contain commas) and the standard "" escape for an embedded quote.
# Whitespace inside fields is preserved; outer trimming happens at the call site.
func split_csv_line(line: String) -> Array:
	var result: Array = []
	var i: int = 0
	var n: int = line.length()
	while i <= n:
		var field: String = ""
		if i < n and line[i] == "\"":
			i += 1
			while i < n:
				if line[i] == "\"":
					if i + 1 < n and line[i + 1] == "\"":
						field += "\""
						i += 2
					else:
						i += 1
						break
				else:
					field += line[i]
					i += 1
		else:
			while i < n and line[i] != ",":
				field += line[i]
				i += 1
		result.append(field)
		if i < n and line[i] == ",":
			i += 1
			if i == n:
				# Trailing comma → empty final field.
				result.append("")
				break
		else:
			break
	return result
