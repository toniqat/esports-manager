class_name VnDialogueView
extends Control

# ── Visual-novel dialogue (interview · outing) ───────────────────────────────
#
# The pilot's full-body illustration stands in the middle of the screen, one line at a
# time is spoken in the speech bubble at the bottom, a tap advances.
#
#   sub / title                  ← header (day · activity / pilot name)
#        ( full-body art )       ← `PilotImages.full_for(pilot_id)`, placeholder slab if none
#   ┌[name plate]──────────┐
#   │ line text            │     ← one line per tap ("화면을 눌러 계속")
#   └──────────────────────┘
#
# Choices: the screen dims and the answers are listed vertically in the centre.
# Flow: `open(...)` → lines one per tap → choices → `choice_picked(idx)` → the owner
# applies the effects and calls `show_result(MentalEvents.outcome_view(state, outcome))`
# → the picked answer (manager line) and the reply lines, one per tap → result panel
# over the dim (no title: `EventResultPanel` — the pilot's portrait on the panel's top edge,
# bars from the view's `result_blocks`, or plain note chips — then the verdict chip) → tap →
# `closed`.
#
# Line grammar (mental_texts.csv line marker, first char after translation): plain = the
# pilot (name plate = the pilot's name), `>text` = the manager (manager name plate, the
# illustration dims), `*text` = narration (no name plate), `&text` = the partner of a
# joint-training talk (the art switches to the partner, partner name plate), `@text` = tag
# (header only, skipped here).
#
# Choices may carry a preview line (`previews`, `MentalEvents.preview_text`: check chance +
# effect directions) shown under each answer.
#
# Drop-in for `MessengerView` on the week screen's evening dialog: same signals, same
# `show_result` / `is_open` / `reveal_all`, `open` takes a pilot id instead of a portrait.
# **The layout lives in `UI_View_VnDialogue.tscn`**; looks are `OutgameTheme.tres`
# variations (`VnDialogue*`). Create with `VnDialogueView.create()` (`.new()` is an empty Control).
#
# Like `MessengerView` the view never indents itself (the owning screen sits on the safe
# top): it extends `%Background` / `%Dim` into the notch band and lifts `%SafeArea` /
# `%Overlay` by the bottom inset. The root is STOP, so it blocks the screen underneath;
# taps are read on release from the root's `gui_input` (every child but the answer
# buttons ignores the mouse).

signal choice_picked(idx: int)
signal closed

const SCENE_PATH: String = "res://features/season/mental/UI_View_VnDialogue.tscn"
const CHOICE_SCENE: PackedScene = preload("res://features/season/mental/UI_Comp_VnChoiceButton.tscn")

## Typewriter speed (characters per second); a tap while typing shows the whole line.
const TYPE_CHARS_PER_SEC: float = 60.0
## Fade of the whole view on `open` and of the dim / panels (seconds).
const FADE_SEC: float = 0.2
## Illustration tint while the manager speaks (the pilot listens).
const ART_LISTEN_MODULATE: Color = Color(0.62, 0.62, 0.66, 1.0)

enum Stage { LINES, CHOICES, REPLY, WAIT, OUTCOME, DONE }

## Bottom hint once the outcome is shown, an l10n key translated when shown.
@export var outcome_hint: String = L.PRESS_MESSENGER_HINT_CLOSE

var _speaker: String = ""
var _lines: Array = []
var _choices: Array = []
var _previews: Array = []
var _pilot_tex: Texture2D = null
var _partner_tex: Texture2D = null
var _partner_name: String = ""
var _queue: Array = []               # lines still to show in this stage (LINES / REPLY)
var _stage: int = Stage.DONE
var _result_ready: bool = false
var _verdict: int = 0                # 0 no check / 1 passed / -1 failed
var _notes: Array = []
var _blocks: Array = []              # `outcome_view.result_blocks` ([] → `_notes` as text chips)
var _type_tween: Tween = null
var _art_tween: Tween = null
var _picked_frame: int = -1          # process frame of the answer tap (its release is not a tap)

