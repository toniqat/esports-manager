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
#     [ 팀 부지 맵 + 선수 토큰 ]              ← 훈련일: 고정 (%MapPin)
#     [ 사건 · 오후 카드 ]                     ← 세로 스크롤
#     [선수][선수][선수][선수][선수]           ← 항상 (%PilotRow, 오늘 스트레스 증감 강조)
#    [ 오전 / 오후 ][        다음        ]    ← 하단 바
#
# 레일의 **지금 요일 한 칸만 앰버로 채워진다** — 지나온 날은 흰 글자, 남은 날은
# 흐린 글자다.
#
# ── 훈련일 (월~금) = 오전 → 오후 → 저녁 ───────────────────────────────────────
# 훈련일은 다섯 단계(`_stage`)로 흐르고, 단계는 **기록에서 읽는다** (따로 저장하지 않는다):
#   MORNING   `week_day_log` 에 그날이 없다. 맵에서 선수가 그날 훈련 시설 자리에 서 있고,
#             초상화 위 말풍선이 그 시간의 훈련 이름을 말한다.
#             "다음" = `TrainingBoard.apply_day_training` 으로 정산 → 결과를 `week_day_log[day]` 에.
#   RESULT    정산됐고 오전 만남이 아직 열리지 않았다. 그날 결과(능력치 · 스트레스 · 숙련 · 기벽)가
#             초상화 위에서 떠올라 흐려진다(`_play_result_fx`). 연출이 끝나면 스스로
#             `MentalSystem.begin_morning` → 오전 만남. "다음" = 연출을 건너뛴다.
#   TALK      오전 만남(훈련 소감): 선수 하나를 눌러 만난다 (외출 없음). 합동 훈련(같은 타일)이면
#             함께 훈련한 선수도 같이 온다. "다음" = 오후 (`AfternoonAway.begin`; 아직 만날 수
#             있으면 경고 팝업).
#   AFTERNOON the afternoon record exists. Pilots who can be visited are lit; a tap = visit (`VisitMenu`, §15 D).
#             "다음" = 저녁 (아직 할 수 있으면 경고 → 패스로 기록) — `MentalSystem.begin_dusk` 가
#             사건을 굴리고, 사건이 없으면 바로 다음 날.
#   EVENING   저녁 사건(선수가 아니라 팀에 일어나는 일, 저절로 열린다). "다음" = 다음 날.
# **이미 정산된 날은 다시 정산하지 않는다** — 경기를 치르고 같은 요일로 돌아와도,
# 불러오기를 해도 같은 기록을 다시 그린다.
#
# ── Weekend (Sat · Sun) ── one player match per week, on Sunday ─────────────
#   Sat STADIUM   stadium map; "경기 준비" → MatchFlow PREP + BAN_PICK (picks stored,
#                 `SeasonHub.on_week_day_match_prep`), then AFTERNOON → EVENING on the
#                 team map (no training, no morning talk).
#   Sun STADIUM   stadium map; "경기 시작" → BattleSim with the Saturday picks
#                 (`SeasonHub.on_week_day_match_start`) → standings → PRESS
#                 (stadium map, "기자회견" → `SeasonHub.open_press`) → AFTERNOON (team
#                 map, visit, §15 D) → EVENING (the incident rolls) → "주 마감 →".
# A weekend day without a player match runs AFTERNOON → EVENING only. The weekend
# stages are read from the records too (picks in `pending_match`, the week's result,
# `MentalSystem.press_answered`, the afternoon / dusk records).
#
# ── 씬 ──────────────────────────────────────────────────────────────────────
# **배치 · 스타일은 `UI_View_WeekProgressView.tscn` 이 갖는다** (레일 · 머리글 · 구분선 ·
# 스크롤 · 하단 선수 카드 줄 `%PilotRow` · 하단 바). 훈련일의 맵(`WeekMapSection`(+ `BaseMap` ·
# `WeekMapPilot`))은 스크롤 위에 고정된 `%MapPin` 에, 목록의 카드는 아이템 씬(`WeekMatchCard` ·
# `WeekNoteCard` · `WeekIncidentCard` · `WeekAfternoonCard` · `WeekAfternoonDoneCard`)을 `%List` 에 붙인다.
# 이 스크립트는 `%` 노드에 데이터를 넣고, 데이터에 따라 바뀌는 색(역할 띠 · 오늘 칩 ·
# 내 경기 카드 · 상승/하락 · 오후에 못 부르는 선수의 흐림)과 기기 인셋만 코드로 넣는다.
# 생성은 `create()`.

const SCENE_PATH: String = "res://features/season/week/UI_View_WeekProgressView.tscn"
const MATCH_CARD_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekMatchCard.tscn")
const NOTE_CARD_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekNoteCard.tscn")
const AFTERNOON_CARD_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekAfternoonCard.tscn")
const AFTERNOON_DONE_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekAfternoonDoneCard.tscn")
const TALK_CARD_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekTalkCard.tscn")
const INCIDENT_CARD_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekIncidentCard.tscn")
const MAP_SECTION_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekMapSection.tscn")
const MAP_PILOT_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekMapPilot.tscn")

const STAT_KEYS: Array   = PlayerData.STAT_KEYS

## Day stage, read from the records (`_stage`). STADIUM / PRESS are weekend-only.
enum Stage { OFF, MORNING, RESULT, TALK, AFTERNOON, EVENING, STADIUM, PRESS }

# ── 데이터에 따라 바뀌는 치수 (나머지 배치는 씬) ──
const MATCH_CARD_H: float = 168.0    # the player's match card (others: OTHER_MATCH_H)
const OTHER_MATCH_H: float = 96.0
const EVE_PORTRAIT_D: float = 84.0
const MAP_PORTRAIT_D: float = 84.0
# Result FX (RESULT stage): each line rises FX_RISE px and fades over FX_TIME s, the next
# line of the same pilot starts FX_STAGGER s later; the afternoon starts FX_TAIL s after the last.
const FX_RISE: float = 72.0
const FX_TIME: float = 1.4
const FX_STAGGER: float = 0.5
const FX_TAIL: float = 0.25
## Start offset between pilots (seat order), so neighbouring tokens' texts sit at different heights.
const FX_PILOT_STAGGER: float = 0.2
const DONE_TEXT_X_NO_PORTRAIT: float = 28.0   # afternoon summary without a pilot (pass)
## The picked map token (morning talk pick / afternoon visit open) is drawn this much larger,
## around its centre. A token that cannot be picked gets the black masks instead
## (`_token_dimmed`; `%Mask` + each gauge's `set_dimmed`).
const MAP_PICKED_SCALE: float = 1.2

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
@onready var _map_pin: Control = %MapPin
## The scroll's top as authored (no map). On training days it moves under `%MapPin`.
@onready var _scroll_top: float = _list_scroll.offset_top
@onready var _stage_btn: Button = %Stage
@onready var _action_btn: Button = %Action

var _built: bool = false
var _day: int = 0

var _chip_panels: Array = []       # 7 Panel (scene: %Days/Day*/Chip)
var _chip_labels: Array = []       # 7 Label (… /Chip/Letter)

