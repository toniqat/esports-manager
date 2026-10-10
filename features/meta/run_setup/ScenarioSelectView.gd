class_name ScenarioSelectView
extends Control

# Full-screen scenario (league) pick, shown INSIDE the lobby (`features/meta/lobby/`). The lobby
# keeps its level disc + settings disc drawn above this view and slides its wallet / nav away while
# it is open. **Layout / look live in `UI_View_ScenarioSelectView.tscn`**; this script fills data,
# places the art and runs the animations.
#
#   art (enters at the whole viewport height incl. notch band + bottom inset, cover-cropped so the
#        main character's face sits mid-screen; once the slabs are in it zooms out to the band
#        between them, its top / bottom edges tucked ART_TUCK under the slabs — `_set_zoom`)
#   giant dark slab (`%Slab`, a plain rectangle far larger than the screen) rotated so its top edge
#   reads as a diagonal; it swings in counter-clockwise. A second one (`%TopSlab`) is the same
#   slab turned 180° along the top — parallel edge, about half as tall — and swings in with it.
#   The contents do NOT rotate — they sit at their final place and fade in as the slab arrives:
#       [salary-cap card]              [‹]  league logo  [›]
#                                           league name
#                                           • ━ •  (index pills)
#       bar: 뒤로 (1) / 시나리오 선택 (2)
#   black wipe (`ScenarioWipe`, last child — over all of this view's UI, under the lobby top bar so
#   its level / settings discs stay visible): black grows from one edge until the screen is black,
#   holds, the content swaps, black recedes off the opposite edge. Used for open and close; a
#   league change runs the same wipe on `%ArtWipe`, which covers the art only (under the slabs).
#   The logo sits half over the slab edge (`_place_league`).
#
# One scenario is shown at a time; ‹ / › (or a horizontal swipe on the art) step through
# `RunRules.scenarios()` (first row: no ‹, last row: no ›). Art, logo and focus come from
# `scenarios.csv` (`art`, `logo`, `art_focus_x`).

signal back_requested
signal scenario_chosen(scenario_id: int)
## Emitted when `close()` has finished (view hidden).
signal closed

const SCENE_PATH: String = "res://features/meta/run_setup/UI_View_ScenarioSelectView.tscn"

const WIPE_IN_SEC: float = 0.32     # black sweeps in until the screen is black (linear; the shader eases)
const WIPE_HOLD_SEC: float = 0.10   # fully black beat (the swap happens at its start)
const WIPE_OUT_SEC: float = 0.32    # black keeps travelling and leaves off the far edge
const SWING_SEC: float = 0.60       # slab swing in (open)
const CLOSE_SEC: float = 0.55       # close: slabs out, art zoom in and wipe in — all together
const SWING_DELAY: float = 0.14     # open: the swing starts this far into the wipe-out (seen, not under black)
const SWING_ANGLE: float = 0.55     # rad, extra clockwise angle of the slab while swung out
const SWING_DROP: float = 260.0     # px the pivot also drops while swung out
const SWING_PIVOT := Vector2(-600.0, 600.0)  # pivot: left of the screen / below the bottom edge
const CONTENT_FADE_AT: float = 0.72 # content fade-in starts at this fraction of the swing
const CONTENT_FADE_SEC: float = 0.22
const CONTENT_OUT_SEC: float = 0.16
const SLAB_EDGE_LEFT: float = 260.0   # slab top edge height above the safe bottom at the left screen edge
const SLAB_SLOPE: float = 130.0 / 1080.0  # edge rise per px to the right (fixed angle on every width)
const TOP_EDGE_RIGHT: float = 100.0 # top slab: lower edge this far below the safe top at the RIGHT edge,
									# falling SLAB_SLOPE per px to the left (parallel to the bottom edge)
const ART_TUCK: float = 10.0        # zoomed-out art: its top / bottom edges sit this far past the slabs'
									# notches (top slab's right end, bottom slab's left end)
