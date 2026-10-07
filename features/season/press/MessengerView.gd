class_name MessengerView
extends Control

# ── Messenger dialogue (press conference · interview · outing · incident) ─────
#
# Full-screen chat log. The other side speaks on the LEFT (round portrait +
# white bubble with a wedge), the manager answers on the RIGHT (amber bubble).
#
#   (○) ◀ line 1            ← one line per tap ("화면을 눌러 계속")
#       ◀ line 2
#                    answer 1 ▶   ← choices appear once every line is shown
#                    answer 2 ▶
#
# Flow: `open(...)` → lines one per tap → choices → `choice_picked(idx)` →
# the owner applies effects and calls `show_outcome(reply_lines, notes, verdict)`
# (or `show_result(view)` with `MentalEvents.outcome_view(state, apply_choice result)`)
# → reply bubbles + note chips, hint "화면을 눌러 닫기" → tap → `closed`.
#
# Line grammar (same as mental_texts.csv line marker): plain = left speaker, `>text` =
# manager bubble on the right, `*text` = centred narration.
#
# **The frame lives in `UI_View_MessengerView.tscn`** (background, sub / title, divider, the
# scroll with the `%Log` column and the `%Answers` block, the bottom hint — edit them in
# the editor; styles are `OutgameTheme.tres` variations). **Every log line is an item scene**
# in this folder, appended to `%Log`: `MessengerNpcBubble` · `MessengerPlayerBubble` ·
# `MessengerNarration` · `MessengerNoteChip`; answers are `MessengerAnswerButton`s in
# `%AnswerList`. Sizes come from the containers (wrapped text decides each line's height).
# Create with `MessengerView.create()` (`.new()` is an empty Control).
#
# The view never indents itself — its parent screen already sits on the safe
# top (`ScreenMetrics.indent_to_safe_top`); it fills the parent, extends its
# `%Background` into the notch band and lifts `%SafeArea`'s bottom by the bottom inset.
#
# Taps are received by this view on **release** (see press/README.md
# "Implementation notes"): `DragScroll` swallows presses inside the scroll, and
# drag gestures are filtered out with `_drag.moved`. The root is STOP so an
# overlay copy blocks the screen underneath.

signal choice_picked(idx: int)
signal closed

const SCENE_PATH: String = "res://features/season/press/UI_View_MessengerView.tscn"
const NARRATION_SCENE: PackedScene = preload("res://features/season/press/UI_Comp_MessengerNarration.tscn")
const ANSWER_SCENE: PackedScene = preload("res://features/season/press/UI_Comp_MessengerAnswerButton.tscn")

enum Stage { LINES, CHOICES, OUTCOME, DONE }

## Bottom hint once the outcome is shown (the press screen moves on instead of closing).
@export var outcome_hint: String = "화면을 눌러 닫기"

var _portrait: Texture2D = null      # null → reporter microphone glyph
var _lines: Array = []
var _choices: Array = []
var _shown: int = 0
var _stage: int = Stage.DONE
var _last_side: String = ""          # "npc" / "me" / "narr" — portrait only when the speaker changes

@onready var _title_lbl: Label = %Title
@onready var _sub_lbl: Label = %Sub
@onready var _hint_lbl: Label = %Hint
@onready var _body: Control = %Body
@onready var _log: Control = %Log
@onready var _answers: Control = %Answers
@onready var _answer_list: Control = %AnswerList
@onready var _scroll: ScrollContainer = %Scroll
var _drag: DragScroll
var _press_outside_scroll: bool = false
var _picked_frame: int = -1         # process frame of the answer tap (its release is not a tap)


## Instantiates the scene. Load (not preload) — preloading its own scene is a
## script ↔ scene cycle.
static func create() -> MessengerView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MessengerView


func _ready() -> void:
	gui_input.connect(_on_tap_input)
	# Drag / fling scrolling instead of the engine's touch drag. `%Scroll` / `%Body`
	# are PASS in the scene so releases bubble up to this view.
	_drag = DragScroll.attach(_scroll)
	# Device sizes only — the layout itself is the scene's. The column is at least as wide as
	# the screen, so an overflowing log's scroll bar goes past the right edge (see `%Scroll`).
	ScreenMetrics.extend_background(%Background)
	(%SafeArea as Control).offset_bottom = -maxf(0.0, ScreenMetrics.insets().w)
	_body.custom_minimum_size.x = ScreenMetrics.vp_w()
	if UiPreview.is_standalone(self):
		_fill_preview()


# ── API ──────────────────────────────────────────────────────────────────────
## Start a fresh dialogue. `portrait` = the left speaker (null → reporter glyph).
func open(sub: String, title: String, portrait: Texture2D, lines: Array, choices: Array) -> void:
	_sub_lbl.text = sub
	_title_lbl.text = title
	_portrait = portrait
	_lines = lines.duplicate()
	_choices = choices.duplicate()
	_shown = 0
	_last_side = ""
	_stage = Stage.LINES
	_clear(_log)
	_clear_answers()
	_reveal_next_line()


## After `choice_picked`: append the speaker's reply lines and effect notes.
## `verdict` = 0 no check / 1 passed / -1 failed (mental check chip).
func show_outcome(reply_lines: Array, notes: Array, verdict: int = 0) -> void:
	for l in reply_lines:
		_add_line(String(l))
	if verdict != 0:
		_add_note("멘탈 판정 성공" if verdict > 0 else "멘탈 판정 실패", verdict > 0)
	for n in notes:
		_add_note(String(n), true)
	_stage = Stage.OUTCOME
	_refresh_hint()
	_scroll_to_bottom()


