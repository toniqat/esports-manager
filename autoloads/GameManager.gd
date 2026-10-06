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
		# 오브젝트 오판 확률 — MatchFlow 가 상대 리그 순위로 매긴다
		# (`OBJ_MISJUDGE_MIN` ~ `OBJ_MISJUDGE_MAX`). 기본값은
		# `ObjectiveSystem.AI_MISJUDGE_DEFAULT` 와 같은 const.csv 키.
		"enemy_misjudge_chance": ConstTable.num("OBJ_AI_MISJUDGE_DEFAULT"),
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
	# 주간 훈련판 — 5열(선수, 자리 순서) × 5행(월~금)에 올려 둔 타일 목록.
	# Array of {tile: String(training_tiles.id), x: int(0..4 선수), y: int(0..4 요일)}.
	# 빈 칸은 기초 훈련(T01)이 자동으로 메우므로 목록에 적지 않는다.
	"training_board": [],
	# ── 주 진행 (시간 경과 화면) ──────────────────────────────
	# 지금 보고 있는 요일 (0 = 월 … 6 = 일). **-1 은 주가 아직 안 열렸다는
	# 뜻**이다 — 허브 · 기자회견 · 훈련 계획 구간이 전부 -1 이고, 그 값이
	# 순위표의 "확인"이 주로 돌아갈지 허브로 돌아갈지를 가른다.
	"week_day": -1,
	# 요일별 훈련 결과 기록. `day(int) → Array[{pilot_id, name, role, seat,
	# before, after, ups, exp}]`. 적으는 자리는 `TrainingBoard.apply_day_training`
	# 을 부르는 `WeekProgressView` 하나다 — 이미 있으면 다시 정산하지
	# 않으므로 경기를 치르고 같은 요일로 돌아와도 훈련이 두 번 먹지 않는다.
	"week_day_log": {},
	# 훈련 EXP 의 **나머지 통장**. `seat(int) → {stat: int}`. `TRAINING_EXP_PER_POINT`
	# (const.csv) 가 스탯 1 인데 요일마다 따로 나누면 문턱에 못 미치는 하루치가
	# 다섯 날 매일 0 점이 된다 —
	# 나머지를 다음 날로 넘겨야 다섯 날의 합이 한 주 한 번과 같아진다.
	# 주가 시작될 때 비운다(`TrainingBoard.reset_week_progress`).
	"training_exp_carry": {},
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
	# ── 런 (M1 / M2) — 계약: docs/outgame_dev_plan.md §10 ─────────────────
	# 런 시드. AI 로스터 분배 등 런 시작 때의 무작위가 모두 이 값에서 나온다.
	"run_seed": 0,
	# 런 설정 스냅샷 — 런 중 바뀌지 않는다. 모양은 §10.2:
	#   {scenario: int, team_id: int, pilot_ids: Array[int](5, 역할 순),
	#    pilot_levels: {"<pilot_id>": int}, salary_cap: int, salary_total: int}
	"run_setup": {},
	# 경기 MVP / 페이즈 POM 집계(`RunStats`). 문자열 키만 쓴다 — §10.4.
	"run_stats": {},
	# 정산이 끝난 런(`RunResult.settle_current_run`). true 면 자동 저장하지 않는다.
	"run_over": false,
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
		"training_board": [],
	"week_day": -1,
	"week_day_log": {},
	"training_exp_carry": {},
		"tournament_stage": GameEnums.TournamentStage.LEAGUE,
		"phase_results": {},
		"pending_match": null,
		"current_tournament": null,
		"intl_team_meta": [],
		"intl_pilots": [],
		"match_resume": null,
		"run_seed": 0,
		"run_setup": {},
		"run_stats": {},
		"run_over": false,
	}


# ── 런 시작 (M1) ─────────────────────────────────────────────────────────────
# 마지막으로 정산된 런의 결과 — `RunResult.settle_current_run` 이 채우고 정산
# 화면(`scenes/RunResult.tscn`)이 읽는다. 메모리에만 산다(정산은 이미 프로필에 썼다).
var last_run_result: Dictionary = {}


