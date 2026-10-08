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
# ── 씬 ──────────────────────────────────────────────────────────────────────
# **배치 · 스타일은 `UI_View_WeekProgressView.tscn` 이 갖는다** (레일 · 머리글 · 구분선 ·
# 스크롤 · 하단 버튼). 목록의 카드는 아이템 씬(`WeekMatchCard` · `WeekNoteCard` ·
# `WeekIncidentCard` · `WeekEveningCard`(+ `WeekEveningSlot`) · `WeekEveningDoneCard` ·
# `WeekPilotCard`(+ `WeekStatCell`))을 `%List`(VBox, 간격 = 카드 사이)에 붙인다.
# 이 스크립트는 `%` 노드에 데이터를 넣고, 데이터에 따라 바뀌는 색(역할 띠 · 오늘 칩 ·
# 내 경기 카드 · 상승/하락)과 기기 인셋만 코드로 넣는다. 생성은 `create()`.
#
# 배치 규약은 다른 시즌 화면과 같다: 화면째 `indent_to_safe_top` 으로 내리고
# 배경만 `extend_background` 로 노치 자리까지 늘린다. `%SafeArea` 의 아래는 아래
# 인셋만큼 올리고(= `safe_h()`), 하단 버튼은 그 인셋 밑까지 색면을 늘린다.

const SCENE_PATH: String = "res://features/season/week/UI_View_WeekProgressView.tscn"
const MATCH_CARD_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekMatchCard.tscn")
const NOTE_CARD_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekNoteCard.tscn")
const PILOT_CARD_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekPilotCard.tscn")
const STAT_CELL_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekStatCell.tscn")
const EVENING_CARD_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekEveningCard.tscn")
const EVENING_SLOT_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekEveningSlot.tscn")
const EVENING_DONE_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekEveningDoneCard.tscn")
const INCIDENT_CARD_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekIncidentCard.tscn")

const STAT_KEYS: Array   = PlayerData.STAT_KEYS

# ── 데이터에 따라 바뀌는 치수 (나머지 배치는 씬) ──
const CARD_H: float      = 148.0     # training card without quirk lines
const MATCH_CARD_H: float = 168.0    # the player's match card (others: OTHER_MATCH_H)
const OTHER_MATCH_H: float = 96.0
const PORTRAIT_D: float  = 88.0
const QUIRK_LINE_H: float = 34.0     # one quirk event line under a training card
const EVE_PORTRAIT_D: float = 84.0
const DONE_TEXT_X_NO_PORTRAIT: float = 28.0   # evening summary without a pilot (pass)

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

@onready var _week_lbl: Label = %WeekLabel
@onready var _phase_lbl: Label = %Phase
@onready var _title_lbl: Label = %Title
@onready var _date_small_lbl: Label = %DateSmall
@onready var _date_big_lbl: Label = %DateBig
@onready var _list_scroll: ScrollContainer = %Scroll
@onready var _list_body: VBoxContainer = %List
@onready var _list_end: Control = %ListEnd
@onready var _action_btn: Button = %Action

var _built: bool = false
var _day: int = 0

var _chip_panels: Array = []       # 7 Panel (scene: %Days/Day*/Chip)
var _chip_labels: Array = []       # 7 Label (… /Chip/Letter)

# M7 — evening / incident dialogs.
var _sel_pid: int = -1                # pilot picked on the evening card
var _sel_day: int = -1                # weekday `_sel_pid` belongs to
var _overlay: MessengerView = null    # dialog on top of the screen, null when closed
var _overlay_kind: String = ""        # "evening" / "incident"


## Instantiates the scene. `WeekProgressView.new()` is an empty Control — don't use it.
## Load (not preload) — preloading its own scene is a script ↔ scene cycle.
static func create() -> WeekProgressView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as WeekProgressView


