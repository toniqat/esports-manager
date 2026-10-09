class_name EventResultBar
extends Control

# One progress bar of an `EventResultPanel` row: the value before → after an event result.
# `_draw` widget (placed as the `Bar` node of the panel's row template); colours are
# `OutgameTheme` palette constants, the track / fill shape is the shared `ProgressTrack` box.
#
# Values are in **bars** (`MentalEvents.result_blocks` row `from` / `to`):
# - `stack` — 0..1 = the bar, 1..2 = overflow drawn again from the left in dark `NEGATIVE`
#   (stress over the threshold up to `STRESS_MAX`).
# - `wrap` — the whole part counts filled bars (trust level up, awakening gauge crossed): the
#   fill runs to the end, restarts at 0 and goes on. `end_full` = stop on a full bar (top level).
# A gain paints the added part in the delta colour (`good` → `POSITIVE`, else `NEGATIVE`); a
# loss leaves the removed part as a faint ghost of that colour. `play` animates from → to.

## Run time of the before → after fill (seconds) and the wait before it (the panel fades in).
const PLAY_SEC: float = 0.7
const DELAY_SEC: float = 0.3
## Alpha of the ghost that marks a removed part.
const GHOST_ALPHA: float = 0.35
## Overflow layer is `NEGATIVE` darkened by this much, so an unwelcome gain (also red) on top
## of it still reads as the added part.
const OVER_DARKEN: float = 0.3

var _from: float = 0.0
var _to: float = 0.0
var _wrap: bool = false
var _end_full: bool = false
var _good: bool = true
var _shown: float = 0.0
var _tween: Tween = null
var _sb: StyleBoxFlat = null


## Show `row` (`MentalEvents.result_blocks` row). `animate` = run the fill from `from` to `to`
## (only inside the tree), else draw the end state at once.
func play(row: Dictionary, animate: bool = true) -> void:
	_from = maxf(0.0, float(row.get("from", 0.0)))
	_to = maxf(0.0, float(row.get("to", 0.0)))
	_wrap = String(row.get("mode", "stack")) == "wrap"
	_end_full = bool(row.get("end_full", false))
	_good = bool(row.get("good", true))
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if animate and is_inside_tree() and not is_equal_approx(_from, _to):
		_set_shown(_from)
		_tween = create_tween()
		_tween.tween_interval(DELAY_SEC)
		_tween.tween_method(_set_shown, _from, _to, PLAY_SEC) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_set_shown(_to)


func _set_shown(v: float) -> void:
	_shown = v
	queue_redraw()


func _draw() -> void:
	_box(1.0, OutgameTheme.SURFACE_SUNK)
	var dc: Color = OutgameTheme.POSITIVE if _good else OutgameTheme.NEGATIVE
	var ghost := Color(dc, GHOST_ALPHA)
	var gain: bool = _to >= _from
	var over: Color = OutgameTheme.NEGATIVE.darkened(OVER_DARKEN)
	if _wrap:
		var lap: float = floorf(_shown)
		var frac: float = _shown - lap
		if _end_full and is_equal_approx(_shown, _to) and frac < 0.0001 and _shown > 0.0:
			lap -= 1.0
			frac = 1.0
		if gain:
			var start: float = clampf(_from - lap, 0.0, 1.0) if lap <= floorf(_from) else 0.0
			_box(frac, dc)
			_box(minf(start, frac), OutgameTheme.ACCENT)
		else:
			_box(clampf(_from - lap, 0.0, 1.0), ghost)
			_box(frac, OutgameTheme.ACCENT)
		return
	# stack: base bar, then the overflow layer over it.
	if gain:
		_box(minf(_shown, 1.0), dc)
		_box(minf(minf(_from, _shown), 1.0), OutgameTheme.ACCENT)
		if _shown > 1.0:
			_box(_shown - 1.0, dc)
			_box(clampf(_from - 1.0, 0.0, _shown - 1.0), over)
	else:
		_box(minf(_from, 1.0), ghost)
		_box(minf(_shown, 1.0), OutgameTheme.ACCENT)
		if _shown > 1.0:
			_box(_from - 1.0, ghost)
			_box(_shown - 1.0, over)


## A rounded box over the first `share` (0..1) of the bar.
func _box(share: float, color: Color) -> void:
	var w: float = clampf(share, 0.0, 1.0) * size.x
	if w <= 0.5:
		return
	if _sb == null:
		_sb = StyleBoxFlat.new()
		_sb.anti_aliasing = true
	_sb.bg_color = color
	_sb.set_corner_radius_all(mini(OutgameTheme.BAR_RADIUS, int(size.y * 0.5)))
	draw_style_box(_sb, Rect2(Vector2.ZERO, Vector2(w, size.y)))