const ZOOM_AT: float = 0.25         # open: art zoom-out starts at this fraction of the slab swing ...
const ZOOM_SEC: float = 0.50        # ... and runs this long (cubic in-out — trails the slabs, ease-out)
const LEAGUE_SLIDE: float = 90.0    # league change: logo / name slide this far while fading
const DOT_SEC: float = 0.40         # league change: the current-pill highlight glides to the next pill
const TIP_GAP: float = 14.0         # salary-cap tooltip sits this far above the pill
const TIP_EDGE: float = 16.0        # ... and at least this far inside the safe area
const SLAB_LEAD: float = 500.0      # slab corner sits this far before the left screen edge (along the edge)
const SWIPE_MIN: float = 110.0      # px of horizontal drag that counts as a swipe on the art
const DOT_W: float = 14.0           # league index pill width (current one: DOT_ON_W)
const DOT_ON_W: float = 40.0
const TOP_SHADE_H: float = 260.0

var selected_id: int = 0

var _rows: Array = []               # RunRules.scenarios()
var _index: int = 0                 # position of selected_id in _rows
var _busy: bool = false             # open / close / swap animation running — input ignored
var _tween: Tween
var _pivot_home := Vector2.ZERO    # %SlabPivot position in its final pose (_place_slab)
var _top_pivot_home := Vector2.ZERO  # %TopSlabPivot position in its final pose
var _zoom: float = 0.0              # art: 0 = full viewport height, 1 = framed between the slabs
var _view_top: float = 0.0          # this view's top in the viewport (the lobby indents it)
var _swing: float = 0.0             # current slab swing (0 = in place, 1 = swung out)
var _drag_from: Variant = null      # swipe start (Vector2) or null
var _ui_tween: Tween                # league change: logo / name slide-out + pill glide
var _league_home: Dictionary = {}   # %Logo / %LogoShadow / %LeagueName → scene x


static func create() -> ScenarioSelectView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ScenarioSelectView


func _ready() -> void:
	_rows = RunRules.scenarios()
	OutgameTheme.fit_bottom_bar(%Bar, %Safe)
	# The pill shares the bar row (vertically centred on it).
	var bar: Control = %Bar
	var pill: Control = %CapPill
	var pill_h: float = pill.offset_bottom - pill.offset_top
	pill.offset_top = (bar.offset_top + bar.offset_bottom - pill_h) * 0.5
	pill.offset_bottom = pill.offset_top + pill_h
	pill.pressed.connect(_show_cap_tip)
	(%TipCatcher as Button).pressed.connect(_hide_cap_tip)
	_build_dots()
	for n in [%Logo, %LogoShadow, %LeagueName]:
		_league_home[n] = (n as Control).position.x
	resized.connect(_fit_viewport)
	get_viewport().size_changed.connect(_fit_viewport)
	(%ArtClip as Control).resized.connect(_layout_art)
	(%PrevButton as Button).pressed.connect(func() -> void: _step(-1))
	(%NextButton as Button).pressed.connect(func() -> void: _step(1))
	(%FloatingBarButton_Back as Button).pressed.connect(_on_back_pressed)
	(%FloatingBarButton_Choose as Button).pressed.connect(_on_choose_pressed)
	(%ArtClip as Control).gui_input.connect(_on_art_input)
	_fit_viewport.call_deferred()
	if UiPreview.is_standalone(self):
		_fill_preview()


