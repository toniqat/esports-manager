class_name SeasonPilotCard
extends Panel

# Small vertical pilot card shown five in a row (seat order) on the season hub and at the
# bottom of the week screen: round portrait inside a **trust ring** on top
# (`TrustRing`, progress toward the next trust level in the trust band colour) with the trust
# **level** on a pill at its bottom-right (`MentalSystem.level_of_trust` / `progress_of_trust`),
# then three gauges (`PilotGauge`: stress · trust · awakening). No card background
# (`SeasonPilotCardBare`): the parts sit on the page. Each gauge shows its value under the ring
# (stress number · trust / awakening percent); the week screen adds that day's changes
# (`set_day_deltas`: ring segment + `(+N)` / `(+N%)` under the value). No
# position badge — the seat order (`GameEnums.ROLE_DISPLAY_ORDER`) says the role. Tapping the card emits `pressed(pilot_id)`; the
# screens open `SeasonPilotDetail` with it.
#
# **Layout lives in `UI_Comp_SeasonPilotCard.tscn`.** This script fills `%` nodes and paints
# the data colours (ring / pill = `HubView.trust_color`).

signal pressed(pilot_id: int)

const SCENE_PATH: String = "res://features/season/UI_Comp_SeasonPilotCard.tscn"

## Pilot shown on this card (-1 = empty seat).
var pilot_id: int = -1
## Values shown by the last `show_pilot` (`set_day_deltas` redraws the gauges with them).
var _stress: int = 0
var _trust: int = 0
## `set_gauges_visible` — false keeps the three gauges (and their value / change lines) hidden.
var _gauges_on: bool = true


static func create() -> SeasonPilotCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as SeasonPilotCard


func _ready() -> void:
	(%Hit as Button).pressed.connect(_on_hit)
	if UiPreview.is_standalone(self):
		_fill_preview()


## Shows / hides the three gauges with their value and change lines (default shown; the
## PREP screen hides them). Positions are fixed in the scene, so the rest of the card stays put.
func set_gauges_visible(on: bool) -> void:
	_gauges_on = on
	_show_gauges(on and pilot_id >= 0)


## Whether the card reacts to taps (the detail sheet's own header card does not).
func set_tappable(on: bool) -> void:
	(%Hit as Button).visible = on


## Fills the card. `trust` / `stress` are the run values (`MentalSystem.trust` points — shown
## as level + progress here, `StressSystem.value`); the awakening gauge is read from the run
## (`Awakening.gauge`). The gauges show just the values — the week screen calls
## `set_day_deltas` after for the day's changes.
func show_pilot(pid: int, trust: int, stress: int) -> void:
	pilot_id = pid
	_draw_portrait(PilotImages.circle_for(pid))
	var level: int = MentalSystem.level_of_trust(trust)
	var col: Color = HubView.trust_color(level)
	var ring: TrustRing = %Ring
	ring.ratio = MentalSystem.progress_of_trust(trust)
	ring.color = col
	var pill: Panel = %TrustPill
	pill.visible = true
	pill.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(col, int(pill.custom_minimum_size.y * 0.5)))
	(%TrustText as Label).text = "%d" % level
	_stress = stress
	_trust = trust
	_show_gauges(_gauges_on)
	(%PilotGauge_Stress as PilotGauge).show_stress(stress)
	(%PilotGauge_Trust as PilotGauge).show_trust(trust)
	(%PilotGauge_Awaken as PilotGauge).show_awakening(
			Awakening.gauge(_run_state(), pid), Awakening.threshold())
	_show_run_level(pid)
	(%Hit as Button).disabled = false


## Empty seat: blank portrait, no gauges, no numbers.
func show_empty() -> void:
	pilot_id = -1
	_draw_portrait(null)
	(%Ring as TrustRing).ratio = 0.0
	(%TrustPill as Control).visible = false
	(%LevelChip as Control).visible = false
	_show_gauges(false)
	(%Hit as Button).disabled = true


## §15 B training level chip: `level` < 1 hides it; `alert` (bar full / limit-break goal open)
## paints it in the accent colour instead of the dark rail.
func set_training_level(level: int, alert: bool) -> void:
	var chip: Panel = %LevelChip
	chip.visible = level >= 1
	if not chip.visible:
		return
	(%LevelText as Label).text = Loc.t(L.TRAINING_LEVEL_CHIP, {"n": level})
	chip.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
			OutgameTheme.ACCENT if alert else OutgameTheme.RAIL, int(chip.custom_minimum_size.y * 0.5)))


func _show_gauges(on: bool) -> void:
	for g in [%PilotGauge_Stress, %PilotGauge_Trust, %PilotGauge_Awaken]:
		(g as Control).visible = on


## The run's `season_state` ({} outside a run).
func _run_state() -> Dictionary:
	var gm: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameManager")
	return gm.season_state if gm != null else {}


## Reads the run's training level for `pid` (`TrainingLevel`; my run pilots only).
func _show_run_level(pid: int) -> void:
	var state: Dictionary = _run_state()
	if not TrainingLevel.has_level(state, pid):
		set_training_level(0, false)
		return
	set_training_level(TrainingLevel.level(state, pid),
			TrainingLevel.awaiting_break(state, pid))


## The gauges with the changes that led to the shown values (week screen: the day's stress /
## trust points / awakening gauge change; 0 = just the value). Call after `show_pilot`.
func set_day_deltas(stress_delta: int, trust_delta: int, awaken_delta: int) -> void:
	if pilot_id < 0:
		return
	(%PilotGauge_Stress as PilotGauge).show_stress(_stress, stress_delta)
	(%PilotGauge_Trust as PilotGauge).show_trust(_trust, trust_delta)
	(%PilotGauge_Awaken as PilotGauge).show_awakening(
			Awakening.gauge(_run_state(), pilot_id), Awakening.threshold(), awaken_delta)


## Short pop on the change lines — the week screen calls it when the day's changes land.
func pulse_deltas() -> void:
	for g in [%PilotGauge_Stress, %PilotGauge_Trust, %PilotGauge_Awaken]:
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


## F6 단독 실행 미리보기 — 신뢰가 반을 넘고 위축된 미드 선수 한 장, 오늘 스트레스 +12 · 신뢰 +3 · 깨달음 +10 (`resources/UiPreview.gd`).
## 얼굴이 나오게 실제 선수 id(Corin)를 쓴다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var t_max: int = ConstTable.int_of("TRUST_MAX")
	show_pilot(2, int(float(t_max) * 0.6),
			ConstTable.int_of("STRESS_THRESHOLD") + 20)
	set_day_deltas(12, 3, 10)
	set_training_level(2, true)
	UiPreview.trace(pressed, "pressed")
