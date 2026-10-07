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
# (or `show_result(outcome)` with a `MentalEvents.apply_choice` result)
# → reply bubbles + note chips, hint "화면을 눌러 닫기" → tap → `closed`.
#
# Line grammar (same as mental_events.csv): plain = left speaker, `>text` =
# manager bubble on the right, `*text` = centred narration.
#
# **The frame lives in `MessengerView.tscn`** (background, sub / title, divider, the
# scroll and the bottom hint — edit them in the editor; styles are `OutgameTheme.tres`
# variations). The chat log itself — bubbles, wedges, narration, note chips and answer
# buttons — is still placed by code under `%Body`: each line's height is measured from
# its text. Create with `MessengerView.create()` (`.new()` is an empty Control).
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

const MARGIN_X: float      = 40.0
const PORTRAIT_D: float    = 96.0
const BUBBLE_MAX_W: float  = 700.0
const BUBBLE_PAD_X: float  = 26.0
const BUBBLE_PAD_Y: float  = 20.0
const BUBBLE_GAP: float    = 18.0
const WEDGE_W: float       = 18.0
const WEDGE_H: float       = 22.0
const LINE_FONT: int       = 27
const NARR_FONT: int       = 24
const NOTE_FONT: int       = 22
const NOTE_H: float        = 46.0
const ANSWER_FONT: int     = 26
const ANSWER_H: float      = 96.0
const ANSWER_GAP: float    = 14.0

const SCENE_PATH: String = "res://features/season/press/MessengerView.tscn"

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
@onready var _scroll: ScrollContainer = %Scroll
var _drag: DragScroll
var _body_y: float = 0.0
var _press_outside_scroll: bool = false
var _answer_holder: Control
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
	# Device insets only — the layout itself is the scene's.
	ScreenMetrics.extend_background(%Background)
	(%SafeArea as Control).offset_bottom = -maxf(0.0, ScreenMetrics.insets().w)
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
	for c in _body.get_children():
		c.queue_free()
	_body_y = 0.0
	_answer_holder = null
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


## Shortcut for a `MentalEvents.apply_choice` result `{checked, ok, say, notes}`.
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
		_add_npc_bubble(text, _last_side != "npc")


func _add_npc_bubble(text: String, with_portrait: bool) -> void:
	_last_side = "npc"
	var bubble_x: float = MARGIN_X + PORTRAIT_D + 26.0
	var body_w: float = minf(BUBBLE_MAX_W, ScreenMetrics.vp_w() - bubble_x - MARGIN_X)
	var h: float = _text_block_height(text, body_w - BUBBLE_PAD_X * 2.0, LINE_FONT) \
			+ BUBBLE_PAD_Y * 2.0
	if with_portrait:
		var holder: Control = OutgameTheme.add_round_portrait(_body, _portrait,
				Vector2(MARGIN_X, _body_y), PORTRAIT_D, OutgameTheme.BORDER)
		if _portrait == null:
			var glyph := Control.new()
			glyph.size = Vector2(PORTRAIT_D, PORTRAIT_D)
			glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glyph.draw.connect(_draw_reporter_glyph.bind(glyph))
			holder.add_child(glyph)
	_add_bubble_panel(Vector2(bubble_x, _body_y), Vector2(body_w, h), text,
			OutgameTheme.SURFACE, OutgameTheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	if with_portrait:
		_add_wedge(Vector2(bubble_x - WEDGE_W + 1.0, _body_y + 26.0), true)
	_advance(h + BUBBLE_GAP)


func _add_player_bubble(text: String) -> void:
	_last_side = "me"
	var body_w: float = BUBBLE_MAX_W - 60.0
	var h: float = _text_block_height(text, body_w - BUBBLE_PAD_X * 2.0, LINE_FONT) \
			+ BUBBLE_PAD_Y * 2.0
	var x: float = ScreenMetrics.vp_w() - MARGIN_X - body_w
	_add_bubble_panel(Vector2(x, _body_y), Vector2(body_w, h), text,
			OutgameTheme.ACCENT, OutgameTheme.TEXT_ON_FILL, HORIZONTAL_ALIGNMENT_RIGHT, false)
	_add_wedge(Vector2(x + body_w - 1.0, _body_y + 24.0), false)
	_advance(h + BUBBLE_GAP)


func _add_narration(text: String) -> void:
	_last_side = "narr"
	var w: float = ScreenMetrics.vp_w() - MARGIN_X * 4.0
	var h: float = _text_block_height(text, w, NARR_FONT) + 12.0
	var lbl := UiHelpers.mk_label(_body, text, NARR_FONT, OutgameTheme.TEXT_SUB,
			Vector2(MARGIN_X * 2.0, _body_y + 6.0), Vector2(w, h), HORIZONTAL_ALIGNMENT_CENTER)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_advance(h + BUBBLE_GAP)


## Effect / verdict chip, centred. `good` picks the tint.
func _add_note(text: String, good: bool) -> void:
	_last_side = "narr"
	var font: Font = ThemeDB.fallback_font
	var w: float = minf(ScreenMetrics.vp_w() - MARGIN_X * 2.0,
			font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NOTE_FONT).x + 56.0)
	OutgameTheme.add_chip(_body, text, Vector2((ScreenMetrics.vp_w() - w) * 0.5, _body_y),
			Vector2(w, NOTE_H), OutgameTheme.ACCENT_DIM if good else OutgameTheme.SURFACE_SUNK,
			OutgameTheme.ACCENT_TEXT if good else OutgameTheme.TEXT_SUB, NOTE_FONT)
	_advance(NOTE_H + 10.0)


