class_name MechLabBody
extends VBoxContainer

# Mech-lab section of the facility sheet (§16, `MechResearch.make_body`) — read-only
# mastery overview of my five pilots (role display order) against the lab's research mech
# (`MechResearch.lab_mech`): what each pilot gains on completion, the level / bar of that
# mech plus their own-role mechs, top-3 mastery, the next mech upgrade, and their quirks
# (§14 — the research quirk roll happens on lab completion). Choosing the research and
# its target mech is the facility sheet's research list, not this body.
#
# **Layout lives in `UI_View_MechLabBody.tscn`** (+ item scenes `UI_Comp_MasteryPilotRow` ·
# `UI_Comp_MasteryMechChip` · `UI_Comp_MasteryQuirkLine`). This script fills `%` nodes,
# instances rows and applies data colours (level bar / grade colours, chip variation =
# `PrimaryButton` for the lab mech), the round portrait (`_draw` widget into `%Portrait`)
# and each card's height. Built with `create(state)`; it fills itself once in the tree,
# `refresh()` refills in place (rows / chips reused).

const SCENE_PATH: String = "res://features/season/mastery/UI_View_MechLabBody.tscn"
const PILOT_ROW_SCENE: PackedScene = preload("res://features/season/mastery/UI_Comp_MasteryPilotRow.tscn")
const CHIP_SCENE: PackedScene = preload("res://features/season/mastery/UI_Comp_MasteryMechChip.tscn")
const QUIRK_LINE_SCENE: PackedScene = preload("res://features/season/mastery/UI_Comp_MasteryQuirkLine.tscn")
## Chips per pilot card: the lab mech first, then own-role mechs.
const CHIP_COUNT: int = 3

var _state: Dictionary = {}
var _bound: bool = false


## Instantiates the scene bound to `state` (fills on entering the tree). `.new()` is an empty box.
static func create(state: Dictionary) -> MechLabBody:
	var body := (load(SCENE_PATH) as PackedScene).instantiate() as MechLabBody
	body._state = state
	body._bound = true
	return body


func _ready() -> void:
	if _bound:
		refresh()
	elif UiPreview.is_standalone(self):
		_fill_preview()


## Refills the whole body from the bound state.
func refresh() -> void:
	var state: Dictionary = _state
	var enabled: bool = MechMastery.is_enabled(state)
	%Empty.visible = not enabled
	%Main.visible = enabled
	if not enabled:
		return
	%Head.text = Loc.t(L.MASTERY_PANEL_HEAD, {"name": StaffSystem.owner_name(state, "knowledge"),
			"value": StaffSystem.effective(state, "knowledge")})
	var pilots: Array = MechMastery.my_pilots(state)
	var any_pid: int = (pilots[0] as PlayerData).id if not pilots.is_empty() else -1
	%Gain.text = Loc.t(L.MASTERY_PANEL_GAIN, {"mult": "%.2f" % MechMastery.gain_mult(state, any_pid)})

	var mech: int = MechResearch.lab_mech(state)
	var raw: int = 0
	var target: Label = %Target
	if mech >= 0:
		raw = MechResearch.raw_gain(ResearchSystem.row(String(ResearchSystem.active(state, MechResearch.FID)["rid"])))
		target.text = Loc.t(L.RESEARCH_MECH_BODY_TARGET, {"mech": MechMastery.mech_name(mech),
				"n": MechMastery.gain_preview(state, any_pid, raw)})
		target.theme_type_variation = &"AccentLabel"
	else:
		target.text = Loc.t(L.RESEARCH_MECH_BODY_NO_TARGET)
		target.theme_type_variation = &"FaintLabel"

	var legend: Array = []
	for lv in MechMastery.LEVEL_MAX + 1:
		legend.append("%s %s" % [MechMastery.level_name(lv), MechMastery.pct_text(lv)])
	%Legend.text = Loc.t(L.MASTERY_PANEL_LEGEND, {"tiers": "  ".join(legend)})

	var quirks_on: bool = QuirkSystem.is_enabled(state)
	%QuirkOdds.visible = quirks_on
	if quirks_on:
		var odds: Array = QuirkSystem.grade_odds(state)
		var parts: Array = []
		for g in QuirkSystem.GRADE_COUNT:
			parts.append("%s %d%%" % [QuirkSystem.grade_name(g), roundi(float(odds[g]))])
		%QuirkOdds.text = Loc.t(L.RESEARCH_MECH_BODY_QUIRK_ODDS, {
				"pct": ConstTable.int_of("QUIRK_RESEARCH_CHANCE"), "odds": "  ".join(parts)})

	var rows: Array = _ensure(%Pilots, PILOT_ROW_SCENE, pilots.size())
	for i in rows.size():
		_fill_pilot_row(rows[i], pilots[i] as PlayerData, mech, raw, quirks_on)


