class_name HomeTab
extends Control

# 로비의 홈 탭 — 진행 중인 런 카드와 행동 바: 런이 있으면 가운데 `이어하기` + 그 왼쪽의 둥근 X
# 버튼(새 게임 = 런 포기 모달), 없으면 빈 상태 카드와 `게임 시작` 하나. 탭 계약은 `LobbyScreen.gd` 머리말.
# The capsule is half the usual row width and 10 % taller, centred (`bar_scale`, applied by the
# host); the round X slot hangs left of it (`LobbyScreen._lift_bar`).
#
# **레이아웃 · 스타일의 정본은 `UI_View_HomeTab.tscn`** — 이 스크립트는 `%노드` 에 글을 넣고
# 런 카드 / 빈 카드 중 하나를 보일 뿐이다. 생성은 `HomeTab.create()`.
#
# `게임 시작` 을 누를 때 런이 없으면 host 의 시나리오 선택 모드(`open_scenario_select`)를
# 연다. 런이 있을 때 X 는 **런 포기 모달**(`AbandonRunPopup`: 런 요약 + 경고)을 띄운다 — 확인하면 그 런을
# **포기로 정산**(`RunResult.settle_current_run("abandon")`, 실패 정산이지만 보상은
# 준다)하고 정산 화면으로 간다. 그 화면의 `새 런` 이 런 준비로 잇는다.

## Action bar font (32 before the home bar grew 10 %).
const BAR_FONT: int = 35
const SCENE_PATH: String = "res://features/meta/lobby/UI_View_HomeTab.tscn"
## Round "new game" (abandon) slot icon.
const NEW_GAME_ICON: String = "res://resources/images/ui/lobby/icon_close.svg"

var _host: LobbyScreen
var _gm: Node
var _pm: Node
var _has_run: bool = false
var _meta: Dictionary = {}


## 씬을 인스턴스한다. `HomeTab.new()` 는 빈 Control 이라 쓰지 않는다.
static func create() -> HomeTab:
	return (load(SCENE_PATH) as PackedScene).instantiate() as HomeTab


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


func bar_specs() -> Array:
	# 런이 있으면 둥근 X(새 게임 = 포기 모달) + 가운데 이어하기. 없으면 게임 시작 하나.
	if SaveSystem.has_run():
		return [
			{"text": "", "icon": NEW_GAME_ICON, "round": true, "style": "ghost"},
			{"text": Loc.t(L.LOBBY_HOME_CONTINUE), "style": "primary", "font": BAR_FONT, "weight": 1.0},
		]
	return [{"text": Loc.t(L.LOBBY_HOME_START), "style": "primary", "font": BAR_FONT, "weight": 1.0}]


## Optional host hook (`LobbyScreen._lift_bar`): the row's total width × x (centred) and the
## capsule height × y. Home = half the full row, 10 % taller.
func bar_scale() -> Vector2:
	return Vector2(0.5, 1.1)


func setup(host: LobbyScreen) -> void:
	_host = host
	_gm = get_node("/root/GameManager")
	_pm = get_node("/root/ProfileManager")
	_has_run = SaveSystem.has_run()
	_meta = SaveSystem.read_run_meta() if _has_run else {}
	_fill()


func on_shown() -> void:
	pass


func on_bar_pressed(i: int) -> void:
	if _has_run and i == 1:
		_on_continue_pressed()
	else:
		_on_start_pressed()


# ── Fill (레이아웃 · 스타일은 UI_View_HomeTab.tscn) ─────────────────────────────────────
func _fill() -> void:
	var mgr_lv: int = ManagerProgress.level_of(_pm.profile)
	%Summary.text = Loc.t(L.LOBBY_HOME_SUMMARY, {"level": mgr_lv,
			"pilots": (_pm.owned_pilot_ids() as Array).size(),
			"traits": (_pm.owned_trait_ids() as Array).size()})
	if _has_run and not _meta.is_empty():
		_show_run(_meta)
	else:
		%RunCard.visible = false
		%EmptyCard.visible = true


## 런 카드를 `meta`(`SaveSystem.read_run_meta()`)로 채우고 빈 카드를 숨긴다.
func _show_run(meta: Dictionary) -> void:
	%EmptyCard.visible = false
	%RunCard.visible = true
	var tx: Dictionary = run_texts(meta, _gm)
	%Phase.text = tx["phase"]
	%LiveChip.visible = bool(meta.get("match_in_progress", false))
	%Date.text = tx["date"]
	%Team.text = tx["team"]
	%Trophies.text = tx["trophies"]
	%Record.text = tx["record"]
	%SavedAt.text = tx["saved_at"]


