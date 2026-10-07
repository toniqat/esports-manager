class_name MatchFlow
extends Node2D

# Top-level orchestrator for the pre-battle match flow:
#   LOAD -> PREP -> BAN_PICK -> LAUNCH (change_scene to BattleSim)
#
# Each child controller (MatchPrepController, BanPickController) builds its own
# UI on enter() and emits phase_finished when done. MatchFlow advances the state
# machine and feeds GameManager.match_ctx.
#
# **열거값 둘이 자리만 지킨다 — `ASSIGN` 과 `JUNGLE_START`.**
#   • 메크 배정은 밴픽 화면이 끝난 자리에서 그대로 이어진다
#     (`BanPickController._enter_assign_mode`) — 그래서 밴픽 결과가 이미
#     `assigned_mech` 까지 채운 로스터를 들고 온다.
#   • 정글 시작 방향은 **BattleSim 안으로 들어갔다**
#     (`features/battle_sim/gambit/JungleStartOverlay.gd`) — 좌우 중 어느
#     정글로 갈지는 전장을 보면서 정하는 것이지, 전장을 못 본 채 "LEFT / RIGHT"
#     두 글자 중에 고르는 것이 아니었다. `jungle_start/JungleStartController.gd`
#     는 삭제됐다.
# 두 열거값은 세이브 호환(`match_resume.phase`)을 위해 남는다.

signal phase_changed(new_phase: int)

@onready var gm: Node                          = get_node("/root/GameManager")
@onready var canvas: CanvasLayer               = $CanvasLayer
@onready var _prep:     Node                   = $MatchPrepController
@onready var _ban_pick: Node                   = $BanPickController

var phase: int = GameEnums.MatchPhase.LOAD

# Loaded from DB at LOAD phase. Stays read-only after.
var all_players: Array = []   # Array[PlayerData]
var all_mechs:   Array = []   # Array[MechData]

# Team IDs to draft rosters for. Defaults are the standalone-MatchFlow case
# (player vs Team 1); when launched from Season we overwrite enemy_team_id
# from season_state.pending_match.
var player_team_id: int = 0
var enemy_team_id:  int = 1

# Filled by BanPickController.
var banned_mech_ids: Array      = []  # Array[int]
var player_picked_mech_ids: Array = []  # Array[int]
var enemy_picked_mech_ids: Array  = []  # Array[int]
var player_side: int             = GameEnums.DraftSide.BLUE

# 에디터 실행 + 시즌 경기일 때만 생긴다(`_setup_cheats`). 그 밖에는 null.
var _cheat_menu: MatchCheatMenu = null

# Match rosters are **copies** of the season pilots (`PlayerData.duplicate()`),
# built once per team id by `_team_roster` — ban/pick writes `assigned_mech` and
# `_finalize_rosters` adds pilot mods + mech mastery on them, so the originals
# in `season_state.all_pilots` / `intl_pilots` are never touched (plan §11.3).
var _roster_cache: Dictionary = {}   # team_id(int) → Array[PlayerData] (copies, role 0..4)
var _rosters_finalized: bool = false