# M7 — afternoon / incident dialogs.
var _sel_pid: int = -1                # pilot picked on the map this morning / afternoon (-1 = none)
var _sel_day: int = -1                # weekday `_sel_pid` belongs to
var _sel_stage: int = Stage.OFF       # stage `_sel_pid` was picked in (a new half drops it)
var _overlay: VnDialogueView = null   # talk / afternoon / limit-break / incident dialogue, null when closed
var _overlay_kind: String = ""        # "talk" / "evening" / "limit_break" / "incident"
var _overlay_pid: int = -1            # the dialogue's pilot (limit break answers by pilot)
var _visit_menu: VisitMenu = null     # afternoon visit popup (pick / menu / courses / result)
var _awaken_view: Node = null         # §15 C AwakeningView while it is open
var _skip_popup: ConfirmPopup = null  # "skip the morning talk / afternoon?" warning, made on first use

var _pilot_cards: Array = []          # SeasonPilotCard x5 (scene %PilotRow, seat order)
var _tokens: Dictionary = {}          # pilot id -> map token of the current list build
var _fx_day: int = -1                 # weekday whose result FX is playing (-1 = none)


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
	_pilot_cards = (%PilotRow as Control).get_children()
	for c in _pilot_cards:
		(c as SeasonPilotCard).pressed.connect(_on_pilot_card_pressed)
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
	OutgameTheme.fit_bottom_bar(%Bar, %SafeArea)


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not _built:
		return
	_day = clampi(int(_gm.season_state.get("week_day", 0)), 0,
			CalendarSystem.DAYS_PER_WEEK - 1)
	_advance_weekend()
	_refresh_rail()
	_refresh_header()
	_rebuild_list()
	_refresh_pilot_row()
	_refresh_action_button()
	if _stage() == Stage.RESULT and _fx_day != _day:
		_play_result_fx()
	_open_pending.call_deferred()


## What opens by itself after a redraw, one at a time (each one's close redraws again):
## a talk / visit / afternoon dialog left open by a reload, a queued awakening
## (`Awakening.next_pending`, §15 C — after every state change that can raise the gauge),
## then at the evening the limit-break event (`LimitBreak.pending_event`, §15 B) before the
## incident. The day cannot be confirmed past any of them.
func _open_pending() -> void:
	if _busy() or not is_inside_tree():
		return
	var s: Dictionary = _gm.season_state
	if _talk_open():
		_open_talk_session(MentalSystem.begin_talk(s, _day, -1))
	elif MentalSystem.visit_open(s, _day) >= 0 and _stage() == Stage.AFTERNOON:
		_open_visit_menu(MentalSystem.visit_open(s, _day))
	elif _evening_open():
		_open_evening_session(MentalSystem.begin_evening(s, _day, "", -1))
	elif _open_awakening():
		pass
	elif MentalSystem.dusk_started(s, _day) and LimitBreak.pending_event(s, _day) >= 0:
		_open_limit_break(LimitBreak.pending_event(s, _day))
	elif MentalSystem.incident_pending(s, _day):
		_open_incident()


## A dialog, the visit popup or an awakening is on screen (taps on the screen wait).
func _busy() -> bool:
	return _overlay != null or _visit_menu != null or _awaken_view != null


## Where the day stands — read from the records, never stored on its own.
## Training days (Mon–Fri): no `week_day_log[day]` = MORNING, settled without a talk
## record = RESULT, talk record (`MentalSystem.morning_started`) = TALK, afternoon rolled
## (`AfternoonAway.started`) = AFTERNOON, evening marked (`MentalSystem.dusk_started`) =
## EVENING. Old saves reach the afternoon without a talk record: the talk is skipped.
## Weekend: STADIUM while the Saturday prep / Sunday match is open, PRESS until the
## Sunday press conference is answered, then the afternoon / evening records.
func _stage() -> int:
	var s: Dictionary = _gm.season_state
	if not CalendarSystem.is_training_day(_day):
		if _weekend_stage() != Stage.OFF:
			return _weekend_stage()
		if AfternoonAway.started(s, _day):
			return Stage.EVENING if MentalSystem.dusk_started(s, _day) else Stage.AFTERNOON
		return Stage.EVENING if MentalSystem.dusk_started(s, _day) else Stage.OFF
	if not _week_log().has(_day):
		return Stage.MORNING
	if AfternoonAway.started(s, _day):
		return Stage.EVENING if MentalSystem.dusk_started(s, _day) else Stage.AFTERNOON
	if MentalSystem.morning_started(s, _day):
		return Stage.TALK
	return Stage.RESULT


## STADIUM / PRESS of a weekend day, else OFF. Needs the hub (F6 preview: OFF).
func _weekend_stage() -> int:
	if _hub == null:
		return Stage.OFF
	if _day == CalendarSystem.PREP_DAY and _hub.needs_match_prep(_day):
		return Stage.STADIUM
	if _day == CalendarSystem.MATCH_DAY:
		if _hub.has_player_match_on_day(_day):
			return Stage.STADIUM
		if _hub.press_pending():
			return Stage.PRESS
	return Stage.OFF


## Weekend days move on by themselves once nothing is left to decide: a weekend day
## without stadium / press opens its afternoon (`AfternoonAway.begin`) — the Sunday of a
## match too, after the press (§15 D: STADIUM → PRESS → AFTERNOON (visit) → EVENING).
## Recorded and saved, so a reload lands on the same stage. (Old saves whose match
## Sunday already rolled its evening stay in the evening.)
func _advance_weekend() -> void:
	if _hub == null or CalendarSystem.is_training_day(_day) or _weekend_stage() != Stage.OFF:
		return
	var s: Dictionary = _gm.season_state
	if not AfternoonAway.started(s, _day) and not MentalSystem.dusk_started(s, _day):
		AfternoonAway.begin(s, _day)
		_save("afternoon")


## 그날 훈련을 정산한다 (오전의 "다음"). **기록이 이미 있으면 아무것도 하지 않는다** —
## 경기를 치르고 같은 요일로 돌아오는 경로가 실제로 있고, 거기서 다시 정산하면 훈련이
## 두 번 먹는다.
func _settle_day() -> void:
	if not CalendarSystem.is_training_day(_day):
		return
	var log: Dictionary = _week_log()
	if log.has(_day):
		return
	var board: TrainingBoard = _board()
	log[_day] = board.apply_day_training(_day) if board != null else []
	_save("training_settled")


## Autosave after a stage change / answer (`SeasonHub.autosave`). No hub (F6 preview) = no save.
func _save(reason: String) -> void:
	if _hub != null:
		_hub.autosave(reason)


## The training board: the hub's, or the F6 preview's own child.
func _board() -> TrainingBoard:
	if _hub != null:
		return _hub.get_node_or_null("TrainingBoard") as TrainingBoard
	return get_node_or_null("PreviewBoard") as TrainingBoard


## 오후로 넘어간다 (오전 만남의 "다음"): 만나지 않았으면 패스로 기록하고, 혼자 외출(스트레스가
## 높은 선수) → 아니면 숙소 휴식을 선수마다 한 번 굴린다. `AfternoonAway` 가 기록하고, 다시
## 불러도 그 기록을 돌려준다.
func _begin_afternoon() -> void:
	MentalSystem.pass_talk(_gm.season_state, _day)
	AfternoonAway.begin(_gm.season_state, _day)
	_save("afternoon")


