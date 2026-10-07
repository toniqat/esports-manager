class_name GameOverView
extends Control

# Game-over screen. Six tournaments, any non-title ends the run (§3 M2):
#   - a league phase's playoff cut missed      (playoff_failed_qualification)
#   - a league phase's playoff SF / F lost     (playoff_lost)
#   - any INTL lost, in any round              (intl_failed_campaign)
# SeasonHub settles the run (RunResult, outcome "fail") before this screen
# shows, so run.save is already gone. Only action: `정산` → RunResult.tscn.
#
# **Layout lives in `UI_View_GameOverView.tscn`** (title, reason / summary lines, bottom bar). This
# script binds `%` nodes, fills the texts and applies the safe-area offsets (pattern B).
# Create with `GameOverView.create()`.

const SCENE_PATH: String = "res://features/season/UI_View_GameOverView.tscn"

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _reason_lbl: Label
var _summary_lbl: Label
var _built: bool = false
# 탈락 라운드 · 순위를 읽는 매니저 — 실제 게임은 `_hub` 의 것을 매번 다시 읽는다
# (`_resolve_refs`). 호스트가 없는 F6 미리보기만 직접 넣는다.
var _league: LeagueManager = null
var _tournament: TournamentManager = null
var _intl: InternationalTournament = null


## Instantiates the scene. `GameOverView.new()` is an empty Control — don't use it.
static func create() -> GameOverView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as GameOverView


func _ready() -> void:
	_bind()
	if UiPreview.is_standalone(self):
		_fill_preview()
	refresh()


# Idempotent — SeasonHub calls this each time it routes to GAME_OVER.
func ensure_view() -> void:
	_bind()
	refresh()
	# 캠페인이 끝났다 — 이 화면이 열리는 것 자체가 결과다.
	Haptics.play(Haptics.Kind.ERROR)


# ── Bind ─────────────────────────────────────────────────────────────────────
func _bind() -> void:
	if _built:
		return
	_built = true
	# 화면 전체를 안전 영역 위끝까지 내리고, 배경만 노치 자리까지 다시 덮는다.
	ScreenMetrics.indent_to_safe_top(self)
	ScreenMetrics.extend_background(%Background)
	OutgameTheme.fit_bottom_bar(%BottomBar, %SafeBottom)
	_reason_lbl = %Reason
	_summary_lbl = %Summary
	# 갈 길은 하나 — 정산 화면.
	%Settle.pressed.connect(_on_settle_pressed)


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not _built:
		return
	_resolve_refs()
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	var phase_name: String = GameEnums.phase_label(phase)

	# 어느 대회에서 끝났는가는 페이즈가, 어떻게 끝났는가는 phase_results 와
	# 아직 남아 있는 대진표(탈락 직후라 페이즈가 넘어가지 않았다)가 말해 준다.
	var is_intl: bool = (phase == GameEnums.SeasonPhase.PRESEASON_INTL
			or phase == GameEnums.SeasonPhase.MIDSEASON_INTL
			or phase == GameEnums.SeasonPhase.REGULAR_INTL)
	var lost_at: String = _lost_round_label()
	if is_intl:
		_reason_lbl.text = "%s %s에서 탈락했습니다." % [phase_name, lost_at] if lost_at != "" 				else "%s에서 우승하지 못했습니다." % phase_name
		_summary_lbl.text = _title_summary_text()
	elif bool(s.get("phase_results", {}).get(phase, {}).get("made_playoffs", false)):
		_reason_lbl.text = "%s 플레이오프 %s에서 탈락했습니다." % [phase_name, lost_at] if lost_at != "" 				else "%s 플레이오프에서 우승하지 못했습니다." % phase_name
		_summary_lbl.text = _title_summary_text()
	else:
		_reason_lbl.text = "%s 플레이오프 진출에 실패했습니다." % phase_name
		_summary_lbl.text = _league_rank_text()


func _resolve_refs() -> void:
	if _hub == null:
		return
	_league = _hub.get_node_or_null("LeagueManager") as LeagueManager
	_tournament = _hub.get_node_or_null("TournamentManager") as TournamentManager
	_intl = _hub.get_node_or_null("InternationalTournament") as InternationalTournament