func _ready() -> void:
	gm.reset_match_ctx()
	# Season-driven match: read player/enemy team ids from pending_match. The
	# player team is the drafted team_id=0 (already updated by TeamDraft), the
	# enemy is whichever team the schedule paired us with.
	var pending = gm.season_state.get("pending_match", null) if gm.season_state.get("active", false) else null
	if pending != null:
		player_team_id = int(gm.season_state["player_team_id"])
		enemy_team_id  = int(pending["enemy_team_id"])
	if not _load_data():
		return
	_setup_cheats()

	# Mid-match resume path: title-screen "이어하기" landed here because the
	# slot was saved between BAN_PICK start and BattleSim launch. Skip ahead
	# to the saved phase. Consume the resume hint immediately so a subsequent
	# pre-ban-pick save (still fired below) writes the freshly-derived state.
	var resume = gm.season_state.get("match_resume", null) if gm.season_state.get("active", false) else null
	if typeof(resume) == TYPE_DICTIONARY:
		gm.season_state["match_resume"] = null
		var resume_phase: int = int((resume as Dictionary).get("phase", GameEnums.MatchPhase.BAN_PICK))
		if resume_phase == GameEnums.MatchPhase.LAUNCH:
			# Post-gambit snapshot — rebuild match_ctx from the resume payload
			# and jump straight to BattleSim. No UI needed.
			_resume_at_launch(resume)
			return
		# BAN_PICK resume: restore player_side and fall through to the normal
		# entry path (the pre-ban-pick save below will re-save with the same
		# player_side, idempotent).
		player_side = int((resume as Dictionary).get("player_side", GameEnums.DraftSide.BLUE))
	else:
		# Fresh entry — 플레이어는 **항상 블루**다. 진영은 밴픽 순서(레드 =
		# 선밴/선픽, 블루 = 후밴/후픽)와 인게임 선(블루 = 전략 포인트 선점 +
		# 선턴, BattleSim.seed_side_costs)을 동시에 결정하는데, 두 축이 다
		# 갖춰지기 전까지는 한쪽으로 고정해 둔다. 진영 추첨을 되살릴 때는 이
		# 한 줄만 되돌리면 된다 — 아래 흐름은 이미 player_side 를 그대로 타고
		# 내려가고, BattleSim 도 match_ctx.player_side 를 읽어 블루를 정한다.
		player_side = GameEnums.DraftSide.BLUE

	# Wire signals
	_prep.phase_finished.connect(_on_prep_finished)
	_ban_pick.phase_finished.connect(_on_ban_pick_finished)

	# Resume entry skips PREP — the player already committed to the match
	# when the pre-ban-pick save fired.
	if typeof(resume) == TYPE_DICTIONARY:
		_enter_phase(GameEnums.MatchPhase.BAN_PICK)
		return

	# Fresh entry shows the prep dashboard first.
	_enter_phase(GameEnums.MatchPhase.PREP)


func _load_data() -> bool:
	# Season-driven match: reuse the already-mutated pilot pool (the draft
	# rewrites team_ids; reloading from DB would clobber that). Mechs still
	# come from the DB since they're never mutated post-load.
	var pending = gm.season_state.get("pending_match", null) if gm.season_state.get("active", false) else null
	if pending != null and (gm.season_state["all_pilots"] as Array).size() > 0:
		all_players = gm.season_state["all_pilots"]
		var mechs_only: Dictionary = gm.load_match_data()
		if mechs_only.has("error"):
			_show_error(mechs_only["error"])
			return false
		all_mechs = mechs_only["mechs"]
		print("MatchFlow: season mode — %d pilots from season_state, %d mechs" % [all_players.size(), all_mechs.size()])
		return true
	var result: Dictionary = gm.load_match_data()
	if result.has("error"):
		_show_error(result["error"])
		return false
	all_players = result["players"]
	all_mechs   = result["mechs"]
	print("MatchFlow: loaded %d players, %d mechs" % [all_players.size(), all_mechs.size()])
	return true


func _enter_phase(p: int) -> void:
	phase = p
	phase_changed.emit(p)
	_refresh_cheats()
	match p:
		GameEnums.MatchPhase.PREP:
			var p_roster := _team_roster(player_team_id)
			var e_roster := _team_roster(enemy_team_id)
			var p_name: String = _team_name(player_team_id)
			var e_name: String = _team_name(enemy_team_id)
			_prep.enter(p_roster, e_roster, p_name, e_name)
		GameEnums.MatchPhase.BAN_PICK:
			# 밴픽 화면은 위/아래에 양 팀 파일럿 초상화를 세우므로 로스터와
			# 팀명이 함께 필요하다 — 배정(ASSIGN)은 아직 멀었지만, 누구를
			# 위해 고르는지가 안 보이면 21대 중 무엇을 골라야 할지도 안 보인다.
			_ban_pick.enter(all_mechs, player_side,
					_team_roster(player_team_id), _team_roster(enemy_team_id),
					_team_name(player_team_id), _team_name(enemy_team_id))
		GameEnums.MatchPhase.LAUNCH:
			_launch_battle()