## 저녁으로 넘어간다 (오후의 "다음"): 오후 행동이 없었으면 패스로 기록하고 사건을 한 번 굴린다.
## 사건이 없으면 저녁에 멈출 일이 없으므로 바로 다음 날로.
func _begin_evening() -> void:
	var s: Dictionary = _gm.season_state
	if not MentalSystem.evening_done(s, _day):
		MentalSystem.begin_evening(s, _day, MentalSystem.ACTION_PASS, -1)
	# A quiet evening (no incident, no limit-break event) goes straight on — except the
	# Sunday, which stops on its evening for "주 마감 →".
	if MentalSystem.begin_dusk(s, _day).is_empty() and LimitBreak.pending_event(s, _day) < 0 \
			and _day < CalendarSystem.DAYS_PER_WEEK - 1:
		_leave_day()
		return
	_save("incident")
	refresh()


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
	for c in _map_pin.get_children():
		_map_pin.remove_child(c)
		c.queue_free()
	# No map (match days): the list starts where the scene puts it.
	_map_pin.visible = false
	_list_scroll.offset_top = _scroll_top
	# The cards keep the scroll's anchored width (as the code-built list did) — the VBox
	# would otherwise shrink by the bar's width. Measured from the anchors, not from
	# `size`: an overflowing scroll grows by its bar, and reading that back would widen
	# the list on every refresh.
	_list_body.custom_minimum_size.x = _list_scroll.get_parent_area_size().x \
			+ _list_scroll.offset_right - _list_scroll.offset_left

	var stage: int = _stage()
	if stage != Stage.OFF:
		# Base map (pinned), then what the player still has to decide: the afternoon
		# card first (its buttons must not fall below the fold), then the incident.
		_add_map_section(stage)
		if stage == Stage.TALK:
			_add_talk_card()
		elif stage == Stage.AFTERNOON:
			_add_afternoon_card()
		_add_incident_card()
		# The day's training results are shown on the map (rising texts) and in the
		# bottom cards' stress change; the list only says when nothing was settled.
		if CalendarSystem.is_training_day(_day) and stage != Stage.MORNING \
				and (_week_log().get(_day, []) as Array).is_empty():
			_add_note_card(Loc.t(L.SEASON_WEEK_NO_TRAINING_LOG))
	# The round's matches: on Sunday (the match day), and on Saturday while the
	# prep for them is open.
	var md: int = CalendarSystem.matchday_of(_day)
	if stage == Stage.STADIUM and _day == CalendarSystem.PREP_DAY:
		md = CalendarSystem.matchday_of(CalendarSystem.MATCH_DAY)
	if md >= 0:
		_add_match_cards(md)
	elif stage == Stage.OFF:
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


# ── 팀 부지 맵 ───────────────────────────────────────────────────────────────
## The team's base map with my five pilots. Morning / result: each stands on the
## spot of that day's training colour (`BaseMap.spot_of_color`). Afternoon: a pilot
## resting goes to the dorm, one out alone to the entrance (both dimmed), and a
## pilot that cannot be asked any more is dimmed on its spot.
func _add_map_section(stage: int) -> void:
	var s: Dictionary = _gm.season_state
	# Pinned above the scroll (`%MapPin`), so the map stays while the cards scroll;
	# the list starts one card gap under it.
	var section: Control = MAP_SECTION_SCENE.instantiate() as Control
	_map_pin.add_child(section)
	_map_pin.visible = true
	_list_scroll.offset_top = _map_pin.offset_bottom \
			+ float(_list_body.get_theme_constant("separation"))
	var hint: String = Loc.t(L.SEASON_WEEK_MAP_HINT_MORNING)
	if stage == Stage.STADIUM:
		hint = Loc.t(L.SEASON_WEEK_MAP_HINT_STADIUM_PREP if _day == CalendarSystem.PREP_DAY
				else L.SEASON_WEEK_MAP_HINT_STADIUM_MATCH)
	elif stage == Stage.PRESS:
		hint = Loc.t(L.SEASON_WEEK_MAP_HINT_PRESS)
	elif stage == Stage.EVENING and not MentalSystem.incident_pending(s, _day) \
			and MentalSystem.incident_session(s, _day).is_empty():
		hint = Loc.t(L.SEASON_WEEK_MAP_HINT_EVENING_QUIET)
	elif stage == Stage.RESULT:
		hint = Loc.t(L.SEASON_WEEK_MAP_HINT_RESULT)
	elif stage == Stage.TALK:
		hint = Loc.t(L.SEASON_WEEK_MAP_HINT_TALK_DONE if MentalSystem.talk_done(s, _day)
				else L.SEASON_WEEK_MAP_HINT_TALK)
	elif stage == Stage.AFTERNOON:
		hint = Loc.t(L.SEASON_WEEK_MAP_HINT_AFTERNOON_DONE if MentalSystem.evening_done(s, _day)
				else L.SEASON_WEEK_MAP_HINT_AFTERNOON)
	elif stage == Stage.EVENING:
		hint = Loc.t(L.SEASON_WEEK_MAP_HINT_EVENING)
	(section.get_node("%Hint") as Label).text = hint

	var stadium: bool = stage == Stage.STADIUM or stage == Stage.PRESS
	var map: BaseMap = BaseMap.create_stadium() if stadium \
			else BaseMap.create(RunRules.team_map_id(int(s.get("player_team_id", 0))))
	map.name = "BaseMap_Stadium" if stadium else "BaseMap_Team"
	(section.get_node("%MapHolder") as Control).add_child(map)
	map.size = BaseMap.DESIGN_SIZE
	if not stadium:
		# §16 — the facility research bubbles, read-only (the hub map is the tappable one);
		# they sit under the pilot tokens (`%Facilities` layer).
		ResearchBubble.populate(map, s, false)

	var rows_by_pid: Dictionary = {}
	for raw in (_week_log().get(_day, []) as Array):
		var row: Dictionary = raw
		rows_by_pid[int(row["pilot_id"])] = row
	var colors: Dictionary = {}
	var names: Dictionary = {}
	var groups: Dictionary = {}
	var board: TrainingBoard = _board()
	if board != null and CalendarSystem.is_training_day(_day):
		colors = board.day_colors(_day)
		names = board.day_tile_names(_day)
		groups = board.day_groups(_day)

	if _sel_day != _day or _sel_stage != stage or not _can_pick(stage, _sel_pid):
		_sel_day = _day
		_sel_stage = stage
		_sel_pid = -1

	_tokens.clear()
	var entries: Array = []
	for raw_pid in _my_pilots_in_seat_order():
		var pid: int = int(raw_pid)
		var row: Dictionary = rows_by_pid.get(pid, {})
		var color: String = String(row.get("color", ""))
		var facility: String = String(row.get("facility", ""))
		var pd: PlayerData = MentalEvents.pilot_of(s, pid)
		var seat: int = GameEnums.role_seat(pd.role) if pd != null else -1
		if row.is_empty():
			color = String(colors.get(seat, ""))
			facility = String((groups.get(seat, {}) as Dictionary).get("facility", ""))
		# The training's facility (joint training = one shared spot), else its colour's spot.
		var spot: String = BaseMap.spot_of_facility(facility if facility != "" else color)
		if stadium:
			spot = _stadium_spot(stage)
		var away: String = AfternoonAway.away_of(s, _day, pid) \
				if stage == Stage.AFTERNOON or stage == Stage.EVENING else ""
		if away == AfternoonAway.AWAY_DORM:
			spot = BaseMap.SPOT_DORM
		elif away == AfternoonAway.AWAY_SELF_OUTING:
			spot = BaseMap.SPOT_ENTRANCE
		var token: Control = _add_map_token(map, stage, pid, String(names.get(seat, "")), away)
		_tokens[pid] = token
		var hold: Control = token.get_node("%Portrait")
		entries.append({"node": token, "spot": spot, "anchor": hold.position + hold.size * 0.5})
	map.place_tokens(entries)