## 런 준비 화면(`features/meta/run_setup/`)이 부르는 **유일한 런 시작 입구**.
## `run_setup` 모양은 `docs/outgame_dev_plan.md` §10.2. 성공이면 "" — 이후
## `Season.tscn` 은 DRAFT 없이 HUB 부터 연다. 실패면 사람이 읽는 한 줄이고
## `season_state` 는 건드리지 않은(검증 실패) 또는 비운(분배 실패) 상태다.
##
## 순서: 검증(`RunRules.validate_lineup`, Lv1 풀 · 프로필 보유 레벨) → 시즌 뼈대
## (`_init_season_core`) → `run_seed` → 내 5인을 내 팀으로 · `RunRules.apply_level`
## → 나머지 선수 AI 분배(`RunRoster`) → `team_rosters` 재구성 → `run_setup` 스냅샷.
##
## 테스트 런(`use_test_run`, 에디터 직접 실행)은 프로필 보유를 보지 않는다 —
## 네임드 선수 누구나 최대 레벨까지 고를 수 있다(샐러리캡 · 역할 규칙은 그대로).
func start_run(run_setup: Dictionary) -> String:
	var data := load_match_data()
	if data.has("error"):
		return data["error"]
	var pool: Array = data["players"]
	var team_id: int = int(run_setup.get("team_id", 0))
	if team_id < 0 or team_id >= TEAM_COUNT:
		return "알 수 없는 팀 id %d" % team_id
	var scenario_id: int = int(run_setup.get("scenario", 0))
	if RunRules.scenario(scenario_id).is_empty():
		return "알 수 없는 시나리오 id %d" % scenario_id

	var pilot_ids: Array = []
	for raw in (run_setup.get("pilot_ids", []) as Array):
		pilot_ids.append(int(raw))
	var levels: Dictionary = {}
	var raw_levels: Dictionary = run_setup.get("pilot_levels", {})
	for pid in pilot_ids:
		levels[str(pid)] = int(raw_levels.get(str(pid), 1))
	var err: String = RunRules.validate_lineup(pilot_ids, levels, scenario_id, pool,
			_owned_levels_for_run(pool))
	if err != "":
		return err

	err = _init_season_core(team_id, pool)
	if err != "":
		return err
	var pilots: Array = season_state["all_pilots"]
	var run_seed: int = _fresh_run_seed()
	season_state["run_seed"] = run_seed

	var assignment: Dictionary = RunRoster.assign(pilots, team_id, pilot_ids, run_seed, TEAM_COUNT)
	if String(assignment.get("error", "")) != "":
		reset_season_state()
		return String(assignment["error"])
	RunRoster.apply(pilots, assignment["teams"])

	# 내 5인 — 레벨은 런 사본(all_pilots)에만 얹는다. 스냅샷은 역할 순으로 적는다.
	var picked: Array = []
	for raw in pilots:
		var pd := raw as PlayerData
		if pilot_ids.has(pd.id):
			RunRules.apply_level(pd, int(levels[str(pd.id)]))
			picked.append(pd)
	picked.sort_custom(func(a, b): return (a as PlayerData).role < (b as PlayerData).role)
	var ordered_ids: Array = []
	var applied_levels: Dictionary = {}
	for raw in picked:
		var pd := raw as PlayerData
		ordered_ids.append(pd.id)
		applied_levels[str(pd.id)] = pd.level
	season_state["team_rosters"] = RunRoster.build_rosters(pilots, TEAM_COUNT)

	# 캡 · 합계는 화면이 보낸 값을 믿지 않고 여기서 다시 낸다(샐러리는 Lv1 기준
	# `pd.salary` + 레벨 가산이라 레벨을 얹은 뒤에도 같은 식이 맞다).
	season_state["run_setup"] = {
		"scenario": scenario_id,
		"team_id": team_id,
		"pilot_ids": ordered_ids,
		"pilot_levels": applied_levels,
		"salary_cap": RunRules.salary_cap(scenario_id),
		"salary_total": RunRules.lineup_salary(picked, applied_levels),
	}
	return ""