func _ready() -> void:
	for slot in (%Days as Control).get_children():
		var chip: Panel = slot.get_node_or_null("Chip") as Panel
		var lbl: Label = slot.get_node_or_null("Chip/Letter") as Label
		if chip != null and lbl != null:
			_chip_panels.append(chip)
			_chip_labels.append(lbl)
	_action_btn.pressed.connect(_on_action_pressed)
	# Drag / fling scrolling instead of the engine's touch drag.
	DragScroll.attach(_list_scroll)
	if UiPreview.is_standalone(self):
		_fill_preview()
	ensure_view()


func ensure_view() -> void:
	if not _built:
		_fit_safe_area()
		_built = true
	refresh()


## Device insets only — every position is the scene's. The screen drops to the safe top,
## the paper extends back up into the notch band, `%SafeArea` ends on the safe bottom
## (`ScreenMetrics.safe_h()`), and the bottom bar's colour field runs on under the inset.
func _fit_safe_area() -> void:
	ScreenMetrics.indent_to_safe_top(self)
	ScreenMetrics.extend_background(%Background)
	OutgameTheme.fit_bottom_bar(_action_btn, %SafeArea)


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
	_week_lbl.text = Loc.t(L.TERM_WEEK_COUNT, {"n": int(_gm.season_state.get("phase_week", 1))})
	for d in _chip_panels.size():
		var chip: Panel = _chip_panels[d]
		var lbl: Label = _chip_labels[d]
		lbl.text = OutgameTheme.day_letter(d)
		# 오늘 = `WeekDayChipToday`(앰버 칩), 나머지 = `WeekDayChip`(투명) — 변형 이름만 바꾼다.
		chip.theme_type_variation = &"WeekDayChipToday" if d == _day else &"WeekDayChip"
		if d == _day:
			lbl.add_theme_color_override("font_color", OutgameTheme.RAIL)
		else:
			# 지나온 날은 흰 글자로 남는다 — 남은 날과 구분되어야 "며칠 남았나"가
			# 레일만 보고 읽힌다.
			lbl.add_theme_color_override("font_color",
					OutgameTheme.TEXT_ON_FILL if d < _day else OutgameTheme.RAIL_TEXT)


func _refresh_header() -> void:
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	_phase_lbl.text = Loc.t(L.SEASON_COMMON_PHASE_WEEK, {
		"phase": GameEnums.phase_label(phase), "week": int(s["phase_week"])})
	_title_lbl.text = OutgameTheme.day_name(_day)
	# 달력은 주의 월요일에 서 있으므로 요일만큼 더해 그날 날짜를 만든다.
	var date: Dictionary = _date_of_day(_day)
	_date_small_lbl.text = Loc.t(L.SEASON_WEEK_DATE, {"year": int(date["year"]), "month": int(date["month"])})
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
		if c == _list_end:
			continue
		_list_body.remove_child(c)
		c.queue_free()
	# The cards keep the scroll's anchored width (as the code-built list did) — the VBox
	# would otherwise shrink by the bar's width. Measured from the anchors, not from
	# `size`: an overflowing scroll grows by its bar, and reading that back would widen
	# the list on every refresh.
	_list_body.custom_minimum_size.x = _list_scroll.get_parent_area_size().x \
			+ _list_scroll.offset_right - _list_scroll.offset_left

	var md: int = CalendarSystem.matchday_of(_day)
	if md >= 0:
		_add_match_cards(md)

	if CalendarSystem.is_training_day(_day):
		# M7 — the day's incident (if any) and the evening action sit above
		# the training results: they are what the player still has to decide.
		_add_incident_card()
		_add_evening_card()
		var rows: Array = _week_log().get(_day, [])
		if rows.is_empty():
			_add_note_card(Loc.t(L.SEASON_WEEK_NO_TRAINING_LOG))
		else:
			for i in rows.size():
				_add_pilot_card(rows[i])
	elif md >= 0:
		pass   # 주말 — 경기 카드가 이미 그 자리를 답했다
	else:
		_add_note_card(Loc.t(L.SEASON_WEEK_NO_SCHEDULE))

	# The end marker stays last: the separation before it is the gap under the last card.
	_list_body.move_child(_list_end, -1)
	if _list_scroll != null:
		_list_scroll.scroll_vertical = 0