func _fill_pilot_row(row: Panel, pd: PlayerData, mech: int, raw: int, quirks_on: bool) -> void:
	var state: Dictionary = _state
	var portrait: Control = row.get_node("%Portrait")
	if row.get_meta(&"pilot_id", -1) != pd.id:
		row.set_meta(&"pilot_id", pd.id)
		for c in portrait.get_children():
			c.queue_free()
		OutgameTheme.add_round_portrait(portrait, PilotImages.circle_for(pd.id), Vector2.ZERO,
				portrait.size.x, OutgameTheme.ROLE_COLORS[clampi(pd.role, 0, 4)])
	row.get_node("%Name").text = pd.name
	(row.get_node("%PositionBadge_Position") as PositionBadge).set_role(int(pd.role))

	# What this pilot gets from the lab's research (or that there is none).
	var res_l: Label = row.get_node("%Research")
	if mech >= 0:
		var lv: int = MechMastery.level_of(state, pd.id, mech)
		var at_max: bool = MechMastery.value(state, pd.id, mech) >= MechMastery.max_value()
		res_l.text = Loc.t(L.RESEARCH_MECH_BODY_PILOT_MAX if at_max else L.RESEARCH_MECH_BODY_PILOT_TARGET,
				{"mech": MechMastery.mech_name(mech), "level": MechMastery.level_name(lv),
				"n": MechMastery.gain_preview(state, pd.id, raw)})
		res_l.add_theme_color_override("font_color", OutgameTheme.TEXT_SUB if at_max else OutgameTheme.ACCENT_TEXT)
	else:
		res_l.text = Loc.t(L.RESEARCH_MECH_BODY_PILOT_NONE)
		res_l.add_theme_color_override("font_color", OutgameTheme.TEXT_SUB)

	var tops: Array = []
	for e in MechMastery.top_mechs(state, pd.id, 3):
		tops.append("%s %s" % [MechMastery.mech_name(int(e["mech_id"])),
				MechMastery.level_name(MechMastery.level_for_value(int(e["value"])))])
	row.get_node("%TopMechs").text = Loc.t(L.MASTERY_PANEL_TOP_MECHS, {"list": "  ·  ".join(tops)})

	# Chips: the lab mech first, then own-role mechs (read-only).
	var ids: Array = []
	if mech >= 0:
		ids.append(mech)
	for e in MechMastery.mechs_of_role(pd.role):
		if ids.size() >= CHIP_COUNT:
			break
		if not ids.has(int(e["id"])):
			ids.append(int(e["id"]))
	var chips: Array = _ensure(row.get_node("%Chips"), CHIP_SCENE, ids.size())
	for i in chips.size():
		var chip: Button = chips[i]
		var mid: int = int(ids[i])
		var v: int = MechMastery.value(state, pd.id, mid)
		var lv: int = MechMastery.level_for_value(v)
		chip.text = "%s\n%s · %s" % [MechMastery.mech_name(mid), MechMastery.level_name(lv),
				MechMastery.pct_text(lv)]
		chip.theme_type_variation = &"PrimaryButton" if mid == mech else &"GhostButton"
		var bar: ColorRect = chip.get_node("%LevelBar")
		bar.color = MechMastery.level_color(lv)
		bar.anchor_right = MechMastery.value_progress(v)

	# §15 A — the next mech upgrade of the lab mech (or the pilot's growth mech).
	var up_mech: int = mech if mech >= 0 else MechMastery.growth_mech(state, pd)
	row.get_node("%NextUpgrade").text = _next_upgrade_text(state, pd.id, up_mech)

	(row.get_node("%Quirks") as Control).visible = quirks_on
	if quirks_on:
		_fill_quirks(row, pd)
	# Card height = content + its top / bottom pads (the scene's `%Content` offsets).
	var content: Control = row.get_node("%Content")
	row.custom_minimum_size.y = content.offset_top + content.get_combined_minimum_size().y \
			+ _card_pad_bottom(row, content)