## 에디터 직접 실행용 기본 편성 — 샐러리캡이 가장 높은 시나리오, `team_id` 팀,
## 역할마다 스타터(`players.starter = 1`) 중 id 가 가장 낮은 선수, 전원 Lv1.
## 스타터가 없는 역할은 그 역할의 네임드 중 id 가 가장 낮은 선수로 채운다.
func default_run_setup(team_id: int = 0) -> Dictionary:
	var scenario_id: int = 0
	var best_cap: int = -1
	for s in RunRules.scenarios():
		var cap: int = int((s as Dictionary).get("salary_cap", 0))
		if cap > best_cap:
			best_cap = cap
			scenario_id = int((s as Dictionary)["id"])

	var starters: Dictionary = {}
	var db := SQLite.new()
	db.path = db_path()
	db.verbosity_level = SQLite.QUIET
	if db.open_db():
		db.query("SELECT id FROM players WHERE starter = 1")
		for row in db.query_result:
			starters[int(row["id"])] = true
		db.close_db()

	var data := load_match_data()
	# role → 정렬 키(스타터가 아니면 큰 수를 더해 뒤로 민다). 작을수록 앞.
	var non_starter_rank: int = 1 << 30
	var best: Dictionary = {}
	for raw in (data.get("players", []) as Array):
		var pd := raw as PlayerData
		if pd.is_mob:
			continue
		var key: int = pd.id + (0 if starters.has(pd.id) else non_starter_rank)
		if not best.has(pd.role) or key < int(best[pd.role]):
			best[pd.role] = key
	var pilot_ids: Array = []
	var levels: Dictionary = {}
	for r in GameEnums.Role.size():
		if best.has(r):
			var pid: int = int(best[r]) % non_starter_rank
			pilot_ids.append(pid)
			levels[str(pid)] = 1
	return {
		"scenario": scenario_id,
		"team_id": team_id,
		"pilot_ids": pilot_ids,
		"pilot_levels": levels,
		"salary_cap": RunRules.salary_cap(scenario_id),
		"salary_total": 0,   # start_run 이 다시 낸다
	}


# `validate_lineup` 의 `owned_max_levels`. 테스트 런은 네임드 전원 최대 레벨,
# 아니면 프로필 컬렉션.
func _owned_levels_for_run(pool: Array) -> Dictionary:
	if not use_test_run:
		var pm: Node = get_node_or_null("/root/ProfileManager")
		if pm != null:
			return pm.owned_max_levels()
	var out: Dictionary = {}
	var top: int = RunRules.max_level()
	for raw in pool:
		var pd := raw as PlayerData
		if not pd.is_mob:
			out[str(pd.id)] = top
	return out


# 0 이 아닌 새 런 시드. 0 은 "런 시드 없음"(옛 세이브 · 시작 전)으로 읽힌다.
func _fresh_run_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s: int = 0
	while s == 0:
		s = int(rng.randi())
	return s


## 에디터에서 `Season.tscn` 을 바로 실행했을 때(`season_state.active == false`)
## SeasonHub 가 부르는 기본 경로. 직접 실행도 정식 런과 **같은 길**을 타도록
## `start_run(default_run_setup(player_team_id))` 와 같다.
func init_season(player_team_id: int = 0) -> String:
	return start_run(default_run_setup(player_team_id))


# Season skeleton shared by every run start: resets season_state, stores the
# 40-pilot pool (Lv1 copies straight from game.db) with its CSV team ids, team
# meta, INTL pool, CSV-based rosters, empty standings and an empty training
# board, and marks the state active. `start_run` then re-distributes rosters.
# Returns "" on success or an error string. Never calls start_run / init_season.
func _init_season_core(player_team_id: int, pilots: Array) -> String:
	reset_season_state()
	if pilots.size() != TEAM_COUNT * 5:
		return "Expected %d pilots, got %d — rebuild game.db" % [TEAM_COUNT * 5, pilots.size()]

	season_state["all_pilots"] = pilots
	season_state["player_team_id"] = player_team_id
	season_state["team_meta"] = _load_team_meta()
	var intl: Dictionary = _load_intl_pool()
	season_state["intl_team_meta"] = intl["teams"]
	season_state["intl_pilots"]    = intl["pilots"]

	season_state["team_rosters"] = RunRoster.build_rosters(pilots, TEAM_COUNT)

	# Empty league standings
	var standings: Dictionary = {}
	for t in TEAM_COUNT:
		standings[t] = {"wins": 0, "losses": 0}
	season_state["league_standings"] = standings

	# 훈련판은 빈 채 시작한다 — 빈 칸은 기초 훈련이 자동으로 메우므로
	# "아무것도 안 놓은 판"과 "기초로 도배한 판"이 같은 결과를 낸다.
	season_state["training_board"] = []

	season_state["active"] = true
	return ""


