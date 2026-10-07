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
#
# The screen is `UI_View_PressConferenceView.tscn` — one `MessengerView` instance
# (`%MessengerView_Messenger`, its `outcome_hint` set in the scene). Create with
# `PressConferenceView.create()` (`.new()` is an empty Control).

const SCENE_PATH: String = "res://features/season/press/UI_View_PressConferenceView.tscn"

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")
@onready var _messenger: MessengerView = %MessengerView_Messenger

var _built: bool = false


## Instantiates the scene. Load (not preload) — preloading its own scene is a
## script ↔ scene cycle.
static func create() -> PressConferenceView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as PressConferenceView


func _ready() -> void:
	_messenger.choice_picked.connect(_on_answer_picked)
	_messenger.closed.connect(_finish)
	if UiPreview.is_standalone(self):
		_fill_preview()
	ensure_view()


## Called every time SeasonHub routes here — opens this week's conference.
func ensure_view() -> void:
	if not _built:
		ScreenMetrics.indent_to_safe_top(self)
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
		GameEnums.phase_label(int(s["current_phase"])), int(s["phase_week"]),
		String(view["tag"]) if String(view["tag"]) != "" else "e스포츠"]
	_messenger.open(sub, "기자회견", null, view["lines"], view["choices"])


func _on_answer_picked(idx: int) -> void:
	var s: Dictionary = _gm.season_state
	_messenger.show_result(MentalEvents.outcome_view(s, MentalSystem.resolve_press(s, idx)))


func _finish() -> void:
	if _hub != null and _hub.has_method("on_press_finished"):
		_hub.on_press_finished()


## F6 단독 실행 미리보기 — 메모리 런의 이번 주 질문을 질문 줄까지 다 펼쳐 답변이 보이는
## 상태(`resources/UiPreview.gd`). 질문은 이어지는 `ensure_view` 가 열므로 펼치기는 지연 호출.
## 답을 고르면 메모리 런에만 적용되고, 마지막 탭은 호스트가 없어 아무 일도 안 한다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	if UiPreview.ensure_run() == null:
		return
	UiPreview.trace(_messenger.closed, "press closed")
	_messenger.reveal_all.call_deferred()
