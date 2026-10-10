class_name WeekProgressView
extends Control

# ── 시간 경과 화면 (월 → 일) ─────────────────────────────────────────────────
#
# **맨 위에 가로 요일 레일**(왼쪽 → 오른쪽으로 월 … 일), 그 아래 머리글과
# 그날의 카드 목록.
#
#   ┌──────────────────────────────────────┐
#   │  15  16 [DAY 17] 18  19  20  21        │  ← 요일 레일: 칸마다 페이즈 안의 날 수
#   │  MON TUE   WED   THU FRI SAT SUN       │    (CalendarSystem.day_in_phase) · 요일 영문 약칭
#   └──────────────────────────────────────┘
#                  프리시즌                    ← 페이즈 이름 (가운데)
#           오전     오후     저녁             ← time row: previous · NOW · next (%TimeRow)
#     [ 사건 · 오후 카드 ]                     ← 세로 스크롤 (%Scroll, 맵 위)
#   [ 팀 부지 맵 + 선수 토큰 (1200 폭, 좌우 60 잘림) ] ← 화면 높이 가운데 (%MapPin)
#     [선수][선수][선수][선수][선수]           ← 항상, 맵 바로 아래 (%PilotRow, 스트레스 링에 오늘 증감)
#    [ 오전 / 오후 ][        다음        ]    ← 하단 바
#
# 레일의 **지금 요일 한 칸만 앰버 알약(%DayHighlight)이 깔린다** — 지나온 날은 흰 글자,
# 남은 날은 흐린 글자다. 날이 바뀌면 알약이 미끄러져 온다.
# A finished half moves on by itself through black (`_next_auto`, `WeekFade`); "다음" skips.
#
# ── 훈련일 (월~금) = 오전 → 오후 → 저녁 ───────────────────────────────────────
# 훈련일은 다섯 단계(`_stage`)로 흐르고, 단계는 **기록에서 읽는다** (따로 저장하지 않는다):
#   MORNING   `week_day_log` 에 그날이 없다. 맵에서 선수가 그날 훈련 시설 자리에 서 있고,
#             초상화 위 말풍선이 그 시간의 훈련 이름을 말한다.
#             "다음" = `TrainingBoard.apply_day_training` 으로 정산 → 결과를 `week_day_log[day]` 에.
#   RESULT    정산됐고 오전 만남이 아직 열리지 않았다. 그날 결과(능력치 · 스트레스 · 숙련 · 기벽)가
#             초상화 위에서 떠올라 흐려진다(`_play_result_fx`). 연출이 끝나면 스스로
#             `MentalSystem.begin_morning` → 오전 만남. "다음" = 연출을 건너뛴다.
#   TALK      오전 만남(훈련 소감): 선수 하나를 누르면 그 위에 말풍선(`VisitMenu.open_talk`) →
#             만남 → 대화 (그 선수만). 끝나면 스스로 오후로. "다음" = 오후 (`AfternoonAway.begin`;
#             아직 만날 수 있으면 경고 팝업).
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
# 맵 아래 선수 카드 줄 `%PilotRow` · 스크롤 · 하단 바). 맵(`WeekMapSection`(+ `BaseMap` ·
# `WeekMapPilot`))은 고정된 `%MapPin` 에, 목록의 카드는 아이템 씬(`WeekMatchCard` ·
# `WeekNoteCard` · `WeekIncidentCard` · `WeekAfternoonCard` · `WeekAfternoonDoneCard`)을 `%List` 에 붙인다.
# 이 스크립트는 `%` 노드에 데이터를 넣고, 데이터에 따라 바뀌는 색(역할 띠 · 오늘 칩 ·
# 내 경기 카드 · 상승/하락 · 오후에 못 부르는 선수의 흐림)과 기기 인셋만 코드로 넣는다.
# 생성은 `create()`.

const SCENE_PATH: String = "res://features/season/week/UI_View_WeekProgressView.tscn"
const MATCH_CARD_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekMatchCard.tscn")
const NOTE_CARD_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekNoteCard.tscn")
const AFTERNOON_CARD_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekAfternoonCard.tscn")
const AFTERNOON_DONE_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekAfternoonDoneCard.tscn")
const INCIDENT_CARD_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekIncidentCard.tscn")
const MAP_SECTION_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekMapSection.tscn")
const MAP_PILOT_SCENE: PackedScene = preload("res://features/season/week/UI_Comp_WeekMapPilot.tscn")