# ── Game DB 경로 ──────────────────────────────────────────────────────
# 경로 결정(에디터 = res://, 기기 = pck 에서 user:// 로 뽑은 사본)은
# `resources/GameDb.gd` 한 곳에 산다 — `ConstTable` 이 오토로드보다 먼저
# DB 를 열어야 해서 정적 클래스로 옮겼다. 여기는 기존 호출부를 위한 창구다.
func db_path() -> String:
	return GameDb.path()


# Loads players + mechs from game.db. Returns {"players": Array[PlayerData], "mechs": Array[MechData]}.
# On failure returns {"error": String}.
func load_match_data() -> Dictionary:
	var db := SQLite.new()
	db.path = db_path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		return {"error": "Cannot open %s" % db_path()}

	db.query("SELECT * FROM players ORDER BY team_id, role")
	if db.query_result.is_empty():
		db.close_db()
		return {"error": "players table empty — rebuild game.db"}
	var players: Array = []
	for row in db.query_result:
		players.append(PlayerData.new(
			int(row["id"]), row["name"], int(row["role"]), int(row["team_id"]),
			int(row["field_hit"]), int(row["field_eva"]),
			int(row["engage_hit"]), int(row["engage_eva"]),
			int(row["atk_growth"]), int(row["hp_growth"]),
			# 옛 game.db(스킬 이전)도 열리도록 기본값과 함께 읽는다 — 그때는
			# 전원이 "스킬 없는 네임드"가 되고 그림도 평소 컷 그대로다.
			int(row.get("skill_id", -1)), int(row.get("is_mob", 0)) != 0))
		(players[-1] as PlayerData).pilot_cards = parse_card_ids(String(row.get("pilot_cards", "")))
		(players[-1] as PlayerData).salary = int(row.get("salary", 0))
		(players[-1] as PlayerData).rarity = int(row.get("rarity", 0))

	db.query("SELECT * FROM mechs ORDER BY id")
	if db.query_result.is_empty():
		db.close_db()
		return {"error": "mechs table empty — rebuild game.db"}
	var mechs: Array = []
	for row in db.query_result:
		var md := MechData.new(
			int(row["id"]), row["name"],
			int(row["hp"]), int(row["atk"]),
			int(row.get("presence", 4)))
		# 역할군은 기본값 -1 로 읽는다 — `role` 컬럼이 없는 옛 game.db 에서도
		# 메크 목록 자체는 그대로 서고, 분류만 "없음"이 된다.
		md.role = int(row.get("role", -1))
		mechs.append(md)

	db.close_db()
	# 실루엣 컷 목록은 한 번만 심는다 — PilotImages 는 static 이라 이후의 모든
	# 초상화 조회(전장 마커 · 스트립 · 교전 무대 · 상세 패널)가 자동으로 갈린다.
	var mob_ids: Array = []
	for raw in players:
		var pd := raw as PlayerData
		if pd.is_mob:
			mob_ids.append(pd.id)
	PilotImages.set_mob_ids(mob_ids)
	return {"players": players, "mechs": mechs}


# Loads the 8-team metadata list from game.db. Returns an Array indexed by
# team_id (0..7) of {id, name, short_name} dicts. Falls back to a synthesized
# placeholder list if the table is missing (e.g. before first Rebuild game.db).
func _load_team_meta() -> Array:
	var fallback: Array = []
	for t in TEAM_COUNT:
		fallback.append({"id": t, "name": "Team %d" % t, "short_name": "T%d" % t})

	var db := SQLite.new()
	db.path = db_path()
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
	db.path = db_path()
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
			int(row["field_hit"]), int(row["field_eva"]),
			int(row["engage_hit"]), int(row["engage_eva"]),
			int(row["atk_growth"]), int(row["hp_growth"])))
		(pilots[-1] as PlayerData).pilot_cards = parse_card_ids(String(row.get("pilot_cards", "")))
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
# Which run file autosave / load goes to (SaveSystem.run_path()). Defaults to
# true so running Season.tscn / MatchFlow.tscn directly from the editor
# autosaves into the hidden test run file (user://run_test.save) instead of the
# real run. The lobby (`features/meta/lobby/`) sets it to false on _ready.
var use_test_run: bool = true


