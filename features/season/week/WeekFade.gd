class_name WeekFade
extends RefCounted

# ── Fade through black (week screen) ─────────────────────────────────────────
# `through(mid)`: the screen fades to black (`FADE_IN`), `mid` runs while it is black (open /
# close a dialogue, move to the next half of the day or the next day), then the black fades
# away (`HOLD` + `FADE_OUT`). The black is a full-screen STOP `ColorRect` on its own
# `CanvasLayer` under the tree root, so it covers every popup and survives the week view being
# rebuilt or hidden in `mid` (`SeasonHub.goto`). Static only.

const FADE_IN: float = 0.22
const HOLD: float = 0.08
const FADE_OUT: float = 0.32
## Above the week screen's popups (`VisitMenu` 20, dialogs) — the black covers everything.
const LAYER: int = 90

static var _layer: CanvasLayer = null
static var _rect: ColorRect = null
static var _tween: Tween = null
## While black: the time `mid` ran (msec) — `clear_delay` counts from it.
static var _mid_at: int = -1


## Fade to black, run `mid`, fade back. While a fade is already running `mid` simply runs now
## (the running fade covers it).
static func through(mid: Callable) -> void:
	if is_active():
		_run(mid)
		return
	_ensure_layer()
	if _rect == null:
		_run(mid)
		return
	_layer.visible = true
	_rect.modulate.a = 0.0
	_mid_at = -1
	_tween = (Engine.get_main_loop() as SceneTree).create_tween()
	_tween.tween_property(_rect, "modulate:a", 1.0, FADE_IN)
	_tween.tween_callback(func() -> void:
		_mid_at = Time.get_ticks_msec()
		_run(mid))
	_tween.tween_interval(HOLD)
	_tween.tween_property(_rect, "modulate:a", 0.0, FADE_OUT)
	_tween.tween_callback(func() -> void:
		_layer.visible = false
		_mid_at = -1)


## A fade is running (the screen is going black, black, or clearing).
static func is_active() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


## Seconds until the screen is clear again (0 when no fade runs) — an animation started in
## `mid` waits this long so it plays where it can be seen.
static func clear_delay() -> float:
	if not is_active():
		return 0.0
	if _mid_at < 0:
		return FADE_IN + HOLD + FADE_OUT
	var since: float = float(Time.get_ticks_msec() - _mid_at) / 1000.0
	return maxf(0.0, HOLD + FADE_OUT * 0.5 - since)


static func _run(mid: Callable) -> void:
	if mid.is_valid():
		mid.call()


static func _ensure_layer() -> void:
	if _layer != null and is_instance_valid(_layer):
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_layer = CanvasLayer.new()
	_layer.name = "WeekFade"
	_layer.layer = LAYER
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_rect)
	# Deferred: `through` may run while the root is busy adding children (a `_ready`).
	tree.root.add_child.call_deferred(_layer)