const STAT_KEYS: Array   = PlayerData.STAT_KEYS

## Weekday (Mon 0 … Sun 6) → English abbreviation key (header, under DAY N).
const DAY_ABBR: Array = [  # l10n-keys: term.day.abbr.*
	L.TERM_DAY_ABBR_MON, L.TERM_DAY_ABBR_TUE, L.TERM_DAY_ABBR_WED, L.TERM_DAY_ABBR_THU,
	L.TERM_DAY_ABBR_FRI, L.TERM_DAY_ABBR_SAT, L.TERM_DAY_ABBR_SUN,
]

## Day stage, read from the records (`_stage`). STADIUM / PRESS are weekend-only.
enum Stage { OFF, MORNING, RESULT, TALK, AFTERNOON, EVENING, STADIUM, PRESS }

# ── 데이터에 따라 바뀌는 치수 (나머지 배치는 씬) ──
const MATCH_CARD_H: float = 168.0    # the player's match card (others: OTHER_MATCH_H)
const OTHER_MATCH_H: float = 96.0
const EVE_PORTRAIT_D: float = 84.0
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
## around its centre. A token that cannot be picked gets the black mask instead
## (`_token_dimmed`; `%Mask`).
const MAP_PICKED_SCALE: float = 1.2
## Map time-of-day change between two stages of a day (sun + pilots walking), and from one
## day's evening to the next morning (through the night; the pilots walk in its second
## half, `NIGHT_WALK_DELAY`).
const STAGE_TIME: float = 1.4
const NIGHT_TIME: float = 2.8
const NIGHT_WALK_DELAY: float = 0.45
## Rail: the amber pill slides from the last shown weekday to today over `RAIL_SLIDE`; the
## "DAY" tag of today grows in (width + alpha) meanwhile, the old one fades over `TAG_FADE`.
const RAIL_SLIDE: float = 0.45
const TAG_FADE: float = 0.25
## Time row (`%TimePrev` · `%TimeNow` · `%TimeNext`): slot spacing (matches the scene's
## authored offsets), the small sides' scale and alpha, and the shift time.
const TIME_SLOT_DX: float = 300.0
const TIME_SIDE_SCALE: float = 0.55
const TIME_SIDE_ALPHA: float = 0.45
const TIME_SHIFT: float = 0.5
## Half of the day → its label key (오전 · 오후 · 저녁), see `_stage_half`.
const HALF_KEYS: Array = [  # l10n-keys: season.week.stage.*
	L.SEASON_WEEK_STAGE_MORNING, L.SEASON_WEEK_STAGE_AFTERNOON, L.SEASON_WEEK_STAGE_EVENING,
]
## What the day moves on to by itself once its half is done (`_next_auto`).
enum Auto { NONE, AFTERNOON, EVENING, NEXT_DAY }

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

@onready var _phase_lbl: Label = %Phase
@onready var _list_scroll: ScrollContainer = %Scroll
@onready var _list_body: VBoxContainer = %List
@onready var _list_end: Control = %ListEnd
@onready var _map_pin: Control = %MapPin
@onready var _pilot_row: Control = %PilotRow
@onready var _day_highlight: Control = %DayHighlight
@onready var _time_row: Control = %TimeRow
@onready var _time_prev: Label = %TimePrev
@onready var _time_now: Label = %TimeNow
@onready var _time_next: Label = %TimeNext
@onready var _stage_btn: Button = %FloatingBarButton_Stage
@onready var _action_btn: Button = %FloatingBarButton_Action

var _built: bool = false
var _day: int = 0

var _chip_panels: Array = []       # 7 Panel (scene: %Days/Day*/Chip)
var _chip_nums: Array = []         # 7 Label (… /Chip/Box/NumRow/Num): day inside the phase
var _chip_tags: Array = []         # 7 Label (… /Chip/Box/NumRow/DayTag): "DAY", today only
var _chip_abbrs: Array = []        # 7 Label (… /Chip/Box/Abbr): MON … SUN

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
var _map: BaseMap = null              # map of the current list build (null = none)
var _rail_tween: Tween = null         # highlight slide + chip text colours
var _time_tween: Tween = null         # time row shift
var _time_ghost: Label = null         # incoming "next" label during the time row shift
## The last drawn map, across rebuilds and screens (the view is re-made per day):
## `{scene, day, stage, hour, tokens}` — the next draw animates from it (`_animate_map`).
static var _map_memory: Dictionary = {}
## The rail's last shown `{week, day}` (the highlight slides from it) and the time row's
## last `{day, half}` (it shifts on from it) — static for the same reason.
static var _rail_memory: Dictionary = {}
static var _half_memory: Dictionary = {}