# ── Card Pool (used by CardPhaseManager in battle sim) ────────────────────────
# Each entry mirrors a row from the cards table. CardPhaseManager pulls 6 random
# entries per pilot at match start, wraps each in a CardData instance, and tags
# it with the owning PilotData (시전자 rule).
var card_pool_bs: Array = []  # Array of {id,name,cost,uses,cast_method,target,cast_range,area,keyword,effect,description,scope,pool,card_type,card_cat,excl_group,charge_max}


func _ready() -> void:
	_load_card_pool_bs()
	_load_pilot_card_slots()
	_load_pilot_skills()
	_load_mech_skills()
	_load_training_tiles()


func _load_card_pool_bs() -> void:
	var db := SQLite.new()
	db.path = db_path()
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
			# card_type / card_cat 도 같은 이유로 기본값과 함께 읽는다.
			"card_type":   String(row.get("card_type", CardData.TYPE_PILOT)),
			"card_cat":    String(row.get("card_cat", CardData.CAT_NONE)),
			# 상호 배타 그룹 — 비어 있으면 제약 없음.
			"excl_group":  String(row.get("excl_group", "")),
			# 충전 상한 — `charge` 키워드를 단 카드만 읽는다.
			"charge_max":  int(row.get("charge_max", 0)),
		})
	db.close_db()
	print("GameManager: card pool loaded — %d cards" % card_pool_bs.size())


## cards 테이블 한 행을 id 로. 없으면 빈 Dictionary.
func card_def(card_id: int) -> Dictionary:
	for raw in card_pool_bs:
		var def: Dictionary = raw as Dictionary
		if int(def.get("id", -1)) == card_id:
			return def
	return {}


# ── 고정 파일럿 카드 (pilot_card_slots + players.pilot_cards) ─────────────────
# 선수마다 파일럿 카드 3장이 **고정**이다 — 매 판 새로 뽑지 않는다. 원본은
# `players.csv` / `intl_players.csv` 의 `pilot_cards`(카드 id 를 `|` 로 이은 것)이고,
# 그 칸이 비었거나 깨졌으면 `pilot_card_slots` 로 **선수 id 를 씨앗 삼아** 결정적으로
# 뽑는다 — 같은 선수는 언제 몇 번을 물어도 같은 3장을 받는다.
#
# 슬롯 표는 포지션마다 세 칸이고, 각 칸은 카드 분류(`cards.card_cat`) 목록이다.
# 한 칸은 **분류가 하나라도 겹치고 시전자 제약(`scope`)이 그 포지션을 허락하는**
# 풀 카드(`pool = 1`) 중 하나로 채운다. 같은 카드는 두 번 들지 않는다.
const PILOT_CARDS_PER_PLAYER: int = 3
var pilot_card_slots: Dictionary = {}   # String position → Array[Array[String]] (칸마다 분류 목록)
## DB 의 `pilot_cards` 원문 캐시 — 선수 id → Array[int]. 옛 세이브에서 복원한
## 선수(필드가 비어 있다)를 같은 선수의 DB 행으로 채우는 데 쓴다.
var _db_pilot_cards: Dictionary = {}
var _db_pilot_cards_loaded: bool = false


## `"12|36|41"` → `[12, 36, 41]`. 빈 조각과 숫자가 아닌 조각은 버린다.
static func parse_card_ids(raw: String) -> Array:
	var out: Array = []
	for part in raw.split("|", false):
		var t: String = (part as String).strip_edges()
		if t.is_valid_int():
			out.append(int(t))
	return out


