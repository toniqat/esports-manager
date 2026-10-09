class_name PilotGauge
extends Control

# One small stat gauge of a `SeasonPilotCard` (`UI_Comp_PilotGauge.tscn`, no panel — it sits
# straight on the page): a flat icon inside a radial ring (`GaugeRing`), an optional number in
# the icon (`%Center`), the value under the ring (`%Value`) and the change under that
# (`%Delta`). Three kinds, chosen by the fill call; each takes an optional `delta` = the change
# that led to the shown value (week screen: today's change; 0 = just the value, no segment,
# no change line):
#   stress     `show_stress(value, delta)` — icon + ring in the stress band colour (≤30 green ·
#              ≤60 yellow · ≤100 orange · >100 red), ring full at `STRESS_LAP`, a second lap
#              (dark red) on top above it; the exact value under the ring, `(+N)` / `(-N)`
#   trust      `show_trust(points, delta_points)` — pink heart, the trust **level** inside it,
#              ring = progress inside the level (`MentalSystem.level_of_trust` /
#              `progress_of_trust`), `64%` under it, `(+N%)` in percent of a level (a level-up
#              wraps: the ring shows the new level's part and the old level's rest as added)
#   awakening  `show_awakening(gauge, threshold, delta)` — orange bulb, ring = gauge /
#              threshold, `45%`, `(+N%)`; a crossed threshold (the gauge already dropped) shows
#              a full ring at 100% with the delta
# Change segment (`GaugeRing.seg_*`): the ring holds the value before the change, the added
# part in a lighter tone (rise) or the removed part as a faint ghost (fall). `(+N)` is red for
# stress, green for trust / awakening (and the reverse for a fall).
# `set_dimmed(true)` lays the round black mask (`%Mask`) over the ring and fades the numbers.
# Colours are data (code).

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
## Change segment: a rise is the band colour mixed toward white by this much; a fall is the
## removed part's colour at this alpha.
const RISE_LIGHTEN: float = 0.5
const FALL_ALPHA: float = 0.28
## Number opacity while dimmed.
const DIM_TEXT_ALPHA: float = 0.35

@onready var _ring: GaugeRing = %Ring
@onready var _icon: TextureRect = %Icon
@onready var _center: Label = %Center
@onready var _value: Label = %Value
@onready var _delta: Label = %Delta
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


## `v` = the current stress; `delta` = the change that led to it (0 = none shown).
func show_stress(v: int, delta: int = 0) -> void:
	var s_max: int = ConstTable.int_of("STRESS_MAX")
	var before: int = clampi(v - delta, 0, maxi(s_max, v))
	var base: int = mini(before, v)
	var col: Color = stress_color(v)
	_fill(ICON_STRESS, col, _lap_of(base), _over_of(base, s_max), "", str(v))
	_value.theme_type_variation = &"NegativeLabel" if v > STRESS_LAP else &"BodyLabel"
	_segment(_lap_of(before) + _over_of(before, s_max), _lap_of(v) + _over_of(v, s_max), delta,
			col, stress_color(before), C_DARK_RED)
	_show_delta("(%+d)" % delta, delta, true)


## `points` = trust points now; `delta_points` = the change that led to them.
func show_trust(points: int, delta_points: int = 0) -> void:
	var per: int = maxi(1, ConstTable.int_of("TRUST_PER_LEVEL"))
	var lv: int = MentalSystem.level_of_trust(points)
	var p_after: float = MentalSystem.progress_of_trust(points)
	var before: int = maxi(0, points - delta_points)
	var lv_before: int = MentalSystem.level_of_trust(before)
	var p_before: float = MentalSystem.progress_of_trust(before)
	_fill(ICON_HEART, C_PINK, minf(p_before, p_after), 0.0, str(lv), _pct(p_after))
	_value.theme_type_variation = &"BodyLabel"
	if lv > lv_before:
		# Level-up: the new level only holds today's part; the old level's rest is added too.
		_ring.ratio = 0.0
		if lv - lv_before >= 2 or p_after >= p_before:
			_segment(0.0, 1.0, 1, C_PINK, C_PINK, C_PINK)
		else:
			_segment(p_before, 1.0 + p_after, 1, C_PINK, C_PINK, C_PINK)
	elif lv < lv_before:
		_segment(p_after, 1.0, -1, C_PINK, C_PINK, C_PINK)
	else:
		_segment(p_before, p_after, delta_points, C_PINK, C_PINK, C_PINK)
	var d_pct: int = roundi(float(delta_points) * 100.0 / float(per))
	_show_delta("(%+d%%)" % d_pct, d_pct if delta_points != 0 else 0, false)


