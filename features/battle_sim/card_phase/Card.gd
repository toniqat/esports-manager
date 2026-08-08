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
const HOVER_TWEEN_DURATION := 0.08

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

const DIM_MODULATE: Color = Color(0.42, 0.42, 0.48, 1.0)

@onready var card_front: Panel = $CardFront
@onready var card_back: Panel = $CardBack
@onready var name_label: Label = $CardFront/MarginContainer/VBox/HeaderRow/NameLabel
@onready var cost_label: Label = $CardFront/MarginContainer/VBox/HeaderRow/CostLabel
@onready var back_cost_label: Label = $CardBack/BackCostLabel
@onready var owner_face_wrap: CenterContainer = $CardFront/MarginContainer/VBox/OwnerFaceWrap
@onready var owner_face: TextureRect = $CardFront/MarginContainer/VBox/OwnerFaceWrap/OwnerFace


func setup(card_data: CardData, player_card: bool, start_face_up: bool = false) -> void:
	data = card_data
	is_player_card = player_card
	face_up = start_face_up
	_apply_data()
	_apply_back_style()
	card_front.visible = start_face_up
	card_back.visible = not start_face_up


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

## Smoothly move this card to target slot position / rotation / scale.
## Kills any in-progress layout tween first to prevent conflicts.
## ease_type / trans_type accept Tween.EaseType / Tween.TransitionType int values.
func tween_to(target_pos: Vector2, target_rot: float, target_scale: Vector2,
		duration: float,
		ease_type: int = Tween.EASE_OUT,
		trans_type: int = Tween.TRANS_SPRING) -> void:
	if _active_tween != null and _active_tween.is_running():
		_active_tween.kill()
	_active_tween = create_tween().set_parallel()
	(_active_tween.tween_property(self, "global_position", target_pos, duration)
			.set_ease(ease_type).set_trans(trans_type))
	(_active_tween.tween_property(self, "rotation", target_rot, duration)
			.set_ease(ease_type).set_trans(trans_type))
	(_active_tween.tween_property(self, "scale", target_scale, duration)
			.set_ease(ease_type).set_trans(trans_type))


# ── Interaction ───────────────────────────────────────────────────────────────

func store_base_y() -> void:
	_stored_base_y = position.y


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
		card_hovered.emit(self)


func _on_mouse_exited() -> void:
	if not face_up or not is_player_card:
		return
	if _is_hovered:
		_is_hovered = false
		_tween_hover_brightness(false)
		card_unhovered.emit(self)


func _tween_hover_brightness(active: bool) -> void:
	if _hover_tween != null and _hover_tween.is_running():
		_hover_tween.kill()
	var target: Color = (Color(HOVER_BRIGHTEN, HOVER_BRIGHTEN, HOVER_BRIGHTEN, 1.0)
			if active else Color.WHITE)
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "modulate", target, HOVER_TWEEN_DURATION)


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
