class_name Card
extends Control

signal card_clicked(card: Card)
signal card_hovered(card: Card)
signal card_unhovered(card: Card)

const CARD_W := 160.0
const CARD_H := 220.0

## Pixels the card jumps upward when selected (clicked) in the BattleSim hand.
## CardPhaseManager applies this lift to the selected card so it visually
## detaches from the rest of the hand while its description box is open.
const PRESS_LIFT     := 40.0
## Modulate multiplier applied while the mouse is hovering over a face-up
## player card. Above 1.0 → brighter (Godot canvas modulate supports values
## > 1 for an additive-feeling brighten).
const HOVER_BRIGHTEN := 1.25
const HOVER_TWEEN_DURATION := 0.04
## Scale applied to a hovered face-up player card — the card comes closer to
## the screen, so it reads slightly bigger (and casts a bigger shadow).
const HOVER_SCALE := 1.2
## Hover / selection reactions snap out fast and settle slow (cubic EASE_OUT)
## so the card feels like it jumps to the cursor rather than drifting to it.
const HOVER_EASE  : int = Tween.EASE_OUT
const HOVER_TRANS : int = Tween.TRANS_CUBIC

# ── Floating shadow ───────────────────────────────────────────────────────────
# Hand cards hover above the table rather than lying on it. The gap between a
# card and its shadow encodes that height: at rest the card sits close to the
# surface (short offset, tight and dark shadow); hovering pulls it toward the
# screen (offset pushed out, shadow spread wider and lightened); a selected
# card floats highest of all. The shadow is a Panel child at draw index 0, so
# it inherits the card's fan rotation and hover scale for free.
const SHADOW_REST_OFFSET     := Vector2(2.0, 10.0)
const SHADOW_HOVER_OFFSET    := Vector2(5.0, 24.0)
const SHADOW_SELECTED_OFFSET := Vector2(6.0, 32.0)
## StyleBoxFlat.shadow_size — blur radius bleeding out of the shadow slab.
const SHADOW_REST_BLUR      := 6
const SHADOW_HOVER_BLUR     := 26
const SHADOW_SELECTED_BLUR  := 32
## Shadow darkness. The further a shadow falls from its caster, the more it
## spreads and the lighter it reads.
const SHADOW_REST_ALPHA     := 0.50
const SHADOW_HOVER_ALPHA    := 0.36
const SHADOW_SELECTED_ALPHA := 0.32
## Extra spread of the shadow slab itself (multiplied on top of the card scale).
const SHADOW_REST_SPREAD     := 1.0
const SHADOW_HOVER_SPREAD    := 1.06
const SHADOW_SELECTED_SPREAD := 1.08
const SHADOW_TWEEN_DURATION  := 0.05

var data: CardData = null
var face_up: bool = false
var is_player_card: bool = true
var is_animating: bool = false
var is_selected: bool = false

# True while CardPhaseManager is dimming the hand (it's not the player's turn,
# or the player turn-start banner is still playing). Hover/click feedback is
# suppressed in this state so the dimmed look stays consistent.
var _is_dimmed: bool = false

var _is_hovered:  bool  = false
var _active_tween: Tween  = null
var _stored_base_y: float = 0.0
var _hover_tween:  Tween  = null

# Layout scale requested by the last tween_to() — the hover enlargement is
# multiplied on top of this instead of overwriting it.
var _base_scale: Vector2 = Vector2.ONE
var _shadow: Panel = null
var _shadow_tween: Tween = null
var _float_tween: Tween  = null

const DIM_MODULATE: Color = Color(0.42, 0.42, 0.48, 1.0)

@onready var card_front: Panel = $CardFront
@onready var card_back: Panel = $CardBack
@onready var name_label: Label = $CardFront/MarginContainer/VBox/HeaderRow/NameLabel
@onready var cost_label: Label = $CardFront/MarginContainer/VBox/HeaderRow/CostLabel
@onready var back_cost_label: Label = $CardBack/BackCostLabel
@onready var owner_face_wrap: CenterContainer = $CardFront/MarginContainer/VBox/OwnerFaceWrap
@onready var owner_face: TextureRect = $CardFront/MarginContainer/VBox/OwnerFaceWrap/OwnerFace


func _ready() -> void:
	_build_shadow()


func setup(card_data: CardData, player_card: bool, start_face_up: bool = false) -> void:
	data = card_data
	is_player_card = player_card
	face_up = start_face_up
	_apply_data()
	_apply_back_style()
	card_front.visible = start_face_up
	card_back.visible = not start_face_up
	# setup() may run before or after _ready() depending on the caller's
	# add_child ordering, so both paths re-assert the shadow visibility.
	if _shadow != null:
		_shadow.visible = player_card


