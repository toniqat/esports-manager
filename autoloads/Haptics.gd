extends Node

## Haptic feedback for iOS and Android.
##
## Two layers, use whichever fits:
##
##   Haptics.play(Haptics.Kind.SELECT)   # high level — one call, any platform
##   Haptics.selection()                 # low level — maps 1:1 to the native API
##
## The high-level layer is the one to reach for in game code: it absorbs the
## `enabled` toggle, the platform check and the no-plugin fallback, so call
## sites never branch. Drop to the low-level layer when you want an iOS style
## that has no cross-platform meaning (soft / rigid) or a custom intensity.
##
## Every call is a silent no-op on desktop, so you never need to guard.

# Mirrors HapticsImpactStyle in ios/plugin/haptics/haptics.h and
# HapticsImpactType.fromStyle on Android. Same int, either platform.
const STYLE_LIGHT := 0
const STYLE_MEDIUM := 1
const STYLE_HEAVY := 2
const STYLE_SOFT := 3
const STYLE_RIGID := 4

## What happened, rather than how hard to buzz. Prefer this over the styles.
enum Kind {
	SELECT,   ## a value changed under the finger — tab, filter, snapped tile
	LIGHT,    ## a small confirmed action — button, toggle, card picked up
	MEDIUM,   ## a committed action — confirm, drop, lock in
	HEAVY,    ## a heavy world event — kill, structure destroyed, impact
	SOFT,     ## a soft, diffuse landing (iOS 13+; approximated elsewhere)
	RIGID,    ## a hard, crisp stop (iOS 13+; approximated elsewhere)
	SUCCESS,  ## an outcome resolved in the player's favour
	WARNING,  ## an outcome that needs attention
	ERROR,    ## a rejected action or a loss
}

## Turn this off from a settings screen and persist it yourself. The OS-level
## haptics switch is not readable from Godot, so this is the only toggle the
## player has inside the game.
var enabled: bool = true

var _plugin: Object = null
var _mobile: bool = false
var _warned: bool = false

# duration_ms / amplitude for the Input.vibrate_handheld fallback used when the
# native plugin is missing. Crude by design — this exists so a build without the
# plugin still feels like something, not so it can pass for the real thing.
const _FALLBACK := {
	Kind.SELECT: [10, 0.20],
	Kind.LIGHT: [20, 0.35],
	Kind.MEDIUM: [35, 0.60],
	Kind.HEAVY: [55, 1.00],
	Kind.SOFT: [45, 0.30],
	Kind.RIGID: [15, 1.00],
	Kind.SUCCESS: [60, 0.70],
	Kind.WARNING: [80, 0.80],
	Kind.ERROR: [110, 1.00],
}


func _ready() -> void:
	init()


## Idempotent. Called automatically; exposed for projects that add the autoload
## after startup or reload it.
func init() -> void:
	var os_name := OS.get_name()
	_mobile = os_name == "iOS" or os_name == "Android"
	if _mobile and Engine.has_singleton("Haptics"):
		_plugin = Engine.get_singleton("Haptics")


# --- capability ---------------------------------------------------------------

## True when the native plugin is loaded and the device can actually vibrate.
## Use it to decide whether to *show* a haptics setting, not to guard calls —
## calls are already safe.
func is_supported() -> bool:
	if _plugin == null:
		return false
	return _plugin.is_supported()


## True when the plugin is loaded at all, whatever the hardware reports.
func has_plugin() -> bool:
	return _plugin != null


## Warms the Taptic Engine so the next feedback lands without latency. Worth
## calling a beat ahead — on screen open or on finger-down — because the first
## haptic of a session is otherwise noticeably late. No-op on Android.
func prepare() -> void:
	if _plugin != null:
		_plugin.prepare()


# --- high level ---------------------------------------------------------------

## The call game code should use.
func play(kind: int) -> void:
	if not enabled or not _mobile:
		return

	if _plugin == null:
		_fallback(kind)
		return

	match kind:
		Kind.SELECT: _plugin.selection()
		Kind.LIGHT: _plugin.light()
		Kind.MEDIUM: _plugin.medium()
		Kind.HEAVY: _plugin.heavy()
		Kind.SOFT: _plugin.soft()
		Kind.RIGID: _plugin.rigid()
		Kind.SUCCESS: _plugin.notify_success()
		Kind.WARNING: _plugin.notify_warning()
		Kind.ERROR: _plugin.notify_error()
		_: _plugin.medium()


# --- low level ----------------------------------------------------------------

## intensity is 0..1. Values below 1.0 need iOS 13+ / Android 8+; older
## versions fall back to the nearest fixed-strength effect.
func impact(style: int, intensity: float = 1.0) -> void:
	if not enabled or not _mobile:
		return
	if _plugin == null:
		_fallback(_kind_for_style(style))
		return
	_plugin.impact(style, intensity)


func light() -> void:
	play(Kind.LIGHT)


func medium() -> void:
	play(Kind.MEDIUM)


func heavy() -> void:
	play(Kind.HEAVY)


func soft() -> void:
	play(Kind.SOFT)


func rigid() -> void:
	play(Kind.RIGID)


func selection() -> void:
	play(Kind.SELECT)


func notify_success() -> void:
	play(Kind.SUCCESS)


func notify_warning() -> void:
	play(Kind.WARNING)


func notify_error() -> void:
	play(Kind.ERROR)


# --- internals ----------------------------------------------------------------

func _kind_for_style(style: int) -> int:
	match style:
		STYLE_LIGHT: return Kind.LIGHT
		STYLE_HEAVY: return Kind.HEAVY
		STYLE_SOFT: return Kind.SOFT
		STYLE_RIGID: return Kind.RIGID
		_: return Kind.MEDIUM


func _fallback(kind: int) -> void:
	if not _warned:
		_warned = true
		push_warning("[Haptics] Plugin not found — falling back to Input.vibrate_handheld(). Enable the Haptics plugin in the export preset.")
	var f: Array = _FALLBACK.get(kind, _FALLBACK[Kind.MEDIUM])
	Input.vibrate_handheld(f[0], f[1])
