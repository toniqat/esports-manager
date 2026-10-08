class_name SeasonPilotCard
extends Panel

# Small vertical pilot card shown five in a row (seat order) on the season hub and at the
# bottom of the week screen: position badge on top, round portrait inside a **trust ring**
# (`TrustRing`, trust / TRUST_MAX in the trust band colour) with the trust number on a pill at
# its bottom-right, then the stress line and one emphasised note line (hub: the mood when
# shaken; week: that day's stress change). Tapping the card emits `pressed(pilot_id)`; the
# screens open `SeasonPilotDetail` with it.
#
# **Layout lives in `UI_Comp_SeasonPilotCard.tscn`.** This script fills `%` nodes and paints
# the data colours (ring / pill = `HubView.trust_color`, stress / note label variations).

signal pressed(pilot_id: int)

const SCENE_PATH: String = "res://features/season/UI_Comp_SeasonPilotCard.tscn"

## Pilot shown on this card (-1 = empty seat).
var pilot_id: int = -1


static func create() -> SeasonPilotCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as SeasonPilotCard


func _ready() -> void:
	(%Hit as Button).pressed.connect(_on_hit)
	if UiPreview.is_standalone(self):
		_fill_preview()


## Whether the card reacts to taps (the detail sheet's own header card does not).
func set_tappable(on: bool) -> void:
	(%Hit as Button).visible = on


## Fills the card. `trust` / `stress` are the run values (`MentalSystem.trust`,
## `StressSystem.value`). The note line shows the mood when shaken, else stays empty —
## callers that have something to say there (the week's stress change) call `set_note` after.
func show_pilot(pid: int, role: int, trust: int, stress: int) -> void:
	pilot_id = pid
	(%PositionBadge_Role as PositionBadge).set_role(role)
	_draw_portrait(PilotImages.circle_for(pid))
	var t_max: int = maxi(1, ConstTable.int_of("TRUST_MAX"))
	var col: Color = HubView.trust_color(trust)
	var ring: TrustRing = %Ring
	ring.ratio = float(trust) / float(t_max)
	ring.color = col
	var pill: Panel = %TrustPill
	pill.visible = true
	pill.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(col, int(pill.custom_minimum_size.y * 0.5)))
	(%TrustText as Label).text = "%d" % trust
	var shaken: bool = StressSystem.is_over(stress)
	var sl: Label = %Stress
	sl.text = Loc.t(L.MENTAL_UI_STRESS_VALUE, {"n": stress})
	sl.theme_type_variation = &"NegativeLabel" if shaken else &"CaptionLabel"
	set_note(StressSystem.mood_label(StressSystem.Mood.SHAKEN) if shaken else "", &"NegativeLabel")
	(%Hit as Button).disabled = false


## Empty seat: badge of the seat's role, blank portrait, no numbers.
func show_empty(role: int) -> void:
	pilot_id = -1
	(%PositionBadge_Role as PositionBadge).set_role(role)
	_draw_portrait(null)
	(%Ring as TrustRing).ratio = 0.0
	(%TrustPill as Control).visible = false
	(%Stress as Label).text = "—"
	set_note("", &"CaptionLabel")
	(%Hit as Button).disabled = true


## The emphasised line under the stress (`variation` = a label variation such as
## `NegativeLabel` / `PositiveLabel`); "" hides it.
func set_note(text: String, variation: StringName) -> void:
	var nl: Label = %StressNote
	nl.text = text
	nl.theme_type_variation = variation
	nl.visible = text != ""


## Short pop on the note line — the week screen calls it when the day's stress change lands.
func pulse_note() -> void:
	var nl: Label = %StressNote
	if not nl.visible:
		return
	nl.pivot_offset = nl.size * 0.5
	nl.scale = Vector2.ONE * 1.6
	var tw: Tween = nl.create_tween()
	tw.tween_property(nl, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw_portrait(tex: Texture2D) -> void:
	var slot: Control = %Portrait
	for c in slot.get_children():
		slot.remove_child(c)
		c.queue_free()
	OutgameTheme.add_round_portrait(slot, tex, Vector2.ZERO, slot.size.x)


func _on_hit() -> void:
	if pilot_id >= 0:
		pressed.emit(pilot_id)


## F6 단독 실행 미리보기 — 신뢰가 반을 넘고 위축된 미드 선수 한 장 (`resources/UiPreview.gd`).
## 얼굴이 나오게 실제 선수 id(Corin)를 쓴다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var t_max: int = ConstTable.int_of("TRUST_MAX")
	show_pilot(2, GameEnums.Role.ASSASSIN, int(float(t_max) * 0.6),
			ConstTable.int_of("STRESS_THRESHOLD") + 20)
	UiPreview.trace(pressed, "pressed")