# ── Floating shadow ───────────────────────────────────────────────────────────

## Builds the drop shadow slab and parks it at draw index 0 so both CardBack
## and CardFront cover it. Only player cards cast one — the AI hand peek and
## the 찾기 grid are flat rows where a shadow would only add noise.
func _build_shadow() -> void:
	if _shadow != null:
		return
	_shadow = Panel.new()
	_shadow.name = "DropShadow"
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow.size = Vector2(CARD_W, CARD_H)
	_shadow.pivot_offset = Vector2(CARD_W, CARD_H) * 0.5
	_shadow.position = SHADOW_REST_OFFSET
	_shadow.modulate = Color(1.0, 1.0, 1.0, SHADOW_REST_ALPHA)
	_shadow.visible = is_player_card
	add_child(_shadow)
	move_child(_shadow, 0)
	_apply_shadow_blur(SHADOW_REST_BLUR)


func _apply_shadow_blur(blur: int) -> void:
	if _shadow == null:
		return
	var sb := StyleBoxFlat.new()
	# The slab core lightens as it blurs out, so a high-lift shadow reads as a
	# soft pool rather than a hard black rectangle trailing the card.
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.8 if blur <= SHADOW_REST_BLUR else 0.55)
	sb.corner_radius_top_left     = 10
	sb.corner_radius_top_right    = 10
	sb.corner_radius_bottom_left  = 10
	sb.corner_radius_bottom_right = 10
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	sb.shadow_size  = blur
	_shadow.add_theme_stylebox_override("panel", sb)


## Re-poses the card and its shadow for the current hover / selected state.
## Card scale grows on hover only; the shadow drops further away (and softens)
## for both hover and selection, since either state lifts the card off the table.
func _refresh_float_state() -> void:
	var target_scale: Vector2 = _base_scale * (HOVER_SCALE if _is_hovered else 1.0)
	if _float_tween != null and _float_tween.is_running():
		_float_tween.kill()
	_float_tween = create_tween()
	(_float_tween.tween_property(self, "scale", target_scale, SHADOW_TWEEN_DURATION)
			.set_ease(HOVER_EASE).set_trans(HOVER_TRANS))

	if _shadow == null:
		return
	var offset: Vector2 = SHADOW_REST_OFFSET
	var alpha: float    = SHADOW_REST_ALPHA
	var spread: float   = SHADOW_REST_SPREAD
	var blur: int       = SHADOW_REST_BLUR
	if is_selected:
		offset = SHADOW_SELECTED_OFFSET
		alpha  = SHADOW_SELECTED_ALPHA
		spread = SHADOW_SELECTED_SPREAD
		blur   = SHADOW_SELECTED_BLUR
	elif _is_hovered:
		offset = SHADOW_HOVER_OFFSET
		alpha  = SHADOW_HOVER_ALPHA
		spread = SHADOW_HOVER_SPREAD
		blur   = SHADOW_HOVER_BLUR
	_apply_shadow_blur(blur)
	if _shadow_tween != null and _shadow_tween.is_running():
		_shadow_tween.kill()
	_shadow_tween = create_tween().set_parallel() \
			.set_ease(HOVER_EASE).set_trans(HOVER_TRANS)
	_shadow_tween.tween_property(_shadow, "position", offset, SHADOW_TWEEN_DURATION)
	_shadow_tween.tween_property(_shadow, "scale", Vector2(spread, spread),
			SHADOW_TWEEN_DURATION)
	_shadow_tween.tween_property(_shadow, "modulate",
			Color(1.0, 1.0, 1.0, alpha), SHADOW_TWEEN_DURATION)


func _apply_back_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.05, 0.18, 1.0)
	style.corner_radius_top_left     = 10
	style.corner_radius_top_right    = 10
	style.corner_radius_bottom_left  = 10
	style.corner_radius_bottom_right = 10
	style.border_color = Color(0.4, 0.3, 0.6, 1.0)
	style.border_width_bottom = 2
	style.border_width_top    = 2
	style.border_width_left   = 2
	style.border_width_right  = 2
	card_back.add_theme_stylebox_override("panel", style)


## Cost number colours: white when the displayed cost matches the card's
## printed (data.cost) value, green when reduced by an active modifier, red
## when increased. Surfaced via update_displayed_cost so CardPhaseManager can
## refresh the card whenever effective_cost_for changes.
const COST_COLOR_BASE     := Color(1.0, 1.0, 1.0)
const COST_COLOR_REDUCED  := Color(0.45, 1.0, 0.45)
const COST_COLOR_INCREASED := Color(1.0, 0.45, 0.45)


