class_name SeasonPilotCard
extends Panel

# Small vertical pilot card shown five in a row (seat order) on the season hub and at the
# bottom of the week screen: round portrait inside a **level ring** on top (`ProgressRing` =
# the run-only 깨달음 level's EXP bar, `TrainingLevel.progress`; LINK blue, ACCENT while capped =
# limit break due or max) with the level chip `Lv N` centred on the ring's top edge like a tab
# (`set_training_level`; painted in the ring's colour, small faded `Lv` + the number), then two
# gauges (`PilotGauge`: stress · trust). No card
# background (`SeasonPilotCardBare`): the parts sit on the page. Each gauge shows its value
# under the ring (stress number · trust percent); the week screen adds that day's changes
# (`set_day_deltas`: gauge ring segment + `+N` / `+N%` under the value, the day's level EXP
# as a light segment on the portrait ring) and is drawn larger (`set_week_layout`). No position badge — the seat order (`GameEnums.ROLE_DISPLAY_ORDER`) says the role. Tapping the card emits `pressed(pilot_id)`; the
# screens open `SeasonPilotDetail` with it.
#
# **Layout lives in `UI_Comp_SeasonPilotCard.tscn`.** This script fills `%` nodes and paints
# the data colours.

signal pressed(pilot_id: int)

const SCENE_PATH: String = "res://features/season/UI_Comp_SeasonPilotCard.tscn"
## `set_week_layout` growth from the scene sizes: portrait (ring · portrait · level chip) and
## the two gauges (ring · icon · numbers).
const WEEK_PORTRAIT_SCALE: float = 1.1
const WEEK_GAUGE_SCALE: float = 1.2

## Pilot shown on this card (-1 = empty seat).
var pilot_id: int = -1
## Values shown by the last `show_pilot` (`set_day_deltas` redraws the gauges with them).
var _stress: int = 0
var _trust: int = 0
## `set_gauges_visible` — false keeps the two gauges (and their value / change lines) hidden.
var _gauges_on: bool = true
## Colour of the portrait ring (`_set_ring`) — the level chip is painted with it.
var _ring_color: Color = OutgameTheme.LINK
## `set_week_layout` already applied.
var _week_layout: bool = false


static func create() -> SeasonPilotCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as SeasonPilotCard


func _ready() -> void:
	(%Hit as Button).pressed.connect(_on_hit)
	if UiPreview.is_standalone(self):
		_fill_preview()


## Shows / hides the two gauges with their value and change lines (default shown; the
## PREP screen hides them). Positions are fixed in the scene, so the rest of the card stays put.
func set_gauges_visible(on: bool) -> void:
	_gauges_on = on
	_show_gauges(on and pilot_id >= 0)


## Whether the card reacts to taps (the detail sheet's own header card does not).
func set_tappable(on: bool) -> void:
	(%Hit as Button).visible = on


## Fills the card. `trust` / `stress` are the run values (`MentalSystem.trust` points,
## `StressSystem.value`); the level ring and chip are read from the run (`TrainingLevel`).
## The gauges show just the values — the week screen calls `set_day_deltas` after for the
## day's changes.
func show_pilot(pid: int, trust: int, stress: int) -> void:
	pilot_id = pid
	_draw_portrait(PilotImages.circle_for(pid))
	_stress = stress
	_trust = trust
	_show_gauges(_gauges_on)
	(%PilotGauge_Stress as PilotGauge).show_stress(stress)
	(%PilotGauge_Trust as PilotGauge).show_trust(trust)
	_show_run_level(pid, 0)
	(%Hit as Button).disabled = false


## Empty seat: blank portrait, no gauges, no numbers.
func show_empty() -> void:
	pilot_id = -1
	_draw_portrait(null)
	_set_ring(0.0, 0.0, OutgameTheme.LINK)
	set_training_level(0)
	_show_gauges(false)
	(%Hit as Button).disabled = true


