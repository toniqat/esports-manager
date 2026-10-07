class_name BracketView
extends Control

# Phase 7 — playoff bracket screen. 4-team single elimination visualised as
# two semifinal panels stacked on the left and a final panel on the right.
# Each match panel shows team_a / team_b, the winner indicator, and the
# scheduled date. Player team is tinted gold, played matches dim losers.
#
# **Layout lives in `BracketView.tscn`** — build it with `BracketView.create()`. The three
# boxes are `BracketMatchBox.tscn` instances placed in `%Bracket` (semis column + final,
# vertically centred by the HBox) and bound as `%SF1` `%SF2` `%Final`; each paints its own
# data colours (`BracketMatchBox.show_match`). The script fills text and applies the
# device-dependent bits: safe-area top indent, background into the notch, bottom bar inset.

## Built from `BracketView.tscn` — use `create()`, not `.new()`.
const SCENE_PATH: String = "res://features/season/tournament/BracketView.tscn"

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
	%OkButton.pressed.connect(_on_back_pressed)
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
## (`SeasonHub.on_standings_confirmed`). 하나뿐인 행동이라 **하단 구간을 통째로
## 차지한다** — 자리는 씬의 앵커가, 기기 몫(각진 모서리 · 아래 인셋)만 코드가
## 넣는다(`OutgameTheme.style_bottom_button`).
func _layout_ok_button() -> void:
	var btn: Button = %OkButton
	OutgameTheme.style_bottom_button(btn, "primary", OutgameTheme.FONT_BTN_PRIMARY)
	btn.offset_top = -(OutgameTheme.BOTTOM_BAR_H + maxf(0.0, ScreenMetrics.insets().w))


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not is_inside_tree():
		return
	_resolve_refs()
	if _tournament == null:
		return

	var phase: int = int(_gm.season_state["current_phase"])
	%Phase.text = "현재 페이즈: %s" % HubView.PHASE_NAMES.get(phase, "—")

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
	%Stage.text = "단계: %s" % _stage_name(stage)

	var pid: int = int(_gm.season_state["player_team_id"])
	var nxt = _tournament.next_unplayed_player_match()
	if nxt == null:
		%NextMatch.text = "플레이어 경기 없음 / 종료됨"
	else:
		var opp_id: int = int(nxt["team_b"]) if int(nxt["team_a"]) == pid else int(nxt["team_a"])
		var opp_name: String = "TBD"
		if opp_id >= 0 and _league != null:
			opp_name = _league.team_name(opp_id)
		%NextMatch.text = "다음 매치: %s — %d주차 vs %s" % [
			_tournament.slot_label(int(nxt["slot"])),
			int(nxt["phase_week"]),
			opp_name,
		]

	var b: Array = _tournament.bracket()
	var boxes: Array = _match_boxes()
	for i in boxes.size():
		(boxes[i] as BracketMatchBox).show_match(b[i] if i < b.size() else {}, pid, _team_text)


## Slot order = bracket index order (SF1, SF2, F).
func _match_boxes() -> Array:
	return [%SF1, %SF2, %Final]


func _team_text(team_id: int) -> String:
	if _league == null:
		return "Team %d" % team_id
	return "%s  (%s)" % [_league.team_name(team_id), _league.team_short_name(team_id)]


func _stage_name(stage: int) -> String:
	match stage:
		GameEnums.TournamentStage.PLAYOFF_SF: return "4강 진행 중"
		GameEnums.TournamentStage.PLAYOFF_F:  return "결승 진행 중"
		GameEnums.TournamentStage.CHAMPION:   return "우승 결정"
	return "—"


# ── Button handlers ─────────────────────────────────────────────────────────
func _on_back_pressed() -> void:
	if _hub != null and _hub.has_method("on_standings_confirmed"):
		_hub.on_standings_confirmed()
