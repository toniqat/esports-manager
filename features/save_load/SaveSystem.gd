class_name SaveSystem
extends RefCounted

# Static helpers for the title-screen save/load system.
#
# Three slots are stored as JSON files under user://saves/slot{0,1,2}.save.
# Each file holds {version, meta, season_state}. The `meta` block lets the
# title screen list slots without reconstructing the full season state.
#
# Auto-save trigger points (all wired outside this file):
#   1. SeasonHub: DRAFT → HUB transition (post-draft).
#   2. MatchFlow: right before BAN_PICK starts (pre-match).
#   3. MatchFlow: right after JUNGLE_START finishes, before BattleSim launch
#      (post-gambit). season_state.match_resume captures the locked-in match
#      state so resume re-enters MatchFlow at LAUNCH (→ BattleSim) directly.
#   4. SeasonHub: right after _consume_pending_match_result clears the
#      finished match (post-match).
# No save fires while BattleSim is running. Manual saving is not exposed.

const SAVE_DIR: String = "user://saves"
const SLOT_COUNT: int = 3
const SAVE_VERSION: int = 1


static func slot_path(idx: int) -> String:
	return "%s/slot%d.save" % [SAVE_DIR, idx]


static func ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


static func slot_exists(idx: int) -> bool:
	return FileAccess.file_exists(slot_path(idx))


# Returns Array[Dictionary] of length SLOT_COUNT. Each entry is the meta
# block ({phase, year, month, day, weekday, team_name, trophies, rank, wins,
# losses, saved_at}) or {} for empty / corrupted slots.
static func list_slots() -> Array:
	var out: Array = []
	for i in SLOT_COUNT:
		out.append(_read_slot_meta(i))
	return out


static func _read_slot_meta(idx: int) -> Dictionary:
	if not slot_exists(idx):
		return {}
	var f: FileAccess = FileAccess.open(slot_path(idx), FileAccess.READ)
	if f == null:
		return {}
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var meta: Variant = (parsed as Dictionary).get("meta", null)
	if typeof(meta) != TYPE_DICTIONARY:
		return {}
	return meta


# Save the current GameManager.season_state into slot `idx`. Returns "" on
# success or an error string. No-op (returns "") when idx < 0 — running
# Season.tscn directly without a slot selected shouldn't crash auto-save.
static func save_slot(idx: int) -> String:
	if idx < 0:
		return ""
	var gm: Node = _get_game_manager()
	if gm == null:
		return "GameManager not found"
	if not bool(gm.season_state.get("active", false)):
		return "season_state inactive — nothing to save"
	ensure_save_dir()
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"meta": _build_meta(gm),
		"season_state": _serialize_season_state(gm.season_state),
	}
	var f: FileAccess = FileAccess.open(slot_path(idx), FileAccess.WRITE)
	if f == null:
		return "Cannot open slot %d for write" % idx
	f.store_string(JSON.stringify(payload))
	f.close()
	return ""


# Read slot `idx` from disk and overwrite GameManager.season_state. Returns
# "" on success or an error string.
static func load_slot(idx: int) -> String:
	if not slot_exists(idx):
		return "Slot %d is empty" % idx
	var f: FileAccess = FileAccess.open(slot_path(idx), FileAccess.READ)
	if f == null:
		return "Cannot open slot %d for read" % idx
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return "Slot %d corrupted (not a JSON object)" % idx
	var payload: Dictionary = parsed
	var ss: Variant = payload.get("season_state", null)
	if typeof(ss) != TYPE_DICTIONARY:
		return "Slot %d corrupted (no season_state)" % idx
	var gm: Node = _get_game_manager()
	if gm == null:
		return "GameManager not found"
	gm.season_state = _deserialize_season_state(ss)
	return ""


static func delete_slot(idx: int) -> String:
	if not slot_exists(idx):
		return ""
	var err: int = DirAccess.remove_absolute(slot_path(idx))
	if err != OK:
		return "Failed to delete slot %d (err=%d)" % [idx, err]
	return ""


static func _get_game_manager() -> Node:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	return loop.root.get_node_or_null("GameManager")


# ── Serialization ────────────────────────────────────────────────────────────
# season_state mostly contains plain dicts/arrays of primitives. The only
# Resource-typed entries are PlayerData arrays (all_pilots, intl_pilots) —
# those need explicit Dict round-trip. assigned_mech is runtime-only (set in
# match flow) and is null at every phase boundary, so we don't persist it.

