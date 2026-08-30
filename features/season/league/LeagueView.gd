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

const PHASE_NAMES: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON:      "프리시즌",
	GameEnums.SeasonPhase.PRESEASON_INTL: "프리시즌 국제대회",
	GameEnums.SeasonPhase.MIDSEASON:      "미드시즌",
	GameEnums.SeasonPhase.MIDSEASON_INTL: "미드시즌 국제대회",
	GameEnums.SeasonPhase.REGULAR:        "정규시즌",
	GameEnums.SeasonPhase.REGULAR_INTL:   "정규시즌 국제대회",
}

const ROW_W: float = 1000.0
const ROW_H: float = 104.0
const ROW_GAP: float = 10.0

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _league: LeagueManager = null
var _phase_lbl: Label
var _next_match_lbl: Label
var _row_widgets: Array = []   # 8 dicts of {panel, stylebox, rank, name, wl, pct, po}
var _ok_btn: Button
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	ensure_view()


# Idempotent — SeasonHub calls this each time it routes to LEAGUE.
func ensure_view() -> void:
	if not _built:
		_build()
		_built = true
	_resolve_league()
	refresh()


func _resolve_league() -> void:
	if _league != null or _hub == null:
		return
	_league = _hub.get_node_or_null("LeagueManager") as LeagueManager


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 제목만 따로 내리면 본문과 겹친다.
	ScreenMetrics.indent_to_safe_top(self)
	OutgameTheme.add_background(self)

	var x0: float = (ScreenMetrics.vp_w() - ROW_W) / 2.0
	_phase_lbl = UiHelpers.mk_label(self, "", 24, OutgameTheme.TEXT_SUB,
			Vector2(x0, 32), Vector2(ROW_W, 30), HORIZONTAL_ALIGNMENT_LEFT)
	UiHelpers.mk_label(self, "리그 순위", 52, OutgameTheme.TEXT,
			Vector2(x0, 66), Vector2(ROW_W, 62), HORIZONTAL_ALIGNMENT_LEFT)
	_next_match_lbl = UiHelpers.mk_label(self, "", 24, OutgameTheme.ACCENT_TEXT,
			Vector2(x0, 136), Vector2(ROW_W, 30), HORIZONTAL_ALIGNMENT_LEFT)

	_build_header()
	_build_rows()
	_build_button()


func _build_header() -> void:
	var header_y: float = 186.0
	var x0: float = (ScreenMetrics.vp_w() - ROW_W) / 2.0
	OutgameTheme.add_divider(self, Vector2(x0, header_y + 34.0), ROW_W)
	UiHelpers.mk_label(self, "순위", 20, OutgameTheme.TEXT_SUB,
			Vector2(x0 + 16, header_y), Vector2(100, 28), HORIZONTAL_ALIGNMENT_CENTER)
	UiHelpers.mk_label(self, "팀", 20, OutgameTheme.TEXT_SUB,
			Vector2(x0 + 126, header_y), Vector2(370, 28), HORIZONTAL_ALIGNMENT_LEFT)
	UiHelpers.mk_label(self, "승-패", 20, OutgameTheme.TEXT_SUB,
			Vector2(x0 + 480, header_y), Vector2(200, 28), HORIZONTAL_ALIGNMENT_CENTER)
	UiHelpers.mk_label(self, "승률", 20, OutgameTheme.TEXT_SUB,
			Vector2(x0 + 680, header_y), Vector2(160, 28), HORIZONTAL_ALIGNMENT_CENTER)
	UiHelpers.mk_label(self, "PO", 20, OutgameTheme.TEXT_SUB,
			Vector2(x0 + 840, header_y), Vector2(144, 28), HORIZONTAL_ALIGNMENT_CENTER)


func _build_rows() -> void:
	var grid_y: float = 236.0
	var x0: float = (ScreenMetrics.vp_w() - ROW_W) / 2.0
	for r in 8:
		var y: float = grid_y + r * (ROW_H + ROW_GAP)
		var panel := Panel.new()
		panel.position = Vector2(x0, y)
		panel.size     = Vector2(ROW_W, ROW_H)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sty: StyleBoxFlat = OutgameTheme.card_style(14)
		panel.add_theme_stylebox_override("panel", sty)
		add_child(panel)

		var rank_lbl := UiHelpers.mk_label(panel, "", 30, OutgameTheme.TEXT_SUB,
				Vector2(16, (ROW_H - 36) / 2.0), Vector2(100, 36),
				HORIZONTAL_ALIGNMENT_CENTER)
		var name_lbl := UiHelpers.mk_label(panel, "", 28, OutgameTheme.TEXT,
				Vector2(126, (ROW_H - 34) / 2.0), Vector2(370, 34),
				HORIZONTAL_ALIGNMENT_LEFT)
		var wl_lbl := UiHelpers.mk_label(panel, "", 26, OutgameTheme.TEXT,
				Vector2(480, (ROW_H - 32) / 2.0), Vector2(200, 32),
				HORIZONTAL_ALIGNMENT_CENTER)
		var pct_lbl := UiHelpers.mk_label(panel, "", 26, OutgameTheme.TEXT_SUB,
				Vector2(680, (ROW_H - 32) / 2.0), Vector2(160, 32),
				HORIZONTAL_ALIGNMENT_CENTER)
		var po_lbl := UiHelpers.mk_label(panel, "", 24, OutgameTheme.POSITIVE,
				Vector2(840, (ROW_H - 32) / 2.0), Vector2(144, 32),
				HORIZONTAL_ALIGNMENT_CENTER)

		_row_widgets.append({
			"panel": panel, "stylebox": sty,
			"rank": rank_lbl, "name": name_lbl,
			"wl": wl_lbl, "pct": pct_lbl, "po": po_lbl,
		})