## "다음 강화 Lv4 · Bastion: …" — the first mech upgrade step (`MechUpgrades`) still
## locked for that pilot on `mech_id`; "" for no mech.
static func _next_upgrade_text(state: Dictionary, pilot_id: int, mech_id: int) -> String:
	if mech_id < 0:
		return ""
	var step: Dictionary = MechUpgrades.next_step(mech_id, MechMastery.level_of(state, pilot_id, mech_id))
	if step.is_empty():
		return Loc.t(L.MASTERY_PANEL_UPGRADES_DONE, {"mech": MechMastery.mech_name(mech_id)})
	return Loc.t(L.MASTERY_PANEL_NEXT_UPGRADE, {"level": MechMastery.level_name(int(step["level"])),
			"mech": MechMastery.mech_name(mech_id), "text": MechUpgrades.step_text(step)})


## Bottom pad of a pilot card = the scene's card height minus `%Content`'s bottom edge, read
## once from the unfilled instance (saved in meta so later refills reuse it).
static func _card_pad_bottom(row: Control, content: Control) -> float:
	if not row.has_meta(&"pad_bottom"):
		row.set_meta(&"pad_bottom", row.custom_minimum_size.y - content.offset_bottom)
	return float(row.get_meta(&"pad_bottom"))


## "기벽 n/slots" head, then one line per quirk: grade pill · name · effect.
func _fill_quirks(row: Control, pd: PlayerData) -> void:
	var state: Dictionary = _state
	var ids: Array = []
	for id in QuirkSystem.quirks_of(state, pd.id):
		if not QuirkSystem.row(int(id)).is_empty():
			ids.append(int(id))
	row.get_node("%Count").text = Loc.t(L.MASTERY_PANEL_QUIRK_COUNT, {
			"n": QuirkSystem.quirks_of(state, pd.id).size(), "slots": QuirkSystem.slots_of(state, pd.id)})
	row.get_node("%Max").text = Loc.t(L.MASTERY_PANEL_QUIRK_MAX, {"n": QuirkSystem.max_slots()})
	(row.get_node("%QuirkEmpty") as Control).visible = QuirkSystem.quirks_of(state, pd.id).is_empty()
	var lines: Array = _ensure(row.get_node("%Lines"), QUIRK_LINE_SCENE, ids.size())
	for i in lines.size():
		var line: Control = lines[i]
		var r: Dictionary = QuirkSystem.row(ids[i])
		var g: int = int(r["grade"])
		var col: Color = QuirkSystem.grade_color(g)
		var pill: Panel = line.get_node("%Grade")
		pill.add_theme_stylebox_override(&"panel", OutgameTheme.flat_style(col, int(pill.size.y * 0.5)))
		(pill.get_child(0) as Label).text = QuirkSystem.grade_name(g)
		var nm: Label = line.get_node("%Name")
		nm.text = QuirkSystem.name_of(ids[i])
		nm.add_theme_color_override("font_color", col)
		line.get_node("%Effect").text = QuirkSystem.effect_text(ids[i])


## Keeps exactly `n` children in `list` (instancing missing ones) and returns them. The
## scene's sample children count as reusable rows.
static func _ensure(list: Node, scene: PackedScene, n: int) -> Array:
	while list.get_child_count() > n:
		var last: Node = list.get_child(list.get_child_count() - 1)
		list.remove_child(last)
		last.queue_free()
	while list.get_child_count() < n:
		list.add_child(scene.instantiate())
	return list.get_children()


## F6 단독 실행 미리보기 — 메모리 런에서 메크 연구소에 첫 대상 메크 연구를 걸고 한 번
## 완료시켜(숙련 · 기벽 굴림) 채운 본문(`resources/UiPreview.gd`).
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var state: Dictionary = gm.season_state
	var rows: Array = ResearchSystem.available(state, MechResearch.FID)
	if not rows.is_empty():
		var r: Dictionary = rows[0]
		var offered: Array = ResearchSystem.targets(state, r)
		if not offered.is_empty():
			var mid: String = String((offered[0] as Dictionary)["id"])
			MechResearch.on_complete(state, r, mid)
			ResearchSystem.select(state, MechResearch.FID, String(r["id"]), mid)
	_state = state
	_bound = true
	refresh()
