class_name CostDonut
extends Control

## Donut (ring) gauge for 전략 포인트 (작전 점수). One instance per side:
##  - player: sits at the top-right of the hand row, above the Discard counter,
##    and doubles as the 턴 넘기기 button (see below).
##  - enemy: mirrors the same look at the top-right of the screen, under the
##    right edge of the AI hand peek. Never interactive.
##
## Player interaction (BattleSim spec):
##   1. tap the donut during 작전 단계 → the ring unwinds and re-winds in the
##      opposite direction (the "flip") and the face becomes 턴 넘기기.
##   2. tap it again in that state → ends the 작전 단계.
##   3. tap anywhere else on screen → flips back to the 전략 포인트 donut.
##
## Input is handled in `_input` (not `_gui_input`) so the outside-tap revert
## works no matter which control swallowed the press — hand cards call
## accept_event(), so a `_gui_input`/`_unhandled_input` pair would never see it.

## Emitted when the donut is pressed while showing the 턴 넘기기 face and that
## action is currently allowed.
signal end_turn_pressed

const RADIUS       := 56.0
const RING_WIDTH   := 16.0
## Ring flip (전략 포인트 ↔ 턴 넘기기) duration.
const FLIP_DUR     := 0.30
## Ring re-fill duration when the point total changes.
const VALUE_DUR    := 0.22
## Ring starts at 12 o'clock; positive sweep = clockwise, negative = flipped.
const START_ANGLE  := -PI * 0.5
const ARC_SEGMENTS := 72

const TRACK_COLOR    := Color(0.16, 0.16, 0.20, 0.95)
const BG_COLOR       := Color(0.05, 0.05, 0.08, 0.92)
const RIM_COLOR      := Color(0.30, 0.30, 0.38, 0.90)
const BUTTON_COLOR   := Color(1.00, 0.78, 0.18)
const DISABLED_COLOR := Color(0.34, 0.34, 0.40)

const VALUE_FONT_SIZE  := 44
const BUTTON_FONT_SIZE := 20
const BUTTON_TEXT      := "턴\n넘기기"

## Ring colour while showing 전략 포인트. Set per side by HudBuilder.
var fill_color: Color = Color(0.25, 0.60, 1.00)
## Only the player donut reacts to presses.
var interactive: bool = false

var _value: int      = 0
var _max_value: int  = 8
var _flipped: bool   = false
## True only during 작전 단계 — outside it the donut is a pure readout.
var _flip_allowed: bool = false
## Mirrors CardPhaseManager.can_end_card_phase(); a disabled 턴 넘기기 face
## renders grey and swallows presses.
var _end_enabled: bool = false
## Set while a modal overlay (targeting / pick) owns the screen.
var _locked: bool = false
var _sweep: float = 0.0
var _tween: Tween = null
var _label: Label = null


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	pivot_offset = Vector2(RADIUS, RADIUS)
	# Presses are routed through _input, so the node itself never blocks the
	# controls beneath it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	# Offsets included — set_anchors_preset alone keeps the label at its
	# text-sized rect in the top-left corner instead of filling the donut.
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_refresh_label()


## Places the donut so its centre lands on `center` (canvas coordinates).
func set_center(center: Vector2) -> void:
	position = center - Vector2(RADIUS, RADIUS)


## Syncs the readout. `maxv` is the 100% mark (PHASE_THRESHOLD); the number in
## the middle is the raw value, so boost cards can push it past the full ring.
func set_value(v: int, maxv: int) -> void:
	var changed: bool = (v != _value or maxv != _max_value)
	_value = v
	_max_value = maxi(1, maxv)
	_refresh_label()
	if changed and not _flipped:
		_animate_sweep_to(_value_sweep(), VALUE_DUR)


## Whether tapping the donut may flip it into the 턴 넘기기 face at all
## (작전 단계 only). Turning it off flips an already-flipped donut back.
func set_flip_allowed(allowed: bool) -> void:
	_flip_allowed = allowed
	if not allowed:
		set_flipped(false)


## Whether pressing the 턴 넘기기 face actually ends the phase.
func set_end_enabled(enabled: bool) -> void:
	if _end_enabled == enabled:
		return
	_end_enabled = enabled
	queue_redraw()


## Modal overlays lock the donut so a press can't reach it through the dim.
func set_locked(locked: bool) -> void:
	_locked = locked
	if locked:
		set_flipped(false)


func is_flipped() -> bool:
	return _flipped


func set_flipped(flipped: bool) -> void:
	if _flipped == flipped:
		return
	_flipped = flipped
	_animate_sweep_to(-TAU if flipped else _value_sweep(), FLIP_DUR)


# ── Internals ────────────────────────────────────────────────────────────────

func _value_sweep() -> float:
	var ratio: float = clampf(float(_value) / float(_max_value), 0.0, 1.0)
	return ratio * TAU


func _animate_sweep_to(target: float, duration: float) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	(_tween.tween_method(_set_sweep, _sweep, target, duration)
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC))


func _set_sweep(v: float) -> void:
	_sweep = v
	_refresh_label()
	queue_redraw()


# Face swap happens exactly when the ring passes through empty, so the number
# and the 턴 넘기기 caption never overlap the wrong ring direction.
func _refresh_label() -> void:
	if _label == null:
		return
	if _sweep < 0.0:
		_label.text = BUTTON_TEXT
		_label.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
		_label.add_theme_color_override("font_color",
				Color.WHITE if _end_enabled else DISABLED_COLOR.lightened(0.35))
	else:
		_label.text = str(_value)
		_label.add_theme_font_size_override("font_size", VALUE_FONT_SIZE)
		_label.add_theme_color_override("font_color", Color.WHITE)


func _active_fill() -> Color:
	if _sweep < 0.0:
		return BUTTON_COLOR if _end_enabled else DISABLED_COLOR
	return fill_color


func _draw() -> void:
	var c := size * 0.5
	var ring_r: float = RADIUS - RING_WIDTH * 0.5
	draw_circle(c, ring_r - RING_WIDTH * 0.5 + 1.0, BG_COLOR)
	draw_arc(c, ring_r, 0.0, TAU, ARC_SEGMENTS, TRACK_COLOR, RING_WIDTH, true)
	if absf(_sweep) > 0.0005:
		draw_arc(c, ring_r, START_ANGLE, START_ANGLE + _sweep, ARC_SEGMENTS,
				_active_fill(), RING_WIDTH, true)
	draw_arc(c, RADIUS, 0.0, TAU, ARC_SEGMENTS, RIM_COLOR, 2.0, true)


func _input(event: InputEvent) -> void:
	if not interactive:
		return
	var press_pos := Vector2.ZERO
	var pressed: bool = false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed = true
			press_pos = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch and event.pressed:
		pressed = true
		press_pos = (event as InputEventScreenTouch).position
	if not pressed:
		return
	if not _hits(press_pos):
		# Any press outside the donut drops the 턴 넘기기 face. The event is
		# left unhandled so whatever was actually clicked still reacts.
		set_flipped(false)
		return
	if _locked:
		return
	# Inside the donut: swallow the press either way so hand cards / the
	# battlefield underneath never see it.
	get_viewport().set_input_as_handled()
	if _flipped:
		if _end_enabled:
			set_flipped(false)
			end_turn_pressed.emit()
		return
	if _flip_allowed:
		set_flipped(true)


func _hits(point: Vector2) -> bool:
	var rect := get_global_rect()
	return rect.get_center().distance_to(point) <= RADIUS