func _on_prep_finished(_result: Dictionary) -> void:
	# Player confirmed the match-up. Pre-ban-pick autosave fires here so a
	# resume from this slot drops back into BAN_PICK directly — PREP is
	# only shown on first-time entry. Skipped when running MatchFlow
	# standalone (no pending_match).
	if gm.season_state.get("active", false) and gm.season_state.get("pending_match", null) != null:
		gm.season_state["match_resume"] = {
			"phase":           GameEnums.MatchPhase.BAN_PICK,
			"player_side":     player_side,
			"banned_mech_ids": [],
			"player_picked_mech_ids": [],
			"enemy_picked_mech_ids":  [],
			"player_assigned_mech_ids": [],
			"enemy_assigned_mech_ids":  [],
			"jungle_start_dir": -1,
		}
		_autosave("pre_ban_pick")
	_enter_phase(GameEnums.MatchPhase.BAN_PICK)


func _on_ban_pick_finished(result: Dictionary) -> void:
	# 밴픽 화면이 배정까지 마치고 돌아온다 — `PlayerData.assigned_mech` 는 이미
	# 채워져 있고, 결과는 그 로스터를 그대로 넘겨준다(예전 AssignController 가
	# 하던 일이 그 화면 안으로 들어왔다).
	banned_mech_ids        = result["banned"]
	player_picked_mech_ids = result["player_picks"]
	enemy_picked_mech_ids  = result["enemy_picks"]
	gm.match_ctx["player_roster"] = result["player_roster"]
	gm.match_ctx["enemy_roster"]  = result["enemy_roster"]
	# Mechs are assigned — pilot mods + mastery go onto the copies, and the
	# pairing is recorded in pending_match before the post-ban-pick save.
	_finalize_rosters(result["player_roster"], result["enemy_roster"])
	# 정글 시작 방향은 이제 BattleSim 이 묻는다 — 여기서는 기본값만 심어 둔다
	# (상대 정글러와 단독 실행이 읽는 값이고, 아군 정글러의 값은 개시 직전에
	# `JungleStartOverlay` 가 덮어쓴다).
	gm.match_ctx["jungle_start_dir"] = GameEnums.JungleStartDir.LEFT
	# Post-gambit autosave (trigger #3). 밴픽과 배정이 끝나 매치 상태가 전부
	# 확정된 자리다 — 예전에는 정글 방향까지 여기 들어왔지만, 그 선택이
	# BattleSim 으로 옮겨 가면서 저장 시점이 한 단계 앞으로 당겨졌다. 재개는
	# 어차피 전투를 처음부터 다시 돌리므로 정글 방향도 그때 다시 묻는다.
	if gm.season_state.get("active", false):
		var p_ids: Array = _roster_mech_ids(gm.match_ctx.get("player_roster", []))
		var e_ids: Array = _roster_mech_ids(gm.match_ctx.get("enemy_roster",  []))
		gm.season_state["match_resume"] = {
			"phase":           GameEnums.MatchPhase.LAUNCH,
			"player_side":     player_side,
			"banned_mech_ids": banned_mech_ids.duplicate(),
			"player_picked_mech_ids": player_picked_mech_ids.duplicate(),
			"enemy_picked_mech_ids":  enemy_picked_mech_ids.duplicate(),
			"player_assigned_mech_ids": p_ids,
			"enemy_assigned_mech_ids":  e_ids,
			"jungle_start_dir": int(GameEnums.JungleStartDir.LEFT),
		}
		_autosave("post_ban_pick")
	_enter_phase(GameEnums.MatchPhase.LAUNCH)