## Adds an item scene to the list and returns it (the end marker is moved last afterwards).
func _add_item(scene: PackedScene) -> Control:
	var item: Control = scene.instantiate() as Control
	_list_body.add_child(item)
	return item


## 이번 주 그 경기일의 경기들. 플레이어 경기가 맨 위, 나머지는 그 아래로.
func _add_match_cards(matchday: int) -> void:
	var entries: Array = _matches_on_day(matchday)
	if entries.is_empty():
		_add_note_card(Loc.t(L.SEASON_WEEK_NO_MATCH_DAY, {"day": OutgameTheme.day_name(_day)}))
		return
	for e_raw in entries:
		var e: Dictionary = e_raw
		var is_player: bool = bool(e["player"])
		var card: Panel = _add_item(MATCH_CARD_SCENE) as Panel
		card.custom_minimum_size.y = MATCH_CARD_H if is_player else OTHER_MATCH_H
		var tag: Label = card.get_node("%Tag")
		var title: Label = card.get_node("%Title")
		var status: Label = card.get_node("%Status")
		var hint: Label = card.get_node("%Hint")
		tag.text = String(e["tag"])
		title.text = String(e["title"])
		status.text = String(e["status"])
		hint.text = String(e["hint"])
		hint.visible = is_player
		var fg_sub: Color = OutgameTheme.TEXT_SUB
		if is_player:
			# 내 경기는 어두운 색면 — "이 화면을 떠나는" 버튼과 같은 색.
			card.add_theme_stylebox_override("panel",
					OutgameTheme.card_style(OutgameTheme.CARD_RADIUS, OutgameTheme.RAIL))
			fg_sub = OutgameTheme.RAIL_TEXT
			tag.add_theme_color_override("font_color", fg_sub)
			hint.add_theme_color_override("font_color", fg_sub)
			title.add_theme_color_override("font_color", OutgameTheme.TEXT_ON_FILL)
		var status_col: Color = fg_sub
		if String(e["result"]) == "win":
			status_col = OutgameTheme.POSITIVE
		elif String(e["result"]) == "loss":
			status_col = OutgameTheme.NEGATIVE
		status.add_theme_color_override("font_color", status_col)


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
			out.append(_match_row(m2, pid, Loc.t(L.SEASON_WEEK_TAG_LEAGUE), league))

	# 플레이어 경기를 맨 위로.
	out.sort_custom(func(a, b): return bool(a["player"]) and not bool(b["player"]))
	return out


func _match_row(m: Dictionary, pid: int, tag: String, namer: Node) -> Dictionary:
	var ta: int = int(m["team_a"]); var tb: int = int(m["team_b"])
	var is_player: bool = (ta == pid or tb == pid)
	var played: bool = bool(m["played"])
	# `result` = the player's own outcome ("win" / "loss" / "") and colours the status;
	# `status` is display text only.
	var status: String = Loc.t(L.SEASON_WEEK_RESULT_SCHEDULED)
	var result: String = ""
	if played:
		var winner: int = int(m["winner"])
		if is_player:
			result = "win" if winner == pid else "loss"
			status = Loc.t(L.SEASON_WEEK_RESULT_WIN if winner == pid else L.SEASON_WEEK_RESULT_LOSS)
		else:
			status = Loc.t(L.SEASON_WEEK_TEAM_WIN, {"team": _team_name(namer, winner)})
	var title: String = "%s  vs  %s" % [_team_name(namer, ta), _team_name(namer, tb)]
	if is_player:
		var opp: int = tb if ta == pid else ta
		title = "vs  %s" % _team_name(namer, opp)
	return {
		"player": is_player, "tag": tag, "title": title, "status": status, "result": result,
		"hint": Loc.t(L.SEASON_WEEK_HINT_START if (is_player and not played)
				else L.SEASON_WEEK_HINT_DONE),
	}