## 지금 대진표에서 플레이어 팀이 진 경기의 라운드 이름("4강 1경기" · "결승" …).
## 대진표가 없거나 진 경기가 없으면 "".
func _lost_round_label() -> String:
	var s: Dictionary = _gm.season_state
	var t = s.get("current_tournament", null)
	if t == null:
		return ""
	var pid: int = int(s["player_team_id"])
	var b: Array = t.get("bracket", [])
	for i in b.size():
		var m: Dictionary = b[i]
		if not bool(m["played"]) or int(m["winner"]) == pid:
			continue
		if int(m["team_a"]) != pid and int(m["team_b"]) != pid:
			continue
		if String(t.get("type", "")) == "INTL":
			return _intl.slot_label(i) if _intl != null else ""
		return _tournament.slot_label(i) if _tournament != null else ""
	return ""


func _league_rank_text() -> String:
	var s: Dictionary = _gm.season_state
	var pid: int = int(s["player_team_id"])
	var league: LeagueManager = _league
	if league == null:
		return ""
	var ranked: Array = league.standings_ranked()
	for i in ranked.size():
		if int(ranked[i]["team_id"]) == pid:
			var row: Dictionary = ranked[i]
			return "최종 순위 %d위 — %d승 %d패" % [
				i + 1, int(row["wins"]), int(row["losses"]),
			]
	return ""


func _title_summary_text() -> String:
	var pr: Dictionary = _gm.season_state.get("phase_results", {})
	var wins: int = 0
	for k in pr.keys():
		var r: Dictionary = pr[k]
		if int(r.get("champion", -1)) == int(_gm.season_state["player_team_id"]):
			wins += 1
		if int(r.get("intl_champion", -1)) == int(_gm.season_state["player_team_id"]):
			wins += 1
	return "캠페인 우승 %d회 — 캠페인 종료" % wins


# ── Button handler ──────────────────────────────────────────────────────────
# 정산(프로필 반영 · run.save 삭제)은 SeasonHub 가 이 화면에 들어서며 이미 했다.
# 여기서는 결과 화면으로 넘어가기만 한다.
func _on_settle_pressed() -> void:
	get_tree().change_scene_to_file(RunResult.SCENE_PATH)


## F6 단독 실행 미리보기 — 메모리 런의 프리시즌 리그를 다 치르고, 플레이오프 결승에서
## 진 상태(`resources/UiPreview.gd`). 결과는 실제 길대로 `TournamentManager.record_result` 로
## 적는다(메모리만). 정산(`RunResult.settle_current_run`)은 부르지 않는다 — 실제로도 SeasonHub 가
## 이 화면 **전에** 하는 일이다. "정산" 버튼은 장면을 넘기지 않고 출력만 한다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	if UiPreview.ensure_run() == null:
		return
	var s: Dictionary = _gm.season_state
	_league = UiPreview.ensure_league(self, CalendarSystem.LEAGUE_WEEKS[int(s["current_phase"])])
	_tournament = TournamentManager.new()
	_tournament.name = "PreviewPlayoff"
	add_child(_tournament)
	var b: Array = UiPreview.playoff_bracket(s, _league)
	var pid: int = int(s["player_team_id"])
	# 4강은 우리 팀이 이기고, 결승은 진다.
	for slot in 2:
		var m: Dictionary = b[slot]
		var a: int = int(m["team_a"])
		var bb: int = int(m["team_b"])
		var winner: int = pid if pid == a or pid == bb else _league.simulate_ai_match(a, bb)
		_tournament.record_result(slot, winner)
	s["phase_week"] = int(s["phase_week"]) + 1
	var fin: Dictionary = b[2]
	_tournament.record_result(2, int(fin["team_b"]) if int(fin["team_a"]) == pid else int(fin["team_a"]))
	%Settle.pressed.disconnect(_on_settle_pressed)
	UiPreview.trace(%Settle.pressed, "정산")