## `gauge` = the gauge now (0 .. threshold − 1); `delta` = the change that led to it. A rise
## that crossed the threshold (the gauge dropped by it) shows a full ring at 100%.
func show_awakening(gauge: int, threshold: int, delta: int = 0) -> void:
	var thr: int = maxi(1, threshold)
	var before: int = gauge - delta
	var after: int = gauge
	if delta > 0 and before < 0:
		while before < 0:
			before += thr
		after = thr
	before = clampi(before, 0, thr)
	var r_before: float = float(before) / float(thr)
	var r_after: float = clampf(float(after) / float(thr), 0.0, 1.0)
	_fill(ICON_BULB, C_BULB, minf(r_before, r_after), 0.0, "", _pct(r_after))
	_value.theme_type_variation = &"BodyLabel"
	_segment(r_before, r_after, delta, C_BULB, C_BULB, C_BULB)
	var d_pct: int = roundi(float(delta) * 100.0 / float(thr))
	_show_delta("(%+d%%)" % d_pct, d_pct if delta != 0 else 0, false)


func set_dimmed(on: bool) -> void:
	_mask.visible = on
	var a: float = DIM_TEXT_ALPHA if on else 1.0
	_value.modulate.a = a
	_delta.modulate.a = a


## Short pop on the change line (`%Delta`) — the week screen calls it when the day's change lands.
func pulse_delta() -> void:
	if not _delta.visible:
		return
	_delta.pivot_offset = _delta.size * 0.5
	_delta.scale = Vector2.ONE * 1.6
	var tw: Tween = _delta.create_tween()
	tw.tween_property(_delta, "scale", Vector2.ONE, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Change segment `from` → `to` (lap units, see `GaugeRing`): `dir` > 0 = a rise in a lighter
## tone of `col` (second lap: of `over_col`), < 0 = the removed part as a ghost of `fall_col`.
func _segment(from: float, to: float, dir: int, col: Color, fall_col: Color,
		over_col: Color) -> void:
	if dir == 0:
		return
	_ring.seg_from = from
	_ring.seg_to = to
	if dir > 0:
		_ring.seg_color = col.lerp(Color.WHITE, RISE_LIGHTEN)
		_ring.seg_over_color = over_col.lerp(Color.WHITE, RISE_LIGHTEN)
	else:
		_ring.seg_color = Color(fall_col, FALL_ALPHA)
		_ring.seg_over_color = Color(over_col, FALL_ALPHA)


## `%Delta` = `text` when `dir` ≠ 0; red for a rise when `rise_is_bad` (stress), else green.
func _show_delta(text: String, dir: int, rise_is_bad: bool) -> void:
	_delta.visible = dir != 0
	if dir == 0:
		return
	_delta.text = text
	var bad: bool = (dir > 0) == rise_is_bad
	_delta.theme_type_variation = &"NegativeLabel" if bad else &"PositiveLabel"


## "64%" for a 0..1 share.
static func _pct(share: float) -> String:
	return "%d%%" % roundi(clampf(share, 0.0, 1.0) * 100.0)


## First-lap share of a stress value.
func _lap_of(v: int) -> float:
	return clampf(float(v) / float(STRESS_LAP), 0.0, 1.0)


## Second-lap share of a stress value (100 → `s_max`).
func _over_of(v: int, s_max: int) -> float:
	return clampf(float(v - STRESS_LAP) / float(maxi(1, s_max - STRESS_LAP)), 0.0, 1.0)


func _fill(icon: Texture2D, col: Color, lap: float, over: float, center: String,
		value: String) -> void:
	_icon.texture = icon
	_icon.modulate = col
	_ring.color = col
	_ring.ratio = lap
	_ring.over_ratio = maxf(over, 0.0)
	_ring.seg_from = 0.0
	_ring.seg_to = 0.0
	_ring.over_color = C_DARK_RED
	_center.text = center
	_center.visible = center != ""
	_value.text = value
	_value.visible = value != ""
	_delta.visible = false


## F6 preview — stress past the first lap after today's rise of 25 (hand-written values).
func _fill_preview() -> void:
	UiPreview.stage(self)
	show_stress(140, 25)
