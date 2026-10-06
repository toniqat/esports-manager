class_name WeekProgressView
extends Control

# ── 시간 경과 화면 (월 → 일) ─────────────────────────────────────────────────
#
# **맨 위에 가로 요일 레일**(왼쪽 → 오른쪽으로 월 … 일), 그 아래 머리글과
# 그날의 카드 목록.
#
#   ┌──────────────────────────────────────┐
#   │ 3주  월  화 [수] 목  금  토  일          │  ← 요일 레일
#   └──────────────────────────────────────┘
#     프리시즌 · 3주차              1년 12월   ← 머리글 (요일 · 날짜)
#     수요일                              5
#    ─────────────────────────────────────
#     [ 파일럿 카드 ]  ← 그날 훈련 결과        ← 세로 스크롤
#     [ 파일럿 카드 ]
#           [        확인        ]            ← 다음 날로
#
# 예전에는 레일이 **왼쪽 세로 기둥**이었다.
# 그러면 화면 폭 1080 에서 152px 가 레일 몫으로 빠져 카드의 스탯 여섯 칸이
# 좁아졌고, 요일이 위에서 아래로 흐르는 것은 달력을 읽는 방향(왼쪽 → 오른쪽)과
# 어긋났다.
#
# 레일의 **지금 요일 한 칸만 앰버로 채워진다** — 지나온 날은 흰 글자, 남은 날은
# 흐린 글자다. 그 한 칸이 이 화면이 답하는 유일한 질문("지금 며칠인가")이라
# 다른 강조를 두지 않는다.
#
# ── 요일이 하는 일 ──────────────────────────────────────────────────────────
# **월~금**은 훈련일이다. 그 요일에 처음 닿을 때 `TrainingBoard.apply_day_training`
# 이 판의 그 줄을 정산해 선수 스탯을 실제로 올리고, 결과 줄 목록을
# `season_state["week_day_log"][day]` 에 적는다. **이미 적혀 있으면 다시
# 정산하지 않는다** — 경기를 치르고 같은 요일로 돌아와도 훈련이 두 번 먹으면 안 된다.
#
# **토·일**은 경기일이다(`CalendarSystem.MATCH_DAYS`). 그날 플레이어 경기가
# 배정돼 있으면 아래 버튼이 "확인" 대신 **"경기 시작"** 이 되고, 그것을 누르면
# MatchFlow 로 넘어간다. 경기를 마치고 순위표에서 확인을 누르면 같은 요일로
# 돌아오는데, 그때는 그 경기가 `played` 라 버튼이 다시 "확인"이 된다.
#
# 배치 규약은 다른 시즌 화면과 같다: 화면째 `indent_to_safe_top` 으로 내리고
# 배경만 `extend_background` 로 노치 자리까지 늘린다. 색은 전부 `OutgameTheme`.

const PHASE_NAMES: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON:      "프리시즌",
	GameEnums.SeasonPhase.PRESEASON_INTL: "프리시즌 국제대회",
	GameEnums.SeasonPhase.MIDSEASON:      "미드시즌",
	GameEnums.SeasonPhase.MIDSEASON_INTL: "미드시즌 국제대회",
	GameEnums.SeasonPhase.REGULAR:        "정규시즌",
	GameEnums.SeasonPhase.REGULAR_INTL:   "정규시즌 국제대회",
}
const STAT_KEYS: Array   = PlayerData.STAT_KEYS
const STAT_SHORT: Array  = PlayerData.STAT_SHORT

# ── 배치 ─────────────────────────────────────────────────────────────────────
## 상단 가로 레일 — 왼쪽 끝에 `N주`, 그 오른쪽에 요일 칩 일곱이 고르게 선다.
const RAIL_X: float      = 24.0
const RAIL_TOP: float    = 26.0
const RAIL_H: float      = 96.0
const RAIL_WEEK_W: float = 104.0     # `N주` 라벨 칸
const RAIL_PAD: float    = 14.0
const CHIP_D: float      = 72.0

const CONTENT_X: float   = 40.0
const HEAD_TOP: float    = RAIL_TOP + RAIL_H + 26.0
const TITLE_Y: float     = HEAD_TOP + 92.0
const LIST_TOP: float    = HEAD_TOP + 224.0

const CARD_H: float      = 148.0
const CARD_GAP: float    = 14.0
const MATCH_CARD_H: float = 168.0
const PORTRAIT_D: float  = 88.0

# ── 오늘 저녁 (evening) card — M7 ──
const EVE_SLOT_TOP: float = 104.0
const EVE_SLOT_H: float   = 170.0
const EVE_PORTRAIT_D: float = 84.0
const EVE_BTN_H: float    = 84.0
const EVE_CARD_H: float   = EVE_SLOT_TOP + EVE_SLOT_H + 24.0 + EVE_BTN_H + 28.0
const EVE_DONE_H: float   = 150.0
const INCIDENT_H: float   = 150.0

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _built: bool = false
var _day: int = 0