func _apply_data() -> void:
	if data == null:
		return
	name_label.text = data.card_name
	cost_label.text = str(data.cost)
	cost_label.add_theme_font_size_override("font_size", 22)
	cost_label.add_theme_color_override("font_color", COST_COLOR_BASE)
	cost_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	cost_label.add_theme_constant_override("outline_size", 3)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_label.add_theme_constant_override("outline_size", 3)
	var col := _cost_color(data.cost)
	var style := StyleBoxFlat.new()
	style.bg_color = col
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	card_front.add_theme_stylebox_override("panel", style)
	_apply_owner_face()


# Sets the owner pilot face image filling the card body. Falls back to a
# fully-transparent texture when no face image is available (standalone runs
# without a roster / INTL pilots without art); the cost-coloured card front
# still shows through. Card description is intentionally NOT rendered on
# the card itself — it's surfaced by CardPhaseManager's description box only
# when the card is selected.
func _apply_owner_face() -> void:
	if owner_face_wrap == null or owner_face == null:
		return
	var tex: Texture2D = null
	if data != null and data.owner_pilot != null:
		tex = PilotImages.face_for(data.owner_pilot.pilot_id)
	owner_face.texture = tex
	# Wrap stays visible even without a texture so the card layout doesn't
	# collapse; the cost-coloured card front shows through the empty area.
	owner_face_wrap.visible = true


func _cost_color(cost: int) -> Color:
	match cost:
		1: return Color(0.2, 0.6, 0.9)
		2: return Color(0.2, 0.75, 0.4)
		3: return Color(0.9, 0.75, 0.1)
		4: return Color(0.9, 0.45, 0.1)
		5: return Color(0.85, 0.2, 0.2)
		6: return Color(0.6, 0.1, 0.8)
		_: return Color(0.15, 0.1, 0.25)


# ── Layout Tween ──────────────────────────────────────────────────────────────

## Converts a viewport-space layout slot into the raw `position` this card must
## hold to land there.
##
## Do NOT tween `global_position` on these cards. `Control.global_position` is
## the *rotated-and-scaled top-left corner*, not the card's anchor: its getter
## returns `position + pivot − R·S·pivot` and its setter inverts that using
## whatever rotation/scale the node happens to have at the instant of the write.
## Once hover scaling entered the picture that made the landing spot depend on
## the live scale — a card written at scale 1.2 settles ~15px right and ~22px
## below the same card written at scale 1.0, which is exactly how the lifted
## card drifted up-right and the deselected card sank below its slot. `position`
## has no such coupling (the card's visual centre is always `position + pivot`),
## so all layout goes through it.
func layout_position_from_global(target_global: Vector2) -> Vector2:
	var parent_ci := get_parent() as CanvasItem
	if parent_ci == null:
		return target_global
	return parent_ci.get_global_transform_with_canvas().affine_inverse() * target_global


## Smoothly move this card to target slot position / rotation / scale.
## `target_pos` is the viewport-space slot (same convention as before — the
## card's unrotated top-left); it is converted through
## `layout_position_from_global` so rotation and hover scale never bend it.
## Kills any in-progress layout tween first to prevent conflicts.
## `target_scale` is the card's *layout* scale — the hover enlargement is
## multiplied on top of it, so a relayout mid-hover doesn't snap the card back
## down to 1.0.
## ease_type / trans_type accept Tween.EaseType / Tween.TransitionType int values.
func tween_to(target_pos: Vector2, target_rot: float, target_scale: Vector2,
		duration: float,
		ease_type: int = Tween.EASE_OUT,
		trans_type: int = Tween.TRANS_SPRING) -> void:
	if _active_tween != null and _active_tween.is_running():
		_active_tween.kill()
	# `scale` has exactly one owner at a time. Unless the caller is actually
	# changing the layout scale (nobody does today — every caller passes ONE),
	# the layout tween keeps its hands off it and `_refresh_float_state` stays
	# the sole driver. Two tweens racing over `scale` is what used to strand a
	# hovered card at 1.0: a relayout fired mid-hover captured the hover factor
	# from a transient `_is_hovered` and killed the hover tween on its way past.
	var takes_scale: bool = not _base_scale.is_equal_approx(target_scale)
	_base_scale = target_scale
	_active_tween = create_tween().set_parallel()
	(_active_tween.tween_property(self, "position",
			layout_position_from_global(target_pos), duration)
			.set_ease(ease_type).set_trans(trans_type))
	(_active_tween.tween_property(self, "rotation", target_rot, duration)
			.set_ease(ease_type).set_trans(trans_type))
	if takes_scale:
		if _float_tween != null and _float_tween.is_running():
			_float_tween.kill()
		var scale_goal: Vector2 = _base_scale * (HOVER_SCALE if _is_hovered else 1.0)
		(_active_tween.tween_property(self, "scale", scale_goal, duration)
				.set_ease(ease_type).set_trans(trans_type))


