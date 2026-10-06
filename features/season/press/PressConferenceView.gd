class_name PressConferenceView
extends Control

# ── Press conference (right before the week starts) ──────────────────────────
#
# A messenger screen (`MessengerView`): the reporter speaks on the left, the
# manager answers on the right. Lines appear one per tap, then 2–3 answers;
# the picked answer is applied by `MentalSystem.resolve_press` (team trust ±,
# a temporary manager-stat mod, or — for a question that mentions a pilot —
# that pilot's trust ±), the effects show as chips, and a tap moves on to the
# training plan via `SeasonHub.on_press_finished()`.
#
# The question comes from `mental_events.csv` (kind `press`) — drawn once per
# week by `MentalSystem.press_session` (seeded, stored in `mental.press`), so
# reopening the screen in the same week shows the same question and an
# answered question is never applied twice.
#
# Layout follows the other season screens: the whole screen is indented with
# `indent_to_safe_top`; the messenger paints the background.

const PHASE_NAMES: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON:      "프리시즌",
	GameEnums.SeasonPhase.PRESEASON_INTL: "프리시즌 국제대회",
	GameEnums.SeasonPhase.MIDSEASON:      "미드시즌",
	GameEnums.SeasonPhase.MIDSEASON_INTL: "미드시즌 국제대회",
	GameEnums.SeasonPhase.REGULAR:        "정규시즌",
	GameEnums.SeasonPhase.REGULAR_INTL:   "정규시즌 국제대회",
}

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _built: bool = false
var _messenger: MessengerView


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	ensure_view()


## Called every time SeasonHub routes here — opens this week's conference.
func ensure_view() -> void:
	if not _built:
		ScreenMetrics.indent_to_safe_top(self)
		_messenger = MessengerView.new()
		_messenger.outcome_hint = "화면을 눌러 계속"
		add_child(_messenger)
		_messenger.choice_picked.connect(_on_answer_picked)
		_messenger.closed.connect(_finish)
		_built = true
	_restart()


func _restart() -> void:
	var s: Dictionary = _gm.season_state
	var view: Dictionary = MentalSystem.session_view(s, MentalSystem.press_session(s))
	if view.is_empty():
		# No row could be drawn (empty table) — nothing to ask.
		_messenger.open("", "기자회견", null, ["*오늘은 질문이 없습니다."], [])
		return
	var sub: String = "%s · %d주차 · %s 기자" % [
		PHASE_NAMES.get(int(s["current_phase"]), "—"), int(s["phase_week"]),
		String(view["tag"]) if String(view["tag"]) != "" else "e스포츠"]
	_messenger.open(sub, "기자회견", null, view["lines"], view["choices"])


func _on_answer_picked(idx: int) -> void:
	_messenger.show_result(MentalSystem.resolve_press(_gm.season_state, idx))


func _finish() -> void:
	if _hub != null and _hub.has_method("on_press_finished"):
		_hub.on_press_finished()
