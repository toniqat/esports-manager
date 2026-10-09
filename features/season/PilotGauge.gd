class_name PilotGauge
extends Panel

# One small stat panel under a week-map pilot token (`UI_Comp_PilotGauge.tscn`): a flat
# icon inside a radial ring (`GaugeRing`), an optional number in the icon (`%Center`) and an
# optional number under the ring (`%Value`). Three kinds, chosen by the fill call:
#   stress     `show_stress(value)`  — icon + ring in the stress band colour (≤30 green ·
#              ≤60 yellow · ≤100 orange · >100 red), ring full at `STRESS_LAP`, a second lap
#              (dark red) on top above it; the exact value under the ring
#   trust      `show_trust(points)`  — pink heart, the trust **level** inside it, ring = progress
#              inside the level (`MentalSystem.level_of_trust` / `progress_of_trust`)
#   awakening  `show_awakening(gauge, threshold)` — orange bulb, ring = gauge / threshold
# `set_dimmed(true)` lays the black mask (`%Mask`) over the panel. Colours are data (code).

const ICON_STRESS: Texture2D = preload("res://resources/images/ui/gauge/stress.svg")
const ICON_HEART: Texture2D = preload("res://resources/images/ui/gauge/heart.svg")
const ICON_BULB: Texture2D = preload("res://resources/images/ui/gauge/bulb.svg")

## One full ring of stress; the second lap runs from here to `STRESS_MAX` (200).
const STRESS_LAP: int = 100
const STRESS_GREEN_MAX: int = 30
const STRESS_YELLOW_MAX: int = 60

const C_GREEN: Color = Color(0.180, 0.690, 0.360, 1.0)
const C_YELLOW: Color = Color(0.937, 0.741, 0.090, 1.0)
const C_ORANGE: Color = Color(0.957, 0.502, 0.137, 1.0)
const C_RED: Color = Color(0.878, 0.235, 0.235, 1.0)
const C_DARK_RED: Color = Color(0.478, 0.051, 0.090, 1.0)
const C_PINK: Color = Color(0.937, 0.400, 0.600, 1.0)
const C_BULB: Color = Color(0.976, 0.588, 0.118, 1.0)

@onready var _ring: GaugeRing = %Ring
@onready var _icon: TextureRect = %Icon
@onready var _center: Label = %Center
@onready var _value: Label = %Value
@onready var _mask: Control = %Mask


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## Stress band colour of `v` (icon and first lap).
static func stress_color(v: int) -> Color:
	if v <= STRESS_GREEN_MAX:
		return C_GREEN
	if v <= STRESS_YELLOW_MAX:
		return C_YELLOW
	if v <= STRESS_LAP:
		return C_ORANGE
	return C_RED


func show_stress(v: int) -> void:
	var col: Color = stress_color(v)
	var over_span: int = maxi(1, ConstTable.int_of("STRESS_MAX") - STRESS_LAP)
	_fill(ICON_STRESS, col, float(v) / float(STRESS_LAP),
			float(v - STRESS_LAP) / float(over_span), "", str(v))
	_value.theme_type_variation = &"NegativeLabel" if v > STRESS_LAP else &"BodyLabel"


func show_trust(points: int) -> void:
	_fill(ICON_HEART, C_PINK, MentalSystem.progress_of_trust(points), 0.0,
			str(MentalSystem.level_of_trust(points)), "")


func show_awakening(gauge: int, threshold: int) -> void:
	_fill(ICON_BULB, C_BULB, float(gauge) / float(maxi(1, threshold)), 0.0, "", "")


func set_dimmed(on: bool) -> void:
	_mask.visible = on


func _fill(icon: Texture2D, col: Color, lap: float, over: float, center: String,
		value: String) -> void:
	_icon.texture = icon
	_icon.modulate = col
	_ring.color = col
	_ring.over_color = C_DARK_RED
	_ring.ratio = lap
	_ring.over_ratio = maxf(over, 0.0)
	_center.text = center
	_center.visible = center != ""
	_value.text = value
	_value.visible = value != ""


## F6 preview — a stress panel past the first lap (hand-written value).
func _fill_preview() -> void:
	UiPreview.stage(self)
	show_stress(140)