var _chip_panels: Array = []       # 7 Panel
var _chip_labels: Array = []       # 7 Label
var _week_lbl: Label
var _phase_lbl: Label
var _title_lbl: Label
var _date_small_lbl: Label
var _date_big_lbl: Label
var _list_body: Control
var _list_scroll: ScrollContainer
var _action_btn: Button

# M7 — evening / incident dialogs.
var _sel_pid: int = -1                # pilot picked on the evening card
var _sel_day: int = -1                # weekday `_sel_pid` belongs to
var _overlay: MessengerView = null    # dialog on top of the screen, null when closed
var _overlay_kind: String = ""        # "evening" / "incident"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	ensure_view()


func ensure_view() -> void:
	if not _built:
		_build()
		_built = true
	refresh()


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	ScreenMetrics.indent_to_safe_top(self)
	OutgameTheme.add_background(self)
	_build_rail()
	_build_header()
	_build_list()
	_build_action_button()


## 상단 가로 요일 레일. 어두운 알약 한 장 위에 `N주` 와 요일 칩 일곱.
func _build_rail() -> void:
	var w: float = _rail_w()
	var rail := Panel.new()
	rail.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(OutgameTheme.RAIL, int(RAIL_H * 0.5)))
	rail.position = Vector2(RAIL_X, RAIL_TOP)
	rail.size = Vector2(w, RAIL_H)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rail)

	_week_lbl = UiHelpers.mk_label(rail, "", 24, OutgameTheme.RAIL_TEXT,
			Vector2(12, 0), Vector2(RAIL_WEEK_W - 12.0, RAIL_H),
			HORIZONTAL_ALIGNMENT_CENTER)
	_week_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# 칩 일곱을 레일 안에서 고르게 편다. 왼쪽에 주차 라벨이 앉으므로 그 오른쪽부터.
	var left: float = RAIL_WEEK_W
	var span: float = w - left - RAIL_PAD
	var step: float = span / 7.0
	for d in 7:
		var cx: float = left + step * (float(d) + 0.5) - CHIP_D * 0.5
		var chip := Panel.new()
		chip.position = Vector2(cx, (RAIL_H - CHIP_D) * 0.5)
		chip.size = Vector2(CHIP_D, CHIP_D)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rail.add_child(chip)
		var lbl := UiHelpers.mk_label(chip, OutgameTheme.DAY_LETTERS[d], 30,
				OutgameTheme.RAIL_TEXT, Vector2.ZERO, Vector2(CHIP_D, CHIP_D),
				HORIZONTAL_ALIGNMENT_CENTER)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_chip_panels.append(chip)
		_chip_labels.append(lbl)


func _build_header() -> void:
	var right_w: float = 320.0
	var right_x: float = ScreenMetrics.vp_w() - 40.0 - right_w

	_phase_lbl = UiHelpers.mk_label(self, "", 24, OutgameTheme.TEXT_SUB,
			Vector2(CONTENT_X, HEAD_TOP + 4.0), Vector2(520, 30),
			HORIZONTAL_ALIGNMENT_LEFT)
	_date_small_lbl = UiHelpers.mk_label(self, "", 24, OutgameTheme.TEXT_SUB,
			Vector2(right_x, HEAD_TOP), Vector2(right_w, 30),
			HORIZONTAL_ALIGNMENT_RIGHT)
	_date_big_lbl = UiHelpers.mk_label(self, "", 58, OutgameTheme.TEXT,
			Vector2(right_x, HEAD_TOP + 28.0), Vector2(right_w, 70),
			HORIZONTAL_ALIGNMENT_RIGHT)
	_date_small_lbl.clip_text = true
	_date_big_lbl.clip_text = true

	_title_lbl = UiHelpers.mk_label(self, "", 54, OutgameTheme.TEXT,
			Vector2(CONTENT_X, TITLE_Y), Vector2(600, 66),
			HORIZONTAL_ALIGNMENT_LEFT)

	OutgameTheme.add_divider(self, Vector2(CONTENT_X, LIST_TOP - 26.0),
			ScreenMetrics.vp_w() - CONTENT_X - 40.0)


func _build_list() -> void:
	var w: float = ScreenMetrics.vp_w() - CONTENT_X - 40.0
	var h: float = _list_bottom() - LIST_TOP
	var pack: Dictionary = OutgameTheme.add_vscroll(self,
			Vector2(CONTENT_X, LIST_TOP), Vector2(w, h))
	_list_scroll = pack["scroll"]
	_list_body = pack["body"]


## 이 화면의 행동은 하나뿐이라 **하단 구간을 통째로 차지한다** — 화면 끝에서
## 끝까지 깔리고 아래는 안전선에 밀착한다
## (`OutgameTheme.add_bottom_bar`).
func _build_action_button() -> void:
	var bar: Array = OutgameTheme.add_bottom_bar(self, [
		{"text": "확인", "style": "primary", "font": 34},
	])
	_action_btn = bar[0]
	_action_btn.pressed.connect(_on_action_pressed)