static func _team_name(namer: Node, team_id: int) -> String:
	if namer != null and namer.has_method("team_name"):
		return String(namer.call("team_name", team_id))
	return "Team %d" % team_id


## 선수 한 명의 그날 훈련 결과 카드 (`UI_Comp_WeekPilotCard.tscn`).
## Height = CARD_H + one line per quirk event (+ 8 under the divider).
func _add_pilot_card(row_raw: Variant) -> void:
	var row: Dictionary = row_raw
	var role: int = int(row["role"])
	var quirk_lines: Array = _quirk_lines(row.get("quirk", []))
	var card_h: float = CARD_H
	if not quirk_lines.is_empty():
		card_h += QUIRK_LINE_H * float(quirk_lines.size()) + 8.0
	var card: Panel = _add_item(PILOT_CARD_SCENE) as Panel
	card.custom_minimum_size.y = card_h
	card.add_theme_stylebox_override("panel",
			OutgameTheme.lead_bar_style(OutgameTheme.ROLE_COLORS[role]))

	OutgameTheme.add_round_portrait(card.get_node("%Portrait"),
			PilotImages.circle_for(int(row["pilot_id"])), Vector2.ZERO, PORTRAIT_D)
	(card.get_node("%Name") as Label).text = String(_gm.pilot_name(int(row["pilot_id"])))
	(card.get_node("%PositionBadge_Role") as PositionBadge).set_role(role)

	# Mech mastery of the day (§14 T4, row key `mastery` = raw tile EXP).
	var mastery_txt: String = _mastery_text(int(row["pilot_id"]), int(row.get("mastery", 0)))
	var ml: Label = card.get_node("%Mastery")
	ml.text = mastery_txt
	ml.visible = mastery_txt != ""

	# Stress — current value + what that day's training added (row key `stress`).
	# Shaken (≥ threshold) reads in the negative colour.
	var pid: int = int(row["pilot_id"])
	var stress_now: int = StressSystem.value(_gm.season_state, pid)
	var sl: Label = card.get_node("%Stress")
	sl.text = Loc.t(L.MENTAL_UI_STRESS_DAY, {"n": stress_now, "delta": "%+d" % int(row.get("stress", 0))})
	sl.theme_type_variation = &"NegativeLabel" if StressSystem.is_over(stress_now) else &"CaptionLabel"

	# 스탯 여섯 칸 — 이름 / 지금 값 / 이번 날의 결과.
	#
	# 아래 줄은 **오른 포인트가 있으면 `+N`, 없으면 `모인/TRAINING_EXP_PER_POINT`**
	# (다음 한 점까지 모인 EXP, 문턱은 const.csv)이다. 기초 코스만 깔린 판은 하루
	# EXP 가 그 문턱에 못 미쳐 월~목이 전부 `—` 로 보이고 금요일에 한꺼번에 오르는데,
	# 그러면 이 화면이 매일 답해야 하는 "오늘 뭐가 늘었나"에 나흘 동안 답이 없다.
	var after: Dictionary = row["after"]
	var ups: Dictionary = row["ups"]
	var carry: Dictionary = row.get("carry", {})
	var cells: Array = _ensure_children(card.get_node("%Stats"), STAT_CELL_SCENE, STAT_KEYS.size())
	for i in STAT_KEYS.size():
		var key: String = String(STAT_KEYS[i])
		var cell: Control = cells[i]
		(cell.get_node("%Short") as Label).text = PlayerData.stat_short(i)
		(cell.get_node("%Value") as Label).text = "%d" % int(after.get(key, 0))
		var up: int = int(ups.get(key, 0))
		var result: Label = cell.get_node("%Result")
		result.text = "%d/%d" % [int(carry.get(key, 0)), TrainingBoard.EXP_PER_POINT]
		if up != 0:
			result.text = "+%d" % up if up > 0 else "%d" % up
			result.add_theme_color_override("font_color",
					OutgameTheme.POSITIVE if up > 0 else OutgameTheme.NEGATIVE)
			result.add_theme_font_size_override("font_size", 21)

	# Quirk events of the day (§14 T1 row key `quirk`), one line each under the card body.
	(card.get_node("%QuirkDivider") as Control).visible = not quirk_lines.is_empty()
	var quirks: Control = card.get_node("%Quirks")
	quirks.visible = not quirk_lines.is_empty()
	var template: Label = card.get_node("%QuirkLine")
	template.visible = false
	for raw_line in quirk_lines:
		var line: Array = raw_line
		var ql: Label = template.duplicate() as Label
		ql.text = String(line[0])
		ql.add_theme_color_override("font_color", line[1] as Color)
		ql.visible = true
		quirks.add_child(ql)