# ── Interaction ───────────────────────────────────────────────────────────────

func store_base_y() -> void:
	_stored_base_y = position.y


## True while the cursor is on this card and the hover reaction is showing.
## CardPhaseManager reads it to decide which card the hand row spreads around
## and which card sits on top of the z-order.
func is_hovered() -> bool:
	return _is_hovered


## Updates the top-left cost number to reflect any active cost modifier
## (effective_cost) and colours it: green when reduced below printed cost,
## red when increased, white when unchanged. CardPhaseManager calls this
## from highlight_affordable_cards so every modifier (사전 준비 / 전투 준비
## / 집중 / 정밀 이동) repaints the cost in sync with affordability.
func update_displayed_cost(effective_cost: int) -> void:
	if data == null:
		return
	cost_label.text = str(effective_cost)
	var col: Color = COST_COLOR_BASE
	if effective_cost < data.cost:
		col = COST_COLOR_REDUCED
	elif effective_cost > data.cost:
		col = COST_COLOR_INCREASED
	cost_label.add_theme_color_override("font_color", col)


func set_affordable(affordable: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = _cost_color(data.cost) if affordable else Color(0.25, 0.25, 0.25)
	style.border_color = Color(1.0, 0.9, 0.1, 1.0) if affordable else Color(0.15, 0.15, 0.15)
	style.border_width_bottom = 4 if affordable else 1
	style.border_width_top    = 4 if affordable else 1
	style.border_width_left   = 4 if affordable else 1
	style.border_width_right  = 4 if affordable else 1
	style.corner_radius_top_left     = 10
	style.corner_radius_top_right    = 10
	style.corner_radius_bottom_left  = 10
	style.corner_radius_bottom_right = 10
	card_front.add_theme_stylebox_override("panel", style)


func _on_mouse_entered() -> void:
	if not face_up or not is_player_card or _is_dimmed:
		return
	if not _is_hovered:
		_is_hovered = true
		_tween_hover_brightness(true)
		_refresh_float_state()
		card_hovered.emit(self)


func _on_mouse_exited() -> void:
	if not face_up or not is_player_card:
		return
	if _is_hovered:
		_is_hovered = false
		_tween_hover_brightness(false)
		_refresh_float_state()
		card_unhovered.emit(self)


func _tween_hover_brightness(active: bool) -> void:
	if _hover_tween != null and _hover_tween.is_running():
		_hover_tween.kill()
	var target: Color = (Color(HOVER_BRIGHTEN, HOVER_BRIGHTEN, HOVER_BRIGHTEN, 1.0)
			if active else Color.WHITE)
	_hover_tween = create_tween()
	(_hover_tween.tween_property(self, "modulate", target, HOVER_TWEEN_DURATION)
			.set_ease(HOVER_EASE).set_trans(HOVER_TRANS))


# Toggle the player-hand "dim" state. CardPhaseManager calls this whenever the
# player can't act on the hand — i.e., during BATTLE auto-tick, while the
# turn-start banner is mid-flight, or while the AI is playing its own cards.
func set_dimmed(dim: bool) -> void:
	if _is_dimmed == dim:
		return
	_is_dimmed = dim
	if _hover_tween != null and _hover_tween.is_running():
		_hover_tween.kill()
	_is_hovered = false
	modulate = DIM_MODULATE if dim else Color.WHITE
	# Dropping the hover state also drops the hover enlargement / big shadow.
	_refresh_float_state()


## Marks this card as the hand's lifted selection. CardPhaseManager owns the
## lift itself (position / rotation); the card only owns how far its shadow
## falls, which grows because a selected card floats highest above the table.
func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	_refresh_float_state()


func _gui_input(event: InputEvent) -> void:
	if not face_up or not is_player_card or _is_dimmed:
		return
	# Click-to-select: a press emits card_clicked; CardPhaseManager pops the
	# card up, brings it to the top of the hand, and shows the description
	# box. accept_event() prevents the same press from also firing the
	# outside-click deselect handler in CardPhaseManager._unhandled_input.
	var pressed: bool = false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed = true
	elif event is InputEventScreenTouch and event.pressed:
		pressed = true
	if pressed:
		card_clicked.emit(self)
		accept_event()
