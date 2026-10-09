class_name CostDonut
extends Control

## 전략 포인트 (작전 점수) gauge. One instance per side. The ring is the
## strategy octagon (`StrategyIcon`, pointy top / bottom): each of the 8 faces
## is one point of PHASE_THRESHOLD, filled clockwise from the **upper-right
## face**. Points 9–16 fill a second, brighter lap over the same faces; past 16
## only the number grows.
##
##  - player: sits at the top-left of the hand row, above the Deck counter,
##    and opens the 턴 넘기기 panel (`TurnEndPanel`, see below).
##  - enemy: mirrors the same look at the top-left of the screen, under the
##    left edge of the AI hand peek. Never interactive.
##
## Player interaction:
##   1. tap the donut during 작전 단계 → the donut slides out to the left and the
##      wide 턴 넘기기 panel (`TurnEndPanel`) slides in in its place.
##   2. press and hold the panel `TurnEndPanel.HOLD_SEC` → ends the 작전 단계
##      (only while `set_end_enabled(true)`; disabled = grey, a hold does nothing).
##   3. press outside the panel's hit zone → the panel slides out, the donut back in.
##
## Input is handled in `_input` (not `_gui_input`) — hand cards call accept_event(),
## so a `_gui_input`/`_unhandled_input` pair would never see the outside press.
## Presses are read through `PointerPress`: with mouse-from-touch emulation one tap
## arrives as a touch **and** an emulated mouse press, and reading both used to flip
## the old donut and end the turn on a single tap.

## Emitted when the 턴 넘기기 panel's hold completes and ending is allowed.
signal end_turn_pressed

const RADIUS       := 56.0
const RING_WIDTH   := 16.0
## Donut slide out / back in when the 턴 넘기기 panel opens / closes.
const SLIDE_DUR    := 0.22
## Extra room past the screen's left edge when slid out.
const OFFSCREEN_GAP := 24.0
## Ring re-fill duration when the point total changes.
const VALUE_DUR    := 0.22
## Sweep is in radians of one lap (TAU = 8 faces), clockwise from the 12 o'clock vertex.
## Laps shown before the gauge stops growing (16 points at threshold 8).
const MAX_LAPS     := 2.0
## Fraction of each face's length left empty at both ends — the gap that makes
## the faces read as separate segments.
const FACE_GAP     := 0.06

const TRACK_COLOR    := Color(0.16, 0.16, 0.20, 0.95)
const BG_COLOR       := Color(0.05, 0.05, 0.08, 0.92)
const RIM_COLOR      := Color(0.30, 0.30, 0.38, 0.90)
## Second-lap faces are `fill_color` lightened by this much.
const OVERFLOW_LIGHTEN := 0.55

const VALUE_FONT_SIZE  := 44

## Ring colour while showing 전략 포인트. Set per side by HudBuilder.
var fill_color: Color = Color(0.25, 0.60, 1.00)
## Only the player donut reacts to presses.
var interactive: bool = false

var _value: int      = 0
var _max_value: int  = 8
## The 턴 넘기기 panel is out (the donut slid away).
var _panel_open: bool = false
## True only during 작전 단계 — outside it the donut is a pure readout.
var _flip_allowed: bool = false
## Mirrors CardPhaseManager.can_end_card_phase(); forwarded to the panel (grey,
## a hold does nothing while false).
var _end_enabled: bool = false
## Set while a modal overlay (targeting / pick) owns the screen.
var _locked: bool = false
## Player only — attached by `HudBuilder` (`attach_turn_end_panel`).
var _panel: TurnEndPanel = null
## Canvas position the donut returns to (`set_center`).
var _rest_pos: Vector2 = Vector2.ZERO
var _slide: Tween = null
var _sweep: float = 0.0
var _tween: Tween = null
var _label: Label = null

# ── 손패 미리보기 (`set_preview`) ────────────────────────────────────────────
# 전략 점수를 바꾸는 카드를 끄는 동안 도넛이 **바뀐 뒤의 모습**을 미리 보인다:
# 바깥 하이라이트가 맥박치고, 도넛 위에 더해질 값(`+4` / `-2`)이 뜨고, 가운데
# 숫자가 바뀐 값으로 색이 바뀌어 찍히며 게이지도 그 값까지 차오른다.
const PREVIEW_UP_COLOR   := Color(0.45, 1.00, 0.55)
const PREVIEW_DOWN_COLOR := Color(1.00, 0.45, 0.40)
const PREVIEW_DELTA_FONT := 30
var _preview_on: bool = false
var _preview_delta: int = 0
var _preview_value: int = 0
var _preview_t: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	pivot_offset = Vector2(RADIUS, RADIUS)
	_rest_pos = position
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
	_rest_pos = center - Vector2(RADIUS, RADIUS)
	position = Vector2(_hidden_x() if _panel_open else _rest_pos.x, _rest_pos.y)