## The first `count` children of `holder` (item scenes), instantiating `scene` for
## missing ones and hiding the extras — the scene ships sample items for the editor.
static func _ensure_children(holder: Node, scene: PackedScene, count: int) -> Array:
	while holder.get_child_count() < count:
		holder.add_child(scene.instantiate())
	var out: Array = []
	for i in holder.get_child_count():
		var c: Control = holder.get_child(i) as Control
		c.visible = i < count
		if i < count:
			out.append(c)
	return out


## "숙련 +12 · <mech>" — what the day's mastery cells actually added to the pilot's
## research mech: the same steps as `MechMastery.add_training_exp` (train scale, then
## `gain_preview`'s multipliers). Empty when nothing was earned or mastery is off.
func _mastery_text(pilot_id: int, raw: int) -> String:
	var state: Dictionary = _gm.season_state
	if raw <= 0 or not MechMastery.is_enabled(state):
		return ""
	var amount: int = MechMastery.gain_preview(state, pilot_id,
			roundi(float(raw) * ConstTable.num("MASTERY_TRAIN_SCALE")))
	var mech: int = MechMastery.research_mech(state, pilot_id)
	if mech < 0:   # same fallback as `add_training_exp` — the coach's pick
		var pd: PlayerData = MechMastery.find_pilot(state, pilot_id)
		if pd != null:
			mech = MechMastery.auto_research_mech(state, pd)
	if mech >= 0:
		return Loc.t(L.SEASON_WEEK_MASTERY_MECH, {"n": amount, "mech": MechMastery.mech_name(mech)})
	return Loc.t(L.SEASON_WEEK_MASTERY, {"n": amount})


## Quirk events → `[[text, colour]]`. Row shape (§14.1):
## `[{kind: gain|reroll|slot, result, id?, from?, to?}]`; a missing key = empty list.
## Results that changed nothing ("full" / "max" / "none") are shown faint so the player
## sees the tile fired but had no room.
static func _quirk_lines(events_raw: Variant) -> Array:
	var out: Array = []
	if not (events_raw is Array):
		return out
	for raw in events_raw:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var kind: String = String(e.get("kind", ""))
		var result: String = String(e.get("result", ""))
		match kind:
			"gain":
				if result == "gain":
					out.append([Loc.t(L.SEASON_WEEK_QUIRK_GAIN, {"name": _quirk_name(int(e.get("id", -1)))}),
							OutgameTheme.ACCENT_TEXT])
				elif result == "full":
					out.append([Loc.t(L.SEASON_WEEK_QUIRK_FULL), OutgameTheme.TEXT_FAINT])
			"reroll":
				if result == "reroll":
					out.append([Loc.t(L.SEASON_WEEK_QUIRK_REROLL, {"from": _quirk_names(e.get("from", [])),
							"to": _quirk_names(e.get("to", []))}), OutgameTheme.ACCENT_TEXT])
				else:
					out.append([Loc.t(L.SEASON_WEEK_QUIRK_NO_REROLL), OutgameTheme.TEXT_FAINT])
			"slot":
				if result == "slot":
					var txt: String = Loc.t(L.TRAINING_QUIRK_OP_SLOT)
					if e.has("to"):
						txt = Loc.t(L.SEASON_WEEK_QUIRK_SLOT_TO, {"n": int(e["to"])})
					out.append([txt, OutgameTheme.POSITIVE])
				else:
					out.append([Loc.t(L.SEASON_WEEK_QUIRK_SLOT_MAX), OutgameTheme.TEXT_FAINT])
	return out