static func _serialize_season_state(s: Dictionary) -> Dictionary:
	return {
		"active":            bool(s.get("active", false)),
		"year":              int(s.get("year", 1)),
		"month":             int(s.get("month", 12)),
		"day":               int(s.get("day", 1)),
		"weekday":           int(s.get("weekday", 0)),
		"current_phase":     int(s.get("current_phase", 0)),
		"phase_week":        int(s.get("phase_week", 1)),
		"player_team_id":    int(s.get("player_team_id", 0)),
		"tournament_stage":  int(s.get("tournament_stage", 0)),
		"team_meta":         s.get("team_meta", []),
		"intl_team_meta":    s.get("intl_team_meta", []),
		"match_schedule":    s.get("match_schedule", []),
		"all_pilots":        _pilots_to_array(s.get("all_pilots", [])),
		"intl_pilots":       _pilots_to_array(s.get("intl_pilots", [])),
		"team_rosters":      s.get("team_rosters", {}),
		"league_standings":  s.get("league_standings", {}),
		"training_board":    s.get("training_board", []),
		"week_day":          int(s.get("week_day", -1)),
		"week_day_log":      s.get("week_day_log", {}),
		"training_exp_carry": s.get("training_exp_carry", {}),
		"phase_results":     s.get("phase_results", {}),
		"pending_match":     s.get("pending_match", null),
		"current_tournament": s.get("current_tournament", null),
		"match_resume":      s.get("match_resume", null),
	}


static func _deserialize_season_state(s: Dictionary) -> Dictionary:
	return {
		"active":            bool(s.get("active", true)),
		"year":              int(s.get("year", 1)),
		"month":             int(s.get("month", 12)),
		"day":               int(s.get("day", 1)),
		"weekday":           int(s.get("weekday", 0)),
		"current_phase":     int(s.get("current_phase", 0)),
		"phase_week":        int(s.get("phase_week", 1)),
		"player_team_id":    int(s.get("player_team_id", 0)),
		"tournament_stage":  int(s.get("tournament_stage", 0)),
		"team_meta":         s.get("team_meta", []),
		"intl_team_meta":    s.get("intl_team_meta", []),
		"match_schedule":    s.get("match_schedule", []),
		"all_pilots":        _array_to_pilots(s.get("all_pilots", [])),
		"intl_pilots":       _array_to_pilots(s.get("intl_pilots", [])),
		"team_rosters":      _int_keyed_dict_in(s.get("team_rosters", {})),
		"league_standings":  _int_keyed_dict_in(s.get("league_standings", {})),
		"training_board":    _board_in(s.get("training_board", [])),
		# 주 진행 상태 셋. 둘 다 **정수 키** dict 이라 되돌리는 손질이
		# 필요하다 — JSON 은 키를 문자열로 돌려주므로 그대로 실으면
		# `log[3]` 이 영원히 빈 배열을 돌려줘 같은 요일 훈련이 두 번 먹는다.
		"week_day":          int(s.get("week_day", -1)),
		"week_day_log":      _int_keyed_dict_in(s.get("week_day_log", {})),
		"training_exp_carry": _exp_carry_in(s.get("training_exp_carry", {})),
		"phase_results":     _int_keyed_dict_in(s.get("phase_results", {})),
		"pending_match":     s.get("pending_match", null),
		"current_tournament": s.get("current_tournament", null),
		"match_resume":      s.get("match_resume", null),
	}