@onready var _sub_lbl: Label = %Sub
@onready var _title_lbl: Label = %Title
@onready var _art: TextureRect = %Art
@onready var _slab: Control = %Slab
@onready var _slab_lbl: Label = %SlabLabel
@onready var _plate: PanelContainer = %NamePlate
@onready var _speaker_lbl: Label = %Speaker
@onready var _text_lbl: Label = %Text
@onready var _dim: Control = %Dim
@onready var _choice_list: Control = %ChoiceList
@onready var _result_panel: Control = %ResultPanel
@onready var _verdict_box: Control = %Verdict
@onready var _result_body: EventResultPanel = %EventResultPanel_Result
@onready var _hint_lbl: Label = %Hint


## Instantiates the scene. Load (not preload): preloading its own scene is a
## script ↔ scene cycle.
static func create() -> VnDialogueView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as VnDialogueView


func _ready() -> void:
	gui_input.connect(_on_tap_input)
	# Device sizes only, the layout itself is the scene's.
	ScreenMetrics.extend_background(%Background)
	ScreenMetrics.extend_background(_dim)
	var bottom: float = -maxf(0.0, ScreenMetrics.insets().w)
	(%SafeArea as Control).offset_bottom = bottom
	(%Overlay as Control).offset_bottom = bottom
	if UiPreview.is_standalone(self):
		_fill_preview()


# ── API ──────────────────────────────────────────────────────────────────────
## Start a fresh dialogue. `pilot_id` = the pilot on stage (`PilotImages.full_for`; no art or
## `-1` → placeholder slab). `speaker` = the pilot's name plate ("" → `title`).
## `previews[i]` = the preview line under answer i ("" = none). `partner_id` / `partner_name` =
## the second pilot of a joint-training talk, who speaks the `&` lines.
func open(sub: String, title: String, pilot_id: int, lines: Array, choices: Array,
		speaker: String = "", previews: Array = [], partner_id: int = -1, partner_name: String = "") -> void:
	_sub_lbl.text = sub
	_title_lbl.text = title
	_speaker = speaker if not speaker.is_empty() else title
	_pilot_tex = PilotImages.full_for(pilot_id) if pilot_id >= 0 else null
	_partner_tex = PilotImages.full_for(partner_id) if partner_id >= 0 else null
	_partner_name = partner_name
	_show_art(_pilot_tex, _speaker)
	_lines = lines.duplicate()
	_choices = choices.duplicate()
	_previews = previews.duplicate()
	_queue = _lines.duplicate()
	_result_ready = false
	_verdict = 0
	_notes = []
	_blocks = []
	_picked_frame = -1
	_clear(_choice_list)
	_clear(_verdict_box)
	_result_body.clear()
	_dim.visible = false
	_choice_list.visible = false
	_result_panel.visible = false
	_stage = Stage.LINES
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, FADE_SEC)
	_advance()


## After `choice_picked`: `MentalEvents.outcome_view(state, outcome)` →
## `{checked, ok, say: [String], notes: [String], result_blocks?: [block]}` (display text;
## call it right after the effects so the bars read the right values). The reply lines follow
## the picked answer, then the result panel: `result_blocks` → `EventResultPanel.show_blocks`
## (per-pilot bars), else `notes` → plain chips (e.g. `LimitBreak.choose_goal`'s view).
func show_result(outcome: Dictionary) -> void:
	for l in outcome.get("say", []):
		_queue.append(String(l))
	_verdict = 0
	if bool(outcome.get("checked", false)):
		_verdict = 1 if bool(outcome.get("ok", false)) else -1
	_notes = (outcome.get("notes", []) as Array).duplicate()
	_blocks = (outcome.get("result_blocks", []) as Array).duplicate()
	_result_ready = true
	if _stage == Stage.WAIT:
		_stage = Stage.REPLY
		_advance()


func is_open() -> bool:
	return _stage != Stage.DONE


## Shows the choices at once (as if every line was tapped through), the last line fully
## typed. For previews / harnesses; the normal flow reveals one line per tap.
func reveal_all() -> void:
	if _stage != Stage.LINES:
		return
	var last: String = ""
	while not _queue.is_empty():
		var l: String = String(_queue.pop_front())
		if _is_shown_line(l):
			last = l
	if not last.is_empty():
		_show_line(last)
	_finish_typing()
	_advance()