func _launch_battle() -> void:
	gm.match_ctx["active"]          = true
	gm.match_ctx["player_side"]     = player_side
	gm.match_ctx["banned_mech_ids"] = banned_mech_ids
	gm.match_ctx["all_mechs"]       = all_mechs
	gm.match_ctx["enemy_misjudge_chance"] = _misjudge_chance_for(enemy_team_id)
	# M8 — my team's in-game traits (`features/battle_sim/trait/TraitHooks.gd`).
	gm.match_ctx["traits"] = TraitSystem.ingame_traits(gm.season_state) \
			if bool(gm.season_state.get("active", false)) else []
	# 밴픽(흰 화면) → 전장(어두운 화면)은 한 장면이 넘어가는 자리라 그냥 갈아
	# 끼우지 않고 암전 → 가짜 로딩 → 밝아짐으로 덮는다. 덮개는 root 에 붙어
	# 씬 전환을 건너 살아남고, BattleSim 의 무거운 `_ready` 가 그 뒤에서 돈다.
	SceneFade.change_scene(get_tree(), "res://scenes/BattleSim.tscn")


## 오브젝트 오판 확률 — 상대 AI 가 수적 열세인데도 오브젝트 교전을 받아들일
## 확률. 리그 순위 1위 `MISJUDGE_MIN` → 꼴찌 `MISJUDGE_MAX` 선형.
## 승패가 같으면 팀 평균 스탯이 높은 쪽이 위다(시즌 초 전원 0-0 에서도 강팀이
## 덜 오판하게). 국제대회 외부 팀(id ≥ 100)은 각 리그 상위권이므로 최소값.
## 시즌 밖(단독 실행)은 두 끝의 중간값.
## 값은 data/csv/const.csv(`OBJ_MISJUDGE_MIN` / `OBJ_MISJUDGE_MAX`) — ConstTable 로 읽는다.
static var MISJUDGE_MIN: float = ConstTable.num("OBJ_MISJUDGE_MIN")
static var MISJUDGE_MAX: float = ConstTable.num("OBJ_MISJUDGE_MAX")

func _misjudge_chance_for(team_id: int) -> float:
	if not gm.season_state.get("active", false):
		return (MISJUDGE_MIN + MISJUDGE_MAX) * 0.5
	if team_id >= 100:
		return MISJUDGE_MIN
	var standings: Dictionary = gm.season_state.get("league_standings", {})
	var avg: Dictionary = {}
	var cnt: Dictionary = {}
	for p_raw in gm.season_state.get("all_pilots", []):
		var p := p_raw as PlayerData
		avg[p.team_id] = float(avg.get(p.team_id, 0.0)) + p.stat_avg()
		cnt[p.team_id] = int(cnt.get(p.team_id, 0)) + 1
	var rows: Array = []
	for t in standings.keys():
		var tid: int = int(t)
		var e: Dictionary = standings[t]
		rows.append({
			"id": tid, "w": int(e["wins"]), "l": int(e["losses"]),
			"s": float(avg.get(tid, 0.0)) / float(maxi(1, int(cnt.get(tid, 0)))),
		})
	rows.sort_custom(func(a, b):
		if a["w"] != b["w"]:
			return a["w"] > b["w"]
		if a["l"] != b["l"]:
			return a["l"] < b["l"]
		if a["s"] != b["s"]:
			return a["s"] > b["s"]
		return a["id"] < b["id"])
	if rows.size() < 2:
		return (MISJUDGE_MIN + MISJUDGE_MAX) * 0.5
	for i in rows.size():
		if int(rows[i]["id"]) == team_id:
			return lerpf(MISJUDGE_MIN, MISJUDGE_MAX, float(i) / float(rows.size() - 1))
	return (MISJUDGE_MIN + MISJUDGE_MAX) * 0.5