func _load_pilot_card_slots() -> void:
	var db := SQLite.new()
	db.path = db_path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		return
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='pilot_card_slots'")
	if not db.query_result.is_empty():
		db.query("SELECT * FROM pilot_card_slots")
		for row in db.query_result:
			var slots: Array = []
			for col in ["slot1", "slot2", "slot3"]:
				var cats: Array = []
				for part in String(row.get(col, "")).split("|", false):
					var c: String = (part as String).strip_edges()
					if not c.is_empty():
						cats.append(c)
				slots.append(cats)
			pilot_card_slots[String(row["position"])] = slots
	db.close_db()


func _ensure_db_pilot_cards() -> void:
	if _db_pilot_cards_loaded:
		return
	_db_pilot_cards_loaded = true
	var db := SQLite.new()
	db.path = db_path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		return
	for table in ["players", "intl_players"]:
		db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='%s'" % table)
		if db.query_result.is_empty():
			continue
		db.query("SELECT * FROM %s" % table)
		for row in db.query_result:
			_db_pilot_cards[int(row["id"])] = parse_card_ids(String(row.get("pilot_cards", "")))
	db.close_db()


## 이 선수의 고정 파일럿 카드 id 3개. 우선순위는 선수 자신의 값 → 같은 id 의 DB
## 행 → 씨앗 뽑기. 앞의 둘에서 온 id 라도 표에 없거나 포지션이 막는 카드는 빼고,
## 모자란 칸은 씨앗 뽑기로 채운다(CSV 오타가 덱을 짧게 만들지 않는다).
func pilot_card_ids_for(pd: PlayerData) -> Array:
	if pd == null:
		return []
	var pos: String = GameEnums.position_key(pd.role)
	var src: Array = pd.pilot_cards
	if src.is_empty():
		_ensure_db_pilot_cards()
		src = _db_pilot_cards.get(pd.id, [])
	var out: Array = []
	for raw in src:
		var id: int = int(raw)
		if out.has(id) or out.size() >= PILOT_CARDS_PER_PLAYER:
			continue
		var def: Dictionary = card_def(id)
		if def.is_empty():
			continue
		if not CardData.positions_of(String(def.get("scope", "any"))).has(pos):
			continue
		out.append(id)
	if out.size() < PILOT_CARDS_PER_PLAYER:
		out = roll_pilot_card_ids(pos, 7919 + pd.id, out)
	return out


## 포지션 슬롯 표로 3장을 **결정적으로** 뽑는다. `keep` 은 이미 정해진 id 들이고
## 그 수만큼 앞 칸을 건너뛴다. 씨앗이 같으면 결과도 같다.
func roll_pilot_card_ids(pos: String, seed_value: int, keep: Array = []) -> Array:
	var out: Array = keep.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var slots: Array = pilot_card_slots.get(pos, [])
	var claimed: Dictionary = {}
	for id in out:
		var g: String = String(card_def(int(id)).get("excl_group", ""))
		if not g.is_empty():
			claimed[g] = true
	var slot_i: int = out.size()
	while out.size() < PILOT_CARDS_PER_PLAYER:
		var cats: Array = slots[slot_i] if slot_i < slots.size() else []
		slot_i += 1
		var bag: Array = _slot_candidates(pos, cats, out, claimed)
		if bag.is_empty():
			# 칸의 분류에 맞는 카드가 없으면 포지션이 허락하는 풀 전체로 물러선다 —
			# 파일럿 카드 3장은 깨져서는 안 되는 불변식이다.
			bag = _slot_candidates(pos, [], out, claimed)
		if bag.is_empty():
			break
		var def: Dictionary = bag[rng.randi_range(0, bag.size() - 1)]
		out.append(int(def["id"]))
		var grp: String = String(def.get("excl_group", ""))
		if not grp.is_empty():
			claimed[grp] = true
	return out


## 슬롯 한 칸의 후보 행들. `cats` 가 비어 있으면 분류를 보지 않는다.
func _slot_candidates(pos: String, cats: Array, taken: Array, claimed: Dictionary) -> Array:
	var out: Array = []
	for raw in card_pool_bs:
		var def: Dictionary = raw as Dictionary
		if int(def.get("pool", 1)) == 0:
			continue
		var id: int = int(def.get("id", -1))
		if taken.has(id):
			continue
		if not CardData.positions_of(String(def.get("scope", "any"))).has(pos):
			continue
		var grp: String = String(def.get("excl_group", ""))
		if not grp.is_empty() and claimed.has(grp):
			continue
		if not cats.is_empty():
			var hit: bool = false
			for part in String(def.get("card_cat", "")).split("|", false):
				if cats.has((part as String).strip_edges()):
					hit = true
					break
			if not hit:
				continue
		out.append(def)
	return out