func _rail_w() -> float:
	return ScreenMetrics.vp_w() - RAIL_X * 2.0


func _list_bottom() -> float:
	return OutgameTheme.bottom_bar_top() - 24.0


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not _built:
		return
	_day = clampi(int(_gm.season_state.get("week_day", 0)), 0,
			CalendarSystem.DAYS_PER_WEEK - 1)
	_settle_day_if_needed()
	# M7 — the incident roll happens once per weekday (recorded, seeded).
	MentalSystem.ensure_incident(_gm.season_state, _day)
	_refresh_rail()
	_refresh_header()
	_rebuild_list()
	_refresh_action_button()
	# An unresolved incident (or an evening dialog left open by a reload) opens
	# by itself — the day cannot be confirmed past it.
	if _overlay == null:
		if MentalSystem.incident_pending(_gm.season_state, _day):
			_open_incident.call_deferred()
		elif _evening_open():
			_open_evening_session.call_deferred(MentalSystem.begin_evening(
					_gm.season_state, _day, "", -1))


## 훈련일에 처음 닿았으면 그날 훈련을 정산한다. **기록이 이미 있으면 아무것도
## 하지 않는다** — 경기를 치르고 같은 요일로 돌아오는 경로가 실제로 있고,
## 거기서 다시 정산하면 훈련이 두 번 먹는다.
func _settle_day_if_needed() -> void:
	if not CalendarSystem.is_training_day(_day):
		return
	var log: Dictionary = _week_log()
	if log.has(_day):
		return
	var board: TrainingBoard = null
	if _hub != null:
		board = _hub.get_node_or_null("TrainingBoard") as TrainingBoard
	if board == null:
		log[_day] = []
		return
	log[_day] = board.apply_day_training(_day)


func _week_log() -> Dictionary:
	if not _gm.season_state.has("week_day_log"):
		_gm.season_state["week_day_log"] = {}
	return _gm.season_state["week_day_log"]


func _refresh_rail() -> void:
	_week_lbl.text = "%d주" % int(_gm.season_state.get("phase_week", 1))
	for d in 7:
		var chip: Panel = _chip_panels[d]
		var lbl: Label = _chip_labels[d]
		if d == _day:
			chip.add_theme_stylebox_override("panel",
					OutgameTheme.flat_style(OutgameTheme.ACCENT, 20))
			lbl.add_theme_color_override("font_color", OutgameTheme.RAIL)
		else:
			chip.add_theme_stylebox_override("panel",
					OutgameTheme.flat_style(Color(0, 0, 0, 0), 20))
			# 지나온 날은 흰 글자로 남는다 — 남은 날과 구분되어야 "며칠 남았나"가
			# 레일만 보고 읽힌다.
			lbl.add_theme_color_override("font_color",
					OutgameTheme.TEXT_ON_FILL if d < _day else OutgameTheme.RAIL_TEXT)


func _refresh_header() -> void:
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	_phase_lbl.text = "%s · %d주차" % [
		PHASE_NAMES.get(phase, "—"), int(s["phase_week"])]
	_title_lbl.text = String(OutgameTheme.DAY_NAMES[_day])
	# 달력은 주의 월요일에 서 있으므로 요일만큼 더해 그날 날짜를 만든다.
	var date: Dictionary = _date_of_day(_day)
	_date_small_lbl.text = "%d년 %d월" % [int(date["year"]), int(date["month"])]
	_date_big_lbl.text = "%d" % int(date["day"])


## 이번 주 월요일에서 `day` 일 뒤의 날짜. 달을 넘길 수 있으므로
## `CalendarSystem.DAYS_IN_MONTH` 를 지난다 — 그냥 더하면 12월 30일 + 3 이 33일이 된다.
func _date_of_day(day: int) -> Dictionary:
	var s: Dictionary = _gm.season_state
	var y: int = int(s["year"]); var m: int = int(s["month"]); var d: int = int(s["day"])
	for _i in day:
		d += 1
		if d > int(CalendarSystem.DAYS_IN_MONTH[m - 1]):
			d = 1
			m += 1
			if m > 12:
				m = 1
				y += 1
	return {"year": y, "month": m, "day": d}


# ── 카드 목록 ────────────────────────────────────────────────────────────────
func _rebuild_list() -> void:
	for c in _list_body.get_children():
		c.queue_free()
	var w: float = ScreenMetrics.vp_w() - CONTENT_X - 40.0
	var y: float = 0.0

	var md: int = CalendarSystem.matchday_of(_day)
	if md >= 0:
		y = _add_match_cards(w, y, md)

	if CalendarSystem.is_training_day(_day):
		# M7 — the day's incident (if any) and the evening action sit above
		# the training results: they are what the player still has to decide.
		y = _add_incident_card(w, y)
		y = _add_evening_card(w, y)
		var rows: Array = _week_log().get(_day, [])
		if rows.is_empty():
			y = _add_note_card(w, y, "훈련 기록이 없습니다")
		else:
			for i in rows.size():
				_add_pilot_card(w, y, rows[i])
				y += CARD_H + CARD_GAP
	elif md >= 0:
		pass   # 주말 — 경기 카드가 이미 그 자리를 답했다
	else:
		y = _add_note_card(w, y, "일정 없음")

	_list_body.custom_minimum_size = Vector2(w, maxf(0.0, y))
	if _list_scroll != null:
		_list_scroll.scroll_vertical = 0


