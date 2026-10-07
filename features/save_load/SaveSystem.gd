class_name SaveSystem
extends RefCounted

# Static helpers for the run save (one in-progress run at a time).
#
# The run lives in a single JSON file, user://run.save, holding
# {version, meta, season_state}. The `meta` block lets the lobby show the
# "이어하기" (continue) card without reconstructing the full season state.
# Account-level progress is NOT here — it lives in user://profile.save
# (autoload ProfileManager).
#
# Test run file: GameManager.use_test_run defaults to true, so running
# Season.tscn / MatchFlow.tscn directly from the editor autosaves into
# user://run_test.save instead of the real run. The lobby sets it to false.
#
# Old 3-slot files (user://saves/slot*.save) are ignored — no migration.
#
# Auto-save trigger points (all wired outside this file):
#   1. SeasonHub: first HUB entry after GameManager.start_run (post-run-start).
#   2. MatchFlow: right before BAN_PICK starts (pre-match).
#   3. MatchFlow: right after ban/pick + mech assignment, before BattleSim
#      launch (post-ban-pick). season_state.match_resume captures the locked-in
#      match state so resume re-enters MatchFlow at LAUNCH (→ BattleSim) directly.
#   4. SeasonHub: right after _consume_pending_match_result clears the
#      finished match (post-match).
# No save fires while BattleSim is running. Manual saving is not exposed.
# The run file is deleted when the run is settled (RunResult.settle_current_run —
# ENDING / GAME_OVER entry or a lobby abandon).

const RUN_PATH: String = "user://run.save"
const TEST_RUN_PATH: String = "user://run_test.save"
# 2 — l10n (설계서 D7): 표시 문자열 사본을 빼고 id · l10n key 만 저장한다(선수
# `name_key`, `team_meta` `name_key` / `short_name_key`, 메타 `team_id`). 다른 버전의
# 런 파일은 읽지 않는다 — `has_run` 이 false, `load_run` 이 오류(새 런 필요).
const SAVE_VERSION: int = 2


# The file every run read / write goes to — the hidden test run when
# GameManager.use_test_run is set (direct editor runs), else the real run.
static func run_path() -> String:
	var gm: Node = _get_game_manager()
	if gm != null and bool(gm.use_test_run):
		return TEST_RUN_PATH
	return RUN_PATH


static func has_run() -> bool:
	return not _read_payload().is_empty()


# Returns the run's meta block ({phase, year, month, day, weekday, team_id,
# trophies, rank, wins, losses, saved_at, match_in_progress, scenario}) or {}
# when there is no run / the file is corrupted / another save version. Ids only —
# the lobby resolves names (`GameManager.team_name`).
static func read_run_meta() -> Dictionary:
	var payload: Dictionary = _read_payload()
	var meta: Variant = payload.get("meta", null)
	if typeof(meta) != TYPE_DICTIONARY:
		return {}
	return meta


# Save the current GameManager.season_state into the run file. Returns "" on
# success or an error string.
static func save_run() -> String:
	var gm: Node = _get_game_manager()
	if gm == null:
		return "GameManager not found"
	if not bool(gm.season_state.get("active", false)):
		return "season_state inactive — nothing to save"
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"meta": _build_meta(gm),
		"season_state": _serialize_season_state(gm.season_state),
	}
	var path: String = run_path()
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Cannot open %s for write (err=%d)" % [path, FileAccess.get_open_error()]
	f.store_string(JSON.stringify(payload))
	f.close()
	return ""


# Read the run file and overwrite GameManager.season_state. Returns "" on
# success or an error string.
static func load_run() -> String:
	var path: String = run_path()
	if not FileAccess.file_exists(path):
		return "No run saved (%s)" % path
	var payload: Dictionary = _read_payload()
	if payload.is_empty():
		return "Run file corrupted or old save version (need %d) — start a new run" % SAVE_VERSION
	var ss: Variant = payload.get("season_state", null)
	if typeof(ss) != TYPE_DICTIONARY:
		return "Run file corrupted (no season_state)"
	var gm: Node = _get_game_manager()
	if gm == null:
		return "GameManager not found"
	gm.season_state = _deserialize_season_state(ss)
	return ""


static func delete_run() -> String:
	var path: String = run_path()
	if not FileAccess.file_exists(path):
		return ""
	var err: int = DirAccess.remove_absolute(path)
	if err != OK:
		return "Failed to delete run (err=%d)" % err
	return ""