## Quirk display name — `QuirkSystem.name_of(id)`, "기벽 #id" when the table has no row.
static func _quirk_name(id: int) -> String:
	if id < 0:
		return Loc.t(L.SEASON_WEEK_QUIRK_GENERIC)
	var name_v: String = QuirkSystem.name_of(id)
	return name_v if name_v != "" else Loc.t(L.SEASON_WEEK_QUIRK_UNKNOWN, {"id": id})


static func _quirk_names(ids_raw: Variant) -> String:
	var names: Array = []
	if ids_raw is Array:
		for id in ids_raw:
			names.append(_quirk_name(int(id)))
	elif ids_raw != null:
		names.append(_quirk_name(int(ids_raw)))
	return Loc.t(L.UI_WORD_NONE) if names.is_empty() else Loc.t(L.UI_LIST_SEPARATOR).join(names)


func _add_note_card(text: String) -> void:
	var card: Control = _add_item(NOTE_CARD_SCENE)
	(card.get_node("%Text") as Label).text = text


# ── 아래 버튼 ────────────────────────────────────────────────────────────────
func _refresh_action_button() -> void:
	if _action_btn == null:
		return
	if _hub != null and _hub.has_player_match_on_day(_day):
		_action_btn.text = Loc.t(L.SEASON_WEEK_BTN_START_MATCH)
		# 하단 바의 칸이라 **바 변형끼리만 갈아입는다** — `DarkButton` 이면 모서리가
		# 도로 둥글어져 이 칸만 화면에서 떠오른다. 갈아입은 뒤 인셋 몫을 다시 얹는다.
		_set_action_kind(&"BarDarkButton")
		return
	_action_btn.text = Loc.t(L.SEASON_WEEK_BTN_END_WEEK if _day >= CalendarSystem.DAYS_PER_WEEK - 1
			else L.UI_BUTTON_CONFIRM)
	_set_action_kind(&"BarPrimaryButton")


func _set_action_kind(variation: StringName) -> void:
	_action_btn.theme_type_variation = variation
	OutgameTheme.fit_bar_button(_action_btn)


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


