class_name StepCapsule
extends Control

# Run-setup step header (`RunSetupScreen` `%Header`): one dark floating capsule with one icon per
# `RunSetupScreen.STEPS` row and a white disc (`%Selector`) behind the current step's icon — the
# same look as the lobby's floating nav capsule. **The shape lives in `UI_Comp_StepCapsule.tscn`**
# (capsule size, icon size / spacing, preview icons). Code owns the state: which icon carries the
# disc (tweened slide), icon tints (current = dark on the disc, done = amber, upcoming = faint)
# and the slide off the top of the screen (lineup CONFIRM, `set_hidden`).
# Variations: `RunSetupStepCapsule` (capsule) · `RunSetupStepSelector` (disc).

const SCENE_PATH: String = "res://features/meta/run_setup/UI_Comp_StepCapsule.tscn"
const SELECTOR_SEC: float = 0.28
## Same timing as the lineup mode switch (`TeamDraftView.MODE_ANIM_SEC`) so both move together.
const SLIDE_SEC: float = 0.38
## Disc margin around an icon (disc = icon + 2 × this).
const SELECTOR_PAD: float = 12.0
## Extra rise past the screen top when hidden, so the drop shadow leaves too.
const HIDE_EXTRA: float = 32.0

const ICON_CURRENT: Color = OutgameTheme.TEXT
const ICON_DONE: Color = OutgameTheme.ACCENT
const ICON_UPCOMING: Color = Color(0.620, 0.620, 0.650, 0.45)   # RAIL_TEXT, dimmed

var current: int = 0
var hidden_up: bool = false

var _icons: Array = []               # Array[TextureRect], in step order
var _rest_top: float = 0.0
var _rest_bottom: float = 0.0
var _sel_tween: Tween
var _slide_tween: Tween
var _ready_done: bool = false


static func create() -> StepCapsule:
	return (load(SCENE_PATH) as PackedScene).instantiate() as StepCapsule


func _ready() -> void:
	if not _ready_done:
		_ready_done = true
		_rest_top = offset_top
		_rest_bottom = offset_bottom
		_collect_icons()
		# Cell rects are known only after the first sort — place the disc then (and on resize).
		(%Icons as Container).sort_children.connect(_place_selector.bind(false))
		_paint(false)
	if UiPreview.is_standalone(self):
		_fill_preview()


func _collect_icons() -> void:
	_icons.clear()
	for c in (%Icons as Node).get_children():
		if c is TextureRect:
			_icons.append(c)


## One icon per step: `icons` = Texture2D per step, `tips` = tooltip text per step (may be empty).
## The scene holds the preview icons; extra steps duplicate the last cell, missing ones are freed.
func setup(icons: Array, tips: Array = []) -> void:
	var box: Node = %Icons
	while _icons.size() < icons.size() and not _icons.is_empty():
		var dup := (_icons[-1] as TextureRect).duplicate() as TextureRect
		box.add_child(dup)
		_icons.append(dup)
	while _icons.size() > icons.size():
		var extra: TextureRect = _icons.pop_back()
		box.remove_child(extra)
		extra.queue_free()
	for i in _icons.size():
		var icon: TextureRect = _icons[i]
		icon.texture = icons[i]
		icon.tooltip_text = String(tips[i]) if i < tips.size() else ""
	current = clampi(current, 0, maxi(0, _icons.size() - 1))
	_paint(false)


## Marks step `i` as current: the disc slides to its icon, tints follow (done / current / upcoming).
func set_step(i: int, animate: bool = true) -> void:
	current = clampi(i, 0, maxi(0, _icons.size() - 1))
	_paint(animate)


## Slides the capsule up past the screen top (and the safe-top notch band above the indented
## root) when `hide_it`, back to its scene rest offsets otherwise.
func set_hidden(hide_it: bool, animate: bool = true) -> void:
	if hide_it == hidden_up and (_slide_tween == null or not _slide_tween.is_running()):
		return
	hidden_up = hide_it
	var target: float = _rest_top
	if hide_it:
		var parent_y: float = 0.0
		var pc := get_parent_control()
		if pc != null:
			parent_y = pc.global_position.y
		target = _rest_top - (_rest_bottom + parent_y + HIDE_EXTRA)
	if _slide_tween != null:
		_slide_tween.kill()
		_slide_tween = null
	if not animate:
		_set_top(target)
		return
	_slide_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_slide_tween.tween_method(_set_top, offset_top, target, SLIDE_SEC)


func _set_top(top: float) -> void:
	offset_top = top
	offset_bottom = top + (_rest_bottom - _rest_top)


func _paint(animate: bool) -> void:
	for i in _icons.size():
		var icon: TextureRect = _icons[i]
		var target: Color = ICON_UPCOMING
		if i == current:
			target = ICON_CURRENT
		elif i < current:
			target = ICON_DONE
		if not animate:
			icon.self_modulate = target
		elif icon.self_modulate != target:
			create_tween().tween_property(icon, "self_modulate", target, SELECTOR_SEC * 0.6)
	_place_selector(animate)


func _place_selector(animate: bool) -> void:
	if current < 0 or current >= _icons.size():
		return
	var icon: TextureRect = _icons[current]
	if icon.size.x <= 0.0:
		return
	var sel: Control = %Selector
	var pad := Vector2(SELECTOR_PAD, SELECTOR_PAD)
	var target := Rect2((%Icons as Control).position + icon.position - pad, icon.size + pad * 2.0)
	if _sel_tween != null:
		_sel_tween.kill()
		_sel_tween = null
	if not animate:
		sel.position = target.position
		sel.size = target.size
		return
	_sel_tween = create_tween().set_parallel(true) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_sel_tween.tween_property(sel, "position", target.position, SELECTOR_SEC)
	_sel_tween.tween_property(sel, "size", target.size, SELECTOR_SEC)


## F6 standalone preview (`resources/UiPreview.gd`) — middle step current (first done, last upcoming).
func _fill_preview() -> void:
	UiPreview.stage(self)
	set_step(1, false)