## 이번 주 그 경기일의 경기들. 플레이어 경기가 맨 위, 나머지는 그 아래로.
func _add_match_cards(w: float, y: float, matchday: int) -> float:
	var entries: Array = _matches_on_day(matchday)
	if entries.is_empty():
		return _add_note_card(w, y, "%s — 예정된 경기 없음"
				% OutgameTheme.DAY_NAMES[_day])
	for e_raw in entries:
		var e: Dictionary = e_raw
		var is_player: bool = bool(e["player"])
		var h: float = MATCH_CARD_H if is_player else 96.0
		var tint: Variant = OutgameTheme.RAIL if is_player else null
		var card := OutgameTheme.add_card(_list_body, Vector2(0, y),
				Vector2(w, h), 18, tint)
		var fg: Color = OutgameTheme.TEXT_ON_FILL if is_player else OutgameTheme.TEXT
		var fg_sub: Color = OutgameTheme.RAIL_TEXT if is_player else OutgameTheme.TEXT_SUB

		UiHelpers.mk_label(card, String(e["tag"]), 22, fg_sub,
				Vector2(28, 20), Vector2(w - 56, 26), HORIZONTAL_ALIGNMENT_LEFT)
		UiHelpers.mk_label(card, String(e["title"]), 34, fg,
				Vector2(28, 50), Vector2(w - 300, 42), HORIZONTAL_ALIGNMENT_LEFT)
		var status_col: Color = fg_sub
		if String(e["status"]) == "승":
			status_col = OutgameTheme.POSITIVE
		elif String(e["status"]) == "패":
			status_col = OutgameTheme.NEGATIVE
		UiHelpers.mk_label(card, String(e["status"]), 30, status_col,
				Vector2(w - 240, 50), Vector2(212, 42), HORIZONTAL_ALIGNMENT_RIGHT)
		if is_player:
			UiHelpers.mk_label(card, String(e["hint"]), 22, fg_sub,
					Vector2(28, 110), Vector2(w - 56, 28), HORIZONTAL_ALIGNMENT_LEFT)
		y += h + CARD_GAP
	return y


## 그 경기일에 잡힌 경기 목록을 화면이 읽을 모양으로. 리그는 스케줄에서,
## 토너먼트는 대진표에서 온다 — 둘의 필드 이름이 거의 같아 한 함수로 모은다.
func _matches_on_day(matchday: int) -> Array:
	var s: Dictionary = _gm.season_state
	var pid: int = int(s["player_team_id"])
	var phase: int = int(s["current_phase"])
	var pweek: int = int(s["phase_week"])
	var out: Array = []

	var league: LeagueManager = null
	var tm: TournamentManager = null
	var intl: InternationalTournament = null
	if _hub != null:
		league = _hub.get_node_or_null("LeagueManager") as LeagueManager
		tm = _hub.get_node_or_null("TournamentManager") as TournamentManager
		intl = _hub.get_node_or_null("InternationalTournament") as InternationalTournament

	# 토너먼트가 돌고 있으면 그쪽이 이번 주의 경기다 (리그 라운드는 안 선다).
	#
	# **대진표를 가진 쪽과 팀 이름을 아는 쪽이 다를 수 있다** — 국제대회는
	# 외부 4팀(id 100..)까지 알아야 해서 `team_name` 을 직접 갖지만,
	# 플레이오프는 국내 8팀뿐이라 `LeagueManager` 의 표를 그대로 쓴다
	# (`TournamentManager` 에는 `team_name` 이 없다). 그래서 둘을 따로 든다.
	var bracket_owner: Node = null
	var namer: Node = league
	if intl != null and intl.is_active():
		bracket_owner = intl
		namer = intl
	elif tm != null and tm.is_active():
		bracket_owner = tm
	if bracket_owner != null:
		for m_raw in (s["current_tournament"]["bracket"] as Array):
			var m: Dictionary = m_raw
			if int(m["phase_week"]) != pweek:
				continue
			if int(m.get("matchday", 0)) != matchday:
				continue
			if int(m["team_a"]) < 0 or int(m["team_b"]) < 0:
				continue
			out.append(_match_row(m, pid,
					String(bracket_owner.call("slot_label", int(m["slot"]))),
					namer))
	elif league != null:
		for m_raw2 in (s["match_schedule"] as Array):
			var m2: Dictionary = m_raw2
			if int(m2.get("phase", -1)) != phase or int(m2.get("phase_week", -1)) != pweek:
				continue
			if int(m2.get("matchday", 0)) != matchday:
				continue
			out.append(_match_row(m2, pid, "리그", league))

	# 플레이어 경기를 맨 위로.
	out.sort_custom(func(a, b): return bool(a["player"]) and not bool(b["player"]))
	return out