## Instantiates the scene. `WeekProgressView.new()` is an empty Control — don't use it.
## Load (not preload) — preloading its own scene is a script ↔ scene cycle.
static func create() -> WeekProgressView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as WeekProgressView


func _ready() -> void:
	for slot in (%Days as Control).get_children():
		var chip: Panel = slot.get_node_or_null("Chip") as Panel
		var num: Label = slot.get_node_or_null("Chip/Box/NumRow/Num") as Label
		var tag: Label = slot.get_node_or_null("Chip/Box/NumRow/DayTag") as Label
		var abbr: Label = slot.get_node_or_null("Chip/Box/Abbr") as Label
		if chip != null and num != null and tag != null and abbr != null:
			_chip_panels.append(chip)
			_chip_nums.append(num)
			_chip_tags.append(tag)
			_chip_abbrs.append(abbr)
	_action_btn.pressed.connect(_on_action_pressed)
	_pilot_cards = _pilot_row.get_children()
	for c in _pilot_cards:
		(c as SeasonPilotCard).set_week_layout()
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
	_refresh_time_row()
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
	elif _next_auto() != Auto.NONE:
		WeekFade.through(_run_auto)


## What the day moves on to by itself now that its half is done — nothing while anything is
## still open or queued (a dialog, the visit popup, the result FX, an awakening, the limit-break
## event, an incident): the morning talk answered → afternoon; the visit settled → evening; the
## evening's events settled → next day (not the Sunday — "주 마감 →" stays a button, and not
## without the hub (F6 preview), which cannot move the day).
func _next_auto() -> int:
	if _busy() or _fx_day == _day:
		return Auto.NONE
	var s: Dictionary = _gm.season_state
	if Awakening.next_pending(s) >= 0:
		return Auto.NONE
	match _stage():
		Stage.TALK:
			if MentalSystem.talk_done(s, _day):
				return Auto.AFTERNOON
		Stage.AFTERNOON:
			if MentalSystem.evening_done(s, _day) and MentalSystem.visit_open(s, _day) < 0 \
					and not _evening_open():
				return Auto.EVENING
		Stage.EVENING:
			if _hub != null and _day < CalendarSystem.DAYS_PER_WEEK - 1 \
					and not MentalSystem.incident_pending(s, _day) \
					and LimitBreak.pending_event(s, _day) < 0:
				return Auto.NEXT_DAY
	return Auto.NONE


## Moves the day on (`_next_auto`), else just redraws. Runs while the screen is black.
func _run_auto() -> void:
	match _next_auto():
		Auto.AFTERNOON:
			_begin_afternoon()
			refresh()
		Auto.EVENING:
			_begin_evening()
		Auto.NEXT_DAY:
			_leave_day()
		_:
			refresh()


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


## Each chip = that weekday's day number inside the phase (`CalendarSystem.day_in_phase`
## counted from this week's Monday) over its abbreviation (MON … SUN); today's chip adds
## the small "DAY" tag left of the number. Today is marked by the amber pill `%DayHighlight`
## behind the (transparent) chips: on a new day of the same week (`_rail_memory`) it slides
## from the last shown weekday, the new "DAY" tag grows in from the left while fading in (the
## number moves right to make room) and the old one fades out.
func _refresh_rail() -> void:
	var s: Dictionary = _gm.season_state
	var monday: int = CalendarSystem.day_in_phase(s) - _day
	var week_id: int = int(s.get("current_phase", 0)) * 1000 + monday
	var was: Dictionary = _rail_memory
	_rail_memory = {"week": week_id, "day": _day}
	var from_day: int = int(was.get("day", -1)) if int(was.get("week", -1)) == week_id else -1
	var animate: bool = from_day >= 0 and from_day != _day
	if _rail_tween != null and _rail_tween.is_valid():
		_rail_tween.kill()
	_rail_tween = null
	var delay: float = WeekFade.clear_delay()
	for d in _chip_panels.size():
		var num: Label = _chip_nums[d]
		var abbr: Label = _chip_abbrs[d]
		var tag: Label = _chip_tags[d]
		num.text = str(monday + d)
		abbr.text = day_abbr(d)
		var col: Color = _rail_text_color(d, _day)
		if animate and (d == from_day or d == _day):
			var col_from: Color = _rail_text_color(d, from_day)
			_tween_rail_color(num, col_from, col, delay)
			_tween_rail_color(abbr, col_from, col, delay)
			if d == _day:
				_tag_in(tag, delay)
			else:
				_tag_out(tag, delay)
		else:
			num.add_theme_color_override("font_color", col)
			abbr.add_theme_color_override("font_color", col)
			_set_tag(tag, d == _day)
	_move_highlight(from_day if animate else _day, _day, delay)