## Rest centre in canvas coordinates (the panel and the chips are placed from it).
func rest_center() -> Vector2:
	return _rest_pos + Vector2(RADIUS, RADIUS)


## Player donut: the 턴 넘기기 panel it opens (`TurnEndPanel`). The panel's hold
## completing becomes `end_turn_pressed`; an outside press brings the donut back.
func attach_turn_end_panel(panel: TurnEndPanel) -> void:
	_panel = panel
	_panel.set_end_enabled(_end_enabled)
	_panel.hold_completed.connect(_on_panel_hold_completed)
	_panel.dismissed.connect(_on_panel_dismissed)


## Syncs the readout. `maxv` is the 100% mark (PHASE_THRESHOLD); the number in
## the middle is the raw value, so boost cards can push it past the full ring.
func set_value(v: int, maxv: int) -> void:
	var changed: bool = (v != _value or maxv != _max_value)
	_value = v
	_max_value = maxi(1, maxv)
	_refresh_label()
	if changed and not _preview_on:
		_animate_sweep_to(_value_sweep(), VALUE_DUR)


## 손패 미리보기. `on` 이면 `delta` 만큼 바뀐 `value_after` 를 미리 보인다.
func set_preview(on: bool, delta: int, value_after: int) -> void:
	if on == _preview_on and delta == _preview_delta and value_after == _preview_value:
		return
	_preview_on = on
	_preview_delta = delta
	_preview_value = value_after
	_preview_t = 0.0
	set_process(on)
	if on:
		set_turn_end_open(false)
	_refresh_label()
	_animate_sweep_to(_value_sweep(), VALUE_DUR)
	queue_redraw()


func _process(delta: float) -> void:
	_preview_t += delta
	queue_redraw()


## Whether tapping the donut may open the 턴 넘기기 panel at all (작전 단계
## only). Turning it off (phase change, modal up) closes an open panel.
func set_flip_allowed(allowed: bool) -> void:
	_flip_allowed = allowed
	if not allowed:
		set_turn_end_open(false)


## Whether holding the 턴 넘기기 panel actually ends the phase.
func set_end_enabled(enabled: bool) -> void:
	if _end_enabled == enabled:
		return
	_end_enabled = enabled
	if _panel != null:
		_panel.set_end_enabled(enabled)


## Modal overlays lock the donut so a press can't reach it through the dim.
func set_locked(locked: bool) -> void:
	_locked = locked
	if locked:
		set_turn_end_open(false)


func is_turn_end_open() -> bool:
	return _panel_open


## Open = the donut slides out left and the panel slides in; closed = the reverse.
func set_turn_end_open(open: bool) -> void:
	if _panel_open == open or (open and _panel == null):
		return
	_panel_open = open
	if _slide != null and _slide.is_running():
		_slide.kill()
	_slide = create_tween()
	(_slide.tween_property(self, "position:x", _hidden_x() if open else _rest_pos.x,
			SLIDE_DUR).set_ease(Tween.EASE_IN if open else Tween.EASE_OUT)
			.set_trans(Tween.TRANS_CUBIC))
	if _panel != null:
		if open:
			_panel.slide_in()
		else:
			_panel.slide_out()


# ── Internals ────────────────────────────────────────────────────────────────

func _hidden_x() -> float:
	return -size.x - OFFSCREEN_GAP


func _value_sweep() -> float:
	var shown: int = _preview_value if _preview_on else _value
	var ratio: float = clampf(float(shown) / float(_max_value), 0.0, MAX_LAPS)
	return ratio * TAU


func _animate_sweep_to(target: float, duration: float) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	(_tween.tween_method(_set_sweep, _sweep, target, duration)
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC))


func _set_sweep(v: float) -> void:
	_sweep = v
	queue_redraw()


func _refresh_label() -> void:
	if _label == null:
		return
	if _preview_on:
		_label.text = str(_preview_value)
		_label.add_theme_font_size_override("font_size", VALUE_FONT_SIZE)
		_label.add_theme_color_override("font_color", _preview_color())
	else:
		_label.text = str(_value)
		_label.add_theme_font_size_override("font_size", VALUE_FONT_SIZE)
		_label.add_theme_color_override("font_color", Color.WHITE)


func _preview_color() -> Color:
	if _preview_delta > 0:
		return PREVIEW_UP_COLOR
	if _preview_delta < 0:
		return PREVIEW_DOWN_COLOR
	return Color.WHITE


func _draw() -> void:
	var c := size * 0.5
	var outer: PackedVector2Array = StrategyIcon.points(c, RADIUS)
	var inner: PackedVector2Array = StrategyIcon.points(c, RADIUS - RING_WIDTH)
	draw_colored_polygon(StrategyIcon.points(c, RADIUS - RING_WIDTH + 1.0), BG_COLOR)
	for i in StrategyIcon.SIDES:
		_draw_face(outer, inner, i, 1.0, TRACK_COLOR, true)
	if absf(_sweep) > 0.0005:
		var faces: float = absf(_sweep) / TAU * float(StrategyIcon.SIDES)
		var cw: bool = _sweep > 0.0
		_draw_lap(outer, inner, minf(faces, float(StrategyIcon.SIDES)), cw, fill_color)
		if faces > float(StrategyIcon.SIDES):
			_draw_lap(outer, inner, faces - float(StrategyIcon.SIDES), cw,
					fill_color.lightened(OVERFLOW_LIGHTEN))
	var rim := outer.duplicate()
	rim.append(outer[0])
	draw_polyline(rim, RIM_COLOR, 2.0, true)
	if _preview_on:
		_draw_preview(c)