func _add_evening_card() -> void:
	var s: Dictionary = _gm.season_state
	var e: Dictionary = MentalSystem.evening(s, _day)
	if MentalSystem.evening_done(s, _day):
		_add_evening_done_card(e)
		return

	var mine: Array = _my_pilots_in_seat_order()
	if _sel_day != _day or not mine.has(_sel_pid):
		_sel_day = _day
		_sel_pid = int(mine[0]) if not mine.is_empty() else -1

	var card: Control = _add_item(EVENING_CARD_SCENE)
	(card.get_node("%Limits") as Label).text = Loc.t(L.SEASON_WEEK_EVENING_LIMITS, {
		"iv": MentalSystem.interviews_left(s), "iv_max": MentalSystem.interviews_per_week(s),
		"out": MentalSystem.outings_left(s), "out_max": ConstTable.int_of("MENTAL_OUTINGS_PER_WEEK")})

	# Pilot row — tap to select. Trust in amber once the outing is unlocked.
	var slots: Array = _ensure_children(card.get_node("%Slots"), EVENING_SLOT_SCENE, mine.size())
	for i in mine.size():
		var pid: int = int(mine[i])
		var slot: Control = slots[i]
		var picked: bool = pid == _sel_pid
		(slot.get_node("%Highlight") as Control).visible = picked
		OutgameTheme.add_round_portrait(slot.get_node("%Portrait"), PilotImages.circle_for(pid),
				Vector2.ZERO, EVE_PORTRAIT_D,
				OutgameTheme.ACCENT if picked else OutgameTheme.BORDER)
		(slot.get_node("%Name") as Label).text = MentalEvents.pilot_name(s, pid)
		var trust: Label = slot.get_node("%Trust")
		trust.text = Loc.t(L.SEASON_WEEK_SLOT_TRUST,
				{"trust": MentalSystem.trust(s, pid), "outings": MentalSystem.outings(s, pid)})
		if MentalSystem.outing_unlocked(s, pid):
			trust.add_theme_color_override("font_color", OutgameTheme.ACCENT_TEXT)
		(slot.get_node("%Hit") as Button).pressed.connect(_on_evening_pilot_picked.bind(pid))

	# Actions. Disabled buttons say why on their own label.
	var can_iv: bool = MentalSystem.can_interview(s) and _sel_pid >= 0
	var can_out: bool = MentalSystem.can_outing(s, _sel_pid) and _sel_pid >= 0
	var out_text: String = Loc.t(L.TERM_ACTIVITY_OUTING)
	if MentalSystem.outings_left(s) <= 0:
		out_text = Loc.t(L.SEASON_WEEK_OUTING_WEEK_DONE)
	elif not MentalSystem.outing_unlocked(s, _sel_pid):
		out_text = Loc.t(L.SEASON_WEEK_OUTING_NEED_TRUST, {"n": ConstTable.int_of("TRUST_OUTING_MIN")})
	var interview: Button = card.get_node("%Interview")
	interview.text = Loc.t(L.TERM_ACTIVITY_INTERVIEW if MentalSystem.can_interview(s)
			else L.SEASON_WEEK_INTERVIEW_WEEK_DONE)
	interview.disabled = not can_iv
	interview.pressed.connect(_on_evening_action.bind(MentalSystem.ACTION_INTERVIEW))
	var outing: Button = card.get_node("%Outing")
	outing.text = out_text
	outing.disabled = not can_out
	outing.pressed.connect(_on_evening_action.bind(MentalSystem.ACTION_OUTING))
	(card.get_node("%Pass") as Button).pressed.connect(
			_on_evening_action.bind(MentalSystem.ACTION_PASS))


func _add_evening_done_card(e: Dictionary) -> void:
	var s: Dictionary = _gm.season_state
	var action: String = String(e.get("action", MentalSystem.ACTION_PASS))
	var pid: int = int(e.get("pilot_id", -1))
	var card: Control = _add_item(EVENING_DONE_SCENE)
	var portrait: Control = card.get_node("%Portrait")
	var head_lbl: Label = card.get_node("%Head")
	var line_lbl: Label = card.get_node("%Line")
	portrait.visible = pid >= 0
	if pid >= 0:
		OutgameTheme.add_round_portrait(portrait, PilotImages.circle_for(pid),
				Vector2.ZERO, EVE_PORTRAIT_D)
	else:
		# No pilot (pass) — the text moves left onto the portrait's spot.
		head_lbl.offset_left = DONE_TEXT_X_NO_PORTRAIT
		line_lbl.offset_left = DONE_TEXT_X_NO_PORTRAIT
	var head: String = Loc.t(L.SEASON_WEEK_EVENING_RESTED)
	if action == MentalSystem.ACTION_INTERVIEW:
		head = Loc.t(L.SEASON_WEEK_EVENING_INTERVIEW, {"name": MentalEvents.pilot_name(s, pid)})
	elif action == MentalSystem.ACTION_OUTING:
		head = Loc.t(L.SEASON_WEEK_EVENING_OUTING, {"name": MentalEvents.pilot_name(s, pid)})
	head_lbl.text = head
	var notes: Array = MentalEvents.note_texts(s, (e.get("outcome", {}) as Dictionary).get("notes", []))
	line_lbl.text = " · ".join(PackedStringArray(notes)) if not notes.is_empty() \
			else Loc.t(L.SEASON_WEEK_RESTED_LINE if action == MentalSystem.ACTION_PASS else L.SEASON_WEEK_NO_CHANGE)