# Parsed run file, or {} when missing / unreadable / not a JSON object.
static func _read_payload() -> Dictionary:
	var path: String = run_path()
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	# 다른 세이브 버전(예: 이름 사본을 든 v1)은 없는 런으로 본다 — 마이그레이션 없음.
	if int((parsed as Dictionary).get("version", 0)) != SAVE_VERSION:
		return {}
	return parsed


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
		# 런 단위 상태(M1/M2). 모두 **문자열 키** 딕셔너리라 그대로 왕복한다.
		"run_seed":          int(s.get("run_seed", 0)),
		"run_setup":         s.get("run_setup", {}),
		"run_stats":         s.get("run_stats", {}),
		"run_over":          bool(s.get("run_over", false)),
		# M3~M7 — 문자열 키만 쓰므로 그대로 왕복한다(§11). 깊은 사본은 세이브
		# 도중 원본이 바뀌어도 쓰는 내용이 흔들리지 않게.
		"staff_mods":        (s.get("staff_mods", []) as Array).duplicate(true),
		"pilot_mods":        (s.get("pilot_mods", []) as Array).duplicate(true),
		"mech_mastery":      (s.get("mech_mastery", {}) as Dictionary).duplicate(true),
		"mastery_research":  (s.get("mastery_research", {}) as Dictionary).duplicate(true),
		"quirks":            (s.get("quirks", {}) as Dictionary).duplicate(true),
		"finance":           (s.get("finance", {}) as Dictionary).duplicate(true),
		"trust":             (s.get("trust", {}) as Dictionary).duplicate(true),
		"outings":           (s.get("outings", {}) as Dictionary).duplicate(true),
		"mental":            (s.get("mental", {}) as Dictionary).duplicate(true),
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
		"team_rosters":      _rosters_in(s.get("team_rosters", {})),
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
		"run_seed":          int(s.get("run_seed", 0)),
		"run_setup":         _run_setup_in(s.get("run_setup", {})),
		"run_stats":         s.get("run_stats", {}),
		"run_over":          bool(s.get("run_over", false)),
		# M3~M7 — 문자열 키만 쓰므로 그대로 왕복한다(§11). 깊은 사본은 세이브
		# 도중 원본이 바뀌어도 쓰는 내용이 흔들리지 않게.
		"staff_mods":        (s.get("staff_mods", []) as Array).duplicate(true),
		"pilot_mods":        (s.get("pilot_mods", []) as Array).duplicate(true),
		"mech_mastery":      (s.get("mech_mastery", {}) as Dictionary).duplicate(true),
		"mastery_research":  (s.get("mastery_research", {}) as Dictionary).duplicate(true),
		"quirks":            (s.get("quirks", {}) as Dictionary).duplicate(true),
		"finance":           (s.get("finance", {}) as Dictionary).duplicate(true),
		"trust":             (s.get("trust", {}) as Dictionary).duplicate(true),
		"outings":           (s.get("outings", {}) as Dictionary).duplicate(true),
		"mental":            (s.get("mental", {}) as Dictionary).duplicate(true),
	}


## 런 설정 스냅샷(`GameManager.start_run`, 계획서 §10.2)을 정수로 되돌린다.
## JSON 을 지나면 `pilot_ids` 가 실수 배열이 되는데, 그대로 두면
## `pilot_ids.has(pd.id)` 같은 비교가 조용히 false 가 된다. `pilot_levels` 는
## 원래 문자열 키라 키는 그대로, 값만 정수로 돌린다. 옛 세이브(빈 딕셔너리)는 빈 채로.
static func _run_setup_in(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {}
	var out: Dictionary = d.duplicate(true)
	for key in ["scenario", "team_id", "salary_cap", "salary_total", "manager_type",
			"preset", "bonus_points"]:
		if out.has(key):
			out[key] = int(out[key])
	var ids: Array = []
	for raw in (d.get("pilot_ids", []) as Array):
		ids.append(int(raw))
	out["pilot_ids"] = ids
	var levels: Dictionary = {}
	var raw_levels: Dictionary = d.get("pilot_levels", {})
	for k in raw_levels.keys():
		levels[str(k)] = int(raw_levels[k])
	out["pilot_levels"] = levels
	# M3 — 감독 스탯 · 스태프 스냅샷(`StaffSystem.snapshot_for_run`).
	var mstats: Dictionary = {}
	var raw_mstats: Dictionary = d.get("manager_stats", {})
	for k in raw_mstats.keys():
		mstats[str(k)] = int(raw_mstats[k])
	out["manager_stats"] = mstats
	var staff: Array = []
	for raw in (d.get("staff", []) as Array):
		var e: Dictionary = (raw as Dictionary).duplicate(true)
		e["id"] = int(e.get("id", 0))
		e["salary"] = int(e.get("salary", 0))
		var st: Dictionary = {}
		var raw_st: Dictionary = e.get("stats", {})
		for k in raw_st.keys():
			st[str(k)] = int(raw_st[k])
		e["stats"] = st
		staff.append(e)
	out["staff"] = staff
	# M8 — equipped traits (ids) · M10 — breakthrough stages of my five.
	var traits: Array = []
	for raw in (d.get("traits", []) as Array):
		traits.append(int(raw))
	out["traits"] = traits
	var bts: Dictionary = {}
	var raw_bts: Dictionary = d.get("pilot_breakthrough", {})
	for k in raw_bts.keys():
		bts[str(k)] = int(raw_bts[k])
	out["pilot_breakthrough"] = bts
	return out


## team_id(int) → Array[int]. 키도 값도 JSON 을 지나며 문자열 / 실수가 된다 —
## 값이 실수로 남으면 `roster.has(pilot_id)` 가 정수 id 를 못 찾는다.
static func _rosters_in(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		var ids: Array = []
		for raw in (d[k] as Array):
			ids.append(int(raw))
		out[int(k)] = ids
	return out


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
			"id": p.id, "name_key": p.name_key, "role": p.role, "team_id": p.team_id,
			"field_hit": p.field_hit, "field_eva": p.field_eva,
			"engage_hit": p.engage_hit, "engage_eva": p.engage_eva,
			"atk_growth": p.atk_growth, "hp_growth": p.hp_growth,
			# 스킬과 모브 표시도 함께 살려야 한다 — 둘 다 CSV 에서 온 값이지만
			# 세이브가 복원하는 것은 CSV 행이 아니라 이 배열이라, 빼면 이어하기한
			# 선수가 전원 스킬 없는 네임드로 부활한다.
			"skill_id": p.skill_id, "is_mob": p.is_mob,
			# 고정 파일럿 카드 3장. 옛 세이브에는 없다 — 그때는 비어 있는 채로
			# 복원되고 `GameManager.pilot_card_ids_for` 가 DB 의 같은 선수 행에서 채운다.
			"pilot_cards": p.pilot_cards.duplicate(),
			# 런 준비 — Lv1 샐러리 · 등급 · 이 런의 레벨(스탯은 이미 레벨 반영 값).
			"salary": p.salary, "rarity": p.rarity, "level": p.level,
			"main_mechs": p.main_mechs.duplicate(),
			# M10 — breakthrough (effects already folded into the fields above).
			"breakthrough": p.breakthrough, "train_bonus_pct": p.train_bonus_pct,
		})
	return out