func _match_row(m: Dictionary, pid: int, tag: String, namer: Node) -> Dictionary:
	var ta: int = int(m["team_a"]); var tb: int = int(m["team_b"])
	var is_player: bool = (ta == pid or tb == pid)
	var played: bool = bool(m["played"])
	var status: String = "예정"
	if played:
		var winner: int = int(m["winner"])
		if is_player:
			status = "승" if winner == pid else "패"
		else:
			status = "%s 승" % _team_name(namer, winner)
	var title: String = "%s  vs  %s" % [_team_name(namer, ta), _team_name(namer, tb)]
	if is_player:
		var opp: int = tb if ta == pid else ta
		title = "vs  %s" % _team_name(namer, opp)
	return {
		"player": is_player, "tag": tag, "title": title, "status": status,
		"hint": "경기를 시작하면 밴픽 화면으로 넘어갑니다" if (is_player and not played)
				else "이 경기는 끝났습니다",
	}


static func _team_name(namer: Node, team_id: int) -> String:
	if namer != null and namer.has_method("team_name"):
		return String(namer.call("team_name", team_id))
	return "Team %d" % team_id


## 선수 한 명의 그날 훈련 결과 카드.
func _add_pilot_card(w: float, y: float, row_raw: Variant) -> void:
	var row: Dictionary = row_raw
	var role: int = int(row["role"])
	var card := Panel.new()
	card.add_theme_stylebox_override("panel",
			OutgameTheme.lead_bar_style(OutgameTheme.ROLE_COLORS[role]))
	card.position = Vector2(0, y)
	card.size = Vector2(w, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_body.add_child(card)

	OutgameTheme.add_round_portrait(card,
			PilotImages.circle_for(int(row["pilot_id"])),
			Vector2(26, (CARD_H - PORTRAIT_D) * 0.5), PORTRAIT_D)

	UiHelpers.mk_label(card, String(row["name"]), 30, OutgameTheme.TEXT,
			Vector2(132, 32), Vector2(240, 38), HORIZONTAL_ALIGNMENT_LEFT)
	UiHelpers.mk_label(card, String(OutgameTheme.ROLE_NAMES[role]), 22,
			OutgameTheme.ROLE_COLORS[role],
			Vector2(132, 74), Vector2(240, 28), HORIZONTAL_ALIGNMENT_LEFT)

	# 스탯 여섯 칸 — 이름 / 지금 값 / 이번 날의 결과.
	#
	# 아래 줄은 **오른 포인트가 있으면 `+N`, 없으면 `모인/TRAINING_EXP_PER_POINT`**
	# (다음 한 점까지 모인 EXP, 문턱은 const.csv)이다. 기초 코스만 깔린 판은 하루
	# EXP 가 그 문턱에 못 미쳐 월~목이 전부 `—` 로 보이고 금요일에 한꺼번에 오르는데,
	# 그러면 이 화면이 매일 답해야 하는 "오늘 뭐가 늘었나"에 나흘 동안 답이 없다.
	var x0: float = 392.0
	var col_w: float = (w - x0 - 24.0) / float(STAT_KEYS.size())
	var after: Dictionary = row["after"]
	var ups: Dictionary = row["ups"]
	var carry: Dictionary = row.get("carry", {})
	for i in STAT_KEYS.size():
		var key: String = String(STAT_KEYS[i])
		var cx: float = x0 + col_w * float(i)
		UiHelpers.mk_label(card, String(STAT_SHORT[i]), 17, OutgameTheme.TEXT_SUB,
				Vector2(cx, 34), Vector2(col_w, 22), HORIZONTAL_ALIGNMENT_CENTER)
		UiHelpers.mk_label(card, "%d" % int(after.get(key, 0)), 28, OutgameTheme.TEXT,
				Vector2(cx, 58), Vector2(col_w, 36), HORIZONTAL_ALIGNMENT_CENTER)
		var up: int = int(ups.get(key, 0))
		var txt: String = "%d/%d" % [int(carry.get(key, 0)), TrainingBoard.EXP_PER_POINT]
		var col: Color = OutgameTheme.TEXT_FAINT
		var size: int = 17
		if up > 0:
			txt = "+%d" % up
			col = OutgameTheme.POSITIVE
			size = 21
		elif up < 0:
			txt = "%d" % up
			col = OutgameTheme.NEGATIVE
			size = 21
		UiHelpers.mk_label(card, txt, size, col,
				Vector2(cx, 100), Vector2(col_w, 26), HORIZONTAL_ALIGNMENT_CENTER)


func _add_note_card(w: float, y: float, text: String) -> float:
	var card := OutgameTheme.add_card(_list_body, Vector2(0, y), Vector2(w, 96))
	var l := UiHelpers.mk_label(card, text, 26, OutgameTheme.TEXT_SUB,
			Vector2(28, 0), Vector2(w - 56, 96), HORIZONTAL_ALIGNMENT_LEFT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return y + 96.0 + CARD_GAP


# ── 아래 버튼 ────────────────────────────────────────────────────────────────
func _refresh_action_button() -> void:
	if _action_btn == null:
		return
	if _hub != null and _hub.has_player_match_on_day(_day):
		_action_btn.text = "경기 시작"
		# 하단 바의 칸이라 **각진 모서리를 유지해야 한다** — `style_dark_button`
		# 을 직접 부르면 모서리가 도로 둥글어져 이 칸만 화면에서 떠오른다.
		OutgameTheme.style_bottom_button(_action_btn, "dark", 34)
		return
	_action_btn.text = "주 마감 →" if _day >= CalendarSystem.DAYS_PER_WEEK - 1 else "확인"
	OutgameTheme.style_bottom_button(_action_btn, "primary", 34)


func _on_action_pressed() -> void:
	if _hub == null or _overlay != null:
		return
	if _hub.has_player_match_on_day(_day):
		_hub.on_week_day_match_start()
		return
	# Leaving a weekday without choosing = the evening was passed.
	if CalendarSystem.is_training_day(_day) \
			and not MentalSystem.evening_done(_gm.season_state, _day):
		MentalSystem.begin_evening(_gm.season_state, _day, MentalSystem.ACTION_PASS, -1)
	_hub.on_week_day_confirmed()


# ── 오늘 저녁 · 사건 (M7) ─────────────────────────────────────────────────────
# One evening action per Mon–Fri: interview / outing / pass. The card picks a
# pilot (portrait row) and an action; the dialog itself is a `MessengerView`
# overlay. State, limits and idempotency live in `MentalSystem` — this screen
# only draws records and forwards taps.

## The evening dialog was started but not answered (e.g. the game was reloaded).
func _evening_open() -> bool:
	if not CalendarSystem.is_training_day(_day):
		return false
	var e: Dictionary = MentalSystem.evening(_gm.season_state, _day)
	return not e.is_empty() and String(e.get("action", "")) != MentalSystem.ACTION_PASS \
			and int(e.get("choice", -1)) < 0


func _add_evening_card(w: float, y: float) -> float:
	var s: Dictionary = _gm.season_state
	var e: Dictionary = MentalSystem.evening(s, _day)
	if MentalSystem.evening_done(s, _day):
		return _add_evening_done_card(w, y, e)

	var mine: Array = _my_pilots_in_seat_order()
	if _sel_day != _day or not mine.has(_sel_pid):
		_sel_day = _day
		_sel_pid = int(mine[0]) if not mine.is_empty() else -1

	var card := OutgameTheme.add_card(_list_body, Vector2(0, y), Vector2(w, EVE_CARD_H), 18)
	UiHelpers.mk_label(card, "오늘 저녁", 32, OutgameTheme.TEXT,
			Vector2(28, 22), Vector2(300, 42))
	var limits: String = "면담 %d/%d · 외출 %d/%d" % [
		MentalSystem.interviews_left(s), MentalSystem.interviews_per_week(s),
		MentalSystem.outings_left(s), ConstTable.int_of("MENTAL_OUTINGS_PER_WEEK")]
	UiHelpers.mk_label(card, limits, 22, OutgameTheme.TEXT_SUB,
			Vector2(w - 428, 30), Vector2(400, 32), HORIZONTAL_ALIGNMENT_RIGHT)
	UiHelpers.mk_label(card, "선수를 고르고 오늘 저녁 할 일을 정하세요 (하루 한 번)", 20,
			OutgameTheme.TEXT_FAINT, Vector2(28, 66), Vector2(w - 56, 28))

	# Pilot row — tap to select. Trust in amber once the outing is unlocked.
	var slot_w: float = (w - 40.0) / float(maxi(1, mine.size()))
	for i in mine.size():
		var pid: int = int(mine[i])
		var sx: float = 20.0 + slot_w * float(i)
		var picked: bool = pid == _sel_pid
		if picked:
			var hl := Panel.new()
			hl.add_theme_stylebox_override("panel",
					OutgameTheme.flat_style(OutgameTheme.ACCENT_DIM, 16))
			hl.position = Vector2(sx + 4.0, EVE_SLOT_TOP)
			hl.size = Vector2(slot_w - 8.0, EVE_SLOT_H)
			hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(hl)
		OutgameTheme.add_round_portrait(card, PilotImages.circle_for(pid),
				Vector2(sx + (slot_w - EVE_PORTRAIT_D) * 0.5, EVE_SLOT_TOP + 12.0),
				EVE_PORTRAIT_D, OutgameTheme.ACCENT if picked else OutgameTheme.BORDER)
		var name_lbl := UiHelpers.mk_label(card, MentalEvents.pilot_name(s, pid), 22,
				OutgameTheme.TEXT, Vector2(sx, EVE_SLOT_TOP + 102.0), Vector2(slot_w, 30),
				HORIZONTAL_ALIGNMENT_CENTER)
		name_lbl.clip_text = true
		var unlocked: bool = MentalSystem.outing_unlocked(s, pid)
		UiHelpers.mk_label(card, "신뢰 %d · 외출 %d" % [MentalSystem.trust(s, pid),
				MentalSystem.outings(s, pid)], 18,
				OutgameTheme.ACCENT_TEXT if unlocked else OutgameTheme.TEXT_SUB,
				Vector2(sx, EVE_SLOT_TOP + 134.0), Vector2(slot_w, 26),
				HORIZONTAL_ALIGNMENT_CENTER)
		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.position = Vector2(sx, EVE_SLOT_TOP)
		hit.size = Vector2(slot_w, EVE_SLOT_H)
		OutgameTheme.style_text_button(hit, 20)
		hit.pressed.connect(_on_evening_pilot_picked.bind(pid))
		card.add_child(hit)

	# Actions. Disabled buttons say why on their own label.
	var by: float = EVE_SLOT_TOP + EVE_SLOT_H + 24.0
	var gap: float = 16.0
	var bw: float = (w - 56.0 - gap * 2.0) / 3.0
	var can_iv: bool = MentalSystem.can_interview(s) and _sel_pid >= 0
	var can_out: bool = MentalSystem.can_outing(s, _sel_pid) and _sel_pid >= 0
	var out_text: String = "외출"
	if MentalSystem.outings_left(s) <= 0:
		out_text = "외출 (이번 주 끝)"
	elif not MentalSystem.outing_unlocked(s, _sel_pid):
		out_text = "외출 (신뢰 %d↑)" % ConstTable.int_of("TRUST_OUTING_MIN")
	var specs: Array = [
		["면담" if MentalSystem.can_interview(s) else "면담 (이번 주 끝)", "primary",
				can_iv, MentalSystem.ACTION_INTERVIEW],
		[out_text, "ghost", can_out, MentalSystem.ACTION_OUTING],
		["패스", "text", true, MentalSystem.ACTION_PASS],
	]
	for i in specs.size():
		var spec: Array = specs[i]
		var b := Button.new()
		b.text = String(spec[0])
		b.focus_mode = Control.FOCUS_NONE
		b.position = Vector2(28.0 + (bw + gap) * float(i), by)
		b.size = Vector2(bw, EVE_BTN_H)
		match String(spec[1]):
			"primary": OutgameTheme.style_primary_button(b, 26)
			"ghost": OutgameTheme.style_ghost_button(b, 26)
			_: OutgameTheme.style_text_button(b, 26)
		b.disabled = not bool(spec[2])
		b.pressed.connect(_on_evening_action.bind(String(spec[3])))
		card.add_child(b)
	return y + EVE_CARD_H + CARD_GAP


func _add_evening_done_card(w: float, y: float, e: Dictionary) -> float:
	var s: Dictionary = _gm.season_state
	var action: String = String(e.get("action", MentalSystem.ACTION_PASS))
	var pid: int = int(e.get("pilot_id", -1))
	var card := OutgameTheme.add_card(_list_body, Vector2(0, y), Vector2(w, EVE_DONE_H), 18)
	var tx: float = 28.0
	if pid >= 0:
		OutgameTheme.add_round_portrait(card, PilotImages.circle_for(pid),
				Vector2(24, (EVE_DONE_H - 84.0) * 0.5), 84.0)
		tx = 132.0
	var head: String = "오늘 저녁 — 쉬었습니다"
	if action == MentalSystem.ACTION_INTERVIEW:
		head = "오늘 저녁 — %s 면담" % MentalEvents.pilot_name(s, pid)
	elif action == MentalSystem.ACTION_OUTING:
		head = "오늘 저녁 — %s 외출" % MentalEvents.pilot_name(s, pid)
	UiHelpers.mk_label(card, head, 28, OutgameTheme.TEXT,
			Vector2(tx, 30), Vector2(w - tx - 28.0, 40))
	var notes: Array = (e.get("outcome", {}) as Dictionary).get("notes", [])
	var line: String = " · ".join(PackedStringArray(notes)) if not notes.is_empty() \
			else ("내일을 위해 일찍 쉬었다" if action == MentalSystem.ACTION_PASS else "변화 없음")
	var l := UiHelpers.mk_label(card, line, 21, OutgameTheme.TEXT_SUB,
			Vector2(tx, 76), Vector2(w - tx - 28.0, 60))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return y + EVE_DONE_H + CARD_GAP


## The day's incident: resolved → summary; pending → a tap target that reopens it.
func _add_incident_card(w: float, y: float) -> float:
	var s: Dictionary = _gm.season_state
	var view: Dictionary = MentalSystem.session_view(s, MentalSystem.incident_session(s, _day))
	if view.is_empty():
		return y
	var inc: Dictionary = (((s.get("mental", {}) as Dictionary).get("days", {}) as Dictionary) \
			.get(str(_day), {}) as Dictionary).get("incident", {})
	var pid: int = int(view["pilot_id"])
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", OutgameTheme.lead_bar_style(OutgameTheme.NEGATIVE))
	card.position = Vector2(0, y)
	card.size = Vector2(w, INCIDENT_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_body.add_child(card)
	OutgameTheme.add_round_portrait(card, PilotImages.circle_for(pid),
			Vector2(28, (INCIDENT_H - 84.0) * 0.5), 84.0)
	UiHelpers.mk_label(card, "사건 — %s · %s" % [String(view["tag"]),
			MentalEvents.pilot_name(s, pid)], 28, OutgameTheme.TEXT,
			Vector2(136, 30), Vector2(w - 164, 40))
	var pending: bool = int(inc.get("choice", -1)) < 0
	var notes: Array = (inc.get("outcome", {}) as Dictionary).get("notes", [])
	var line: String = "눌러서 대응하기" if pending else (
			" · ".join(PackedStringArray(notes)) if not notes.is_empty() else "큰 탈 없이 지나갔다")
	var l := UiHelpers.mk_label(card, line, 21,
			OutgameTheme.NEGATIVE if pending else OutgameTheme.TEXT_SUB,
			Vector2(136, 76), Vector2(w - 164, 60))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if pending:
		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.size = card.size
		OutgameTheme.style_text_button(hit, 20)
		hit.pressed.connect(_open_incident)
		card.add_child(hit)
	return y + INCIDENT_H + CARD_GAP


func _my_pilots_in_seat_order() -> Array:
	var s: Dictionary = _gm.season_state
	var ids: Array = MentalSystem.my_pilot_ids(s)
	ids.sort_custom(func(a, b):
		var pa: PlayerData = MentalEvents.pilot_of(s, int(a))
		var pb: PlayerData = MentalEvents.pilot_of(s, int(b))
		var ra: int = GameEnums.role_seat(pa.role) if pa != null else 99
		var rb: int = GameEnums.role_seat(pb.role) if pb != null else 99
		return ra < rb)
	return ids


func _on_evening_pilot_picked(pid: int) -> void:
	if _overlay != null:
		return
	_sel_pid = pid
	_sel_day = _day
	_rebuild_list()


func _on_evening_action(action: String) -> void:
	if _overlay != null:
		return
	var session: Dictionary = MentalSystem.begin_evening(_gm.season_state, _day, action, _sel_pid)
	if action == MentalSystem.ACTION_PASS or session.is_empty():
		_rebuild_list()
		return
	_open_evening_session(session)


func _open_evening_session(session: Dictionary) -> void:
	if _overlay != null or session.is_empty():
		return
	var s: Dictionary = _gm.season_state
	var view: Dictionary = MentalSystem.session_view(s, session)
	if view.is_empty():
		return
	var pid: int = int(view["pilot_id"])
	var sub: String = "%s 저녁 · 면담" % OutgameTheme.DAY_NAMES[_day]
	if String(view["kind"]) == MentalEvents.KIND_OUTING:
		sub = "%s 저녁 · 외출 %d회째" % [OutgameTheme.DAY_NAMES[_day],
				MentalSystem.outings(s, pid) + 1]
	_open_overlay("evening", sub, MentalEvents.pilot_name(s, pid), pid, view)


func _open_incident() -> void:
	if _overlay != null or not MentalSystem.incident_pending(_gm.season_state, _day):
		return
	var s: Dictionary = _gm.season_state
	var view: Dictionary = MentalSystem.session_view(s, MentalSystem.incident_session(s, _day))
	if view.is_empty():
		return
	var pid: int = int(view["pilot_id"])
	_open_overlay("incident", "%s · 사건 발생 · %s" % [OutgameTheme.DAY_NAMES[_day],
			MentalEvents.pilot_name(s, pid)], String(view["tag"]), pid, view)


func _open_overlay(kind: String, sub: String, title: String, pid: int, view: Dictionary) -> void:
	_overlay_kind = kind
	_overlay = MessengerView.new()
	add_child(_overlay)
	_overlay.choice_picked.connect(_on_overlay_choice)
	_overlay.closed.connect(_on_overlay_closed)
	_overlay.open(sub, title, PilotImages.circle_for(pid), view["lines"], view["choices"])


func _on_overlay_choice(idx: int) -> void:
	var s: Dictionary = _gm.season_state
	var out: Dictionary
	if _overlay_kind == "incident":
		out = MentalSystem.resolve_incident(s, _day, idx)
	else:
		out = MentalSystem.finish_evening(s, _day, idx)
	if _overlay != null:
		_overlay.show_result(out)


func _on_overlay_closed() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_overlay_kind = ""
	refresh()