## 깨달음 level chip: `level` < 1 hides it. The `Lv` prefix is a fixed scene label; the chip's
## colour follows the portrait ring (`_set_ring`).
func set_training_level(level: int) -> void:
	var chip: Panel = %LevelChip
	chip.visible = level >= 1
	if chip.visible:
		(%LevelText as Label).text = str(level)


## Week screen only: the portrait (ring · portrait · level chip) grows by `WEEK_PORTRAIT_SCALE`
## and the two gauges by `WEEK_GAUGE_SCALE`, all from the scene sizes and still centred; the
## gauges move down under the bigger ring (same gap) and `custom_minimum_size.y` grows to fit
## (scene 244 → 274). Call once after `_ready` (again = no-op); the portrait is redrawn if a
## pilot is already shown.
func set_week_layout() -> void:
	if _week_layout:
		return
	_week_layout = true
	var ring: ProgressRing = %Ring
	var gauges: HBoxContainer = %Gauges
	var gap: float = gauges.offset_top - ring.offset_bottom
	var tail: float = custom_minimum_size.y - gauges.offset_bottom
	var pf: float = WEEK_PORTRAIT_SCALE
	# Ring: centred, same top, diameter × pf.
	var d: float = roundf((ring.offset_right - ring.offset_left) * pf)
	ring.offset_left = -d * 0.5
	ring.offset_right = d * 0.5
	ring.offset_bottom = ring.offset_top + d
	ring.width *= pf
	var slot: Control = %Portrait
	var inset: float = roundf(slot.offset_left * pf)
	slot.offset_left = inset
	slot.offset_top = inset
	slot.offset_right = d - inset
	slot.offset_bottom = d - inset
	# Level chip: × pf, still centred on the ring's top stroke (kept inside the card).
	var chip: Panel = %LevelChip
	var chip_size: Vector2 = (chip.custom_minimum_size * pf).round()
	chip.custom_minimum_size = chip_size
	chip.offset_left = -chip_size.x * 0.5
	chip.offset_right = chip_size.x * 0.5
	chip.offset_top = maxf(0.0, roundf(ring.offset_top + ring.width * 0.5 - chip_size.y * 0.5))
	chip.offset_bottom = chip.offset_top + chip_size.y
	_scale_font(%LevelText, pf)
	_scale_font(%LevelPrefix, pf)
	var pad: MarginContainer = %LevelPrefixPad
	pad.add_theme_constant_override(&"margin_top",
			roundi(float(pad.get_theme_constant(&"margin_top")) * pf))
	_paint_chip()
	# Gauges: × WEEK_GAUGE_SCALE (sizes, not `scale`), right under the bigger ring.
	var gf: float = WEEK_GAUGE_SCALE
	gauges.add_theme_constant_override(&"separation",
			roundi(float(gauges.get_theme_constant(&"separation")) * gf))
	for g in [%PilotGauge_Stress, %PilotGauge_Trust]:
		(g as PilotGauge).set_size_factor(gf)
	var gauges_h: float = roundf((gauges.offset_bottom - gauges.offset_top) * gf)
	gauges.offset_top = ring.offset_bottom + gap
	gauges.offset_bottom = gauges.offset_top + gauges_h
	custom_minimum_size.y = gauges.offset_bottom + tail
	if pilot_id >= 0:
		_draw_portrait(PilotImages.circle_for(pilot_id))


static func _scale_font(lbl: Label, f: float) -> void:
	lbl.add_theme_font_size_override(&"font_size",
			roundi(float(lbl.get_theme_font_size(&"font_size")) * f))


func _show_gauges(on: bool) -> void:
	for g in [%PilotGauge_Stress, %PilotGauge_Trust]:
		(g as Control).visible = on


## The run's `season_state` ({} outside a run).
func _run_state() -> Dictionary:
	var gm: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameManager")
	return gm.season_state if gm != null else {}