## Where my pilots stand on the stadium map: the team room on Saturday (analysis and
## ban/pick), the stage booths on Sunday morning, the press room after the match.
func _stadium_spot(stage: int) -> String:
	if stage == Stage.PRESS:
		return BaseMap.SPOT_PRESS
	return BaseMap.SPOT_TEAM_ROOM if _day == CalendarSystem.PREP_DAY else BaseMap.SPOT_BOOTH


## One pilot token on the map (`UI_Comp_WeekMapPilot.tscn`). No name under the portrait:
## the morning shows a speech bubble with the training `course` this pilot does now, the
## afternoon an away chip (혼자 외출 / 숙소 휴식). Under the portrait three gauge panels
## (stress · trust · awakening, `PilotGauge`). A pilot that cannot be picked is covered by the
## black masks (`_token_dimmed`); the picked one (`_token_picked`) is scaled up around its
## centre and drawn over the others. The RESULT stage's rising texts are added later by
## `_play_result_fx`.
func _add_map_token(map: BaseMap, stage: int, pid: int, course: String, away: String) -> Control:
	var s: Dictionary = _gm.season_state
	var token: Control = MAP_PILOT_SCENE.instantiate() as Control
	map.add_token(token)
	var picked: bool = _token_picked(stage, pid)
	OutgameTheme.add_round_portrait(token.get_node("%Portrait"), PilotImages.circle_for(pid),
			Vector2.ZERO, MAP_PORTRAIT_D, OutgameTheme.ACCENT if picked else OutgameTheme.SURFACE)
	var stress_g: PilotGauge = token.get_node("%PilotGauge_Stress")
	var trust_g: PilotGauge = token.get_node("%PilotGauge_Trust")
	var awaken_g: PilotGauge = token.get_node("%PilotGauge_Awaken")
	stress_g.show_stress(StressSystem.value(s, pid))
	trust_g.show_trust(MentalSystem.trust(s, pid))
	awaken_g.show_awakening(Awakening.gauge(s, pid), Awakening.threshold())
	var bubble_on: bool = stage == Stage.MORNING and course != ""
	(token.get_node("%Bubble") as Control).visible = bubble_on
	(token.get_node("%BubbleTail") as CanvasItem).visible = bubble_on
	(token.get_node("%BubbleText") as Label).text = course
	var away_chip: Control = token.get_node("%Away")
	var away_lbl: Label = token.get_node("%Name")
	away_chip.visible = false
	if stage == Stage.AFTERNOON or stage == Stage.EVENING:
		if away == AfternoonAway.AWAY_DORM:
			away_lbl.text = Loc.t(L.SEASON_WEEK_MAP_DORM)
			away_chip.visible = true
		elif away == AfternoonAway.AWAY_SELF_OUTING:
			away_lbl.text = Loc.t(L.SEASON_WEEK_MAP_SELF_OUTING)
			away_chip.visible = true
	var hit: Button = token.get_node("%Hit")
	var can: bool = _can_pick(stage, pid)
	hit.disabled = not can
	if can:
		hit.pressed.connect(_on_map_pilot_picked.bind(pid))
	var dim: bool = _token_dimmed(stage, pid)
	(token.get_node("%Mask") as Control).visible = dim
	for g in [stress_g, trust_g, awaken_g]:
		(g as PilotGauge).set_dimmed(dim)
	if picked:
		token.pivot_offset = token.size * 0.5
		token.scale = Vector2.ONE * MAP_PICKED_SCALE
		token.z_index = 1
	return token


## The token of `pid` is the picked one: the morning talk's pick (until the talk is used) or
## the pilot whose afternoon visit is open (menu / courses / result).
func _token_picked(stage: int, pid: int) -> bool:
	var s: Dictionary = _gm.season_state
	if stage == Stage.TALK:
		return pid == _sel_pid and MentalSystem.can_talk(s, _day, pid)
	if stage == Stage.AFTERNOON:
		return pid >= 0 and pid == MentalSystem.visit_open(s, _day)
	return false


## Black mask over a token: in the talk / afternoon / evening stages every pilot that cannot
## be picked, except the one whose meeting is under way — so once the morning talk or the
## afternoon visit is used, and all evening, every token is dark.
func _token_dimmed(stage: int, pid: int) -> bool:
	var s: Dictionary = _gm.season_state
	if stage == Stage.TALK:
		if MentalSystem.talk_done(s, _day):
			return true
		return not MentalSystem.can_talk(s, _day, pid) and not _in_talk(pid)
	if stage == Stage.AFTERNOON:
		if MentalSystem.evening_done(s, _day):
			return true
		var e: Dictionary = MentalSystem.evening(s, _day)
		if not e.is_empty() and int(e.get("pilot_id", -1)) == pid:
			return false
		return not AfternoonAway.can_request(s, _day, pid)
	return stage == Stage.EVENING


## `pid` may be picked on the map in `stage` (morning talk / afternoon action).
func _can_pick(stage: int, pid: int) -> bool:
	if pid < 0:
		return false
	if stage == Stage.TALK:
		return MentalSystem.can_talk(_gm.season_state, _day, pid)
	if stage == Stage.AFTERNOON:
		return AfternoonAway.can_request(_gm.season_state, _day, pid)
	return false


## `pid` took part in this morning's talk (the met pilot or the joint-training partner).
func _in_talk(pid: int) -> bool:
	var t: Dictionary = MentalSystem.talk(_gm.season_state, _day)
	return int(t.get("pilot_id", -1)) == pid or int(t.get("partner_id", -1)) == pid