# ── 파일럿 스킬 (used by PilotSkillSystem in battle sim) ──────────────────────
# `pilot_skills` 테이블 그대로. 키는 스킬 id 이고 값은 그 행의 Dictionary 다.
# `players.skill_id` 가 이 표를 가리킨다 — 모브 파일럿은 -1 이라 아무것도
# 가리키지 않는다.
var pilot_skills: Dictionary = {}   # int id → {id,key,name,role,type,p1,p2,keyword,description}


func skill_def(skill_id: int) -> Dictionary:
	return pilot_skills.get(skill_id, {})


func _load_pilot_skills() -> void:
	var db := SQLite.new()
	db.path = db_path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_error("GameManager: cannot open data/game.db")
		return
	# 스킬 테이블이 없는 옛 game.db 에서도 조용히 넘어간다 — 그때는 전원이
	# 스킬 없는 파일럿으로 굴러가고 UI 는 스킬 칸을 그리지 않는다.
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='pilot_skills'")
	if db.query_result.is_empty():
		db.close_db()
		print("GameManager: pilot_skills table missing — skills disabled")
		return
	db.query("SELECT * FROM pilot_skills ORDER BY id")
	for row in db.query_result:
		pilot_skills[int(row["id"])] = {
			"id":          int(row["id"]),
			"key":         String(row["key"]),
			"name":        String(row["name"]),
			"role":        int(row["role"]),
			"type":        String(row["type"]),
			"p1":          int(row["p1"]),
			"p2":          int(row["p2"]),
			"keyword":     String(row["keyword"]),
			"description": String(row["description"]),
		}
	db.close_db()
	print("GameManager: pilot skills loaded — %d skills" % pilot_skills.size())


# ── 주간 훈련 타일 (used by TrainingBoard / TrainingView) ───────────────
# `data/csv/training_tiles.csv` 그대로. 배열이고 CSV 순서(= 등급 순서)를
# 유지한다 — 인벤토리 목록이 그 순서 그대로 그려지므로 정렬을 화면 쪽에
# 두면 타일이 늘 때마다 자리가 조용히 바뀐다.
#
# 문법 해석은 여기서 하지 않는다 — `TrainingTile.from_def()` 가 한 행을 타일
# 하나로 조립한다. 이젠은 DB 행을 그대로 나르는 자리다(카드 풀과 같은 규칙).
var training_tiles: Array = []   # Array of {id,name,grade,shape,exp,effect}


## 타일 id 로 한 행을 찾는다. 없으면 빈 Dictionary — 세이브에 남은 타일을
## CSV 에서 지우더라도 판이 통째로 죽지 않게 하기 위해서다.
func training_tile_def(tile_id: String) -> Dictionary:
	for row in training_tiles:
		if String(row["id"]) == tile_id:
			return row
	return {}


func _load_training_tiles() -> void:
	var db := SQLite.new()
	db.path = db_path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_error("GameManager: cannot open data/game.db")
		return
	# 타일 테이블이 없는 옛 game.db 에서도 조용히 넘어간다 — 그때 훈련판은
	# 모든 칸이 기초 훈련인 판이 되고 인벤토리만 비어 있다.
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='training_tiles'")
	if db.query_result.is_empty():
		db.close_db()
		print("GameManager: training_tiles table missing — board falls back to basics")
		return
	db.query("SELECT * FROM training_tiles ORDER BY grade, id")
	for row in db.query_result:
		training_tiles.append({
			"id":          String(row["id"]),
			"name":        String(row["name"]),
			"grade":       int(row["grade"]),
			"shape":       String(row["shape"]),
			"exp":         String(row["exp"]),
			"effect":      String(row["effect"]),
		})
	db.close_db()
	print("GameManager: training tiles loaded — %d tiles" % training_tiles.size())