## Shortcut for a `MentalEvents.outcome_view` result `{checked, ok, say, notes}` (display text).
func show_result(outcome: Dictionary) -> void:
	var verdict: int = 0
	if bool(outcome.get("checked", false)):
		verdict = 1 if bool(outcome.get("ok", false)) else -1
	show_outcome(outcome.get("say", []), outcome.get("notes", []), verdict)


func is_open() -> bool:
	return _stage != Stage.DONE


## Shows every remaining line at once and then the choices (as if tapped through).
## For previews / harnesses — the normal flow reveals one line per tap.
func reveal_all() -> void:
	while _stage == Stage.LINES:
		_reveal_next_line()


# ── Lines ────────────────────────────────────────────────────────────────────
func _reveal_next_line() -> void:
	if _shown >= _lines.size():
		_show_choices()
		return
	_add_line(String(_lines[_shown]))
	_shown += 1
	_refresh_hint()
	_scroll_to_bottom()


func _add_line(text: String) -> void:
	if text.begins_with(">"):
		_add_player_bubble(text.substr(1).strip_edges())
	elif text.begins_with("*"):
		_add_narration(text.substr(1).strip_edges())
	else:
		var b := MessengerNpcBubble.create()
		b.setup(text, _portrait, _last_side != "npc")
		_log.add_child(b)
		_last_side = "npc"


func _add_player_bubble(text: String) -> void:
	_last_side = "me"
	var b := MessengerPlayerBubble.create()
	b.setup(text)
	_log.add_child(b)


func _add_narration(text: String) -> void:
	_last_side = "narr"
	var n: Control = NARRATION_SCENE.instantiate()
	(n.get_node("%Text") as Label).text = text
	_log.add_child(n)


## Effect / verdict chip, centred. `good` picks the tint.
func _add_note(text: String, good: bool) -> void:
	_last_side = "narr"
	var c := MessengerNoteChip.create()
	c.setup(text, good)
	_log.add_child(c)


## Frees every child right away from the layout's point of view (out of the tree now,
## freed at the end of the frame).
static func _clear(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


# ── Choices ──────────────────────────────────────────────────────────────────
func _show_choices() -> void:
	if _answers.visible or _stage != Stage.LINES:
		return
	_stage = Stage.CHOICES
	if _choices.is_empty():
		_stage = Stage.OUTCOME
		_refresh_hint()
		return
	for i in _choices.size():
		var b: Button = ANSWER_SCENE.instantiate()
		b.text = String(_choices[i])
		b.pressed.connect(_on_choice_pressed.bind(i))
		_answer_list.add_child(b)
	_answers.visible = true
	_refresh_hint()
	_scroll_to_bottom()


func _clear_answers() -> void:
	_answers.visible = false
	_clear(_answer_list)


func _on_choice_pressed(idx: int) -> void:
	if _stage != Stage.CHOICES:
		return
	_stage = Stage.OUTCOME
	# The answer Button fires on release, and `DragScroll` has lowered it to
	# PASS — so that same release bubbles on up to `_on_tap_input` and would
	# close the outcome before it is read. Ignore taps from this frame.
	_picked_frame = Engine.get_process_frames()
	_clear_answers()
	_add_player_bubble(String(_choices[idx]))
	_refresh_hint()
	_scroll_to_bottom()
	choice_picked.emit(idx)


# ── Input · helpers ──────────────────────────────────────────────────────────
func _on_tap_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if mb.pressed:
		# A press that reached us came from outside the scroll (header).
		_press_outside_scroll = true
		return
	var outside: bool = _press_outside_scroll
	_press_outside_scroll = false
	if not outside and _drag != null and _drag.moved:
		return
	if Engine.get_process_frames() == _picked_frame:
		return
	match _stage:
		Stage.LINES:
			_reveal_next_line()
		Stage.OUTCOME:
			_stage = Stage.DONE
			_refresh_hint()
			closed.emit()


func _refresh_hint() -> void:
	if _hint_lbl == null:
		return
	match _stage:
		Stage.LINES:
			_hint_lbl.text = "화면을 눌러 계속"
		Stage.CHOICES:
			_hint_lbl.text = "답변을 고르세요"
		Stage.OUTCOME:
			_hint_lbl.text = outcome_hint
		_:
			_hint_lbl.text = ""


## Scroll to the bottom one frame later — new lines are laid out by the containers at the
## end of this frame (wrapped heights included); the scroll bar clamps the value to its end.
func _scroll_to_bottom() -> void:
	if _scroll == null or not is_inside_tree():
		return
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		var bar: VScrollBar = _scroll.get_v_scroll_bar()
		_scroll.scroll_vertical = int(ceil(bar.max_value))


## F6 단독 실행 미리보기 — 손으로 적은 기자회견 한 판: 기자 두 줄 · 해설 · 내 답 한 줄을
## 다 펼쳐 답변 셋이 보이는 상태(`resources/UiPreview.gd`). 답을 고르면 결과 칩까지 나온다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(choice_picked)
	UiPreview.trace(closed)
	choice_picked.connect(func(_idx: int) -> void:
		show_outcome(["좋습니다. 주말 경기 기대하겠습니다."], ["팀 신뢰 +3", "감독 멘탈 +1 (2주)"], 1))
	open("프리시즌 · 3주차 · e스포츠 데일리 기자", "기자회견", null, [
		"주말 경기 상대가 만만치 않다는 평이 많습니다.",
		"솔직히, 이길 자신 있으십니까?",
		"*기자석이 잠시 조용해진다.",
		">상대 분석은 이미 끝냈습니다.",
		"그렇다면 이번 주 훈련의 초점은 어디에 두셨나요?",
	], [
		"저희 선수들을 믿습니다.",
		"쉽지 않겠지만 준비한 게 있습니다.",
		"질문이 좀 무례하시네요.",
	])
	reveal_all()