## Show the view on `scenario_id`; `animate` = black wipe over everything, the art underneath is
## revealed as it recedes while the slab swings in and the contents fade in.
func open(scenario_id: int = 0, animate: bool = true) -> void:
	_kill_tween()
	_index = _index_of(scenario_id)
	selected_id = _row_id(_index)
	_show_row(_index)
	visible = true
	_fit_viewport()
	if not animate:
		_set_art_shown(true)
		_set_swing(0.0)
		_set_zoom(1.0)
		_set_content(1.0)
		_busy = false
		return
	_busy = true
	_set_art_shown(false)
	_set_swing(1.0)
	_set_zoom(0.0)
	_set_content(0.0)
	_tween = _wipe(true, func() -> void: _set_art_shown(true))
	# Runs alongside the wipe-out: slabs swing in, contents fade in place near its end; the art
	# zooms out behind the arriving slabs (starts ZOOM_AT into the swing, trails its ease-out).
	_tween.tween_method(_set_swing, 1.0, 0.0, SWING_SEC).set_delay(SWING_DELAY) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_content, 0.0, 1.0, CONTENT_FADE_SEC) \
			.set_delay(SWING_DELAY + SWING_SEC * CONTENT_FADE_AT)
	_tween.tween_method(_set_zoom, 0.0, 1.0, ZOOM_SEC).set_delay(SWING_DELAY + SWING_SEC * ZOOM_AT) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.chain().tween_callback(func() -> void: _busy = false)