# Resume path for the post-ban-pick save: rebuild match_ctx from the resume
# payload and scene-change directly to BattleSim. Mirrors _on_ban_pick_finished
# + _launch_battle without the UI controllers. 정글 방향은 BattleSim 이 다시
# 물으므로 여기서 복원하는 값은 상대 정글러와 폴백을 위한 기본값이다.
func _resume_at_launch(resume: Dictionary) -> void:
	player_side            = int(resume.get("player_side", GameEnums.DraftSide.BLUE))
	banned_mech_ids        = (resume.get("banned_mech_ids", []) as Array).duplicate()
	player_picked_mech_ids = (resume.get("player_picked_mech_ids", []) as Array).duplicate()
	enemy_picked_mech_ids  = (resume.get("enemy_picked_mech_ids", []) as Array).duplicate()

	var p_roster: Array = _team_roster(player_team_id)
	var e_roster: Array = _team_roster(enemy_team_id)
	var p_assigned: Array = resume.get("player_assigned_mech_ids", [])
	var e_assigned: Array = resume.get("enemy_assigned_mech_ids",  [])
	for i in range(min(5, p_roster.size(), p_assigned.size())):
		(p_roster[i] as PlayerData).assigned_mech = _find_mech(int(p_assigned[i]))
	for i in range(min(5, e_roster.size(), e_assigned.size())):
		(e_roster[i] as PlayerData).assigned_mech = _find_mech(int(e_assigned[i]))

	gm.match_ctx["player_roster"]    = p_roster
	gm.match_ctx["enemy_roster"]     = e_roster
	gm.match_ctx["jungle_start_dir"] = int(resume.get("jungle_start_dir", GameEnums.JungleStartDir.LEFT))
	_finalize_rosters(p_roster, e_roster)
	_launch_battle()


## After mech assignment (fresh or resumed): add the run's temporary pilot mods
## (`PilotMods.apply_to`) and the mech mastery bonus (`MechMastery.apply_to`) to
## the roster **copies**, then write `pending_match.assigned_mechs`
## (`{"<pilot_id>": mech_id}`, both teams) for `MechMastery.record_match`.
## Standalone MatchFlow (no active season) leaves the rosters as they are.
## Runs once — the resume path and the fresh path never both reach here.
func _finalize_rosters(p_roster: Array, e_roster: Array) -> void:
	if _rosters_finalized:
		return
	_rosters_finalized = true
	var s: Dictionary = gm.season_state
	if not bool(s.get("active", false)):
		return
	var assigned: Dictionary = {}
	for roster in [p_roster, e_roster]:
		for raw in roster:
			var pd := raw as PlayerData
			if pd == null:
				continue
			PilotMods.apply_to(s, pd)
			MechMastery.apply_to(s, pd)
			QuirkSystem.apply_to(s, pd)
			if pd.assigned_mech != null:
				assigned[str(pd.id)] = pd.assigned_mech.id
	var pm = s.get("pending_match", null)
	if typeof(pm) == TYPE_DICTIONARY:
		(pm as Dictionary)["assigned_mechs"] = assigned


# Extract the mech IDs from a role-sorted Array[PlayerData] (5 entries).
# Returns [] if the roster is malformed; safe defaults so a corrupt save
# won't crash on resume.
func _roster_mech_ids(roster: Array) -> Array:
	var out: Array = []
	for r in roster:
		var p := r as PlayerData
		if p == null or p.assigned_mech == null:
			out.append(-1)
		else:
			out.append(p.assigned_mech.id)
	return out


func _find_mech(id: int) -> MechData:
	for m_raw in all_mechs:
		var m := m_raw as MechData
		if m.id == id:
			return m
	return null


func _autosave(reason: String) -> void:
	var err: String = SaveSystem.save_run()
	if err != "":
		push_warning("MatchFlow: autosave (%s) failed — %s" % [reason, err])
	else:
		print("MatchFlow: autosave (%s) → %s" % [reason, SaveSystem.run_path()])


# ── 치트 (에디터 실행 전용) ───────────────────────────────────────────────────
# 런 테스트용. 경기 시작 전(PREP · BAN_PICK)에 그 경기를 전투 없이 끝낸다.
# 결과는 BattleSim.end_match 가 적는 것과 같은 모양으로 `pending_match` 에
# 적고 시즌으로 돌아간다 — SeasonHub 가 평소의 경기 끝 경로로 정산한다.
# 결과를 받을 `pending_match` 가 없는 단독 실행에서는 메뉴를 만들지 않는다.
func _setup_cheats() -> void:
	if not OS.has_feature("editor"):
		return
	if not gm.season_state.get("active", false) or gm.season_state.get("pending_match", null) == null:
		return
	_cheat_menu = MatchCheatMenu.create()
	_cheat_menu.name = "MatchCheatMenu"
	add_child(_cheat_menu)
	_refresh_cheats()