## Reads the run's 깨달음 level for `pid` (`TrainingLevel`; my run pilots only): the chip and
## the portrait ring (EXP bar; `exp_delta` = the day's level EXP, shown as a light segment
## ending at the current fill — a level-up today just fills from 0).
func _show_run_level(pid: int, exp_delta: int) -> void:
	var state: Dictionary = _run_state()
	if not TrainingLevel.has_level(state, pid):
		set_training_level(0)
		_set_ring(0.0, 0.0, OutgameTheme.LINK)
		return
	set_training_level(TrainingLevel.level(state, pid))
	var capped: bool = TrainingLevel.is_capped(state, pid)
	var now: float = TrainingLevel.progress(state, pid)
	var before: float = now
	# `exp_delta` is EXP the level actually took today (row `tlexp`, `tlexp` notes; a capped
	# bar takes 0), so:
	# - capped (locked at an even level / Lv max) with a delta = it filled today: the full ring is
	#   the level below's bar (`need_for_level(lv - 1)`); a delta over that bar (an earlier bar
	#   too) just fills from 0. Capped since an earlier day: delta 0, no segment.
	# - filling (incl. after a limit break, `broken`): the current bar. A level-up or a break
	#   today put the whole current EXP in today's delta, so the segment runs from 0.
	var lv: int = TrainingLevel.level(state, pid)
	var need: int = TrainingLevel.need_for_level(lv - 1) if capped \
			else TrainingLevel.exp_need(state, pid)
	if exp_delta > 0 and need > 0:
		before = maxf(0.0, now - float(exp_delta) / float(need))
	_set_ring(before, now, OutgameTheme.ACCENT if capped else OutgameTheme.LINK)


## Portrait ring: solid fill to `before`, the light change segment `before` → `now`; the
## level chip takes the same colour.
func _set_ring(before: float, now: float, col: Color) -> void:
	var ring: ProgressRing = %Ring
	ring.color = col
	ring.ratio = before
	ring.seg_from = before
	ring.seg_to = now
	ring.seg_color = col.lerp(Color.WHITE, PilotGauge.RISE_LIGHTEN)
	_ring_color = col
	_paint_chip()


## Level chip background = the ring colour (pill, radius = half its height).
func _paint_chip() -> void:
	var chip: Panel = %LevelChip
	chip.add_theme_stylebox_override(&"panel", OutgameTheme.flat_style(
			_ring_color, int(chip.custom_minimum_size.y * 0.5)))


## The gauges with the changes that led to the shown values (week screen: the day's stress /
## trust points; 0 = just the value) and the day's 깨달음 level EXP on the portrait ring
## (`exp_delta`, 0 = none). Call after `show_pilot`.
func set_day_deltas(stress_delta: int, trust_delta: int, exp_delta: int = 0) -> void:
	if pilot_id < 0:
		return
	(%PilotGauge_Stress as PilotGauge).show_stress(_stress, stress_delta)
	(%PilotGauge_Trust as PilotGauge).show_trust(_trust, trust_delta)
	_show_run_level(pilot_id, exp_delta)


## Short pop on the change lines — the week screen calls it when the day's changes land.
func pulse_deltas() -> void:
	for g in [%PilotGauge_Stress, %PilotGauge_Trust]:
		(g as PilotGauge).pulse_delta()


func _draw_portrait(tex: Texture2D) -> void:
	var slot: Control = %Portrait
	for c in slot.get_children():
		slot.remove_child(c)
		c.queue_free()
	OutgameTheme.add_round_portrait(slot, tex, Vector2.ZERO, slot.size.x)


func _on_hit() -> void:
	if pilot_id >= 0:
		pressed.emit(pilot_id)


## F6 preview — one shaken mid pilot with trust past half, today's stress +12 · trust +3,
## level chip `Lv 3` in the ring's LINK colour while the ring fills 0.55 → 0.8
## (`resources/UiPreview.gd`; outside a run, so the ring is filled by hand). Uses a real pilot
## id (Corin) so the face shows.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var t_max: int = ConstTable.int_of("TRUST_MAX")
	show_pilot(2, int(float(t_max) * 0.6),
			ConstTable.int_of("STRESS_THRESHOLD") + 20)
	set_day_deltas(12, 3)
	set_training_level(3)
	_set_ring(0.55, 0.8, OutgameTheme.LINK)
	UiPreview.trace(pressed, "pressed")
