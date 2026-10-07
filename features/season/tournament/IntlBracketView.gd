class_name IntlBracketView
extends Control


# Phase 8 — INTL bracket screen. 8-team single elimination visualised as
# 4 QF panels stacked left, 2 SF panels middle, 1 F panel right. Player team
# panels are tinted gold; played matches dim losers, winners pop.
#
# Mirrors features/season/tournament/BracketView.gd (Phase 7 4-team layout)
# but is a separate screen because the panel grid + slot count differ.
#
# **Layout lives in `IntlBracketView.tscn`** — build it with `IntlBracketView.create()`.
# The seven boxes are `IntlMatchBox.tscn` instances (script `BracketMatchBox`) in
# `%Bracket`: a QF column, an SF column and an F column with spacer Controls fixing the
# vertical offsets, bound as `%QF1`..`%QF4` `%SF1` `%SF2` `%Final`. Box sizes (QF 280×130,
# SF 280×150, F 320×170) are the instances' minimum sizes in the scene.

## Built from `IntlBracketView.tscn` — use `create()`, not `.new()`.
const SCENE_PATH: String = "res://features/season/tournament/IntlBracketView.tscn"

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _intl: InternationalTournament = null


static func create() -> IntlBracketView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as IntlBracketView


func _ready() -> void:
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 바탕만 노치 자리까지 도로 늘린다(`docs/mobile_safe_area.md`).
	ScreenMetrics.indent_to_safe_top(self)
	ScreenMetrics.extend_background(%Background)
	_layout_ok_button()
	%OkButton.pressed.connect(_on_back_pressed)
	ensure_view()


# Idempotent — SeasonHub calls this each time it routes to INTL_BRACKET.
func ensure_view() -> void:
	_resolve_refs()
	refresh()


func _resolve_refs() -> void:
	if _hub == null:
		return
	if _intl == null:
		_intl = _hub.get_node_or_null("InternationalTournament") as InternationalTournament


## 버튼은 하나뿐이다("확인") — 주를 넘기는 일은 시간 경과 화면의 일요일
## 마감이 가져갔고, 돌아갈 자리는 버튼이 아니라 주 진행 상태가 정한다
## (`SeasonHub.on_standings_confirmed`). 하나뿐인 행동이라 **하단 구간을 통째로
## 차지한다** — 자리와 각진 모양은 씬(앵커 · `BarPrimaryButton`)이, 기기 몫(아래
## 인셋)만 코드가 넣는다(`OutgameTheme.fit_bottom_bar`).
func _layout_ok_button() -> void:
	OutgameTheme.fit_bottom_bar(%OkButton)


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not is_inside_tree():
		return
	_resolve_refs()
	if _intl == null:
		return

	var phase: int = int(_gm.season_state["current_phase"])
	%Phase.text = "현재 페이즈: %s" % HubView.PHASE_NAMES.get(phase, "—")

	if not _intl.is_active():
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
	var nxt = _intl.next_unplayed_player_match()
	if nxt == null:
		%NextMatch.text = "플레이어 경기 없음 / 종료됨"
	else:
		var opp_id: int = int(nxt["team_b"]) if int(nxt["team_a"]) == pid else int(nxt["team_a"])
		var opp_name: String = "TBD" if opp_id < 0 else _intl.team_name(opp_id)
		%NextMatch.text = "다음 매치: %s — %d주차 vs %s" % [
			_intl.slot_label(int(nxt["slot"])),
			int(nxt["phase_week"]),
			opp_name,
		]

	var b: Array = _intl.bracket()
	var boxes: Array = _match_boxes()
	for i in boxes.size():
		(boxes[i] as BracketMatchBox).show_match(b[i] if i < b.size() else {}, pid, _team_text)


## Slot order = bracket index order (QF1..QF4, SF1, SF2, F).
func _match_boxes() -> Array:
	return [%QF1, %QF2, %QF3, %QF4, %SF1, %SF2, %Final]


func _team_text(team_id: int) -> String:
	if _intl == null:
		return "Team %d" % team_id
	return "%s  (%s)" % [_intl.team_name(team_id), _intl.team_short_name(team_id)]


func _stage_name(stage: int) -> String:
	match stage:
		GameEnums.TournamentStage.INTL_QF: return "8강 진행 중"
		GameEnums.TournamentStage.INTL_SF: return "4강 진행 중"
		GameEnums.TournamentStage.INTL_F:  return "결승 진행 중"
		GameEnums.TournamentStage.CHAMPION: return "우승 결정"
	return "—"


func _on_back_pressed() -> void:
	if _hub != null and _hub.has_method("on_standings_confirmed"):
		_hub.on_standings_confirmed()