## Chip text colour of weekday `d` while `today` is lit: dark on the amber pill; past days
## stay white, remaining days dim — that contrast reads "how many days left" from the rail.
static func _rail_text_color(d: int, today: int) -> Color:
	if d == today:
		return OutgameTheme.RAIL
	return OutgameTheme.TEXT_ON_FILL if d < today else OutgameTheme.RAIL_TEXT


func _tween_rail_color(lbl: Label, from: Color, to: Color, delay: float) -> void:
	lbl.add_theme_color_override("font_color", from)
	var paint: Callable = func(c: Color) -> void:
		lbl.add_theme_color_override("font_color", c)
	var tw: Tween = lbl.create_tween()
	tw.tween_interval(delay)
	tw.tween_method(paint, from, to, RAIL_SLIDE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Full width of a "DAY" tag (its translated text at its font size).
static func _tag_width(tag: Label) -> float:
	var font: Font = tag.get_theme_font("font")
	var fs: int = tag.get_theme_font_size("font_size")
	return ceilf(font.get_string_size(tag.atr(tag.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)


func _set_tag(tag: Label, on: bool) -> void:
	tag.visible = on
	tag.modulate.a = 1.0
	tag.custom_minimum_size.x = _tag_width(tag) if on else 0.0


## Today's tag grows from zero width (right-aligned and clipped: the text slides in from the
## left while the centred row pushes the number right) and fades in.
func _tag_in(tag: Label, delay: float) -> void:
	tag.visible = true
	tag.custom_minimum_size.x = 0.0
	tag.modulate.a = 0.0
	var tw: Tween = tag.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(tag, "custom_minimum_size:x", _tag_width(tag), RAIL_SLIDE) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(tag, "modulate:a", 1.0, RAIL_SLIDE)


## The old day's tag fades out, then gives its width back.
func _tag_out(tag: Label, delay: float) -> void:
	tag.visible = true
	tag.custom_minimum_size.x = _tag_width(tag)
	tag.modulate.a = 1.0
	var tw: Tween = tag.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(tag, "modulate:a", 0.0, TAG_FADE)
	tw.tween_property(tag, "custom_minimum_size:x", 0.0, RAIL_SLIDE - TAG_FADE)
	tw.tween_callback(func() -> void: tag.visible = false)


## Puts `%DayHighlight` behind chip `from_d`, then slides it to chip `to_d` (same = no slide).
## Waits a frame: the chips' positions are only known once the rail is laid out.
func _move_highlight(from_d: int, to_d: int, delay: float) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or to_d < 0 or to_d >= _chip_panels.size():
		return
	var to_x: float = _chip_x(to_d)
	if from_d == to_d or from_d < 0 or from_d >= _chip_panels.size():
		_day_highlight.position.x = to_x
		return
	_day_highlight.position.x = _chip_x(from_d)
	_rail_tween = _day_highlight.create_tween()
	_rail_tween.tween_interval(delay)
	_rail_tween.tween_property(_day_highlight, "position:x", to_x, RAIL_SLIDE) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


## x of chip `d` in the highlight's parent (the rail).
func _chip_x(d: int) -> float:
	var parent: Control = _day_highlight.get_parent() as Control
	return (_chip_panels[d] as Control).global_position.x - parent.global_position.x


func _refresh_header() -> void:
	_phase_lbl.text = GameEnums.phase_label(int(_gm.season_state["current_phase"]))


# ── Time row (오전 · 오후 · 저녁) ────────────────────────────────────────────
## Half of the day a stage belongs to: 0 오전 (morning stages, the Saturday / Sunday stadium),
## 1 오후 (afternoon, the Sunday press), 2 저녁 (evening); -1 = no stage.
static func _stage_half(stage: int) -> int:
	match stage:
		Stage.OFF:
			return -1
		Stage.AFTERNOON, Stage.PRESS:
			return 1
		Stage.EVENING:
			return 2
	return 0


## `%TimeNow` = the current half (big), `%TimePrev` = the one before (none in the morning),
## `%TimeNext` = the one after (after 저녁 the next morning), both small and faint. When the
## day moved one half on since the last draw (`_half_memory`, the next day's morning after an
## evening included) the row shifts left: the old previous slides out left and fades, the old
## current shrinks into the previous slot, the next grows into the centre and a new next fades
## in from the right.
func _refresh_time_row() -> void:
	var half: int = _stage_half(_stage())
	_time_row.visible = half >= 0
	var s: Dictionary = _gm.season_state
	var day_id: int = int(s.get("current_phase", 0)) * 1000 + CalendarSystem.day_in_phase(s)
	var was: Dictionary = _half_memory
	_half_memory = {"day": day_id, "half": half}
	if half < 0:
		return
	var old_half: int = int(was.get("half", -1))
	var old_day: int = int(was.get("day", -1))
	var forward: bool = (old_day == day_id and half == old_half + 1) \
			or (old_day >= 0 and old_day != day_id and old_half == 2 and half == 0)
	if forward:
		_shift_time_row(old_half, half)
	else:
		_set_time_row(half)


static func _half_text(half: int) -> String:
	return Loc.t(String(HALF_KEYS[posmod(half, HALF_KEYS.size())]))  # l10n-dynamic: season.week.stage.*


## The three labels on their slots for `half`, no animation.
func _set_time_row(half: int) -> void:
	_stop_time_shift()
	_time_prev.text = _half_text(half - 1)
	_time_now.text = _half_text(half)
	_time_next.text = _half_text(half + 1)
	_place_time_label(_time_prev, -1.0)
	_place_time_label(_time_now, 0.0)
	_place_time_label(_time_next, 1.0)
	_time_prev.visible = half > 0


## Label on slot `slot` (0 = centre, ±1 = the sides, ±2 = off the row): x offset, scale and alpha
## blend between the slots, so a float slot is an in-between.
func _place_time_label(lbl: Label, slot: float) -> void:
	var half_w: float = lbl.pivot_offset.x
	lbl.offset_left = -half_w + slot * TIME_SLOT_DX
	lbl.offset_right = half_w + slot * TIME_SLOT_DX
	var side: float = clampf(absf(slot), 0.0, 1.0)
	lbl.scale = Vector2.ONE * lerpf(1.0, TIME_SIDE_SCALE, side)
	var a: float = lerpf(1.0, TIME_SIDE_ALPHA, side)
	if absf(slot) > 1.0:
		a *= clampf(2.0 - absf(slot), 0.0, 1.0)
	lbl.modulate.a = a


func _shift_time_row(old_half: int, half: int) -> void:
	_set_time_row(old_half)
	_time_ghost = _time_next.duplicate() as Label
	_time_ghost.text = _half_text(half + 1)
	_time_row.add_child(_time_ghost)
	_place_time_label(_time_ghost, 2.0)
	var ghost: Label = _time_ghost
	var step: Callable = func(f: float) -> void:
		if old_half > 0:
			_place_time_label(_time_prev, -1.0 - f)
		_place_time_label(_time_now, -f)
		# Into a morning there is no previous half: the old evening fades as it moves left.
		if half == 0:
			_time_now.modulate.a *= 1.0 - f
		_place_time_label(_time_next, 1.0 - f)
		if is_instance_valid(ghost):
			_place_time_label(ghost, 2.0 - f)
	_time_tween = _time_row.create_tween()
	_time_tween.tween_interval(WeekFade.clear_delay())
	_time_tween.tween_method(step, 0.0, 1.0, TIME_SHIFT) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_time_tween.tween_callback(_set_time_row.bind(half))


func _stop_time_shift() -> void:
	if _time_tween != null and _time_tween.is_valid():
		_time_tween.kill()
	_time_tween = null
	if _time_ghost != null and is_instance_valid(_time_ghost):
		_time_ghost.queue_free()
	_time_ghost = null


## Weekday `i` (Mon 0 … Sun 6) as its English abbreviation (MON … SUN). Out of range = "".
static func day_abbr(i: int) -> String:
	if i < 0 or i >= DAY_ABBR.size():
		return ""
	return Loc.t(String(DAY_ABBR[i]))  # l10n-dynamic: term.day.abbr.*


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
	_map = null
	_map_pin.visible = false
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
		if stage == Stage.AFTERNOON:
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
	# Pinned (`%MapPin`, centred on the screen's height): the card list stands above it,
	# the pilot row under it.
	var section: Control = MAP_SECTION_SCENE.instantiate() as Control
	_map_pin.add_child(section)
	_map_pin.visible = true

	var stadium: bool = stage == Stage.STADIUM or stage == Stage.PRESS
	var map: BaseMap = BaseMap.create_stadium() if stadium \
			else BaseMap.create(RunRules.team_map_id(int(s.get("player_team_id", 0))))
	map.name = "BaseMap_Stadium" if stadium else "BaseMap_Team"
	_map = map
	# 1200-wide map centred on the full-width holder; the screen crops 60 px each side.
	BaseMap.mount(map, section.get_node("%MapHolder") as Control)

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
		entries.append({"node": token, "spot": spot, "key": pid,
				"anchor": hold.position + hold.size * 0.5, "portrait": PilotImages.circle_for(pid),
				"ring": OutgameTheme.ACCENT if _token_picked(stage, pid) else Color.BLACK})
	map.place_tokens(entries)
	_animate_map(map, stage)


## Time of day on the map for a stage (`BaseMapLighting` hour).
func _stage_hour(stage: int) -> float:
	match stage:
		Stage.MORNING:
			return 8.0
		Stage.RESULT:
			return 9.5
		Stage.TALK:
			return 11.0
		Stage.AFTERNOON:
			return 15.0
		Stage.EVENING:
			return 18.5
		Stage.STADIUM:
			return 10.0 if _day == CalendarSystem.PREP_DAY else 13.0
		Stage.PRESS:
			return 16.5
	return 12.0


## Time passing on the map: when the day or the stage changed since the last draw
## (`_map_memory`), the clock runs from the old hour to this stage's (a new day = through
## the night) and, on the same map, my pilots walk the roads from where they stood.
## A redraw of the same stage only sets the hour (a running animation restarts settled).
func _animate_map(map: BaseMap, stage: int) -> void:
	var s: Dictionary = _gm.season_state
	var day_id: int = int(s.get("current_phase", 0)) * 1000 + CalendarSystem.day_in_phase(s)
	var hour: float = _stage_hour(stage)
	var was: Dictionary = _map_memory
	_map_memory = {"scene": map.scene_file_path, "day": day_id, "stage": stage, "hour": hour,
			"tokens": map.token_state()}
	if was.is_empty() or (int(was["day"]) == day_id and int(was["stage"]) == stage):
		map.set_hour(hour)
		return
	var next_day: bool = int(was["day"]) != day_id
	var from_h: float = float(was["hour"])
	var to_h: float = hour
	if next_day:
		while to_h <= from_h:
			to_h += 24.0
	var time: float = NIGHT_TIME if next_day else STAGE_TIME
	map.play_hour(from_h, to_h, time)
	if String(was["scene"]) == map.scene_file_path:
		var delay: float = time * NIGHT_WALK_DELAY if next_day else 0.0
		map.walk_from(was["tokens"], time - delay, delay)


## A tap on the map while time passes skips to the end.
func _input(event: InputEvent) -> void:
	if _map == null or not is_instance_valid(_map) or not _map.is_animating():
		return
	var pressed: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if not pressed:
		return
	var at: Vector2 = (event as InputEventMouseButton).position if event is InputEventMouseButton \
			else (event as InputEventScreenTouch).position
	if _map_pin.get_global_rect().has_point(at):
		_map.finish_animation()
		get_viewport().set_input_as_handled()


## Where my pilots stand on the stadium map: the team room on Saturday (analysis and
## ban/pick), the stage booths on Sunday morning, the press room after the match.
func _stadium_spot(stage: int) -> String:
	if stage == Stage.PRESS:
		return BaseMap.SPOT_PRESS
	return BaseMap.SPOT_TEAM_ROOM if _day == CalendarSystem.PREP_DAY else BaseMap.SPOT_BOOTH


## One pilot token on the map (`UI_Comp_WeekMapPilot.tscn`). No name under the portrait:
## the morning shows a speech bubble with the training `course` this pilot does now, the
## afternoon an away chip (혼자 외출 / 숙소 휴식). Portrait only — the stress / trust / awakening
## gauges are on the pilot cards under the map. A pilot that cannot be picked is covered by the
## black mask (`_token_dimmed`); the picked one (`_token_picked`) is scaled up around its
## centre and drawn over the others. The RESULT stage's rising texts are added later by
## `_play_result_fx`.
func _add_map_token(map: BaseMap, stage: int, pid: int, course: String, away: String) -> Control:
	var token: Control = MAP_PILOT_SCENE.instantiate() as Control
	map.add_token(token)
	var picked: bool = _token_picked(stage, pid)
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
	(token.get_node("%Mask") as Control).visible = _token_dimmed(stage, pid)
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
		(c as SeasonPilotCard).pulse_deltas()
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
## The five cards under the map (every day). The gauges show the day's changes
## (`_day_delta`: stress · trust points): ring segment + `+N` / `+N%` under the value,
## none at 0; the portrait ring shows the day's 깨달음 level EXP (`tlexp`) as a light segment.
func _refresh_pilot_row() -> void:
	var s: Dictionary = _gm.season_state
	var by_seat: Dictionary = {}
	for raw in MentalSystem.my_pilot_ids(s):
		var pd: PlayerData = MentalEvents.pilot_of(s, int(raw))
		if pd != null:
			by_seat[GameEnums.role_seat(pd.role)] = pd
	for seat in _pilot_cards.size():
		var card: SeasonPilotCard = _pilot_cards[seat]
		if not by_seat.has(seat):
			card.show_empty()
			continue
		var pd2: PlayerData = by_seat[seat]
		card.show_pilot(pd2.id, MentalSystem.trust(s, pd2.id), StressSystem.value(s, pd2.id))
		card.set_day_deltas(_day_delta(pd2.id, "stress"), _day_delta(pd2.id, "trust"),
				_day_delta(pd2.id, "tlexp"))


## Change of `pid`'s `kind` ("stress" · "trust" (points) · "tlexp" (깨달음 level EXP)) on the
## shown weekday so far: the morning training row (`stress` / `tlexp` keys — `tlexp` = the EXP
## the level actually took, `TrainingLevel.on_training_day`), a self outing (stress:
## `AfternoonAway.relief_of`) and the `kind` / `<kind>_all` notes of the day's talk, incident
## and afternoon (visit / evening) outcomes. `<kind>_all` notes carry the clause's nominal
## delta (a clamped pilot reads it unclamped). Not recorded per day, so not counted: the
## Sunday press answer and the match's level EXP.
func _day_delta(pid: int, kind: String) -> int:
	if not CalendarSystem.is_week_day(_day):
		return 0
	var s: Dictionary = _gm.season_state
	var total: int = 0
	for raw in (_week_log().get(_day, []) as Array):
		if int((raw as Dictionary)["pilot_id"]) == pid:
			total += int((raw as Dictionary).get(kind, 0))
	if kind == "stress":
		total += AfternoonAway.relief_of(s, _day, pid)
	var rec: Dictionary = MentalSystem.day_record(s, _day)
	for k in ["talk", "incident", "evening"]:
		var outcome: Dictionary = (rec.get(k, {}) as Dictionary).get("outcome", {})
		for n_raw in (outcome.get("notes", []) as Array):
			var n: Dictionary = n_raw
			var t: String = String(n.get("type", ""))
			if (t == kind and int(n.get("pid", -1)) == pid) or t == kind + "_all":
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
	_open_talk_bubble(pid)


## Morning talk: the bubble over the picked pilot's token (`VisitMenu.open_talk`) — the
## pilot's line and one button, 만남. A tap outside closes it (`_on_talk_dismissed`).
func _open_talk_bubble(pid: int) -> void:
	if _visit_menu == null:
		_visit_menu = _make_visit_menu()
	var token: Control = _tokens.get(pid, null)
	if token != null:
		_visit_menu.point_at(token.get_node("%Portrait"), token)
	_visit_menu.open_talk(_gm.season_state, pid)


## Tap outside the talk bubble: closed, the pick dropped — a tap on another pilot that can be
## met picks that one instead.
func _on_talk_dismissed(at: Vector2) -> void:
	_close_visit_menu()
	var other: int = -1
	for pid in _tokens:
		var hit: Control = (_tokens[pid] as Control).get_node("%Hit")
		if int(pid) != _sel_pid and hit.get_global_rect().has_point(at):
			other = int(pid)
	if other >= 0 and _can_pick(Stage.TALK, other):
		_on_map_pilot_picked(other)
		return
	_sel_pid = -1
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
			WeekFade.through(_to_afternoon)
			return
		Stage.AFTERNOON:
			# Moving on while an interview / outing is still possible asks first.
			if not MentalSystem.evening_done(_gm.season_state, _day) \
					and AfternoonAway.any_request(_gm.season_state, _day):
				_open_skip_popup(Stage.AFTERNOON)
				return
			WeekFade.through(_begin_evening)
			return
	WeekFade.through(_leave_day)


func _to_afternoon() -> void:
	_begin_afternoon()
	refresh()


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
			WeekFade.through(_to_afternoon)
		Stage.AFTERNOON:
			WeekFade.through(_begin_evening)


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

	# Before the visit: the week's coach points (focus training spends them); `%Hint` only
	# when nobody can be visited (the "tap a pilot on the map" instruction was removed).
	var card: Control = _add_item(AFTERNOON_CARD_SCENE)
	var hint: Label = card.get_node("%Hint")
	hint.visible = not AfternoonAway.any_request(s, _day)
	hint.text = Loc.t(L.SEASON_WEEK_AFTERNOON_NONE)
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


func _on_talk_pressed() -> void:
	_close_visit_menu()
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
	menu.talk_picked.connect(_on_talk_pressed)
	menu.dismissed.connect(_on_talk_dismissed)
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
		_visit_menu.show_result(s, out.get("notes", []))


## The focus result confirmed.
func _on_visit_closed() -> void:
	WeekFade.through(func() -> void:
		_close_visit_menu()
		_run_auto())


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
	# Opens through black (`WeekFade`); `_overlay` is set at once, so the screen is busy meanwhile.
	var vn := VnDialogueView.create()
	_overlay = vn
	vn.choice_picked.connect(_on_overlay_choice)
	vn.closed.connect(_on_overlay_closed)
	var partner: int = int(view.get("partner_id", -1))
	var partner_name: String = MentalEvents.pilot_name(_gm.season_state, partner) if partner >= 0 else ""
	WeekFade.through(func() -> void:
		if _overlay != vn or not is_inside_tree():
			return
		add_child(vn)
		vn.open(sub, title, pid, view["lines"], view["choices"], speaker, view.get("previews", []),
				partner, partner_name))


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


## Closes through black; once the screen is black the day moves on by itself when its half
## is done (`_run_auto`), else it redraws.
func _on_overlay_closed() -> void:
	WeekFade.through(func() -> void:
		if _overlay != null:
			_overlay.queue_free()
			_overlay = null
		_overlay_kind = ""
		_overlay_pid = -1
		_run_auto())


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
	_awaken_view.connect("closed", _on_awakening_closed, CONNECT_ONE_SHOT)
	var node: Node = _awaken_view
	WeekFade.through(func() -> void:
		if _awaken_view != node or not is_inside_tree():
			return
		add_child(node)
		node.call("open", pid))
	return true


static func _awakening_view_script() -> Script:
	for c in ProjectSettings.get_global_class_list():
		if String((c as Dictionary).get("class", "")) == "AwakeningView":
			return load(String((c as Dictionary)["path"])) as Script
	return null


func _on_awakening_closed() -> void:
	_save("awakening")
	WeekFade.through(func() -> void:
		if _awaken_view != null and is_instance_valid(_awaken_view) \
				and not _awaken_view.is_queued_for_deletion():
			_awaken_view.queue_free()
		_awaken_view = null
		_run_auto())


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
