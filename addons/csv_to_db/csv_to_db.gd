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
	"cards":       {"req": ["id","name","cost","uses","cast_method","target","cast_range","area","keyword","effect","description","scope","pool","card_type","card_cat","excl_group"], "pk": "id"},
	"game_config": {"req": ["key","value"],                                     "pk": "key"},
	"lane_config": {"req": ["lane_id","name","max_pilots","mid_col","mid_row"], "pk": "lane_id"},
	"players":     {"req": ["id","team_id","name","role","field_hit","field_eva","engage_hit","engage_eva","atk_growth","hp_growth","skill_id","is_mob"], "pk": "id"},
	"pilot_skills": {"req": ["id","key","name","role","type","p1","p2","keyword","description"], "pk": "id"},
	"mechs":       {"req": ["id","name","role","hp","atk","presence"],          "pk": "id"},
	"mech_passives": {"req": ["id","mech_id","key","name","p1","p2","keyword","description"], "pk": "id"},
	"mech_cards":    {"req": ["id","mech_id","name","count","cost","cast_method","target","cast_range","area","keyword","charge_max","effect","trigger","description"], "pk": "id"},
	"teams":       {"req": ["id","name","short_name"],                          "pk": "id"},
	"intl_teams":   {"req": ["id","name","short_name"],                         "pk": "id"},
	"intl_players": {"req": ["id","team_id","name","role","field_hit","field_eva","engage_hit","engage_eva","atk_growth","hp_growth"], "pk": "id"},
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
		# 상호 배타 그룹. 비어 있지 않은 같은 값끼리는 **한 파일럿이 하나만**
		# 가질 수 있다 — 안전한 파밍 ↔ 공격적인 라인전이 첫 사례다. 둘은 같은
		# `lane_stat` 슬롯을 정반대 방향으로 밀어서 한 사람이 둘 다 들면 서로를
		# 지운다(나중에 낸 쪽이 덮어쓴다). CardPhaseManager._sample 이 본다.
		"excl_group":  {"data_type": "text", "not_null": true},
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
		"field_hit":  {"data_type": "int",  "not_null": true},
		"field_eva":  {"data_type": "int",  "not_null": true},
		"engage_hit": {"data_type": "int",  "not_null": true},
		"engage_eva": {"data_type": "int",  "not_null": true},
		"atk_growth": {"data_type": "int",  "not_null": true},
		"hp_growth":  {"data_type": "int",  "not_null": true},
		# 이 파일럿의 고유 파일럿 스킬 id(pilot_skills.id). -1 = 없음(모브).
		"skill_id":  {"data_type": "int",  "not_null": true},
		# 1 = 모브 파일럿 — 스킬이 없고 스탯이 네임드보다 낮으며 초상화가
		# 실루엣 컷으로 나온다(PilotImages.set_mob_ids). 스탯 하향은 런타임
		# 계수가 아니라 **CSV 값 자체**에 이미 반영돼 있다.
		"is_mob":    {"data_type": "int",  "not_null": true},
	},
	"pilot_skills": {
		"id":          {"data_type": "int",  "primary_key": true, "not_null": true},
		# 런타임 분기 키(snake_case). 스킬 하나하나가 고유 효과라 효과 문법을
		# 만드는 대신 이 키로 갈라 쓴다 — PilotSkillSystem 이 소비한다.
		"key":         {"data_type": "text", "not_null": true},
		"name":        {"data_type": "text", "not_null": true},
		# GameEnums.Role. 스킬은 라인(역할)에 묶여 있으므로 같은 역할의
		# 파일럿에게만 붙는다.
		"role":        {"data_type": "int",  "not_null": true},
		# cooldown / charge / passive
		"type":        {"data_type": "text", "not_null": true},
		# cooldown = 재사용까지의 턴 수, charge = 활성화에 드는 충전 수.
		"p1":          {"data_type": "int",  "not_null": true},
		# 최대 충전 수(0 = 충전 없음).
		"p2":          {"data_type": "int",  "not_null": true},
		"keyword":     {"data_type": "text", "not_null": true},
		"description": {"data_type": "text", "not_null": true},
	},
	"mechs": {
		"id":       {"data_type": "int",  "primary_key": true, "not_null": true},
		"name":     {"data_type": "text", "not_null": true},
		# GameEnums.Role. **메크에 역할이 생겼다** — 예전에는 "메크는 역할이
		# 없다"가 설계였지만, 메크마다 고유 패시브와 고유 카드 셋이 붙으면서
		# 그 카드들이 역할군을 전제하게 됐다(탱커의 반응 장갑 / 원딜의 사거리
		# 지정 공격 …). 배정 자체는 여전히 자유다 — 이 값은 밴픽 화면의 분류와
		# 데이터 검증용이고, 어느 슬롯에 어느 메크를 앉힐지는 막지 않는다.
		"role":     {"data_type": "int",  "not_null": true},
		"hp":       {"data_type": "int",  "not_null": true},
		"atk":      {"data_type": "int",  "not_null": true},
		# 존재감 — 전투 개시 시 타겟 어그로 가중치. 근접 메크 4, 원거리 메크 2.
		"presence": {"data_type": "int",  "not_null": true},
	},
	# ── 메크 패시브 ──────────────────────────────────────────────────────────
	# 메크 한 대에 붙는 상시 능력. pilot_skills 와 같은 형태(런타임 분기 키
	# `key` + 파라미터 p1/p2)이고 소비자는 MechSkillSystem 이다. 21대 중 15대만
	# 가지며 나머지 6대는 카드로만 논다.
	"mech_passives": {
		"id":          {"data_type": "int",  "primary_key": true, "not_null": true},
		"mech_id":     {"data_type": "int",  "not_null": true},
		"key":         {"data_type": "text", "not_null": true},
		"name":        {"data_type": "text", "not_null": true},
		# 패시브마다 뜻이 다른 두 숫자. 충전형이면 p1 = 시작 충전, p2 = 최대 충전.
		"p1":          {"data_type": "int",  "not_null": true},
		"p2":          {"data_type": "int",  "not_null": true},
		"keyword":     {"data_type": "text", "not_null": true},
		"description": {"data_type": "text", "not_null": true},
	},
	# ── 메크 카드 ────────────────────────────────────────────────────────────
	# 파일럿이 받는 **메크 카드 3장**이 사라지고, 그 자리를 배정된 메크의 고유
	# 카드 목록이 통째로 채운다. `count` 가 그 메크를 채용했을 때 덱에 들어가는
	# 장수이고 `count = 0` 인 카드는 다른 효과가 만들어 줄 때만 세상에 나온다.
	# 컬럼 구성은 cards.csv 와 나란하되 덱 슬롯(card_type/card_cat/excl_group)과
	# 시전자 제약(scope)이 없다 — 메크 카드의 임자는 메크가 정하기 때문.
	"mech_cards": {
		"id":          {"data_type": "int",  "primary_key": true, "not_null": true},
		"mech_id":     {"data_type": "int",  "not_null": true},
		"name":        {"data_type": "text", "not_null": true},
		# 채용 시 덱에 들어가는 장수. 0 = 별도 효과로만 생성된다.
		"count":       {"data_type": "int",  "not_null": true},
		# **-1 = 사용할 수 없는 카드.** 핸드에 들고 있는 것만으로 효과를 낸다
		# (캐시 · 계시 · 약자 멸시 · 밸런스). 드래그도 거부된다.
		"cost":        {"data_type": "int",  "not_null": true},
		"cast_method": {"data_type": "text", "not_null": true},
		# cards.csv 의 값에 셋이 더 붙는다 — foe(적 파일럿 또는 포탑) /
		# turret_outer(최외곽 적 포탑) / turret_any(살아 있는 적 포탑 전부).
		"target":      {"data_type": "text", "not_null": true},
		"cast_range":  {"data_type": "int",  "not_null": true},
		"area":        {"data_type": "int",  "not_null": true},
		# `|` 로 구분된 목록. exhaust / preserve / volatile 에 **charge** 가 더해졌다.
		"keyword":     {"data_type": "text", "not_null": true},
		# 충전 상한. `charge` 키워드를 단 카드만 읽는다(그 밖에는 0).
		"charge_max":  {"data_type": "int",  "not_null": true},
		"effect":      {"data_type": "text", "not_null": true},
		# 카드 자신에게 붙는 사건 훅(비어 있으면 없음). 패시브가 아니라 **그
		# 카드**가 존재를 얻는 조건이라 여기에 산다 — turret_kill_deck(꿰뚫는
		# 번개) / death_hand(공격 명령).
		"trigger":     {"data_type": "text", "not_null": true},
		"description": {"data_type": "text", "not_null": true},
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
		"field_hit":  {"data_type": "int",  "not_null": true},
		"field_eva":  {"data_type": "int",  "not_null": true},
		"engage_hit": {"data_type": "int",  "not_null": true},
		"engage_eva": {"data_type": "int",  "not_null": true},
		"atk_growth": {"data_type": "int",  "not_null": true},
		"hp_growth":  {"data_type": "int",  "not_null": true},
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
