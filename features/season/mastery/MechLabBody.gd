class_name MechLabBody
extends Control

# Mech-lab facility body (§16, `MechResearch.make_body`, full rect in `FacilityView` `%BodySlot`).
# A 3-column grid of the mechs the lab can research (`MechResearch.targets`, in that order),
# about 4.5 rows visible, only the grid scrolls (`DragScroll`). Each card: mech art · name ·
# role badge · its research progress (`ResearchSystem.progress`, paused points included) and up
# to three suggested pilots (`MechResearch.fit_pilots`: highest mastery first, then own-role
# pilots). Tap a card = research that mech (`ResearchSystem.select`, HUB only — cards are
# disabled once the week runs); the lab's active mech is the highlighted card.
#
# **Layout lives in `UI_View_MechLabBody.tscn`** (+ items `UI_Comp_MechLabCard` ·
# `UI_Comp_MechLabPilot`). This script fills `%` nodes, instances cards and applies data looks
# (card variation = active or not, progress fill, level colour, the round pilot portraits).
# Built with `create(state)`; it fills itself once in the tree, `refresh()` refills in place.

## The body changed the lab's research → `FacilityView` refreshes its header.
signal changed
## A refusal to show as the screen's toast.
signal message(text: String)

const SCENE_PATH: String = "res://features/season/mastery/UI_View_MechLabBody.tscn"
const CARD_SCENE: PackedScene = preload("res://features/season/mastery/UI_Comp_MechLabCard.tscn")
## Suggested pilots per mech card (= the card scene's `MechLabPilot_*` slots).
const PILOTS_PER_CARD: int = 3

var _state: Dictionary = {}
var _bound: bool = false


## Instantiates the scene bound to `state` (fills on entering the tree). `.new()` is an empty box.
static func create(state: Dictionary) -> MechLabBody:
	var body := (load(SCENE_PATH) as PackedScene).instantiate() as MechLabBody
	body._state = state
	body._bound = true
	return body


func _ready() -> void:
	DragScroll.attach(%Scroll)
	if _bound:
		refresh()
	elif UiPreview.is_standalone(self):
		_fill_preview()


## The lab's research row (`mech_study`): the first mech-lab row, {} when none.
static func _lab_row() -> Dictionary:
	var rows: Array = ResearchSystem.rows_for(MechResearch.FID)
	return rows[0] if not rows.is_empty() else {}


## Refills the grid from the bound state.
func refresh() -> void:
	var state: Dictionary = _state
	var r: Dictionary = _lab_row()
	var offered: Array = []
	if not r.is_empty() and MechMastery.is_enabled(state):
		offered = MechResearch.targets(state, r)
	%Empty.visible = offered.is_empty()
	%Scroll.visible = not offered.is_empty()
	var cards: Array = _ensure(%Grid, offered.size())
	if offered.is_empty():
		return
	var rid: String = String(r["id"])
	var act: Dictionary = ResearchSystem.active(state, MechResearch.FID)
	var active_target: String = String(act.get("target", "")) if String(act.get("rid", "")) == rid else ""
	var pickable: bool = ResearchSystem.can_select(state)
	for i in cards.size():
		var t: String = String((offered[i] as Dictionary)["id"])
		_fill_card(cards[i], rid, t, t == active_target, pickable)


func _fill_card(card: Button, rid: String, target: String, is_active: bool, pickable: bool) -> void:
	var state: Dictionary = _state
	var mech: int = int(target)
	card.set_meta(&"target", target)
	card.theme_type_variation = &"SelectableCardButtonOn" if is_active else &"SelectableCardButton"
	card.disabled = not pickable
	(card.get_node("%Art") as TextureRect).texture = MechImages.portrait_for(mech)
	card.get_node("%Name").text = MechMastery.mech_name(mech)
	(card.get_node("%PositionBadge_Role") as PositionBadge).set_role(MechResearch.mech_role(mech))
	var p: float = ResearchSystem.progress(state, MechResearch.FID, rid, target)
	var pct: Label = card.get_node("%Pct")
	pct.text = "%d%%" % roundi(p * 100.0)
	pct.theme_type_variation = &"AccentLabel" if is_active or p > 0.0 else &"FaintLabel"
	var fill: Control = card.get_node("%Fill")
	fill.visible = p > 0.0
	fill.anchor_right = clampf(p, 0.0, 1.0)
	var fit: Array = MechResearch.fit_pilots(state, mech, PILOTS_PER_CARD)
	var slots: Array = card.get_node("%Pilots").get_children()
	for i in slots.size():
		_fill_pilot(slots[i], fit[i] as PlayerData if i < fit.size() else null, mech)


