class_name Card
extends Control

signal card_clicked(card: Card)

const CARD_W := 160.0
const CARD_H := 220.0
const FLIP_DURATION := 0.18  # seconds per half-flip

var data: CardData = null
var face_up: bool = false
var is_player_card: bool = true
var is_animating: bool = false
var is_selected: bool = false

@onready var card_front: Panel = $CardFront
@onready var card_back: Panel = $CardBack
@onready var name_label: Label = $CardFront/MarginContainer/VBox/NameLabel
@onready var cost_label: Label = $CardFront/MarginContainer/VBox/CostLabel
@onready var desc_label: Label = $CardFront/MarginContainer/VBox/DescLabel
@onready var back_cost_label: Label = $CardBack/BackCostLabel


func setup(card_data: CardData, player_card: bool, start_face_up: bool = false) -> void:
	data = card_data
	is_player_card = player_card
	face_up = start_face_up
	_apply_data()
	card_front.visible = start_face_up
	card_back.visible = not start_face_up


func _apply_data() -> void:
	if data == null:
		return
	name_label.text = data.card_name
	cost_label.text = str(data.cost)
	desc_label.text = data.description
	# Tint front panel by cost tier
	var col := _cost_color(data.cost)
	var style := StyleBoxFlat.new()
	style.bg_color = col
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	card_front.add_theme_stylebox_override("panel", style)


func _cost_color(cost: int) -> Color:
	match cost:
		1: return Color(0.2, 0.6, 0.9)   # blue
		2: return Color(0.2, 0.75, 0.4)  # green
		3: return Color(0.9, 0.75, 0.1)  # gold
		4: return Color(0.9, 0.45, 0.1)  # orange
		5: return Color(0.85, 0.2, 0.2)  # red
		6: return Color(0.6, 0.1, 0.8)   # purple
		_: return Color(0.15, 0.1, 0.25) # dark/mythic


# ── Flip Animation ────────────────────────────────────────────────────────────

func flip_to_face_up() -> void:
	if face_up or is_animating:
		return
	is_animating = true
	var tween := create_tween()
	# Shrink to 0 on X axis
	tween.tween_property(self, "scale:x", 0.0, FLIP_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_callback(_swap_to_front)
	# Grow back to 1
	tween.tween_property(self, "scale:x", 1.0, FLIP_DURATION).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): is_animating = false)
	face_up = true


func flip_to_face_down() -> void:
	if not face_up or is_animating:
		return
	is_animating = true
	var tween := create_tween()
	tween.tween_property(self, "scale:x", 0.0, FLIP_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_callback(_swap_to_back)
	tween.tween_property(self, "scale:x", 1.0, FLIP_DURATION).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): is_animating = false)
	face_up = false


func _swap_to_front() -> void:
	card_back.visible = false
	card_front.visible = true


func _swap_to_back() -> void:
	card_front.visible = false
	card_back.visible = true


# ── Arc Movement Animation ────────────────────────────────────────────────────

# Moves card from its current global position to target_global using a bezier arc.
# Calls on_complete when done. pivot_offset should be set to center before calling.
func animate_to(target_global: Vector2, duration: float, on_complete: Callable = Callable()) -> void:
	is_animating = true
	var start: Vector2 = global_position
	var control: Vector2 = _bezier_control(start, target_global)

	var tween := create_tween()
	tween.tween_method(
		func(t: float) -> void:
			global_position = _quadratic_bezier(start, control, target_global, t),
		0.0, 1.0, duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	tween.tween_callback(func() -> void:
		is_animating = false
		if on_complete.is_valid():
			on_complete.call()
	)


func _bezier_control(start: Vector2, end: Vector2) -> Vector2:
	var mid := (start + end) * 0.5
	# Lift midpoint upward on screen (negative Y) for an arc
	mid.y -= 300.0
	return mid


func _quadratic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var q0 := p0.lerp(p1, t)
	var q1 := p1.lerp(p2, t)
	return q0.lerp(q1, t)


# ── Interaction ───────────────────────────────────────────────────────────────

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


const HOVER_SCALE   := Vector2(1.3, 1.3)
const HOVER_Z_INDEX := 10

var _stored_base_y: float = 0.0


func store_base_y() -> void:
	_stored_base_y = position.y


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not is_animating:
			card_clicked.emit(self)


func _on_mouse_entered() -> void:
	if not is_animating and face_up and is_player_card and not is_selected:
		pivot_offset = size / 2
		z_index = HOVER_Z_INDEX
		var tw := create_tween()
		tw.tween_property(self, "scale", HOVER_SCALE, 0.1)


func _on_mouse_exited() -> void:
	if not is_animating and face_up and is_player_card and not is_selected:
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2.ONE, 0.1)
		tw.tween_callback(func(): z_index = 0)
