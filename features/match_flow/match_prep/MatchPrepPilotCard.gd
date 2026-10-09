class_name MatchPrepPilotCard
extends PanelContainer

# One pilot of the PREP screen — a vertical card shaped like the season `SeasonPilotCard`
# (position badge on top, round portrait), five in a row in seat order per team.
#   • Own team: the top part IS a `SeasonPilotCard` instance (trust ring / level pill, stress,
#     note line) drawn without its own card (`MatchPrepCardInner`), so it follows whatever the
#     season card shows.
#   • Opponent: badge + portrait with a role-coloured rim, no trust / stress; the red
#     "경계 대상" chip at the top-right when the analyst names this pilot
#     (`OpponentIntel.build()["threat_pilot_id"]`).
#   Both: the stat total as a big number (`row.total_text` — `?` / `≈n` / exact, by reveal tier)
#   and up to two main-mech chips (opponents only from tier 2; tier 0–1 shows one faint `?`).
# Tapping the card emits `pressed(pilot_id)`; `MatchPrepView` opens the detail sheet.
#
# **Layout lives in `UI_Comp_MatchPrepPilotCard.tscn`.** This script fills `%` nodes, toggles the
# own / opponent top part, draws the opponent portrait and picks label variations (shown vs.
# hidden total, hidden mechs).

signal pressed(pilot_id: int)

const SCENE_PATH: String = "res://features/match_flow/match_prep/UI_Comp_MatchPrepPilotCard.tscn"
## Mech chips shown at most (the scene has this many `MechChip*` nodes).
const MAX_MECHS: int = 2

## Pilot shown on this card (-1 = not filled yet).
var pilot_id: int = -1


static func create() -> MatchPrepPilotCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MatchPrepPilotCard


func _ready() -> void:
	(%Hit as Button).pressed.connect(_on_hit)
	(%SeasonPilotCard_Own as SeasonPilotCard).set_tappable(false)
	if UiPreview.is_standalone(self):
		_fill_preview()


## `row` = one entry of `OpponentIntel.build()["rows"]`. `own` = my team: the season card part
## with `trust` (points) / `stress` (run values). `warn` = the analyst's "경계 대상" pilot.
func fill(row: Dictionary, own: bool, trust: int, stress: int, warn: bool) -> void:
	pilot_id = int(row["pilot_id"])
	var role: int = int(row["role"])
	var inner: SeasonPilotCard = %SeasonPilotCard_Own
	inner.visible = own
	(%EnemyTop as Control).visible = not own
	if own:
		inner.show_pilot(pilot_id, trust, stress)
	else:
		(%PositionBadge_Role as PositionBadge).set_role(role)
		_draw_portrait(PilotImages.circle_for(pilot_id),
				OutgameTheme.ROLE_COLORS[clampi(role, 0, 4)])
	(%Warn as Control).visible = warn and not own

	var shown: bool = bool(row["show_stats"])
	var total: Label = %Overall
	total.text = String(row["total_text"])
	total.theme_type_variation = &"HeadingLabel" if shown else &"FaintLabel"
	_fill_mechs(row)


func _fill_mechs(row: Dictionary) -> void:
	var texts: Array = []
	var faint: bool = false
	if not bool(row["show_mechs"]):
		texts = ["?"]
		faint = true
	else:
		for raw in (row["mechs"] as Array):
			if texts.size() >= MAX_MECHS:
				break
			texts.append(String((raw as Dictionary)["name"]))
		if texts.is_empty():
			texts = [Loc.t(L.MATCH_PREP_NO_MECH)]
			faint = true
	var chips: Array = (%Mechs as Node).get_children()
	for i in chips.size():
		var chip := chips[i] as Control
		chip.visible = i < texts.size()
		if not chip.visible:
			continue
		var lbl := chip.get_node("Text") as Label
		lbl.text = String(texts[i])
		lbl.theme_type_variation = &"FaintLabel" if faint else &"BodyLabel"


func _draw_portrait(tex: Texture2D, ring: Color) -> void:
	var slot: Control = %Portrait
	for c in slot.get_children():
		slot.remove_child(c)
		c.queue_free()
	OutgameTheme.add_round_portrait(slot, tex, Vector2.ZERO, slot.size.x, ring)


func _on_hit() -> void:
	if pilot_id >= 0:
		pressed.emit(pilot_id)


## F6 단독 실행 미리보기 — 분석가가 경계 대상으로 짚은 상대 미드 한 장(2단계: 정확한 합계 + 주력
## 메크 둘). 손으로 적은 값, 얼굴이 나오게 실제 선수 id 를 쓴다.
func _fill_preview() -> void:  # l10n-ignore
	UiPreview.stage(self)
	UiPreview.trace(pressed, "pressed")
	fill({
		"pilot_id": 2, "name": "Shunguang", "role": GameEnums.Role.ASSASSIN,
		"show_stats": true, "exact": true, "total_text": "536",
		"show_mechs": true, "mechs": [{"mech_id": 6, "name": "Headsman"},
				{"mech_id": 7, "name": "Reaper"}],
	}, false, 0, 0, true)
