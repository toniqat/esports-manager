class_name LeagueView
extends Control

# 리그 순위표. 8줄을 승-패 순으로 세우고, 플레이어 팀 줄은 앰버 테두리로,
# 플레이오프 진출권(상위 `PLAYOFF_TEAMS`) 줄은 왼쪽 초록 띠로 표시한다.
# 색은 전부 `OutgameTheme` 를 지난다 — 흰 종이 위의 카드 목록이다.
#
# **아래 버튼은 하나뿐이다("확인").** 예전에는 "돌아가기 / 다음 주 →" 둘이었는데,
# 주를 넘기는 일이 시간 경과 화면의 일요일 마감으로 옮겨 가면서 이 화면에 남은
# 행동은 "다 봤다" 하나가 됐다. 돌아갈 자리는 버튼이 아니라 **주 진행 상태**가
# 정한다(`SeasonHub.on_standings_confirmed` — 주가 돌고 있으면 그 요일로, 아니면 허브로).
#
# Tapping a row opens that team's detail sheet (`HubSheet`): record + the five
# pilots under the analysis reveal rule (`OpponentIntel` / `IntelView`, the same
# scene MatchFlow PREP uses) — body scene `LeagueTeamDetail`. The own team is always fully visible.
#
# **Layout lives in `UI_View_LeagueView.tscn`** (+ one `UI_Comp_LeagueRow.tscn` per rank in `%Rows`) —
# build it with `LeagueView.create()`. The script fills text, wires the rows / button and
# applies the device-dependent bits: safe-area top indent, background extension into the
# notch, and the bottom capsule's placement + bottom inset.

## Built from `UI_View_LeagueView.tscn` — use `create()`, not `.new()`.
const SCENE_PATH: String = "res://features/season/league/UI_View_LeagueView.tscn"
const ROW_SCENE_PATH: String = "res://features/season/league/UI_Comp_LeagueRow.tscn"
const ROW_COUNT: int = 8

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _league: LeagueManager = null
var _row_team_ids: Array = [-1, -1, -1, -1, -1, -1, -1, -1]   # team shown on each row


static func create() -> LeagueView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as LeagueView


func _ready() -> void:
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 바탕만 노치 자리까지 도로 늘린다(`docs/mobile_safe_area.md`).
	ScreenMetrics.indent_to_safe_top(self)
	ScreenMetrics.extend_background(%Background)
	_ensure_rows()
	_layout_ok_button()
	%FloatingBarButton_OkButton.pressed.connect(_on_ok_pressed)
	if UiPreview.is_standalone(self):
		_fill_preview()
	ensure_view()


# Idempotent — SeasonHub calls this each time it routes to LEAGUE.
func ensure_view() -> void:
	_resolve_league()
	refresh()


func _resolve_league() -> void:
	if _league != null or _hub == null:
		return
	_league = _hub.get_node_or_null("LeagueManager") as LeagueManager


## `%Rows` holds exactly `ROW_COUNT` `LeagueRow`s — the scene's preview row is reused,
## the rest are instantiated from the item scene.
func _ensure_rows() -> void:
	var box: Node = %Rows
	while box.get_child_count() > ROW_COUNT:
		var extra: Node = box.get_child(box.get_child_count() - 1)
		box.remove_child(extra)
		extra.queue_free()
	while box.get_child_count() < ROW_COUNT:
		box.add_child((load(ROW_SCENE_PATH) as PackedScene).instantiate())
	for r in ROW_COUNT:
		(box.get_child(r) as LeagueRow).tapped.connect(_on_row_pressed.bind(r))


## The only action, so one full-width floating capsule (40 px side insets, 32 px above the
## safe line). The look is the scene's (`BarPrimaryButton`); placement + device inset are
## `OutgameTheme.fit_bottom_bar`.
func _layout_ok_button() -> void:
	OutgameTheme.fit_bottom_bar(%FloatingBarButton_OkButton)


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not is_inside_tree():
		return
	if _league == null:
		_resolve_league()
	if _league == null:
		return

	var phase: int = int(_gm.season_state["current_phase"])
	%Phase.text = Loc.t(L.SEASON_COMMON_PHASE_WEEK, {
		"phase": GameEnums.phase_label(phase), "week": int(_gm.season_state["phase_week"])})

	var pid: int = int(_gm.season_state["player_team_id"])
	var nxt = _league.next_unplayed_player_match()
	if nxt == null:
		%NextMatch.text = Loc.t(L.SEASON_LEAGUE_NO_NEXT)
	else:
		var opp: int = int(nxt["team_b"]) if int(nxt["team_a"]) == pid else int(nxt["team_a"])
		# matchday 0 = Saturday, 1 = Sunday (`OutgameTheme.day_letter` index 5 / 6).
		%NextMatch.text = Loc.t(L.SEASON_LEAGUE_NEXT_MATCH, {
			"week": int(nxt["phase_week"]),
			"day": OutgameTheme.day_letter(5 if int(nxt.get("matchday", 0)) == 0 else 6),
			"team": _league.team_name(opp),
		})

	var ranked: Array = _league.standings_ranked()
	var po_count: int = int(_gm.PLAYOFF_TEAMS)
	for r in ROW_COUNT:
		var row_view: LeagueRow = %Rows.get_child(r) as LeagueRow
		if r >= ranked.size():
			_row_team_ids[r] = -1
			row_view.clear()
			continue
		var row: Dictionary = ranked[r]
		var tid: int = int(row["team_id"])
		_row_team_ids[r] = tid
		row_view.fill(r + 1,
				"%s  (%s)" % [_league.team_name(tid), _league.team_short_name(tid)],
				int(row["wins"]), int(row["losses"]), r < po_count, tid == pid)


# ── Button handler ──────────────────────────────────────────────────────────
func _on_ok_pressed() -> void:
	if _hub != null and _hub.has_method("on_standings_confirmed"):
		_hub.on_standings_confirmed()


# ── Team detail sheet ─────────────────────────────────────────────────────────
func _on_row_pressed(r: int) -> void:
	var tid: int = int(_row_team_ids[r]) if r < _row_team_ids.size() else -1
	if tid < 0 or _league == null:
		return
	open_team_detail(tid, r + 1)


## Opens the detail sheet of `tid` (ranked `rank`) — record + five pilots under
## the analysis reveal rule. Public so a harness / other screens can open it.
func open_team_detail(tid: int, rank: int) -> HubSheet:
	var state: Dictionary = _gm.season_state
	var is_own: bool = tid == int(state["player_team_id"])
	var table: Dictionary = state.get("league_standings", {})
	var rec: Dictionary = table.get(tid, table.get(str(tid), {}))
	var record: String = Loc.t(
			L.SEASON_LEAGUE_DETAIL_RECORD_MINE if is_own else L.SEASON_LEAGUE_DETAIL_RECORD,
			{"rank": rank, "win": int(rec.get("wins", 0)), "loss": int(rec.get("losses", 0))})
	return LeagueTeamDetail.open(self, "%s  (%s)" % [
			_league.team_name(tid), _league.team_short_name(tid)], record,
			OpponentIntel.build(state, OpponentIntel.team_roster(state, tid), is_own, tid))


## F6 단독 실행 미리보기 — 메모리 런 + 몇 주 치른 리그(`resources/UiPreview.gd`).
## 호스트(`SeasonHub`)가 없어 "확인" · 팀 상세는 아무 일도 안 한다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	if UiPreview.ensure_run() == null:
		return
	_league = UiPreview.ensure_league(self)