## One pilot slot: round portrait (role ring) · name · `Lv3 · 65` on `mech`. null = transparent.
func _fill_pilot(slot: Control, pd: PlayerData, mech: int) -> void:
	slot.modulate.a = 0.0 if pd == null else 1.0
	if pd == null:
		return
	var portrait: Control = slot.get_node("%Portrait")
	if portrait.get_meta(&"pilot_id", -1) != pd.id:
		portrait.set_meta(&"pilot_id", pd.id)
		for c in portrait.get_children():
			c.queue_free()
		OutgameTheme.add_round_portrait(portrait, PilotImages.circle_for(pd.id), Vector2.ZERO,
				portrait.custom_minimum_size.x, OutgameTheme.ROLE_COLORS[clampi(pd.role, 0, 4)])
	slot.get_node("%Name").text = pd.name
	var v: int = MechMastery.value(_state, pd.id, mech)
	var lv: int = MechMastery.level_for_value(v)
	var lvl: Label = slot.get_node("%Level")
	lvl.text = "%s · %d" % [MechMastery.level_name(lv), v]
	lvl.add_theme_color_override("font_color", MechMastery.level_color(lv))


func _on_card_pressed(card: Button) -> void:
	var r: Dictionary = _lab_row()
	if r.is_empty():
		return
	var err: String = ResearchSystem.select(_state, MechResearch.FID, String(r["id"]),
			String(card.get_meta(&"target", "")))
	if err != "":
		message.emit(err)
		return
	refresh()
	changed.emit()


## Keeps exactly `n` cards in `grid` (the scene sample counts as one) and returns them.
func _ensure(grid: Node, n: int) -> Array:
	while grid.get_child_count() > n:
		var last: Node = grid.get_child(grid.get_child_count() - 1)
		grid.remove_child(last)
		last.queue_free()
	while grid.get_child_count() < n:
		grid.add_child(CARD_SCENE.instantiate())
	for c in grid.get_children():
		var card := c as Button
		if not card.has_meta(&"wired"):
			card.set_meta(&"wired", true)
			card.pressed.connect(_on_card_pressed.bind(card))
	return grid.get_children()


## F6 단독 실행 미리보기 — 메모리 런(허브 상태)에서 첫 대상 메크를 연구 중(40%)으로, 둘째 메크에
## 멈춘 진행(20%)을 넣고 채운다. 본문 슬롯 크기를 흉내 내 좌우 · 위아래 여백을 둔다(`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	offset_left = 40.0
	offset_right = -40.0
	offset_top = 224.0
	offset_bottom = -256.0
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var state: Dictionary = gm.season_state
	state["week_day"] = -1
	var r: Dictionary = _lab_row()
	var offered: Array = ResearchSystem.targets(state, r) if not r.is_empty() else []
	if offered.size() >= 2:
		var rid: String = String(r["id"])
		ResearchSystem.points(state, rid, "")  # makes sure `research.points` exists
		var pts: Dictionary = (state.get("research", {}) as Dictionary).get("points", {})
		var first: String = String((offered[0] as Dictionary)["id"])
		var second: String = String((offered[1] as Dictionary)["id"])
		pts[ResearchSystem.key_of(rid, first)] = roundi(ResearchSystem.cost(r) * 0.4)
		pts[ResearchSystem.key_of(rid, second)] = roundi(ResearchSystem.cost(r) * 0.2)
		ResearchSystem.select(state, MechResearch.FID, rid, first)
	_state = state
	_bound = true
	refresh()