func _refresh_cheats() -> void:
	if _cheat_menu == null:
		return
	var actions: Array = []
	if phase == GameEnums.MatchPhase.PREP or phase == GameEnums.MatchPhase.BAN_PICK:
		actions.append({"label": "즉시 승리 (MVP 아군 탑)", "call": _cheat_finish.bind(0)})
		actions.append({"label": "즉시 패배 (MVP 상대 탑)", "call": _cheat_finish.bind(1)})
	_cheat_menu.set_actions(actions)


## 이 경기를 `winner_side`(0 = 내 팀) 승리로 끝낸다. 열 명의 기록은 전부 0,
## MVP 는 이긴 팀의 탑(`RunStats.top_role`).
func _cheat_finish(winner_side: int) -> void:
	var pm = gm.season_state.get("pending_match", null)
	if pm == null:
		return
	var rows: Array = []
	var mvp_id: int = -1
	var sides: Array = [_team_roster(player_team_id), _team_roster(enemy_team_id)]
	for side in sides.size():
		for raw in sides[side]:
			var pd := raw as PlayerData
			rows.append({
				"pilot_id": pd.id, "side": side, "role": pd.role,
				"k": 0, "d": 0, "a": 0, "dmg": 0, "taken": 0, "care": 0,
			})
			if side == winner_side and pd.role == RunStats.top_role():
				mvp_id = pd.id
	pm["winner_side"]  = winner_side
	pm["pilot_stats"]  = rows
	pm["mvp_pilot_id"] = mvp_id
	gm.season_state["match_resume"] = null
	print("MatchFlow: CHEAT — match resolved, winner_side=%d mvp=%d" % [winner_side, mvp_id])
	SceneFade.change_scene(get_tree(), "res://scenes/Season.tscn")


# ── Helpers ──────────────────────────────────────────────────────────────────
func _team_roster(team_id: int) -> Array:
	# Returns 5 PlayerData **copies** sorted by role 0..4 for the given team,
	# cached so every phase (PREP, BAN_PICK, launch, cheat) sees the same objects.
	# League teams (id < 100) live in `all_players`; INTL teams (id >= 100)
	# live in season_state.intl_pilots — only relevant when launched from
	# Season into an INTL phase. Standalone MatchFlow only uses league teams.
	if _roster_cache.has(team_id):
		return _roster_cache[team_id]
	var pool: Array = all_players
	if team_id >= 100:
		pool = gm.season_state.get("intl_pilots", []) if gm.season_state.get("active", false) else []
	var out: Array = []
	for r in range(5):
		for p_raw in pool:
			var p := p_raw as PlayerData
			if p.team_id == team_id and p.role == r:
				out.append(_copy_pilot(p))
				break
	_roster_cache[team_id] = out
	return out


# `Resource.duplicate()` copies the exported fields; the list fields are
# re-copied so the match copy shares no container with the season original.
static func _copy_pilot(p: PlayerData) -> PlayerData:
	var c := p.duplicate() as PlayerData
	c.pilot_cards = p.pilot_cards.duplicate()
	c.main_mechs = p.main_mechs.duplicate()
	c.assigned_mech = null
	return c


func _team_name(team_id: int) -> String:
	# season_state.team_meta / intl_team_meta (l10n keys, D7) — or the teams.csv
	# package table when MatchFlow is launched directly from the editor.
	return String(gm.team_name(team_id))


func _show_error(msg: String) -> void:
	var lbl := Label.new()
	lbl.text = "MatchFlow load error\n\n" + msg + \
		"\n\nRun Project → Tools → Rebuild game.db then restart."
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(lbl)