# ── 훈련 결과 연출 (RESULT) ──────────────────────────────────────────────────
## The day's results rise out of each portrait's top and fade, one line after another
## (stat ups by full name, else the EXP earned · stress change · quirk events).
## When the last line is gone the afternoon starts by itself (`_finish_result_fx`).
func _play_result_fx() -> void:
	_fx_day = _day
	var last_start: float = 0.0
	var k: int = -1
	for raw in (_week_log().get(_day, []) as Array):
		var row: Dictionary = raw
		var token: Control = _tokens.get(int(row["pilot_id"]), null)
		if token == null:
			continue
		k += 1
		var lines: Array = _result_lines(row)
		var start: float = FX_PILOT_STAGGER * float(k)
		last_start = maxf(last_start, start + FX_STAGGER * float(maxi(0, lines.size() - 1)))
		var holder: Control = token.get_node("%Floats")
		var template: Label = token.get_node("%FloatLine")
		for i in lines.size():
			_add_float(holder, template, lines[i], start + FX_STAGGER * float(i))
	for c in _pilot_cards:
		(c as SeasonPilotCard).pulse_note()
	var total: float = last_start + FX_TIME + FX_TAIL
	get_tree().create_timer(total).timeout.connect(_on_result_fx_timeout.bind(_day))


## One rising line `[text, colour]`: after `delay` it fades in, rises `FX_RISE` over `FX_TIME`
## and fades out over the second half. The tween lives on the label, so a rebuilt map
## (the label freed) simply drops it.
func _add_float(holder: Control, template: Label, line: Array, delay: float) -> void:
	var lbl: Label = template.duplicate() as Label
	lbl.text = String(line[0])
	lbl.add_theme_color_override("font_color", line[1] as Color)
	lbl.modulate.a = 0.0
	lbl.visible = true
	holder.add_child(lbl)
	var y0: float = lbl.position.y
	var tw: Tween = lbl.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(lbl, "modulate:a", 1.0, FX_TIME * 0.15)
	tw.parallel().tween_property(lbl, "position:y", y0 - FX_RISE, FX_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, FX_TIME * 0.5).set_delay(FX_TIME * 0.5)


func _on_result_fx_timeout(day: int) -> void:
	if _fx_day == day and _day == day:
		_finish_result_fx()


## End of the result FX (or Next pressed during it): open the morning talk and redraw.
func _finish_result_fx() -> void:
	_fx_day = -1
	if _stage() != Stage.RESULT:
		return
	MentalSystem.begin_morning(_gm.season_state, _day)
	_save("morning_talk")
	refresh()


## Rising lines for one training row, `[[text, colour]]` in display order.
func _result_lines(row: Dictionary) -> Array:
	var out: Array = []
	var ups: Dictionary = row.get("ups", {})
	for i in STAT_KEYS.size():
		var up: int = int(ups.get(String(STAT_KEYS[i]), 0))
		if up != 0:
			out.append(["%s %+d" % [PlayerData.stat_label(i), up],
					OutgameTheme.POSITIVE if up > 0 else OutgameTheme.NEGATIVE])
	if out.is_empty():
		var total: int = 0
		for v in (row.get("exp", {}) as Dictionary).values():
			total += int(v)
		out.append([Loc.t(L.SEASON_WEEK_MAP_EXP, {"n": total}), OutgameTheme.POSITIVE])
	var stress: int = int(row.get("stress", 0))
	if stress != 0:
		out.append([Loc.t(L.SEASON_WEEK_MAP_STRESS, {"delta": "%+d" % stress}),
				OutgameTheme.NEGATIVE if stress > 0 else OutgameTheme.POSITIVE])
	out.append_array(_quirk_lines(row.get("quirk", [])))
	return out


# ── 하단 선수 카드 줄 ─────────────────────────────────────────────────────────
## The five cards above the bottom bar (every day). Note line = the day's stress change
## (`_day_stress_delta`), red when it rose, green when it fell, hidden at 0.
func _refresh_pilot_row() -> void:
	var s: Dictionary = _gm.season_state
	var by_seat: Dictionary = {}
	for raw in MentalSystem.my_pilot_ids(s):
		var pd: PlayerData = MentalEvents.pilot_of(s, int(raw))
		if pd != null:
			by_seat[GameEnums.role_seat(pd.role)] = pd
	for seat in _pilot_cards.size():
		var card: SeasonPilotCard = _pilot_cards[seat]
		var role: int = int(GameEnums.ROLE_DISPLAY_ORDER[seat])
		if not by_seat.has(seat):
			card.show_empty(role)
			continue
		var pd2: PlayerData = by_seat[seat]
		card.show_pilot(pd2.id, role, MentalSystem.trust(s, pd2.id), StressSystem.value(s, pd2.id))
		var delta: int = _day_stress_delta(pd2.id)
		if delta != 0:
			card.set_note("%+d" % delta, &"NegativeLabel" if delta > 0 else &"PositiveLabel")


## Stress change of `pid` on the shown weekday so far: the morning training (row key `stress`),
## a self outing (`AfternoonAway.relief_of`) and the `stress` notes of the day's incident and
## afternoon action outcomes.
func _day_stress_delta(pid: int) -> int:
	if not CalendarSystem.is_week_day(_day):
		return 0
	var s: Dictionary = _gm.season_state
	var total: int = 0
	for raw in (_week_log().get(_day, []) as Array):
		if int((raw as Dictionary)["pilot_id"]) == pid:
			total += int((raw as Dictionary).get("stress", 0))
	total += AfternoonAway.relief_of(s, _day, pid)
	var rec: Dictionary = MentalSystem.day_record(s, _day)
	for k in ["talk", "incident", "evening"]:
		var outcome: Dictionary = (rec.get(k, {}) as Dictionary).get("outcome", {})
		for n_raw in (outcome.get("notes", []) as Array):
			var n: Dictionary = n_raw
			if String(n.get("type", "")) == "stress" and int(n.get("pid", -1)) == pid:
				total += int(n.get("delta", 0))
	return total


func _on_pilot_card_pressed(pid: int) -> void:
	if _busy():
		return
	SeasonPilotDetail.open(self, pid)


## Map tap. Morning talk: pick the pilot (the talk card asks). Afternoon: visit the tapped
## pilot straight away (tokens never overlap, so there is no "who?" picker).
func _on_map_pilot_picked(pid: int) -> void:
	if _busy():
		return
	if _stage() == Stage.AFTERNOON:
		_start_visit(pid)
		return
	_sel_pid = pid
	_sel_day = _day
	_sel_stage = _stage()
	_rebuild_list()


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
	# Hint under my card: Saturday = today's prep, Sunday = straight to the match when the
	# picks are stored (else the full PREP → ban/pick flow), afterwards = over.
	var hint_key: String = L.SEASON_WEEK_HINT_DONE
	if is_player and not played:
		hint_key = L.SEASON_WEEK_HINT_START
		if _day == CalendarSystem.PREP_DAY:
			hint_key = L.SEASON_WEEK_HINT_PREP
		elif _hub != null and _hub.match_picks_ready():
			hint_key = L.SEASON_WEEK_HINT_MATCH_READY
	return {
		"player": is_player, "tag": tag, "title": title, "status": status, "result": result,
		"hint": Loc.t(hint_key),  # l10n-dynamic: season.week.hint_*
	}


static func _team_name(namer: Node, team_id: int) -> String:
	if namer != null and namer.has_method("team_name"):
		return String(namer.call("team_name", team_id))
	return "Team %d" % team_id


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


