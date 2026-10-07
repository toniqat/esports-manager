class_name HubSheet
extends CanvasLayer

# The **shared detail sheet** opened by the hub manage cards (staff · mech research · finance)
# and the standings team detail. Dims the whole screen and shows one white card inside the
# safe area (title · vertically scrolling body · bottom `닫기`). Same pattern as
# `meta/lobby/ConfirmPopup.gd`.
#
# **The frame's layout lives in `HubSheet.tscn`** (card size / margins, title, divider,
# scroll, close button — edit them in the editor). Styles come from the shared theme on
# `Root` (`resources/OutgameTheme.tres`: `PopupCard` · `TitleLabel` · `Divider` ·
# `GhostButton` · `DimPanel`). This script only binds `%` nodes, puts the title in, wires
# close, and offsets `%SafeArea` by the device's safe-area insets.
#
# **The body is filled by the caller.** The hub panels (`FinancePanel` · `StaffPanel` ·
# `MasteryPanel`) are scenes: `open(host)` adds one panel instance under `body` and the panel
# reports its own height (`set_body_height(size.y)` on `resized`). Only the standings team
# detail (`LeagueView`) still builds absolute-positioned children in code, card-local width
# `body_w()`.
#
# Usage (a panel scene's `open(host)`):
#   var sheet := HubSheet.open_on(host, "스태프")
#   var panel := create()                   # the panel's own scene
#   sheet.body.add_child(panel)             # the panel calls sheet.set_body_height(size.y)
#   sheet.closed.connect(...)               # on close
#
# `HubView` already connects `closed` to its `refresh()`, so panels that change state
# inside the sheet don't need to call the hub themselves. A sheet is one-shot: `close()`
# frees it, the next `open_on` instantiates a fresh one.

signal closed

const SCENE_PATH: String = "res://features/season/HubSheet.tscn"

## Scroll content root — callers add absolutely positioned children here.
var body: Control = null


## Instantiates the scene. `HubSheet.new()` is an empty CanvasLayer — don't use it.
## Load (not preload) — preloading its own scene is a script ↔ scene cycle.
static func create() -> HubSheet:
	return (load(SCENE_PATH) as PackedScene).instantiate() as HubSheet


## Opens a sheet under `host` and returns it.
static func open_on(host: Node, title: String) -> HubSheet:
	var sheet := create()
	host.add_child(sheet)
	sheet._open(title)
	return sheet


func _ready() -> void:
	body = %Body
	%Dim.pressed.connect(close)
	%Close.pressed.connect(close)
	# Drag / fling scrolling instead of the engine's touch drag (`DragScroll`).
	DragScroll.attach(%Scroll)
	# A press on the card must not fall through to the dim — `%Card` is STOP in the scene.


## Body width (inside the scroll) = card width minus the `%Pad` side margins. Valid right
## after `open_on` — the card is anchor-sized, not container-sized, so no layout pass is needed.
func body_w() -> float:
	var pad: MarginContainer = %Pad
	return (%Card as Control).size.x - float(pad.get_theme_constant(&"margin_left")) \
			- float(pad.get_theme_constant(&"margin_right"))


## Tells the scroll how tall the body is.
func set_body_height(h: float) -> void:
	if body != null:
		body.custom_minimum_size.y = h


## The card itself, for callers that need fixed controls outside the scroll
## (card-local coordinates). Callers create those controls.
func card() -> Panel:
	return %Card


func close() -> void:
	if is_queued_for_deletion():
		return
	visible = false
	closed.emit()
	queue_free()


func _open(title: String) -> void:
	%Title.text = title
	_fit_safe_area()


## `%SafeArea` is the full screen shrunk to the safe area; the card's own top / bottom
## gaps inside it are scene offsets.
func _fit_safe_area() -> void:
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = ScreenMetrics.bottom_y() - ScreenMetrics.viewport_size().y