# ── Flow ─────────────────────────────────────────────────────────────────────
## Next step of the current stage: the next queued line, else the stage's ending.
func _advance() -> void:
	while not _queue.is_empty():
		var l: String = String(_queue.pop_front())
		if _is_shown_line(l):
			_show_line(l)
			_refresh_hint()
			return
	match _stage:
		Stage.LINES:
			_show_choices()
		Stage.REPLY:
			if _result_ready:
				_show_outcome()
			else:
				_stage = Stage.WAIT
				_refresh_hint()


func _show_choices() -> void:
	if _choices.is_empty():
		_stage = Stage.OUTCOME
		_refresh_hint()
		return
	_stage = Stage.CHOICES
	for i in _choices.size():
		var item: Control = CHOICE_SCENE.instantiate()
		var b: Button = item.get_node("%Button")
		b.text = String(_choices[i])
		b.pressed.connect(_on_choice_pressed.bind(i))
		var preview: Label = item.get_node("%Preview")
		preview.text = String(_previews[i]) if i < _previews.size() else ""
		preview.visible = not preview.text.is_empty()
		_choice_list.add_child(item)
	_fade_in(_dim)
	_fade_in(_choice_list)
	_refresh_hint()


func _on_choice_pressed(idx: int) -> void:
	if _stage != Stage.CHOICES:
		return
	# The release that fired the button must not count as a tap on the view too.
	_picked_frame = Engine.get_process_frames()
	_dim.visible = false
	_choice_list.visible = false
	_clear(_choice_list)
	_stage = Stage.REPLY
	# The picked answer is the manager's line, the replies (`show_result`) queue after it.
	_queue.push_front(">" + String(_choices[idx]))
	_advance()
	choice_picked.emit(idx)


## Result panel over the dim: the result body (`EventResultPanel`, its main pilot's portrait on
## the panel's top edge) + verdict chip under it (when the entry rolled a check). Nothing to show → the hint asks for the closing tap right away.
func _show_outcome() -> void:
	_stage = Stage.OUTCOME
	if _verdict != 0:
		var v := MessengerNoteChip.create()
		v.setup(Loc.t(L.PRESS_MESSENGER_CHECK_PASS if _verdict > 0 else L.PRESS_MESSENGER_CHECK_FAIL),
				_verdict > 0)
		_verdict_box.add_child(v)
	if not _blocks.is_empty():
		_result_body.show_blocks(_blocks)
	else:
		_result_body.show_texts(_notes)
	_result_body.visible = not _result_body.is_empty()
	_verdict_box.visible = _verdict != 0
	if _verdict != 0 or not _result_body.is_empty():
		_fade_in(_dim)
		_fade_in(_result_panel)
	_refresh_hint()


func _close() -> void:
	_stage = Stage.DONE
	_refresh_hint()
	closed.emit()


# ── Lines ────────────────────────────────────────────────────────────────────
## `@tag` lines belong to the header, empty lines are skipped.
static func _is_shown_line(text: String) -> bool:
	return not text.strip_edges().is_empty() and not text.begins_with("@")


func _show_line(text: String) -> void:
	var listening: bool = false
	if text.begins_with(">"):
		_set_plate(Loc.t(L.TERM_PERSON_MANAGER), &"VnDialogueNamePlateMine")
		_set_text(text.substr(1).strip_edges(), &"BodyLabel")
		listening = true
	elif text.begins_with("*"):
		_plate.visible = false
		_set_text(text.substr(1).strip_edges(), &"SubLabel")
	elif text.begins_with("&"):
		_show_art(_partner_tex, _partner_name)
		_set_plate(_partner_name, &"VnDialogueNamePlate")
		_set_text(text.substr(1).strip_edges(), &"BodyLabel")
	else:
		_show_art(_pilot_tex, _speaker)
		_set_plate(_speaker, &"VnDialogueNamePlate")
		_set_text(text, &"BodyLabel")
	_tint_art(ART_LISTEN_MODULATE if listening else Color.WHITE)