# ── 아래 바 ──────────────────────────────────────────────────────────────────
func _refresh_action_button() -> void:
	if _action_btn == null:
		return
	var stage: int = _stage()
	_stage_btn.visible = stage != Stage.OFF
	var stage_key: String = L.SEASON_WEEK_STAGE_MORNING
	if stage == Stage.AFTERNOON or stage == Stage.PRESS:
		stage_key = L.SEASON_WEEK_STAGE_AFTERNOON
	elif stage == Stage.EVENING:
		stage_key = L.SEASON_WEEK_STAGE_EVENING
	_stage_btn.text = Loc.t(stage_key)  # l10n-dynamic: season.week.stage.*
	if stage == Stage.STADIUM:
		# 하단 바의 칸이라 **바 변형끼리만 갈아입는다** — `DarkButton` 이면 모서리가
		# 도로 둥글어져 이 칸만 화면에서 떠오른다. 갈아입은 뒤 인셋 몫을 다시 얹는다.
		_action_btn.text = Loc.t(L.SEASON_WEEK_BTN_MATCH_PREP if _day == CalendarSystem.PREP_DAY
				else L.SEASON_WEEK_BTN_START_MATCH)
		_set_action_kind(&"BarDarkButton")
		return
	if stage == Stage.PRESS:
		_action_btn.text = Loc.t(L.TERM_ACTIVITY_PRESS)
	elif _day >= CalendarSystem.DAYS_PER_WEEK - 1 and (stage == Stage.EVENING or stage == Stage.OFF):
		_action_btn.text = Loc.t(L.SEASON_WEEK_BTN_END_WEEK)
	elif stage != Stage.OFF:
		_action_btn.text = Loc.t(L.UI_BUTTON_NEXT)
	else:
		_action_btn.text = Loc.t(L.UI_BUTTON_CONFIRM)
	_set_action_kind(&"BarPrimaryButton")


func _set_action_kind(variation: StringName) -> void:
	_action_btn.theme_type_variation = variation
	OutgameTheme.fit_bar_button(_action_btn)


func _on_action_pressed() -> void:
	if _busy() or (_skip_popup != null and _skip_popup.is_open()):
		return
	match _stage():
		Stage.STADIUM:
			if _hub == null:
				return
			if _day == CalendarSystem.PREP_DAY:
				_hub.on_week_day_match_prep()
			else:
				_hub.on_week_day_match_start()
			return
		Stage.PRESS:
			if _hub != null:
				_hub.open_press()
			return
		Stage.MORNING:
			_settle_day()
			refresh()
			return
		Stage.RESULT:
			# Skip the rest of the result FX.
			_finish_result_fx()
			return
		Stage.TALK:
			# Moving on while a morning talk is still possible asks first.
			if _any_talk():
				_open_skip_popup(Stage.TALK)
				return
			_begin_afternoon()
			refresh()
			return
		Stage.AFTERNOON:
			# Moving on while an interview / outing is still possible asks first.
			if not MentalSystem.evening_done(_gm.season_state, _day) \
					and AfternoonAway.any_request(_gm.season_state, _day):
				_open_skip_popup(Stage.AFTERNOON)
				return
			_begin_evening()
			return
	_leave_day()


## Some pilot can still be met this morning (the skip warning).
func _any_talk() -> bool:
	for pid in MentalSystem.my_pilot_ids(_gm.season_state):
		if MentalSystem.can_talk(_gm.season_state, _day, int(pid)):
			return true
	return false


## Off to the next day (or the match). An unused afternoon is recorded as a pass.
func _leave_day() -> void:
	if _hub == null:
		return
	if _hub.has_player_match_on_day(_day):
		_hub.on_week_day_match_start()
		return
	if CalendarSystem.is_week_day(_day) and AfternoonAway.started(_gm.season_state, _day) \
			and not MentalSystem.evening_done(_gm.season_state, _day):
		MentalSystem.begin_evening(_gm.season_state, _day, MentalSystem.ACTION_PASS, -1)
	_hub.on_week_day_confirmed()


## Skip warning for the morning talk (`Stage.TALK`) or the afternoon (`Stage.AFTERNOON`).
func _open_skip_popup(stage: int) -> void:
	if _skip_popup == null:
		_skip_popup = ConfirmPopup.create()
		add_child(_skip_popup)
		_skip_popup.confirmed.connect(_on_skip_confirmed)
	if stage == Stage.TALK:
		_skip_popup.open(Loc.t(L.SEASON_WEEK_SKIP_TALK_TITLE), Loc.t(L.SEASON_WEEK_SKIP_TALK_BODY),
				Loc.t(L.UI_BUTTON_CANCEL), Loc.t(L.SEASON_WEEK_SKIP_CONFIRM))
	else:
		_skip_popup.open(Loc.t(L.SEASON_WEEK_SKIP_TITLE), Loc.t(L.SEASON_WEEK_SKIP_BODY),
				Loc.t(L.UI_BUTTON_CANCEL), Loc.t(L.SEASON_WEEK_SKIP_CONFIRM))


func _on_skip_confirmed() -> void:
	match _stage():
		Stage.TALK:
			_begin_afternoon()
			refresh()
		Stage.AFTERNOON:
			_begin_evening()


# ── 오후 · 사건 (M7) ──────────────────────────────────────────────────────────
# One afternoon action per Mon–Fri: interview / outing (or pass by moving on). The
# map picks a pilot, the afternoon card picks the action; the dialog itself is an
# overlay. State, the trust gate and idempotency live in `MentalSystem` (the record keeps
# its old name `evening`) — this screen only draws records and forwards taps.

## The afternoon dialog was started but not answered (e.g. the game was reloaded).
func _evening_open() -> bool:
	if not CalendarSystem.is_week_day(_day):
		return false
	var e: Dictionary = MentalSystem.evening(_gm.season_state, _day)
	return not e.is_empty() and String(e.get("action", "")) != MentalSystem.ACTION_PASS \
			and int(e.get("choice", -1)) < 0


func _add_afternoon_card() -> void:
	var s: Dictionary = _gm.season_state
	if MentalSystem.evening_done(s, _day):
		_add_afternoon_done_card(MentalSystem.evening(s, _day))
		return

	# Before the visit: how to visit (tap a pilot on the map → `VisitMenu`) and the week's
	# coach points (focus training spends them).
	var card: Control = _add_item(AFTERNOON_CARD_SCENE)
	(card.get_node("%Hint") as Label).text = Loc.t(L.SEASON_WEEK_AFTERNOON_PICK
			if AfternoonAway.any_request(s, _day) else L.SEASON_WEEK_AFTERNOON_NONE)
	(card.get_node("%Coach") as Label).text = Loc.t(L.SEASON_WEEK_AFTERNOON_COACH,
			{"n": StaffSystem.coach_points(s), "max": StaffSystem.coach_points_grant(s)})


