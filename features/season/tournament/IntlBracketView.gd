class_name IntlBracketView
extends Control


# Phase 8 — INTL bracket screen. 8-team single elimination visualised as
# 4 QF panels stacked left, 2 SF panels middle, 1 F panel right. Player team
# panels are tinted gold; played matches dim losers, winners pop.
#
# Mirrors features/season/tournament/BracketView.gd (Phase 7 4-team layout)
# but is a separate screen because the panel grid + slot count differ.
#
# **Layout lives in `UI_View_IntlBracketView.tscn`** — build it with `IntlBracketView.create()`.
# The seven boxes are `UI_Comp_IntlMatchBox.tscn` instances (script `BracketMatchBox`) in
# `%Bracket`: a QF column, an SF column and an F column with spacer Controls fixing the
# vertical offsets, bound as `%IntlMatchBox_QF1`..`%IntlMatchBox_QF4` `%IntlMatchBox_SF1` `%IntlMatchBox_SF2` `%IntlMatchBox_Final`. Box sizes (QF 280×130,
# SF 280×150, F 320×170) are the instances' minimum sizes in the scene.

## Built from `UI_View_IntlBracketView.tscn` — use `create()`, not `.new()`.
const SCENE_PATH: String = "res://features/season/tournament/UI_View_IntlBracketView.tscn"

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
	if UiPreview.is_standalone(self):
		_fill_preview()
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
	%Phase.text = "현재 페이즈: %s" % GameEnums.phase_label(phase)

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
	return [%IntlMatchBox_QF1, %IntlMatchBox_QF2, %IntlMatchBox_QF3, %IntlMatchBox_QF4, %IntlMatchBox_SF1, %IntlMatchBox_SF2, %IntlMatchBox_Final]


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


## F6 단독 실행 미리보기 — 메모리 런의 프리시즌 리그 상위 넷 + 해외 넷으로 프리시즌
## 국제대회를 깔고, 8강 넷이 끝나 4강을 기다리는 대진표(`resources/UiPreview.gd`). 결과는
## 실제 길대로 `record_result` 로 적는다(메모리만). 호스트가 없어 "확인" 은 아무 일도 안 한다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	if UiPreview.ensure_run() == null:
		return
	var s: Dictionary = _gm.season_state
	var lm: LeagueManager = UiPreview.ensure_league(self,
			CalendarSystem.LEAGUE_WEEKS[int(s["current_phase"])])
	_intl = InternationalTournament.new()
	_intl.name = "PreviewIntl"
	add_child(_intl)
	# 리그 팀 이름은 대회 매니저가 자기 리그로 읽는데, 보통은 호스트에서 찾는다.
	_intl.bind_league(lm)
	var pid: int = int(s["player_team_id"])
	var top4: Array = []
	for row in lm.standings_ranked().slice(0, 4):
		top4.append(int(row["team_id"]))
	if not top4.has(pid):
		top4[3] = pid
	var intl_ids: Array = []
	for t in (s["intl_team_meta"] as Array).slice(0, 4):
		intl_ids.append(int(t["id"]))
	if intl_ids.size() < 4:
		return
	s["current_phase"] = GameEnums.SeasonPhase.PRESEASON_INTL
	s["phase_week"] = 1
	# `InternationalTournament._bootstrap_intl` 과 같은 짝: 리그 시드 ↔ 해외 시드 엇갈림.
	var pairs: Array = [
		[top4[0], intl_ids[3]], [top4[1], intl_ids[2]], [top4[2], intl_ids[1]], [top4[3], intl_ids[0]],
		[-1, -1], [-1, -1], [-1, -1],
	]
	var b: Array = []
	for slot in pairs.size():
		var round_: int = 1 if slot < 4 else (2 if slot < 6 else 3)
		b.append({
			"slot": slot, "round": round_, "phase_week": round_,
			"team_a": int(pairs[slot][0]), "team_b": int(pairs[slot][1]),
			"year": int(s["year"]), "month": int(s["month"]), "day": int(s["day"]),
			"weekday": 0, "matchday": 0, "played": false, "winner": -1,
		})
	s["current_tournament"] = {
		"type": "INTL",
		"phase_at_start": int(s["current_phase"]),
		"stage": GameEnums.TournamentStage.INTL_QF,
		"bracket": b,
	}
	for slot in 4:
		var m: Dictionary = b[slot]
		var a: int = int(m["team_a"])
		var bb: int = int(m["team_b"])
		var winner: int = pid if pid == a or pid == bb else _intl.simulate_ai_match(a, bb)
		_intl.record_result(slot, winner)
	s["phase_week"] = 2
	UiPreview.trace(%OkButton.pressed, "확인")