# ── 메크 패시브 / 메크 카드 (used by MechSkillSystem + CardPhaseManager) ──────
# 파일럿 스킬이 **선수**에게 붙는 한 수라면 이 둘은 **기체**에 붙는다. 표는
# `data/csv/mech_passives.csv`(15행) 와 `data/csv/mech_cards.csv`(64행)이고,
# 짝은 `mechs.id` 다 — `players.skill_id` 같은 포인터 컬럼이 없는 것은 메크
# 한 대가 자기 패시브 하나와 자기 카드 셋을 통째로 소유하기 때문이다.
#
# 세 표를 들고 있는 이유가 각각 다르다.
#   • `mech_passives`  — mech_id → 그 메크의 패시브 행 하나 (없으면 비어 있다)
#   • `mech_cards`     — mech_id → 그 메크의 카드 행 배열 (덱을 돌릴 때 훑는다)
#   • `mech_card_defs` — 카드 id → 행 하나 (효과가 카드를 **지목해** 만들 때.
#     `gen_hand:13` 처럼 id 로 부르는 절이 열 개가 넘어서 매번 배열을 뒤지면
#     같은 선형 탐색이 카드 한 장마다 다시 돈다)
var mech_passives:  Dictionary = {}   # int mech_id → {id,mech_id,key,name,p1,p2,keyword,description}
var mech_cards:     Dictionary = {}   # int mech_id → Array of card def Dictionaries
var mech_card_defs: Dictionary = {}   # int card id → card def Dictionary


## 이 메크의 패시브 행. 패시브가 없는 메크(6대)는 빈 Dictionary.
func mech_passive_def(mech_id: int) -> Dictionary:
	return mech_passives.get(mech_id, {})


## 이 메크가 들고 오는 카드 행들. 알 수 없는 메크면 빈 배열.
func mech_cards_for(mech_id: int) -> Array:
	return mech_cards.get(mech_id, [])


## 메크 카드 한 행을 id 로. 없으면 빈 Dictionary.
func mech_card_def(card_id: int) -> Dictionary:
	return mech_card_defs.get(card_id, {})


func _load_mech_skills() -> void:
	var db := SQLite.new()
	db.path = db_path()
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_error("GameManager: cannot open data/game.db")
		return
	# 두 표가 없는 옛 game.db 에서도 조용히 넘어간다 — 그때는 모든 메크가
	# 패시브도 고유 카드도 없는 상태로 굴러가고 덱에는 파일럿 카드만 들어간다.
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='mech_passives'")
	if not db.query_result.is_empty():
		db.query("SELECT * FROM mech_passives ORDER BY id")
		for row in db.query_result:
			mech_passives[int(row["mech_id"])] = {
				"id":          int(row["id"]),
				"mech_id":     int(row["mech_id"]),
				"key":         String(row["key"]),
				"name":        String(row["name"]),
				"p1":          int(row["p1"]),
				"p2":          int(row["p2"]),
				"keyword":     String(row["keyword"]),
				"description": String(row["description"]),
			}
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='mech_cards'")
	if not db.query_result.is_empty():
		db.query("SELECT * FROM mech_cards ORDER BY id")
		for row in db.query_result:
			var def: Dictionary = {
				"id":          int(row["id"]),
				"mech_id":     int(row["mech_id"]),
				"name":        String(row["name"]),
				"count":       int(row["count"]),
				"cost":        int(row["cost"]),
				"cast_method": String(row["cast_method"]),
				"target":      String(row["target"]),
				"cast_range":  int(row["cast_range"]),
				"area":        int(row["area"]),
				"keyword":     String(row["keyword"]),
				"charge_max":  int(row.get("charge_max", 0)),
				"effect":      String(row["effect"]),
				"trigger":     String(row.get("trigger", "")),
				"description": String(row["description"]),
			}
			mech_card_defs[int(row["id"])] = def
			if not mech_cards.has(int(row["mech_id"])):
				mech_cards[int(row["mech_id"])] = []
			(mech_cards[int(row["mech_id"])] as Array).append(def)
	db.close_db()
	print("GameManager: mech skills loaded — %d passives, %d cards" % [
			mech_passives.size(), mech_card_defs.size()])