func _add_bubble_panel(pos: Vector2, sz: Vector2, text: String, bg: Color, fg: Color,
		align: int, bordered: bool) -> void:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", OutgameTheme.flat_style(bg, 22,
			OutgameTheme.BORDER if bordered else null))
	panel.position = pos
	panel.size = sz
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(panel)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", LINE_FONT)
	lbl.add_theme_color_override("font_color", fg)
	lbl.position = Vector2(BUBBLE_PAD_X, BUBBLE_PAD_Y)
	lbl.size = Vector2(sz.x - BUBBLE_PAD_X * 2.0, sz.y - BUBBLE_PAD_Y * 2.0)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = align as HorizontalAlignment
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)


func _advance(dy: float) -> void:
	_body_y += dy
	_body.custom_minimum_size = Vector2(ScreenMetrics.vp_w(), _body_y)


## Bubble tail — a dedicated childless Control (a Control's `_draw` paints under its children).
func _add_wedge(pos: Vector2, point_left: bool) -> void:
	var w := Control.new()
	w.position = pos
	w.size = Vector2(WEDGE_W, WEDGE_H)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.draw.connect(_draw_wedge.bind(w, point_left))
	_body.add_child(w)


func _draw_wedge(node: Control, point_left: bool) -> void:
	var col: Color = OutgameTheme.SURFACE if point_left else OutgameTheme.ACCENT
	var pts: PackedVector2Array
	if point_left:
		pts = PackedVector2Array([
			Vector2(WEDGE_W, 0.0), Vector2(0.0, WEDGE_H * 0.45), Vector2(WEDGE_W, WEDGE_H)])
	else:
		pts = PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(WEDGE_W, WEDGE_H * 0.45), Vector2(0.0, WEDGE_H)])
	node.draw_colored_polygon(pts, col)


## Reporter portrait placeholder — a microphone. Delete once reporter art exists.
func _draw_reporter_glyph(node: Control) -> void:
	var c: Vector2 = Vector2(PORTRAIT_D, PORTRAIT_D) * 0.5
	var col: Color = OutgameTheme.TEXT_SUB
	node.draw_circle(c, PORTRAIT_D * 0.5 - 2.0, OutgameTheme.SURFACE_SUNK)
	node.draw_rect(Rect2(c.x - 11.0, c.y - 26.0, 22.0, 30.0), col)
	node.draw_circle(Vector2(c.x, c.y - 26.0), 11.0, col)
	node.draw_circle(Vector2(c.x, c.y + 4.0), 11.0, col)
	node.draw_rect(Rect2(c.x - 3.0, c.y + 4.0, 6.0, 22.0), col)
	node.draw_rect(Rect2(c.x - 16.0, c.y + 24.0, 32.0, 6.0), col)


# ── Choices ──────────────────────────────────────────────────────────────────
func _show_choices() -> void:
	if _answer_holder != null or _stage != Stage.LINES:
		return
	_stage = Stage.CHOICES
	if _choices.is_empty():
		_stage = Stage.OUTCOME
		_refresh_hint()
		return
	var w: float = BUBBLE_MAX_W - 60.0
	var x: float = ScreenMetrics.vp_w() - MARGIN_X - w
	_answer_holder = Control.new()
	_answer_holder.position = Vector2(0, _body_y + 10.0)
	_answer_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_answer_holder)
	var y: float = 0.0
	for i in _choices.size():
		var text: String = String(_choices[i])
		var h: float = maxf(ANSWER_H, _text_block_height(text, w - 44.0, ANSWER_FONT) + 34.0)
		var b := Button.new()
		b.text = text
		b.position = Vector2(x, y)
		b.size = Vector2(w, h)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.focus_mode = Control.FOCUS_NONE
		OutgameTheme.style_ghost_button(b, ANSWER_FONT)
		b.pressed.connect(_on_choice_pressed.bind(i))
		_answer_holder.add_child(b)
		y += h + ANSWER_GAP
	_answer_holder.size = Vector2(ScreenMetrics.vp_w(), y)
	_advance(y + 10.0)
	_refresh_hint()
	_scroll_to_bottom()


func _on_choice_pressed(idx: int) -> void:
	if _stage != Stage.CHOICES:
		return
	_stage = Stage.OUTCOME
	# The answer Button fires on release, and `DragScroll` has lowered it to
	# PASS — so that same release bubbles on up to `_on_tap_input` and would
	# close the outcome before it is read. Ignore taps from this frame.
	_picked_frame = Engine.get_process_frames()
	if _answer_holder != null:
		_body_y -= _answer_holder.size.y + 10.0
		_answer_holder.queue_free()
		_answer_holder = null
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


## Scroll to the bottom one frame later (new bubbles are not laid out yet).
func _scroll_to_bottom() -> void:
	if _scroll == null or not is_inside_tree():
		return
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(maxf(0.0, _body_y))


## Height of autowrapped text, asked of the font directly (a just-created
## Label has size 0 in its first frame).
static func _text_block_height(text: String, w: float, font_size: int) -> float:
	var font: Font = ThemeDB.fallback_font
	var line_h: float = float(font_size) * 1.35
	var total: float = 0.0
	for para in text.split("\n"):
		var wrapped: int = maxi(1, int(ceil(
				font.get_string_size(para, HORIZONTAL_ALIGNMENT_LEFT, -1,
						font_size).x / maxf(1.0, w))))
		total += line_h * float(wrapped)
	return maxf(line_h, total)


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