## `faces` (fractional) faces of one lap. Clockwise starts at the upper-right
## face (vertex 0 → 1); counter-clockwise at the upper-left (vertex 0 → 7).
func _draw_lap(outer: PackedVector2Array, inner: PackedVector2Array,
		faces: float, cw: bool, col: Color) -> void:
	var n: int = StrategyIcon.SIDES
	for k in ceili(faces):
		var frac: float = clampf(faces - float(k), 0.0, 1.0)
		var face: int = k if cw else n - 1 - k
		_draw_face(outer, inner, face, frac, col, cw)


## One face (vertex `i` → `i + 1`) as a quad between the outer and inner
## octagon, filled `frac` of the way from its start end (`from_start`) or from
## its far end (counter-clockwise fill).
func _draw_face(outer: PackedVector2Array, inner: PackedVector2Array, i: int,
		frac: float, col: Color, from_start: bool) -> void:
	if frac <= 0.0:
		return
	var j: int = (i + 1) % StrategyIcon.SIDES
	var span: float = 1.0 - FACE_GAP * 2.0
	var t0: float
	var t1: float
	if from_start:
		t0 = FACE_GAP
		t1 = FACE_GAP + span * frac
	else:
		t1 = 1.0 - FACE_GAP
		t0 = t1 - span * frac
	var quad := PackedVector2Array([
		outer[i].lerp(outer[j], t0), outer[i].lerp(outer[j], t1),
		inner[i].lerp(inner[j], t1), inner[i].lerp(inner[j], t0)])
	draw_colored_polygon(quad, col)
	var edge := quad.duplicate()
	edge.append(quad[0])
	draw_polyline(edge, col, 1.0, true)


## 미리보기 하이라이트 — 바깥 맥박 팔각 링 + 도형 위 더해질 값.
func _draw_preview(c: Vector2) -> void:
	var col: Color = _preview_color()
	var pulse: float = 0.5 + 0.5 * sin(_preview_t * TAU * 1.4)
	for i in 3:
		var w: float = 4.0 + float(i) * 5.0
		var ring: PackedVector2Array = StrategyIcon.points(c, RADIUS + 3.0 + float(i) * 3.0)
		ring.append(ring[0])
		draw_polyline(ring,
				Color(col.r, col.g, col.b, (0.55 - float(i) * 0.16) * (0.55 + 0.45 * pulse)),
				w, true)
	var font := ThemeDB.fallback_font
	var txt: String = ("+%d" % _preview_delta) if _preview_delta > 0 \
			else (("%d" % _preview_delta) if _preview_delta < 0 else "±0")
	var tsz: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
			PREVIEW_DELTA_FONT)
	var rise: float = 4.0 * pulse
	var at := Vector2(c.x - tsz.x * 0.5, c.y - RADIUS - 14.0 - rise)
	draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
			PREVIEW_DELTA_FONT, 7, Color(0, 0, 0, 0.9))
	draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, PREVIEW_DELTA_FONT, col)


func _input(event: InputEvent) -> void:
	if not interactive or not is_visible_in_tree():
		return
	# While the panel is out it owns every press (hold / outside dismiss).
	if _panel_open:
		return
	if PointerPress.state(event) != PointerPress.PRESS:
		return
	if not _hits(PointerPress.position_of(event)) or _locked:
		return
	# Inside the donut: swallow the press so hand cards / the battlefield
	# underneath never see it.
	get_viewport().set_input_as_handled()
	if _flip_allowed and _panel != null:
		set_turn_end_open(true)
		# 도넛은 Button 이 아니라 `_input` 으로 듣는다 — `HapticUi` 의 자동 배선이
		# 닿지 않는 자리라 여기서 직접 낸다. 판을 연 것뿐 — 아직 아무것도 넘기지 않았다.
		Haptics.play(Haptics.Kind.SELECT)


func _on_panel_hold_completed() -> void:
	if not _end_enabled or not _panel_open:
		return
	set_turn_end_open(false)
	end_turn_pressed.emit()
	# 차례를 넘기는 것은 커밋이다.
	Haptics.play(Haptics.Kind.MEDIUM)


func _on_panel_dismissed() -> void:
	set_turn_end_open(false)


func _hits(point: Vector2) -> bool:
	# The rest spot, not the current one — a donut still sliding back in is
	# already tappable where it will land.
	return rest_center().distance_to(point) <= RADIUS