## Everything starts at once: the contents fade out (`CONTENT_OUT_SEC`) while, for `CLOSE_SEC`, the
## slabs swing out CLOCKWISE along the open path (cubic ease-in), the art zooms back in to the full
## viewport height (cubic ease-out — always ahead of the slabs, so no margin shows as they leave)
## and the black wipe sweeps in from the left. Hold, the art goes, the wipe recedes onto the lobby.
## Hides itself and emits `closed` at the very end.
func close(animate: bool = true) -> void:
	_kill_tween()
	if not animate or not visible:
		visible = false
		_busy = false
		closed.emit()
		return
	_busy = true
	var t := create_tween()
	_tween = t
	t.tween_method(_set_content, 1.0, 0.0, CONTENT_OUT_SEC)
	t.parallel().tween_method(_set_swing, _swing, 1.0, CLOSE_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.parallel().tween_method(_set_zoom, _zoom, 0.0, CLOSE_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_method(_set_wipe.bind(false), 0.0, 1.0, CLOSE_SEC).set_trans(Tween.TRANS_LINEAR)
	t.tween_callback(func() -> void: _set_art_shown(false))
	t.tween_interval(WIPE_HOLD_SEC)
	t.tween_method(_set_wipe.bind(false), 1.0, 2.0, WIPE_OUT_SEC) \
			.set_trans(Tween.TRANS_LINEAR)
	t.tween_callback(func() -> void:
		visible = false
		_busy = false
		closed.emit())


# ── Data ─────────────────────────────────────────────────────────────────────
func _index_of(scenario_id: int) -> int:
	for i in _rows.size():
		if int((_rows[i] as Dictionary).get("id", -1)) == scenario_id:
			return i
	return 0


func _row_id(i: int) -> int:
	if i < 0 or i >= _rows.size():
		return 0
	return int((_rows[i] as Dictionary).get("id", 0))


func _row(i: int) -> Dictionary:
	return _rows[i] if i >= 0 and i < _rows.size() else {}


## Fills art, logo, name, cap card, pills and arrows for row `i` — no animation (`dots = false`:
## leave the pills to a running glide, `_glide_dots`).
func _show_row(i: int, dots: bool = true) -> void:
	var row: Dictionary = _row(i)
	var art: TextureRect = %Art
	art.texture = _load_tex(String(row.get("art", "")))
	art.set_meta(&"focus_x", float(row.get("art_focus_x", 0.5)))
	_layout_art()
	var logo: TextureRect = %Logo
	logo.texture = _load_tex(String(row.get("logo", "")))   # missing file → empty slot, no jump
	(%LogoShadow as TextureRect).texture = logo.texture
	(%LeagueName as Label).text = Loc.t(String(row.get("name_key", "")))  # l10n-dynamic: scenario.*.name
	var cap: int = int(row.get("salary_cap", 0))
	(%CapValue as Label).text = Loc.grouped(cap)
	_fit_pill.call_deferred()
	if dots:
		_refresh_dots()
	_refresh_arrows()


## One index pill per scenario row: the scene's first `%Dots` child is the template.
func _build_dots() -> void:
	var dots: Control = %Dots
	var tpl: Control = dots.get_child(0) as Control
	for i in range(1, _rows.size()):
		dots.add_child(tpl.duplicate())
	dots.visible = _rows.size() > 1


func _refresh_dots() -> void:
	var dots: Control = %Dots
	for i in dots.get_child_count():
		var d: Control = dots.get_child(i) as Control
		var on: bool = i == _index
		d.theme_type_variation = &"ScenarioSelectDotOn" if on else &"ScenarioSelectDot"
		d.custom_minimum_size.x = DOT_ON_W if on else DOT_W


## Pill glide `from` → `to` at progress p (0 → 1): the long pill shrinks while the next one grows
## (the centred row keeps its width, so the highlight reads as sliding over); the accent colour
## hands over at the halfway point.
func _glide_dots(p: float, from: int, to: int) -> void:
	var dots: Control = %Dots
	for i in dots.get_child_count():
		var d: Control = dots.get_child(i) as Control
		var w: float = DOT_W
		if i == from:
			w = lerpf(DOT_ON_W, DOT_W, p)
		elif i == to:
			w = lerpf(DOT_W, DOT_ON_W, p)
		d.custom_minimum_size.x = w
		var on: bool = i == (to if p >= 0.5 else from)
		d.theme_type_variation = &"ScenarioSelectDotOn" if on else &"ScenarioSelectDot"


## League block slide: v = 0 home, ±1 = LEAGUE_SLIDE to the right / left and fully transparent.
func _set_league_shift(v: float) -> void:
	for n in _league_home:
		var c: Control = n
		c.position.x = float(_league_home[n]) + v * LEAGUE_SLIDE
		c.modulate.a = 1.0 - absf(v)


func _refresh_arrows() -> void:
	# Hidden but still laid out (modulate, not visible) so the logo / name never shift.
	var has_prev: bool = _index > 0
	var has_next: bool = _index < _rows.size() - 1
	for spec in [[%PrevButton, has_prev], [%NextButton, has_next]]:
		var b: Button = spec[0]
		var on: bool = spec[1]
		b.disabled = not on
		b.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
		b.modulate.a = 1.0 if on else 0.0


static func _load_tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# ── Art ──────────────────────────────────────────────────────────────────────
## Backdrop, art clip, top shade and wipe span the WHOLE viewport — notch band and bottom inset
## included — wherever the host put this view (the lobby indents its root to the safe top). Then the
## slab and the league block are re-placed.
func _fit_viewport() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var top: float = get_global_rect().position.y
	_view_top = top
	var below: float = vp.y - (top + size.y)
	for n in [%Backdrop, %ArtClip, %ArtWipe, %Wipe, %CapTip]:
		var c: Control = n
		c.offset_top = -top
		c.offset_bottom = below
	var shade: Control = %TopShade
	shade.offset_top = -top
	shade.offset_bottom = -top + TOP_SHADE_H
	_layout_art()
	_place_slab()
	_place_league()


## Height of the slab's top edge above the safe bottom at view x (final pose).
func _edge_h(x: float) -> float:
	return SLAB_EDGE_LEFT + x * SLAB_SLOPE


## Top slab: its lower edge's distance below the view top (= safe top) at view x (final pose).
func _top_edge_h(x: float) -> float:
	return TOP_EDGE_RIGHT + (size.x - x) * SLAB_SLOPE


## Final pose of the slabs. Bottom: its top edge rises from SLAB_EDGE_LEFT above the safe bottom at
## the left screen edge at a fixed angle (SLAB_SLOPE); the rectangle (scene size, far larger than
## the screen) hangs below that edge, its corner SLAB_LEAD before the left edge — all other edges
## are off-screen. Placed under %SlabPivot (off the bottom-left corner), which the swing rotates.
## Top: the same rectangle turned 180° — it hangs ABOVE a parallel edge `_top_edge_h` below the
## safe top, its corner SLAB_LEAD past the right edge, under %TopSlabPivot (off the top-right
## corner = the bottom pivot mirrored through the screen centre).
func _place_slab() -> void:
	var w: float = size.x
	var safe_bottom: float = size.y - OutgameTheme.bottom_inset()
	var left := Vector2(0.0, safe_bottom - SLAB_EDGE_LEFT)
	var right := Vector2(w, safe_bottom - _edge_h(w))
	var dir: Vector2 = (right - left).normalized()
	var corner: Vector2 = left - dir * SLAB_LEAD
	_pivot_home = Vector2(SWING_PIVOT.x, size.y + SWING_PIVOT.y)
	var slab: Control = %Slab
	slab.pivot_offset = Vector2.ZERO
	slab.rotation = dir.angle()
	slab.position = corner - _pivot_home
	var top_right := Vector2(w, _top_edge_h(w))
	_top_pivot_home = Vector2(w - SWING_PIVOT.x, -SWING_PIVOT.y)
	var top_slab: Control = %TopSlab
	top_slab.pivot_offset = Vector2.ZERO
	top_slab.rotation = dir.angle() + PI
	top_slab.position = top_right + dir * SLAB_LEAD - _top_pivot_home
	_set_swing(_swing)


## Puts the league block so the logo's centre sits ON the slab edge at the logo's x (half over the
## art, half over the slab). Only the block's vertical offsets move; its inner layout is the scene's.
func _place_league() -> void:
	var league: Control = %League
	var logo: Control = %Logo
	var h: float = league.offset_bottom - league.offset_top
	var cx: float = size.x + league.offset_left + (logo.offset_left + logo.offset_right) * 0.5
	var cy: float = (logo.offset_top + logo.offset_bottom) * 0.5
	league.offset_top = -_edge_h(cx) - cy
	league.offset_bottom = league.offset_top + h


## Pill width follows its content (icon + number), left edge fixed.
func _fit_pill() -> void:
	var pill: Control = %CapPill
	var row: Control = pill.get_node("Row")
	var w: float = row.get_combined_minimum_size().x + row.offset_left - row.offset_right
	pill.offset_right = pill.offset_left + w


## Salary-cap tooltip above the pill (left-aligned with it, clamped inside the safe area). The next
## tap anywhere hits %TipCatcher, which closes it and swallows that tap.
func _show_cap_tip() -> void:
	if _busy:
		return
	var tip: Control = %CapTip
	var card: Control = %TipCard
	card.modulate.a = 0.0
	tip.visible = true
	# The wrapped label settles its height only once it has its width: give the card its width,
	# let one layout pass run, then shrink it to the now-correct minimum height.
	card.size = Vector2(card.custom_minimum_size.x, 0.0)
	await get_tree().process_frame
	if not tip.visible:
		return
	card.size = Vector2(card.custom_minimum_size.x, 0.0)
	await get_tree().process_frame
	if not tip.visible:
		return
	var pill: Rect2 = (%CapPill as Control).get_global_rect()
	var safe: Rect2 = ScreenMetrics.safe_rect()
	var origin: Vector2 = tip.get_global_rect().position
	var x: float = clampf(pill.position.x, safe.position.x + TIP_EDGE, safe.end.x - TIP_EDGE - card.size.x)
	var y: float = maxf(pill.position.y - TIP_GAP - card.size.y, safe.position.y + TIP_EDGE)
	card.position = Vector2(x, y) - origin
	card.modulate.a = 1.0


func _hide_cap_tip() -> void:
	(%CapTip as Control).visible = false


## Cover-fit between two framings, blended by `_zoom`: 0 = art height = `%ArtClip` height
## (= viewport height); 1 = the band between the slabs — from ART_TUCK above the top slab's highest
## edge point (its right end) to ART_TUCK below the bottom slab's lowest (its left end), so the
## art's top / bottom edges always sit under a slab. Width by aspect (wider only if the screen is
## wider than the art), x so the focus point sits mid-screen, clamped so no side gap. Both framings
## cover the screen sides and the band, so every blend between them does too.
func _layout_art() -> void:
	var art: TextureRect = %Art
	var clip: Vector2 = (%ArtClip as Control).size
	if art.texture == null or clip.y <= 0.0:
		return
	var full: Rect2 = _art_rect(0.0, clip.y)
	var safe_bottom: float = size.y - OutgameTheme.bottom_inset()
	# Band in %ArtClip coords (the clip starts _view_top above this view).
	var band_top: float = _view_top + TOP_EDGE_RIGHT - ART_TUCK
	var band_bottom: float = _view_top + safe_bottom - SLAB_EDGE_LEFT + ART_TUCK
	var framed: Rect2 = _art_rect(band_top, band_bottom)
	art.size = full.size.lerp(framed.size, _zoom)
	art.position = full.position.lerp(framed.position, _zoom)


## Cover-fit rect of the art for the vertical span y0 .. y1 of `%ArtClip` (centred on it).
func _art_rect(y0: float, y1: float) -> Rect2:
	var art: TextureRect = %Art
	var clip: Vector2 = (%ArtClip as Control).size
	var tex: Vector2 = art.texture.get_size()
	var s: float = maxf((y1 - y0) / tex.y, clip.x / tex.x)
	var sz: Vector2 = tex * s
	var focus: float = float(art.get_meta(&"focus_x", 0.5))
	var x: float = clampf(clip.x * 0.5 - focus * sz.x, clip.x - sz.x, 0.0)
	return Rect2(Vector2(x, (y0 + y1 - sz.y) * 0.5), sz)


func _set_zoom(z: float) -> void:
	_zoom = z
	_layout_art()


func _set_art_shown(on: bool) -> void:
	(%Backdrop as CanvasItem).visible = on
	(%ArtLayer as CanvasItem).visible = on


# ── Interaction ──────────────────────────────────────────────────────────────
func _step(d: int) -> void:
	if _busy:
		return
	var to: int = clampi(_index + d, 0, _rows.size() - 1)
	if to == _index:
		return
	_swap_to(to, d)


## League change: the black band sweeps in over the ART only (`%ArtWipe`, under the slabs) from the
## side we are heading to (› = from the right), the row swaps while the art is covered, the band
## leaves on the far side. Slabs and bar stay in view. Meanwhile the logo + name slide out the way
## we are heading (› = to the left) and fade (during the wipe-in), the new ones slide in from the
## other side and fade in (during the wipe-out), and the index highlight glides to the next pill.
func _swap_to(i: int, d: int) -> void:
	_kill_tween()
	_busy = true
	var from: int = _index
	_index = i
	selected_id = _row_id(i)
	var dir: float = signf(float(d))
	_ui_tween = create_tween().set_parallel(true)
	_ui_tween.tween_method(_set_league_shift, 0.0, -dir, WIPE_IN_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_ui_tween.tween_method(_glide_dots.bind(from, i), 0.0, 1.0, DOT_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var on_covered := func() -> void:
		_show_row(i, false)
		_set_league_shift(dir)
	_tween = _wipe(d > 0, on_covered, %ArtWipe)
	_tween.tween_method(_set_league_shift, dir, 0.0, WIPE_OUT_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_callback(func() -> void: _busy = false)


func _on_art_input(ev: InputEvent) -> void:
	if _busy:
		return
	var press: bool = false
	var release: bool = false
	var pos := Vector2.ZERO
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		press = ev.is_pressed()
		release = not press
		pos = (ev as InputEventMouseButton).position
	elif ev is InputEventScreenTouch:
		press = ev.is_pressed()
		release = not press
		pos = (ev as InputEventScreenTouch).position
	if press:
		_drag_from = pos
	elif release and _drag_from != null:
		var dx: float = pos.x - (_drag_from as Vector2).x
		_drag_from = null
		if absf(dx) >= SWIPE_MIN:
			# Drag left = next (the band follows the finger: enters on the right).
			_step(-1 if dx > 0.0 else 1)


func _on_back_pressed() -> void:
	if _busy:
		return
	back_requested.emit()


func _on_choose_pressed() -> void:
	if _busy:
		return
	scenario_chosen.emit(selected_id)


# ── Animation helpers ────────────────────────────────────────────────────────
## Wipe in (0 → 1: black grows from the start edge), `on_covered`, hold, wipe out (1 → 2: black
## recedes off the far edge) on `node` (null = `%Wipe`, the whole view; `%ArtWipe` = art only).
## Returns the tween in parallel mode — steps added right after this call run alongside the
## wipe-out; `.chain()` to run after it.
func _wipe(from_right: bool, on_covered: Callable, node: ScenarioWipe = null) -> Tween:
	var t := create_tween()
	t.tween_method(_set_wipe.bind(from_right, node), 0.0, 1.0, WIPE_IN_SEC) \
			.set_trans(Tween.TRANS_LINEAR)
	t.tween_callback(on_covered)
	t.tween_interval(WIPE_HOLD_SEC)
	t.tween_method(_set_wipe.bind(from_right, node), 1.0, 2.0, WIPE_OUT_SEC) \
			.set_trans(Tween.TRANS_LINEAR)
	t.set_parallel(true)
	return t


func _set_wipe(p: float, from_right: bool, node: ScenarioWipe = null) -> void:
	var w: ScenarioWipe = node if node != null else %Wipe
	w.from_right = from_right
	w.progress = p


## Slab swing: 0 = final tilted pose, 1 = swung out — the bottom slab rotated SWING_ANGLE further
## clockwise around %SlabPivot and dropped SWING_DROP (below the screen), the top slab the mirror
## (same clockwise turn around %TopSlabPivot, raised SWING_DROP — above the screen). 1 → 0 reads
## as both swinging counter-clockwise into place. Only the slabs move; the contents never rotate
## (`_set_content` fades them).
func _set_swing(t: float) -> void:
	_swing = t
	var pivot: Control = %SlabPivot
	pivot.position = _pivot_home + Vector2(0.0, SWING_DROP * t)
	pivot.rotation = SWING_ANGLE * t
	pivot.visible = t < 0.999
	var top: Control = %TopSlabPivot
	top.position = _top_pivot_home - Vector2(0.0, SWING_DROP * t)
	top.rotation = SWING_ANGLE * t
	top.visible = t < 0.999


## Contents (info row + bottom bar) opacity, in place; hidden (no taps) at 0.
func _set_content(a: float) -> void:
	var c: Control = %Content
	c.modulate.a = a
	c.visible = a > 0.001


func _kill_tween() -> void:
	_hide_cap_tip()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _ui_tween != null and _ui_tween.is_valid():
		_ui_tween.kill()
	_ui_tween = null
	_set_wipe(0.0, true)
	_set_wipe(0.0, true, %ArtWipe)
	if not _league_home.is_empty():
		_set_league_shift(0.0)


## F6 standalone preview (`resources/UiPreview.gd`) — lobby-like indent, opens scenario 0
## animated; back / choose / closed only print. Back closes the view, choose re-opens it.
func _fill_preview() -> void:
	UiPreview.stage(self)
	ScreenMetrics.indent_to_safe_top(self)
	UiPreview.trace(back_requested)
	UiPreview.trace(scenario_chosen)
	UiPreview.trace(closed)
	back_requested.connect(func() -> void: close())
	closed.connect(func() -> void: open.call_deferred(selected_id))
	open.call_deferred(0, true)