## The day's incident: resolved → summary; pending → a tap target that reopens it.
func _add_incident_card() -> void:
	var s: Dictionary = _gm.season_state
	var view: Dictionary = MentalSystem.session_view(s, MentalSystem.incident_session(s, _day))
	if view.is_empty():
		return
	var inc: Dictionary = (((s.get("mental", {}) as Dictionary).get("days", {}) as Dictionary) \
			.get(str(_day), {}) as Dictionary).get("incident", {})
	var pid: int = int(view["pilot_id"])
	var card: Panel = _add_item(INCIDENT_CARD_SCENE) as Panel
	card.add_theme_stylebox_override("panel", OutgameTheme.lead_bar_style(OutgameTheme.NEGATIVE))
	OutgameTheme.add_round_portrait(card.get_node("%Portrait"), PilotImages.circle_for(pid),
			Vector2.ZERO, EVE_PORTRAIT_D)
	(card.get_node("%Head") as Label).text = Loc.t(L.SEASON_WEEK_INCIDENT_HEAD, {
			"tag": String(view["tag"]), "name": MentalEvents.pilot_name(s, pid)})
	var pending: bool = int(inc.get("choice", -1)) < 0
	var notes: Array = MentalEvents.note_texts(s, (inc.get("outcome", {}) as Dictionary).get("notes", []))
	var line: Label = card.get_node("%Line")
	line.text = Loc.t(L.SEASON_WEEK_INCIDENT_TAP) if pending else (
			" · ".join(PackedStringArray(notes)) if not notes.is_empty() else Loc.t(L.SEASON_WEEK_INCIDENT_CALM))
	if pending:
		line.theme_type_variation = &"NegativeLabel"
	var hit: Button = card.get_node("%Hit")
	hit.visible = pending
	if pending:
		hit.pressed.connect(_open_incident)


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
	var sub: String = Loc.t(L.SEASON_WEEK_SUB_INTERVIEW, {"day": OutgameTheme.day_name(_day)})
	if String(view["kind"]) == MentalEvents.KIND_OUTING:
		sub = Loc.t(L.SEASON_WEEK_SUB_OUTING, {"day": OutgameTheme.day_name(_day),
				"n": MentalSystem.outings(s, pid) + 1})
	_open_overlay("evening", sub, MentalEvents.pilot_name(s, pid), pid, view)


func _open_incident() -> void:
	if _overlay != null or not MentalSystem.incident_pending(_gm.season_state, _day):
		return
	var s: Dictionary = _gm.season_state
	var view: Dictionary = MentalSystem.session_view(s, MentalSystem.incident_session(s, _day))
	if view.is_empty():
		return
	var pid: int = int(view["pilot_id"])
	_open_overlay("incident", Loc.t(L.SEASON_WEEK_SUB_INCIDENT, {"day": OutgameTheme.day_name(_day),
			"name": MentalEvents.pilot_name(s, pid)}), String(view["tag"]), pid, view)


func _open_overlay(kind: String, sub: String, title: String, pid: int, view: Dictionary) -> void:
	_overlay_kind = kind
	_overlay = MessengerView.create()
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
		_overlay.show_result(MentalEvents.outcome_view(s, out))


func _on_overlay_closed() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_overlay_kind = ""
	refresh()


## F6 단독 실행 미리보기 — 메모리 런의 **수요일**(`resources/UiPreview.gd`). 미리보기 전용
## `TrainingBoard` 에 코치 추천 판을 깔고 월~수를 정산해 두고(호스트가 없으면 이 화면은
## 정산하지 않는다), 그날 사건이 나면 첫 답으로 풀어 둔다 — 덮개 없이 사건 요약 · 오늘 저녁 ·
## 파일럿 훈련 카드가 보이게. "확인"은 호스트(`SeasonHub`)가 없어 아무 일도 안 한다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var s: Dictionary = gm.season_state
	var day: int = 2
	s["week_day"] = day
	var board := TrainingBoard.new()
	board.name = "PreviewBoard"
	add_child(board)
	board.auto_arrange()
	var day_log: Dictionary = _week_log()
	for d in day + 1:
		day_log[d] = board.apply_day_training(d)
	MentalSystem.ensure_incident(s, day)
	if MentalSystem.incident_pending(s, day):
		MentalSystem.resolve_incident(s, day, 0)