static func _array_to_pilots(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var d: Dictionary = r
		var pd := PlayerData.new(
			int(d.get("id", 0)), String(d.get("name_key", "")),
			int(d.get("role", 0)), int(d.get("team_id", 0)),
			int(d.get("field_hit", 50)), int(d.get("field_eva", 50)),
			int(d.get("engage_hit", 50)), int(d.get("engage_eva", 50)),
			int(d.get("atk_growth", 50)), int(d.get("hp_growth", 50)),
			int(d.get("skill_id", -1)), bool(d.get("is_mob", false)))
		# JSON 은 숫자를 float 로 돌려준다 — 카드 id 는 int 로 되돌린다.
		for raw_id in (d.get("pilot_cards", []) as Array):
			pd.pilot_cards.append(int(raw_id))
		pd.salary = int(d.get("salary", 0))
		pd.rarity = int(d.get("rarity", 0))
		pd.level = int(d.get("level", 1))
		for raw_mech in (d.get("main_mechs", []) as Array):
			pd.main_mechs.append(int(raw_mech))
		pd.breakthrough = int(d.get("breakthrough", 0))
		pd.train_bonus_pct = int(d.get("train_bonus_pct", 0))
		out.append(pd)
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


# ── Run meta (for the lobby continue card) ──────────────────────────────────

static func _build_meta(gm: Node) -> Dictionary:
	var s: Dictionary = gm.season_state
	var pid: int = int(s.get("player_team_id", 0))

	var rank_data: Dictionary = _player_rank(s, pid)
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var saved_at: String = "%04d-%02d-%02d %02d:%02d" % [
		dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"],
	]
	# Mid-match flag: true when the run was saved between BAN_PICK start and
	# BattleSim launch. The lobby shows an "경기 진행 중" indicator for it.
	var match_in_progress: bool = (s.get("match_resume", null) != null)
	# 런 시나리오 id(§10.2 run_setup). 런 설정이 없으면 -1. 이름은 저장하지 않는다(D7) —
	# 화면이 `RunRules.scenario(id).name_key` 로 푼다.
	var run_setup: Dictionary = s.get("run_setup", {})
	var scenario_id: int = int(run_setup.get("scenario", -1))
	return {
		"phase":     int(s.get("current_phase", 0)),
		"year":      int(s.get("year", 1)),
		"month":     int(s.get("month", 12)),
		"day":       int(s.get("day", 1)),
		"weekday":   int(s.get("weekday", 0)),
		"team_id":   pid,
		"trophies":  _count_trophies(s, pid),
		"rank":      int(rank_data.get("rank", 0)),
		"wins":      int(rank_data.get("wins", 0)),
		"losses":    int(rank_data.get("losses", 0)),
		"saved_at":  saved_at,
		"match_in_progress": match_in_progress,
		"scenario":  scenario_id if not run_setup.is_empty() else -1,
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
# (the lobby runs before SeasonHub exists).
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
