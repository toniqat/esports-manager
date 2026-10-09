class_name SeasonPilotCard
extends Panel

# Small vertical pilot card shown five in a row (seat order) on the season hub and at the
# bottom of the week screen: round portrait inside a **level ring** on top (`ProgressRing` =
# the run-only 깨달음 level's EXP bar, `TrainingLevel.progress`; LINK blue, ACCENT while capped =
# limit break due or max) with the level chip `Lv N` at its bottom-left (`set_training_level`,
# accent while a limit break is due), then two gauges (`PilotGauge`: stress · trust). No card
# background (`SeasonPilotCardBare`): the parts sit on the page. Each gauge shows its value
# under the ring (stress number · trust percent); the week screen adds that day's changes
# (`set_day_deltas`: gauge ring segment + `(+N)` / `(+N%)` under the value, the day's level EXP
# as a light segment on the portrait ring). No position badge — the seat order (`GameEnums.ROLE_DISPLAY_ORDER`) says the role. Tapping the card emits `pressed(pilot_id)`; the
# screens open `SeasonPilotDetail` with it.
#
# **Layout lives in `UI_Comp_SeasonPilotCard.tscn`.** This script fills `%` nodes and paints
# the data colours.

signal pressed(pilot_id: int)

const SCENE_PATH: String = "res://features/season/UI_Comp_SeasonPilotCard.tscn"

## Pilot shown on this card (-1 = empty seat).
var pilot_id: int = -1
## Values shown by the last `show_pilot` (`set_day_deltas` redraws the gauges with them).
var _stress: int = 0
var _trust: int = 0
## `set_gauges_visible` — false keeps the two gauges (and their value / change lines) hidden.
var _gauges_on: bool = true


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
	(%LevelChip as Control).visible = false
	_show_gauges(false)
	(%Hit as Button).disabled = true


## 깨달음 level chip: `level` < 1 hides it; `alert` (a limit break is due) paints it in the
## accent colour instead of the dark rail.
func set_training_level(level: int, alert: bool) -> void:
	var chip: Panel = %LevelChip
	chip.visible = level >= 1
	if not chip.visible:
		return
	(%LevelText as Label).text = Loc.t(L.TRAINING_LEVEL_CHIP, {"n": level})
	chip.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
			OutgameTheme.ACCENT if alert else OutgameTheme.RAIL, int(chip.custom_minimum_size.y * 0.5)))


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
		set_training_level(0, false)
		_set_ring(0.0, 0.0, OutgameTheme.LINK)
		return
	set_training_level(TrainingLevel.level(state, pid),
			TrainingLevel.awaiting_break(state, pid))
	var capped: bool = TrainingLevel.is_capped(state, pid)
	var now: float = TrainingLevel.progress(state, pid)
	var before: float = now
	# Capped (locked / max): the full ring is the bar that just filled, the level below's.
	var lv: int = TrainingLevel.level(state, pid)
	var need: int = TrainingLevel.need_for_level(lv - 1) if capped \
			else TrainingLevel.exp_need(state, pid)
	if exp_delta > 0 and need > 0:
		before = maxf(0.0, now - float(exp_delta) / float(need))
	_set_ring(before, now, OutgameTheme.ACCENT if capped else OutgameTheme.LINK)


## Portrait ring: solid fill to `before`, the light change segment `before` → `now`.
func _set_ring(before: float, now: float, col: Color) -> void:
	var ring: ProgressRing = %Ring
	ring.color = col
	ring.ratio = before
	ring.seg_from = before
	ring.seg_to = now
	ring.seg_color = col.lerp(Color.WHITE, PilotGauge.RISE_LIGHTEN)


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


## F6 단독 실행 미리보기 — 신뢰가 반을 넘고 위축된 미드 선수 한 장, 오늘 스트레스 +12 · 신뢰 +3,
## 한계돌파 대기(강조색) 레벨 칩 (`resources/UiPreview.gd`; 런 밖이라 링은 손으로 채운다).
## 얼굴이 나오게 실제 선수 id(Corin)를 쓴다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var t_max: int = ConstTable.int_of("TRUST_MAX")
	show_pilot(2, int(float(t_max) * 0.6),
			ConstTable.int_of("STRESS_THRESHOLD") + 20)
	set_day_deltas(12, 3)
	set_training_level(2, true)
	_set_ring(0.55, 0.8, OutgameTheme.LINK)
	UiPreview.trace(pressed, "pressed")