## 훈련판 배치를 정수 좌표로 되돌린다. JSON 은 수를 전부 실수로 되돌려 주므로
## 그냥 실으면 `{x: 0.0, y: 0.0}` 이 되고, 그 뒤 `Vector2i(...)` 로 감싸는 자리마다
## 조용히 형변환이 한 겹 더 붙는다 — 한 자리라도 빠뜨리면 칸 비교가 어긋난다.
static func _board_in(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var d: Dictionary = r
		out.append({
			"tile": String(d.get("tile", "")),
			"x": int(d.get("x", 0)),
			"y": int(d.get("y", 0)),
		})
	return out


## 나머지 EXP 통장을 정수로 되돌린다. 바깥 키(자리 번호)도 안쪽 값(EXP)도
## JSON 을 지나면 문자열 / 실수가 된다 — 그대로 놓아두면 `total / EXP_PER_POINT`
## 이 정수 나눗셈이 아니게 돼 나머지가 조용히 사라진다.
static func _exp_carry_in(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		var pocket: Dictionary = {}
		for sk in (d[k] as Dictionary).keys():
			pocket[String(sk)] = int((d[k] as Dictionary)[sk])
		out[int(k)] = pocket
	return out


static func _pilots_to_array(pilots: Array) -> Array:
	var out: Array = []
	for p in pilots:
		out.append({
			"id": p.id, "name": p.name, "role": p.role, "team_id": p.team_id,
			"field_hit": p.field_hit, "field_eva": p.field_eva,
			"engage_hit": p.engage_hit, "engage_eva": p.engage_eva,
			"atk_growth": p.atk_growth, "hp_growth": p.hp_growth,
			# 스킬과 모브 표시도 함께 살려야 한다 — 둘 다 CSV 에서 온 값이지만
			# 세이브가 복원하는 것은 CSV 행이 아니라 이 배열이라, 빼면 이어하기한
			# 선수가 전원 스킬 없는 네임드로 부활한다.
			"skill_id": p.skill_id, "is_mob": p.is_mob,
		})
	return out


static func _array_to_pilots(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var d: Dictionary = r
		out.append(PlayerData.new(
			int(d.get("id", 0)), String(d.get("name", "")),
			int(d.get("role", 0)), int(d.get("team_id", 0)),
			int(d.get("field_hit", 50)), int(d.get("field_eva", 50)),
			int(d.get("engage_hit", 50)), int(d.get("engage_eva", 50)),
			int(d.get("atk_growth", 50)), int(d.get("hp_growth", 50)),
			int(d.get("skill_id", -1)), bool(d.get("is_mob", false))))
	return out


# JSON.stringify converts integer dict keys to strings; on parse they remain
# strings. season_state has several int-keyed dicts (team_id → standings,
# pilot_id → training week, SeasonPhase → phase_results). This rebuilds the
# int keys after a load.
static func _int_keyed_dict_in(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		out[int(k)] = d[k]
	return out


# ── Slot meta (for TitleScreen cards) ────────────────────────────────────────

static func _build_meta(gm: Node) -> Dictionary:
	var s: Dictionary = gm.season_state
	var pid: int = int(s.get("player_team_id", 0))
	var team_meta: Array = s.get("team_meta", [])
	var team_name: String = "—"
	if pid >= 0 and pid < team_meta.size():
		team_name = String((team_meta[pid] as Dictionary).get("name", "—"))

	var rank_data: Dictionary = _player_rank(s, pid)
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var saved_at: String = "%04d-%02d-%02d %02d:%02d" % [
		dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"],
	]
	# Mid-match flag: true when the slot was saved between BAN_PICK start and
	# BattleSim launch. Used by SlotCard to show an "경기 진행 중" indicator.
	var match_in_progress: bool = (s.get("match_resume", null) != null)
	return {
		"phase":     int(s.get("current_phase", 0)),
		"year":      int(s.get("year", 1)),
		"month":     int(s.get("month", 12)),
		"day":       int(s.get("day", 1)),
		"weekday":   int(s.get("weekday", 0)),
		"team_name": team_name,
		"trophies":  _count_trophies(s, pid),
		"rank":      int(rank_data.get("rank", 0)),
		"wins":      int(rank_data.get("wins", 0)),
		"losses":    int(rank_data.get("losses", 0)),
		"saved_at":  saved_at,
		"match_in_progress": match_in_progress,
	}


# Count campaign-level trophies for the player team — both league-phase
# playoff wins (`champion`) and INTL wins (`intl_champion`).
static func _count_trophies(s: Dictionary, pid: int) -> int:
	var pr: Dictionary = s.get("phase_results", {})
	var n: int = 0
	for k in pr.keys():
		var r: Dictionary = pr[k]
		if int(r.get("champion", -1)) == pid:
			n += 1
		if int(r.get("intl_champion", -1)) == pid:
			n += 1
	return n


# Mirrors LeagueManager.standings_ranked() without depending on the node
# (TitleScreen runs before SeasonHub exists).
static func _player_rank(s: Dictionary, pid: int) -> Dictionary:
	var standings: Dictionary = s.get("league_standings", {})
	var rows: Array = []
	for t in standings.keys():
		var entry: Dictionary = standings[t]
		rows.append({
			"team_id": int(t),
			"wins":    int(entry.get("wins", 0)),
			"losses":  int(entry.get("losses", 0)),
		})
	rows.sort_custom(func(a, b):
		if a["wins"] != b["wins"]:
			return a["wins"] > b["wins"]
		if a["losses"] != b["losses"]:
			return a["losses"] < b["losses"]
		return a["team_id"] < b["team_id"])
	for i in rows.size():
		if int(rows[i]["team_id"]) == pid:
			return {
				"rank":   i + 1,
				"wins":   int(rows[i]["wins"]),
				"losses": int(rows[i]["losses"]),
			}
	return {"rank": 0, "wins": 0, "losses": 0}