## The run card's lines for `meta` (`SaveSystem.read_run_meta()`) — shared with `AbandonRunPopup`.
## Keys: phase · date · team · trophies · record · saved_at. `gm` = the GameManager autoload.
static func run_texts(meta: Dictionary, gm: Node) -> Dictionary:
	var rank: int = int(meta.get("rank", 0))
	var record: String = Loc.t(L.LOBBY_HOME_LEAGUE_NOT_STARTED)
	if rank > 0:
		record = Loc.t(L.LOBBY_HOME_LEAGUE_RANK, {"rank": rank,
				"win": int(meta.get("wins", 0)), "loss": int(meta.get("losses", 0))})
	return {
		"phase": GameEnums.phase_label(int(meta.get("phase", 0))),
		"date": Loc.t(L.LOBBY_HOME_DATE, {
				"year": int(meta.get("year", 1)), "month": int(meta.get("month", 12)),
				"day": int(meta.get("day", 1)), "weekday": _weekday_name(int(meta.get("weekday", 0)))}),
		"team": String(gm.team_name(int(meta.get("team_id", 0)))),
		"trophies": Loc.t(L.LOBBY_HOME_TROPHIES, {"n": int(meta.get("trophies", 0))}),
		"record": record,
		"saved_at": Loc.t(L.LOBBY_HOME_SAVED_AT, {"time": String(meta.get("saved_at", ""))}),
	}


static func _weekday_name(wd: int) -> String:
	if wd >= 0 and wd < OutgameTheme.DAY_LETTERS.size():
		return OutgameTheme.day_letter(wd)
	return "?"


# ── Actions ──────────────────────────────────────────────────────────────────
func _on_continue_pressed() -> void:
	var err: String = SaveSystem.load_run()
	if err != "":
		_host.show_toast(Loc.t(L.LOBBY_HOME_LOAD_FAILED, {"error": err}), true)
		return
	# Mid-match save: jump straight back into MatchFlow (which reads
	# season_state.match_resume on _ready and skips ahead to the saved phase).
	if _gm.season_state.get("match_resume", null) != null:
		get_tree().change_scene_to_file("res://scenes/MatchFlow.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Season.tscn")


func _on_start_pressed() -> void:
	if not _has_run:
		_host.open_scenario_select(true)
		return
	Haptics.play(Haptics.Kind.WARNING)
	_host.open_abandon_run(_meta, _on_abandon_confirmed)


func _on_abandon_confirmed() -> void:
	# 포기 = 그 시점 진척으로 실패 정산(계획서 §10.3) — 셀 수 있게 런을 먼저 싣는다.
	var lerr: String = SaveSystem.load_run()
	if lerr == "":
		Haptics.play(Haptics.Kind.ERROR)
		RunResult.settle_current_run(RunResult.OUTCOME_ABANDON)
		get_tree().change_scene_to_file(RunResult.SCENE_PATH)
		return
	# 깨진 런 — 정산할 것이 없다. 지우고 시나리오 선택으로.
	push_warning("Lobby: abandon could not load run (%s) — deleting without settlement" % lerr)
	var err: String = SaveSystem.delete_run()
	if err != "":
		_host.show_toast(Loc.t(L.LOBBY_HOME_DELETE_FAILED, {"error": err}), true)
		return
	Haptics.play(Haptics.Kind.ERROR)
	_has_run = false
	_meta = {}
	_fill()
	_host.rebuild_bar()
	_host.open_scenario_select(true)


## F6 단독 실행 미리보기 — 메모리 런(몇 주 치른 리그)의 런 카드 (`resources/UiPreview.gd`).
## 런 파일은 읽지도 쓰지도 않는다: 메타는 `SaveSystem` 의 런 메타와 같은 칸을 메모리 런에서
## 채운다. 행동 바는 호스트(`LobbyScreen`) 몫이라 없다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	_pm = get_node("/root/ProfileManager")
	_gm = UiPreview.ensure_run()
	if _gm == null:
		_fill()
		return
	var lm: LeagueManager = UiPreview.ensure_league(self, 3)
	var s: Dictionary = _gm.season_state
	var pid: int = int(s["player_team_id"])
	var rank: int = 0
	var wins: int = 0
	var losses: int = 0
	var ranked: Array = lm.standings_ranked()
	for i in ranked.size():
		if int(ranked[i]["team_id"]) == pid:
			rank = i + 1
			wins = int(ranked[i]["wins"])
			losses = int(ranked[i]["losses"])
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	_has_run = true
	_meta = {
		"phase": int(s.get("current_phase", 0)), "year": int(s.get("year", 1)),
		"month": int(s.get("month", 12)), "day": int(s.get("day", 1)),
		"weekday": int(s.get("weekday", 0)), "team_id": pid,
		"trophies": 1, "rank": rank, "wins": wins, "losses": losses,
		"saved_at": "%04d-%02d-%02d %02d:%02d" % [dt["year"], dt["month"], dt["day"],
				dt["hour"], dt["minute"]],
		"match_in_progress": true,
	}
	_fill()