func _add_afternoon_done_card(e: Dictionary) -> void:
	var s: Dictionary = _gm.season_state
	var action: String = String(e.get("action", MentalSystem.ACTION_PASS))
	var pid: int = int(e.get("pilot_id", -1))
	var card: Control = _add_item(AFTERNOON_DONE_SCENE)
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
	var head: String = Loc.t(L.SEASON_WEEK_AFTERNOON_RESTED)
	var who: String = MentalEvents.pilot_name(s, pid)
	if action == MentalSystem.ACTION_INTERVIEW:
		head = Loc.t(L.SEASON_WEEK_AFTERNOON_INTERVIEW, {"name": who})
	elif action == MentalSystem.ACTION_STORY:
		head = Loc.t(L.SEASON_WEEK_AFTERNOON_STORY, {"name": who})
	elif action == MentalSystem.ACTION_FOCUS:
		head = Loc.t(L.SEASON_WEEK_AFTERNOON_FOCUS, {"name": who,
				"course": FocusTraining.course_name(String(e.get("course", "")))})
	elif action == MentalSystem.ACTION_OUTING:
		head = Loc.t(L.SEASON_WEEK_AFTERNOON_OUTING, {"name": who})
	head_lbl.text = head
	var notes: Array = MentalEvents.note_texts(s, (e.get("outcome", {}) as Dictionary).get("notes", []))
	line_lbl.text = " · ".join(PackedStringArray(notes)) if not notes.is_empty() \
			else Loc.t(L.SEASON_WEEK_RESTED_LINE if action == MentalSystem.ACTION_PASS else L.SEASON_WEEK_NO_CHANGE)


# ── 오전 만남 (훈련 소감) ─────────────────────────────────────────────────────
## The morning talk was started but not answered (e.g. the game was reloaded).
func _talk_open() -> bool:
	if not CalendarSystem.is_training_day(_day):
		return false
	var t: Dictionary = MentalSystem.talk(_gm.season_state, _day)
	return String(t.get("action", "")) == MentalSystem.ACTION_TALK and int(t.get("choice", -1)) < 0


func _add_talk_card() -> void:
	var s: Dictionary = _gm.season_state
	var t: Dictionary = MentalSystem.talk(s, _day)
	if MentalSystem.talk_done(s, _day):
		_add_talk_done_card(t)
		return
	var card: Control = _add_item(TALK_CARD_SCENE)
	var picked: bool = _sel_day == _day and _sel_pid >= 0
	var pilot: Control = card.get_node("%Pilot")
	var hint: Label = card.get_node("%Hint")
	pilot.visible = picked
	hint.visible = not picked
	hint.text = Loc.t(L.SEASON_WEEK_TALK_PICK if _any_talk() else L.SEASON_WEEK_TALK_NONE)
	if picked:
		OutgameTheme.add_round_portrait(card.get_node("%Portrait"), PilotImages.circle_for(_sel_pid),
				Vector2.ZERO, EVE_PORTRAIT_D, OutgameTheme.ACCENT)
		(card.get_node("%Name") as Label).text = MentalEvents.pilot_name(s, _sel_pid)
		var with_lbl: Label = card.get_node("%With")
		var partner: int = MentalSystem.talk_partner(s, _day, _sel_pid)
		if partner >= 0:
			with_lbl.text = Loc.t(L.SEASON_WEEK_TALK_WITH, {"name": MentalEvents.pilot_name(s, partner)})
			with_lbl.theme_type_variation = &"AccentLabel"
		else:
			with_lbl.text = Loc.t(L.SEASON_WEEK_TALK_SOLO, {"trust": MentalSystem.trust_level(s, _sel_pid)})
	var btn: Button = card.get_node("%Talk")
	btn.disabled = not picked
	btn.pressed.connect(_on_talk_pressed)


func _add_talk_done_card(t: Dictionary) -> void:
	var s: Dictionary = _gm.season_state
	var pid: int = int(t.get("pilot_id", -1))
	var partner: int = int(t.get("partner_id", -1))
	var card: Control = _add_item(AFTERNOON_DONE_SCENE)
	OutgameTheme.add_round_portrait(card.get_node("%Portrait"), PilotImages.circle_for(pid),
			Vector2.ZERO, EVE_PORTRAIT_D)
	var head: String = Loc.t(L.SEASON_WEEK_TALK_DONE, {"name": MentalEvents.pilot_name(s, pid)})
	if partner >= 0:
		head = Loc.t(L.SEASON_WEEK_TALK_DONE_PAIR, {"name": MentalEvents.pilot_name(s, pid),
				"name2": MentalEvents.pilot_name(s, partner)})
	(card.get_node("%Head") as Label).text = head
	var notes: Array = MentalEvents.note_texts(s, (t.get("outcome", {}) as Dictionary).get("notes", []))
	(card.get_node("%Line") as Label).text = " · ".join(PackedStringArray(notes)) if not notes.is_empty() \
			else Loc.t(L.SEASON_WEEK_NO_CHANGE)


func _on_talk_pressed() -> void:
	if _busy() or _sel_pid < 0:
		return
	var session: Dictionary = MentalSystem.begin_talk(_gm.season_state, _day, _sel_pid)
	if session.is_empty():
		_rebuild_list()
		return
	_save("talk_open")
	_open_talk_session(session)


func _open_talk_session(session: Dictionary) -> void:
	if _busy() or session.is_empty():
		return
	var s: Dictionary = _gm.season_state
	var view: Dictionary = MentalSystem.session_view(s, session)
	if view.is_empty():
		return
	var pid: int = int(view["pilot_id"])
	_open_overlay("talk", Loc.t(L.SEASON_WEEK_SUB_TALK, {"day": OutgameTheme.day_name(_day)}),
			MentalEvents.pilot_name(s, pid), pid, view)


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


# ── Afternoon visit (방문, §15 D) ─────────────────────────────────────────────
# Tap a pilot → the visit is recorded (`MentalSystem.begin_visit`, saved) → `VisitMenu`, a
# speech bubble over that pilot's (scaled-up) token: 집중 훈련 (courses → result) /
# 이야기 (story dialogue) / 외출 (outing dialogue). A reload with the menu open reopens it.

func _make_visit_menu() -> VisitMenu:
	var menu := VisitMenu.create()
	add_child(menu)
	menu.option_picked.connect(_on_visit_option)
	menu.course_picked.connect(_on_visit_course)
	menu.closed.connect(_on_visit_closed)
	return menu


## Record the visit (the afternoon's one action) and open the menu.
func _start_visit(pid: int) -> void:
	if not MentalSystem.begin_visit(_gm.season_state, _day, pid):
		_close_visit_menu()
		refresh()
		return
	_save("visit")
	_rebuild_list()
	_open_visit_menu(pid)


## Opens (or refills) the menu bubble for `pid`, pointing at that pilot's map token.
func _open_visit_menu(pid: int) -> void:
	if _visit_menu == null:
		if _busy():
			return
		_visit_menu = _make_visit_menu()
	var token: Control = _tokens.get(pid, null)
	if token != null:
		_visit_menu.point_at(token.get_node("%Portrait"), token)
	_visit_menu.open_menu(_gm.season_state, pid, _day)


func _close_visit_menu() -> void:
	if _visit_menu != null:
		_visit_menu.queue_free()
		_visit_menu = null


