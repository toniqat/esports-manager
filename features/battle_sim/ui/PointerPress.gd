class_name PointerPress
extends RefCounted

## One physical tap = **one** press / release for widgets that listen in `_input`.
##
## With `input_devices/pointing/emulate_mouse_from_touch` on (Godot default, this project
## does not override it) every touch with index 0 reaches `_input` **twice**: as the
## `InputEventScreenTouch` and as an emulated `InputEventMouseButton`
## (`device == InputEvent.DEVICE_ID_EMULATION`). Neither is suppressed by
## `set_input_as_handled()` on the other — `Input` dispatches both. A handler that reads
## both kinds sees two presses per tap (the old CostDonut bug: one tap flipped the donut
## and the duplicate press ended the turn).
##
## Rule: read the mouse stream (real or emulated). Touch events count only when the
## project does **not** emulate the mouse, and then only the first finger.

const PRESS := 1
const RELEASE := -1
const NONE := 0


## `PRESS` / `RELEASE` for the one pointer stream we read, `NONE` for everything else.
static func state(event: InputEvent) -> int:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return NONE
		return PRESS if mb.pressed else RELEASE
	if event is InputEventScreenTouch:
		if _mouse_emulated():
			return NONE
		var st := event as InputEventScreenTouch
		if st.index != 0:
			return NONE
		return PRESS if st.pressed else RELEASE
	return NONE


## Viewport position of a press / release event (`Vector2.ZERO` for other events).
static func position_of(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	return Vector2.ZERO


static func _mouse_emulated() -> bool:
	return bool(ProjectSettings.get_setting(
			"input_devices/pointing/emulate_mouse_from_touch", true))
