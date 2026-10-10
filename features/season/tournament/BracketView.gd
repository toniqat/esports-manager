class_name BracketView
extends Control

# Phase 7 — playoff bracket screen. 4-team single elimination visualised as
# two semifinal panels stacked on the left and a final panel on the right.
# Each match panel shows team_a / team_b, the winner indicator, and the
# scheduled date. Player team is tinted gold, played matches dim losers.
#
# **Layout lives in `UI_View_BracketView.tscn`** — build it with `BracketView.create()`. The three
# boxes are `UI_Comp_BracketMatchBox.tscn` instances placed in `%Bracket` (semis column + final,
# vertically centred by the HBox) and bound as `%BracketMatchBox_SF1` `%BracketMatchBox_SF2` `%BracketMatchBox_Final`; each paints its own
# data colours (`BracketMatchBox.show_match`). The script fills text and applies the
# device-dependent bits: safe-area top indent, background into the notch, bottom bar inset.

## Built from `UI_View_BracketView.tscn` — use `create()`, not `.new()`.
const SCENE_PATH: String = "res://features/season/tournament/UI_View_BracketView.tscn"

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _league: LeagueManager = null
var _tournament: TournamentManager = null


static func create() -> BracketView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as BracketView


func _ready() -> void:
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 바탕만 노치 자리까지 도로 늘린다(`docs/mobile_safe_area.md`).
	ScreenMetrics.indent_to_safe_top(self)
	ScreenMetrics.extend_background(%Background)
	_layout_ok_button()
	%FloatingBarButton_OkButton.pressed.connect(_on_back_pressed)
	if UiPreview.is_standalone(self):
		_fill_preview()
	ensure_view()


# Idempotent — SeasonHub calls this each time it routes to PLAYOFF.
func ensure_view() -> void:
	_resolve_refs()
	refresh()


func _resolve_refs() -> void:
	if _hub == null:
		return
	if _league == null:
		_league = _hub.get_node_or_null("LeagueManager") as LeagueManager
	if _tournament == null:
		_tournament = _hub.get_node_or_null("TournamentManager") as TournamentManager


## 버튼은 하나뿐이다("확인") — 주를 넘기는 일은 시간 경과 화면의 일요일
## 마감이 가져갔고, 돌아갈 자리는 버튼이 아니라 주 진행 상태가 정한다
## (`SeasonHub.on_standings_confirmed`). The only action, so one full-width
## floating capsule — the look is the scene's (`BarPrimaryButton`), placement + device inset
## are `OutgameTheme.fit_bottom_bar`.
func _layout_ok_button() -> void:
	OutgameTheme.fit_bottom_bar(%FloatingBarButton_OkButton)


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not is_inside_tree():
		return
	_resolve_refs()
	if _tournament == null:
		return

	var phase: int = int(_gm.season_state["current_phase"])
	%Phase.text = Loc.t(L.SEASON_COMMON_CURRENT_PHASE, {"phase": GameEnums.phase_label(phase)})

	if not _tournament.is_active():
		%Empty.visible = true
		%Stage.text = ""
		%NextMatch.text = ""
		%Bracket.visible = false
		return
	%Empty.visible = false
	%Bracket.visible = true

	var t: Dictionary = _gm.season_state["current_tournament"]
	var stage: int = int(t["stage"])
	%Stage.text = Loc.t(L.SEASON_BRACKET_STAGE, {"stage": _stage_name(stage)})

	var pid: int = int(_gm.season_state["player_team_id"])
	var nxt = _tournament.next_unplayed_player_match()
	if nxt == null:
		%NextMatch.text = Loc.t(L.SEASON_BRACKET_NO_PLAYER_MATCH)
	else:
		var opp_id: int = int(nxt["team_b"]) if int(nxt["team_a"]) == pid else int(nxt["team_a"])
		var opp_name: String = "TBD"
		if opp_id >= 0 and _league != null:
			opp_name = _league.team_name(opp_id)
		%NextMatch.text = Loc.t(L.SEASON_BRACKET_NEXT_MATCH, {
			"slot": _tournament.slot_label(int(nxt["slot"])),
			"week": int(nxt["phase_week"]),
			"team": opp_name,
		})

	var b: Array = _tournament.bracket()
	var boxes: Array = _match_boxes()
	for i in boxes.size():
		(boxes[i] as BracketMatchBox).show_match(b[i] if i < b.size() else {}, pid, _team_text)


## Slot order = bracket index order (SF1, SF2, F).
func _match_boxes() -> Array:
	return [%BracketMatchBox_SF1, %BracketMatchBox_SF2, %BracketMatchBox_Final]


func _team_text(team_id: int) -> String:
	if _league == null:
		return "Team %d" % team_id
	return "%s  (%s)" % [_league.team_name(team_id), _league.team_short_name(team_id)]


func _stage_name(stage: int) -> String:
	match stage:
		GameEnums.TournamentStage.PLAYOFF_SF: return Loc.t(L.SEASON_BRACKET_STAGE_SF)
		GameEnums.TournamentStage.PLAYOFF_F:  return Loc.t(L.SEASON_BRACKET_STAGE_F)
		GameEnums.TournamentStage.CHAMPION:   return Loc.t(L.SEASON_BRACKET_STAGE_CHAMPION)
	return "—"


# ── Button handlers ─────────────────────────────────────────────────────────
func _on_back_pressed() -> void:
	if _hub != null and _hub.has_method("on_standings_confirmed"):
		_hub.on_standings_confirmed()


## F6 단독 실행 미리보기 — 메모리 런의 프리시즌 리그를 다 치르고, 4강 둘이 끝나 결승을
## 기다리는 대진표(`resources/UiPreview.gd`). 결과는 실제 길대로 `record_result` 로 적는다
## (메모리만). 호스트(`SeasonHub`)가 없어 "확인" 은 아무 일도 안 한다.
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
	for slot in 2:
		var m: Dictionary = b[slot]
		var a: int = int(m["team_a"])
		var bb: int = int(m["team_b"])
		var winner: int = pid if pid == a or pid == bb else _league.simulate_ai_match(a, bb)
		_tournament.record_result(slot, winner)
	s["phase_week"] = int(s["phase_week"]) + 1
	UiPreview.trace(%FloatingBarButton_OkButton.pressed, "확인")  # l10n-ignore