func _on_visit_option(option: String) -> void:
	var s: Dictionary = _gm.season_state
	var pid: int = MentalSystem.visit_open(s, _day)
	if pid < 0:
		return
	if option == VisitMenu.OPTION_FOCUS:
		if _visit_menu != null:
			_visit_menu.show_courses(s)
		return
	var action: String = MentalSystem.ACTION_OUTING if option == VisitMenu.OPTION_OUTING \
			else MentalSystem.ACTION_STORY
	var session: Dictionary = MentalSystem.begin_evening(s, _day, action, pid)
	if session.is_empty():
		return
	_close_visit_menu()
	_save("afternoon_open")
	_open_evening_session(session)


func _on_visit_course(id: String) -> void:
	var s: Dictionary = _gm.season_state
	var out: Dictionary = MentalSystem.finish_focus(s, _day, id)
	if out.is_empty():
		if _visit_menu != null:
			_visit_menu.show_courses(s)
		return
	_save("focus")
	if _visit_menu != null:
		_visit_menu.show_result(s, MentalEvents.note_texts(s, out.get("notes", [])))


## The focus result confirmed.
func _on_visit_closed() -> void:
	_close_visit_menu()
	refresh()


func _open_evening_session(session: Dictionary) -> void:
	if _busy() or session.is_empty():
		return
	var s: Dictionary = _gm.season_state
	var view: Dictionary = MentalSystem.session_view(s, session)
	if view.is_empty():
		return
	var pid: int = int(view["pilot_id"])
	var sub: String = Loc.t(L.SEASON_WEEK_SUB_INTERVIEW_PM, {"day": OutgameTheme.day_name(_day)})
	if String(MentalSystem.evening(s, _day).get("action", "")) == MentalSystem.ACTION_STORY:
		sub = Loc.t(L.SEASON_WEEK_SUB_STORY_PM, {"day": OutgameTheme.day_name(_day)})
	if String(view["kind"]) == MentalEvents.KIND_OUTING:
		sub = Loc.t(L.SEASON_WEEK_SUB_OUTING_PM, {"day": OutgameTheme.day_name(_day),
				"n": MentalSystem.outings(s, pid) + 1})
	_open_overlay("evening", sub, MentalEvents.pilot_name(s, pid), pid, view)


func _open_incident() -> void:
	if _busy() or not MentalSystem.incident_pending(_gm.season_state, _day):
		return
	var s: Dictionary = _gm.season_state
	var view: Dictionary = MentalSystem.session_view(s, MentalSystem.incident_session(s, _day))
	if view.is_empty():
		return
	var pid: int = int(view["pilot_id"])
	_open_overlay("incident", Loc.t(L.SEASON_WEEK_SUB_INCIDENT, {"day": OutgameTheme.day_name(_day),
			"name": MentalEvents.pilot_name(s, pid)}), String(view["tag"]), pid, view,
			MentalEvents.pilot_name(s, pid))


func _open_overlay(kind: String, sub: String, title: String, pid: int, view: Dictionary,
		speaker: String = "") -> void:
	_overlay_kind = kind
	_overlay_pid = pid
	# Interviews / outings / incidents = visual-novel dialogue (`mental/VnDialogueView`).
	var vn := VnDialogueView.create()
	_overlay = vn
	add_child(vn)
	vn.choice_picked.connect(_on_overlay_choice)
	vn.closed.connect(_on_overlay_closed)
	var partner: int = int(view.get("partner_id", -1))
	vn.open(sub, title, pid, view["lines"], view["choices"], speaker, view.get("previews", []),
			partner, MentalEvents.pilot_name(_gm.season_state, partner) if partner >= 0 else "")


func _on_overlay_choice(idx: int) -> void:
	var s: Dictionary = _gm.season_state
	if _overlay_kind == "limit_break":
		# `choose_goal` returns the outcome **view** (display text) itself.
		var lb_view: Dictionary = LimitBreak.choose_goal(s, _overlay_pid, idx)
		_save("limit_break")
		if _overlay != null:
			_overlay.show_result(lb_view)
		return
	var out: Dictionary
	if _overlay_kind == "incident":
		out = MentalSystem.resolve_incident(s, _day, idx)
	elif _overlay_kind == "talk":
		out = MentalSystem.finish_talk(s, _day, idx)
	else:
		out = MentalSystem.finish_evening(s, _day, idx)
	_save("choice")
	if _overlay != null:
		_overlay.show_result(MentalEvents.outcome_view(s, out))


func _on_overlay_closed() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_overlay_kind = ""
	_overlay_pid = -1
	refresh()


# ── Limit break (한계돌파, §15 B) — evening, before the incident ──────────────
## The limit-break dialogue of `pid` in the shared `VnDialogueView` (kind `limit_break`):
## `LimitBreak.session` is a `session_view`-shaped dict; the answer goes to `choose_goal`.
func _open_limit_break(pid: int) -> void:
	if _busy():
		return
	var view: Dictionary = LimitBreak.session(_gm.season_state, pid)
	if view.is_empty() or (view.get("choices", []) as Array).is_empty():
		return
	view["lines"] = view.get("lines", [])
	_open_overlay("limit_break", Loc.t(L.SEASON_WEEK_SUB_LIMIT_BREAK, {"day": OutgameTheme.day_name(_day)}),
			MentalEvents.pilot_name(_gm.season_state, pid), pid, view)


# ── Awakening (깨달음, §15 C) ─────────────────────────────────────────────────
## A queued awakening opens right here (`Awakening.next_pending`): C's `AwakeningView`
## (`create()` · `open(pid)` · `closed`), looked up by class name so this screen also runs in
## a tree without it. Its close redraws, which polls again (several queued pilots in turn).
## Not while the morning result FX plays (it opens when the FX ends). True when opened.
func _open_awakening() -> bool:
	if _busy() or _fx_day == _day:
		return false
	var pid: int = Awakening.next_pending(_gm.season_state)
	if pid < 0:
		return false
	var script: Script = _awakening_view_script()
	if script == null:
		return false
	var view: Variant = script.call("create")
	if not (view is Node):
		return false
	_awaken_view = view
	add_child(_awaken_view)
	_awaken_view.connect("closed", _on_awakening_closed, CONNECT_ONE_SHOT)
	_awaken_view.call("open", pid)
	return true


static func _awakening_view_script() -> Script:
	for c in ProjectSettings.get_global_class_list():
		if String((c as Dictionary).get("class", "")) == "AwakeningView":
			return load(String((c as Dictionary)["path"])) as Script
	return null


func _on_awakening_closed() -> void:
	if _awaken_view != null and is_instance_valid(_awaken_view) and not _awaken_view.is_queued_for_deletion():
		_awaken_view.queue_free()
	_awaken_view = null
	_save("awakening")
	refresh()


## F6 단독 실행 미리보기 — 메모리 런의 **수요일 오후**(`resources/UiPreview.gd`). 미리보기 전용
## `TrainingBoard`(`PreviewBoard`)에 코치 추천 판을 깔고 월~수를 정산한 뒤 수요일 오후를 연다
## (호스트가 없으면 `_board()` 가 이 판을 쓴다). 그날 사건이 나면 첫 답으로 풀어 두고,
## Tapping a pilot opens the visit popup (live, in memory) — no overlay covers the map at start.
## "다음"은 호스트(`SeasonHub`)가 없어 날을 넘기지 않는다.
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
	_day = day
	MentalSystem.begin_morning(s, day)
	_begin_afternoon()