## The illustration on stage (the pilot, or the partner while the partner speaks); no art →
## the placeholder slab with `who`.
func _show_art(tex: Texture2D, who: String) -> void:
	_art.texture = tex
	_art.visible = tex != null
	_slab.visible = tex == null
	_slab_lbl.text = who


func _set_plate(who: String, variation: StringName) -> void:
	_plate.visible = not who.is_empty()
	_plate.theme_type_variation = variation
	_speaker_lbl.text = who


## Shows `text` with the typewriter effect; `variation` = the line's label look.
func _set_text(text: String, variation: StringName) -> void:
	_text_lbl.theme_type_variation = variation
	_text_lbl.text = text
	_kill_typing()
	var n: int = text.length()
	if n == 0 or not is_inside_tree():
		_text_lbl.visible_characters = -1
		return
	_text_lbl.visible_characters = 0
	_type_tween = create_tween()
	_type_tween.tween_property(_text_lbl, "visible_characters", n, float(n) / TYPE_CHARS_PER_SEC)
	_type_tween.tween_callback(func() -> void: _text_lbl.visible_characters = -1)


func _is_typing() -> bool:
	return _type_tween != null and _type_tween.is_valid() and _type_tween.is_running()


func _finish_typing() -> void:
	_kill_typing()
	_text_lbl.visible_characters = -1


func _kill_typing() -> void:
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	_type_tween = null


func _tint_art(c: Color) -> void:
	if _art_tween != null and _art_tween.is_valid():
		_art_tween.kill()
	if not is_inside_tree():
		_art.modulate = c
		_slab.modulate = c
		return
	_art_tween = create_tween().set_parallel(true)
	_art_tween.tween_property(_art, "modulate", c, FADE_SEC)
	_art_tween.tween_property(_slab, "modulate", c, FADE_SEC)


# ── Input · helpers ──────────────────────────────────────────────────────────
func _on_tap_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if mb.pressed or Engine.get_process_frames() == _picked_frame:
		return
	if _is_typing():
		_finish_typing()
		return
	match _stage:
		Stage.LINES, Stage.REPLY:
			_advance()
		Stage.OUTCOME:
			_close()


func _refresh_hint() -> void:
	match _stage:
		Stage.LINES, Stage.REPLY:
			_hint_lbl.text = Loc.t(L.UI_BUTTON_TAP_TO_CONTINUE)
		Stage.CHOICES:
			_hint_lbl.text = Loc.t(L.PRESS_MESSENGER_PICK_ANSWER)
		Stage.OUTCOME:
			_hint_lbl.text = Loc.t(outcome_hint)  # l10n-dynamic: press.messenger.hint_close
		_:
			_hint_lbl.text = ""


func _fade_in(c: CanvasItem) -> void:
	c.visible = true
	c.modulate.a = 0.0
	create_tween().tween_property(c, "modulate:a", 1.0, FADE_SEC)


## Frees every child right away from the layout's point of view.
static func _clear(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


## F6 단독 실행 미리보기: 메모리 런(`UiPreview.ensure_run`)에서 내 첫 파일럿과 실제 면담 한 판을
## 뽑아 연다. 대사를 넘기고 답을 고르면 `MentalSystem.finish_evening` 결과가 결과 판까지 나온다.
func _fill_preview() -> void:  # l10n-ignore
	UiPreview.stage(self)
	UiPreview.trace(choice_picked)
	UiPreview.trace(closed)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var s: Dictionary = gm.season_state
	var ids: Array = MentalSystem.my_pilot_ids(s)
	if ids.is_empty():
		return
	var pid: int = int(ids[0])
	var day: int = -1
	var session: Dictionary = {}
	for d in 5:
		session = MentalSystem.begin_evening(s, d, MentalSystem.ACTION_INTERVIEW, pid)
		if not session.is_empty():
			day = d
			break
	if day < 0:
		return
	var view: Dictionary = MentalSystem.session_view(s, session)
	choice_picked.connect(func(idx: int) -> void:
		show_result(MentalEvents.outcome_view(s, MentalSystem.finish_evening(s, day, idx))))
	open(Loc.t(L.TERM_ACTIVITY_INTERVIEW), MentalEvents.pilot_name(s, pid), pid,
			view["lines"], view["choices"], "", view["previews"])
