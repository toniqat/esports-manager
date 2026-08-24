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
			int(row["teamfight"]), int(row["mental"]),
			# 옛 game.db(스킬 이전)도 열리도록 기본값과 함께 읽는다 — 그때는
			# 전원이 "스킬 없는 네임드"가 되고 그림도 평소 컷 그대로다.
			int(row.get("skill_id", -1)), int(row.get("is_mob", 0)) != 0))

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
	_load_pilot_skills()
	_load_mech_skills()


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
			# card_type / card_cat 도 같은 이유로 기본값과 함께 읽는다. 옛 game.db
			# 는 전부 "메크 카드 / 분류 없음"으로 읽혀 덱 구성이 폴백 경로를 탄다.
			"card_type":   String(row.get("card_type", CardData.TYPE_MECH)),
			"card_cat":    String(row.get("card_cat", CardData.CAT_NONE)),
			# 상호 배타 그룹 — 비어 있으면 제약 없음.
			"excl_group":  String(row.get("excl_group", "")),
		})
	db.close_db()
	print("GameManager: card pool loaded — %d cards" % card_pool_bs.size())


# ── 파일럿 스킬 (used by PilotSkillSystem in battle sim) ──────────────────────
# `pilot_skills` 테이블 그대로. 키는 스킬 id 이고 값은 그 행의 Dictionary 다.
# `players.skill_id` 가 이 표를 가리킨다 — 모브 파일럿은 -1 이라 아무것도
# 가리키지 않는다.
var pilot_skills: Dictionary = {}   # int id → {id,key,name,role,type,p1,p2,keyword,description}


func skill_def(skill_id: int) -> Dictionary:
	return pilot_skills.get(skill_id, {})


func _load_pilot_skills() -> void:
	var db := SQLite.new()
	db.path = "res://data/game.db"
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
	db.path = "res://data/game.db"
	db.verbosity_level = SQLite.QUIET
	if not db.open_db():
		push_error("GameManager: cannot open data/game.db")
		return
	# 두 표가 없는 옛 game.db 에서도 조용히 넘어간다 — 그때는 모든 메크가
	# 패시브도 고유 카드도 없는 상태로 굴러가고, 덱 구성은 공용 메크 카드
	# 폴백(cards.csv 의 card_type = mech)을 탄다.
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