func _build_button() -> void:
	var w: float = ROW_W
	var h: float = 100.0
	var x0: float = (ScreenMetrics.vp_w() - w) / 2.0
	# 하단 안전선에 매단다 — 이 자리는 아이폰 홈 인디케이터 / 안드로이드
	# 제스처 바가 터치를 가져가는 구간과 맞닿아 있다.
	var y: float = ScreenMetrics.safe_h() - 40.0 - h

	_ok_btn = Button.new()
	_ok_btn.text = "확인"
	_ok_btn.position = Vector2(x0, y)
	_ok_btn.size     = Vector2(w, h)
	OutgameTheme.style_primary_button(_ok_btn, 34)
	_ok_btn.pressed.connect(_on_ok_pressed)
	add_child(_ok_btn)


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not _built:
		return
	if _league == null:
		_resolve_league()
	if _league == null:
		return

	var phase: int = int(_gm.season_state["current_phase"])
	_phase_lbl.text = "%s · %d주차" % [
		PHASE_NAMES.get(phase, "—"), int(_gm.season_state["phase_week"])]

	var pid: int = int(_gm.season_state["player_team_id"])
	var nxt = _league.next_unplayed_player_match()
	if nxt == null:
		_next_match_lbl.text = "다음 경기 없음"
	else:
		var opp: int = int(nxt["team_b"]) if int(nxt["team_a"]) == pid else int(nxt["team_a"])
		_next_match_lbl.text = "다음 경기: %d주차 %s — vs %s" % [
			int(nxt["phase_week"]),
			"토" if int(nxt.get("matchday", 0)) == 0 else "일",
			_league.team_name(opp),
		]

	var ranked: Array = _league.standings_ranked()
	var po_count: int = int(_gm.PLAYOFF_TEAMS)
	for r in 8:
		var w: Dictionary = _row_widgets[r]
		var sty: StyleBoxFlat = w["stylebox"]
		if r >= ranked.size():
			w["rank"].text = ""
			w["name"].text = ""
			w["wl"].text   = ""
			w["pct"].text  = ""
			w["po"].text   = ""
			sty.bg_color = OutgameTheme.SURFACE_SUNK
			sty.border_color = OutgameTheme.BORDER
			sty.set_border_width_all(1)
			continue

		var row: Dictionary = ranked[r]
		var tid: int = int(row["team_id"])
		var wins: int = int(row["wins"])
		var losses: int = int(row["losses"])
		var played: int = wins + losses
		var pct_s: String = "—" if played == 0 else "%.3f" % (float(wins) / float(played))
		var is_player: bool = (tid == pid)
		var made_po: bool = r < po_count

		w["rank"].text = "%d" % (r + 1)
		w["name"].text = "%s  (%s)" % [_league.team_name(tid), _league.team_short_name(tid)]
		w["wl"].text   = "%d승 %d패" % [wins, losses]
		w["pct"].text  = pct_s
		w["po"].text   = "PO" if made_po else ""

		# 플레이어 줄은 앰버 틴트 + 앰버 테두리, 진출권은 왼쪽 초록 띠 하나.
		# 색면으로 칠하면 그 줄의 숫자가 안 읽힌다 — 흰 종이에서 강조는 테두리다.
		sty.bg_color = OutgameTheme.ACCENT_DIM if is_player else OutgameTheme.SURFACE
		if is_player:
			sty.set_border_width_all(2)
			sty.border_color = OutgameTheme.ACCENT
		elif made_po:
			# `StyleBoxFlat` 의 테두리 색은 **한 가지뿐**이라 "옅은 외곽선 + 초록
			# 왼쪽 띠"를 한 판으로 낼 수 없다. 띠 쪽을 택한다 — 흰 종이 위에서는
			# 그림자가 이미 카드의 윤곽을 만들고 있어 외곽선이 없어도 판이 선다.
			sty.set_border_width_all(0)
			sty.border_width_left = 6
			sty.border_color = OutgameTheme.POSITIVE
		else:
			sty.set_border_width_all(1)
			sty.border_color = OutgameTheme.BORDER

		w["rank"].add_theme_color_override("font_color",
				OutgameTheme.TEXT if is_player else OutgameTheme.TEXT_SUB)


# ── Button handler ──────────────────────────────────────────────────────────
func _on_ok_pressed() -> void:
	if _hub != null and _hub.has_method("on_standings_confirmed"):
		_hub.on_standings_confirmed()
